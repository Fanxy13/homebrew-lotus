import Foundation
import Darwin

// ── /performance: a conversation as a report in a text file ───
// Everything that shows how well and how fast the AI worked: the setup (AI, model, settings, this Mac), the
// totals (time, thinking, steps, tokens, the model's cache and speed), where Lotus had to step in (going on,
// loops, files not cut short, thinking stopped), the whole conversation step by step with the numbers of
// every model request, and the Lotus log of that time. API keys never get in – but the conversation does,
// with what the AI read: the file says so at the top.

// /ai in the terminal: the messages and answers of this session, kept like the web chat keeps them
final class SessionLog: @unchecked Sendable {
    static let shared = SessionLog()
    private let lock = NSLock()
    private var done: [[String: Any]] = []
    private var started: Date?
    private var events: [[String: Any]] = []
    private var piece = ""              // the text or thoughts that are coming in, in one
    private var pieceType = ""

    func user(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        close(ai: "")
        done.append(["role": "user", "text": text, "time": Date().timeIntervalSince1970])
        started = Date()
    }

    func event(_ type: String, _ data: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        guard let s = started else { return }
        if type == "text" || type == "thinking" {
            if pieceType != type { endPiece(); pieceType = type; piece = "" ; events.append(["type": type, "t": Run.tenths(Date().timeIntervalSince(s))]) }
            piece += data["text"] as? String ?? ""
            return
        }
        endPiece()
        var e = data
        e["type"] = type
        e["t"] = Run.tenths(Date().timeIntervalSince(s))
        events.append(e)
    }

    func end(ai: String) {
        lock.lock(); defer { lock.unlock() }
        close(ai: ai)
    }

    // All of it, with the answer that is still being written
    var messages: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        var all = done
        if started != nil {
            var ev = events
            if !pieceType.isEmpty, var last = ev.last { last["text"] = piece; ev[ev.count - 1] = last }
            all.append(["role": "assistant", "events": ev, "ai": "", "time": Date().timeIntervalSince1970])
        }
        return all
    }

    private func endPiece() {
        guard !pieceType.isEmpty, var last = events.last else { pieceType = ""; return }
        last["text"] = piece
        events[events.count - 1] = last
        pieceType = ""
        piece = ""
    }

    private func close(ai: String) {
        guard started != nil else { return }
        endPiece()
        done.append(["role": "assistant", "events": events, "ai": ai, "time": Date().timeIntervalSince1970])
        started = nil
        events = []
    }
}

enum Perf {
    // ── This Mac and the AI ──

    static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "" }
        return String(cString: buf)
    }

    static func sysctlInt(_ name: String) -> Int64 {
        var v: Int64 = 0
        var size = MemoryLayout<Int64>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? v : 0
    }

    // The settings and the machine, as "name: value" rows
    static func setup(_ agent: Agent, place: String) -> [(String, String)] {
        let saved = SettingsFile.read()
        let e = ProcessInfo.processInfo.environment
        func setting(_ k: String) -> String { saved[k] ?? e[k] ?? "" }
        var rows: [(String, String)] = [
            ("Lotus", agent.config.version.isEmpty ? "?" : agent.config.version),
            ("Where", place),
            ("AI", agent.provider.label),
            ("Provider", agent.config.provider + (agent.config.model.isEmpty ? "" : " · " + agent.config.model)),
            ("Thinking", "\(Effort.name(agent.config.effort)) (\(agent.config.effort))"),
            ("Context", "\(agent.provider.usedTokens) of \(agent.provider.budget) tokens used now"),
            ("Tools", agent.usesTools ? "on · \(ToolCatalog.all.count) tools (\(ToolCatalog.lotus.count) Lotus tools)" : "off – chat only"),
            ("Permissions", agent.runner.permissions.auto ? "auto mode" : "ask first"),
            ("Improve prompts", agent.enhanceMode),
        ]
        let perms = Permissions.items.map { "\($0.key.replacingOccurrences(of: "LOTUS_AI_PERM_", with: "").replacingOccurrences(of: "LOTUS_AI_", with: "").lowercased())=\(agent.runner.permissions.value($0.key))" }
        rows.append(("Allowed", perms.joined(separator: " ")))
        let local = setting("LOTUS_AI_LOCAL")
        if agent.config.provider == "local" || !local.isEmpty {
            rows.append(("Model on this Mac", local.isEmpty ? "–" : local))
            rows.append(("Its settings", "context \(setting("LOTUS_AI_CONTEXT")) · answer length \(setting("LOTUS_AI_MAXTOKENS")) · "
                         + "temperature \(setting("LOTUS_AI_TEMP")) · memory saver \(setting("LOTUS_AI_KVBITS") == "0" || setting("LOTUS_AI_KVBITS").isEmpty ? "off" : setting("LOTUS_AI_KVBITS") + " bits")"))
            if let server = modelServer() { rows.append(("Model server", server)) }
        }
        let gb = Double(sysctlInt("hw.memsize")) / 1_073_741_824
        rows.append(("Mac", "\(sysctl("hw.model")) · \(sysctl("machdep.cpu.brand_string")) · \(String(format: "%.0f", gb)) GB · "
                     + "\(ProcessInfo.processInfo.activeProcessorCount) cores"))
        rows.append(("macOS", ProcessInfo.processInfo.operatingSystemVersionString))
        return rows
    }

    // How the model server on this Mac runs (mlx_lm.server), without anything secret: its options only
    static func modelServer() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)   // ps is done when its output ends
        guard let line = out.split(separator: "\n").first(where: { $0.contains("mlx_lm.server") }) else { return nil }
        let words = line.split(separator: " ").map(String.init)
        guard let i = words.firstIndex(where: { $0.hasSuffix("mlx_lm.server") }) else { return nil }
        var opts = Array(words[(i + 1)...])
        if let m = opts.firstIndex(of: "--model"), m + 1 < opts.count { opts[m + 1] = URL(fileURLWithPath: opts[m + 1]).lastPathComponent }
        return "mlx_lm.server " + opts.joined(separator: " ")
    }

    // ── The report ──

    private static func num(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }

    private static func clock(_ t: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date(timeIntervalSince1970: t))
    }

    private static func cut(_ s: String, _ head: Int, _ tail: Int) -> String {
        guard s.count > head + tail + 40 else { return s }
        return String(s.prefix(head)) + "\n[… \(s.count - head - tail) characters left out …]\n" + String(s.suffix(tail))
    }

    private static func indent(_ s: String, _ pad: String = "      ") -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false).map { pad + $0 }.joined(separator: "\n")
    }

    static func report(messages: [[String: Any]], title: String, setup: [(String, String)]) -> String {
        var out: [String] = []
        let now = Date().timeIntervalSince1970
        let firstTime = messages.compactMap { $0["time"] as? Double }.min() ?? now
        out.append("LOTUS AI – PERFORMANCE REPORT")
        out.append("Conversation: \(title.isEmpty ? "(no title)" : title)")
        out.append("Made: \(clock(now)) · from \(clock(firstTime))")
        out.append("This file contains the whole conversation, with what the AI read and ran. API keys are never in it.")
        out.append("")

        // the setup
        out.append("═══ SETUP ═══")
        let w = (setup.map { $0.0.count }.max() ?? 10) + 2
        for (k, v) in setup { out.append((k + ":").padding(toLength: w, withPad: " ", startingAt: 0) + v) }
        out.append("")

        // the totals
        let answers = messages.filter { $0["role"] as? String == "assistant" }
        let users = messages.filter { $0["role"] as? String == "user" }
        let events = answers.flatMap { $0["events"] as? [[String: Any]] ?? [] }
        func of(_ type: String) -> [[String: Any]] { events.filter { $0["type"] as? String == type } }
        let summaries = of("answer"), models = of("model"), tools = of("tool"), results = of("result"), infos = of("info")
        let workedAll = summaries.isEmpty ? answers.map { a in num((a["events"] as? [[String: Any]])?.last?["t"]) }.reduce(0, +)
                                        : summaries.map { num($0["secs"]) }.reduce(0, +)
        // the Mac asleep (lid closed): measured per model request, and taken out of the thinking and the waiting
        let slept = models.map { num($0["slept"]) }.reduce(0, +)
        let working = max(0, workedAll - slept)
        let thought = max(0, of("thought").map { num($0["secs"]) }.reduce(0, +) - slept)
        let modelTime = max(0, models.map { num($0["secs"]) }.reduce(0, +) - slept)
        out.append("═══ TOTALS ═══")
        out.append("Messages: \(users.count) · answers: \(answers.count) · \(summaries.filter { $0["outcome"] as? String == "stopped" }.count) stopped, "
                   + "\(summaries.filter { $0["outcome"] as? String == "failed" }.count) failed, \(of("error").count) errors shown")
        out.append("Working: \(Stats.duration(working)) · thinking: \(Stats.duration(thought))"
                   + (working > 0 ? " (\(Int(thought * 100 / working))%)" : "")
                   + " · waiting for the model: \(Stats.duration(modelTime))" + (working > 0 ? " (\(Int(min(modelTime, working) * 100 / working))%)" : ""))
        if slept >= 5 {
            out.append("The Mac slept: \(Stats.duration(slept)) during the answer (lid closed or sleep) – not counted above")
        }
        var byTool: [String: Int] = [:]
        for t in tools { byTool[t["name"] as? String ?? "?", default: 0] += 1 }
        out.append("Steps: \(tools.count)" + (byTool.isEmpty ? "" : " · " + byTool.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
                   + " · \(results.filter { ($0["error"] as? Bool) == true }.count) failed")
        if !models.isEmpty {
            let measured = models.filter { num($0["prompt"]) >= 0 && ($0["estimated"] as? Bool) != true }
            let prompt = measured.map { num($0["prompt"]) }, cached = measured.map { num($0["cached"]) }
            let wrote = models.map { num($0["wrote"]) }.reduce(0, +)
            let firsts = models.map { num($0["first"]) }
            var speeds: [Double] = [], reading: [Double] = []
            for m in models {
                let gen = num(m["secs"]) - num(m["first"])
                if gen > 0.5 { speeds.append(num(m["wrote"]) / gen) }
                if num(m["prompt"]) > 0 && num(m["first"]) > 0.2 { reading.append((num(m["prompt"]) - max(0, num(m["cached"]))) / num(m["first"])) }
            }
            func avg(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
            out.append("Model requests: \(models.count) · wrote \(Int(wrote)) tokens"
                       + (speeds.isEmpty ? "" : " · \(String(format: "%.1f", avg(speeds))) tokens/s while writing"))
            if !prompt.isEmpty {
                let total = prompt.reduce(0, +), fromCache = cached.reduce(0, +)
                out.append("Prompts: \(Int(total)) tokens in all, \(Int(avg(prompt))) on average, \(Int(prompt.max() ?? 0)) the largest · "
                           + "from the cache: \(Int(fromCache)) (\(total > 0 ? Int(fromCache * 100 / total) : 0)%)"
                           + (reading.isEmpty ? "" : " · read at \(Int(avg(reading))) tokens/s"))
            }
            out.append("First token after: \(String(format: "%.1f", avg(firsts))) s on average, \(String(format: "%.1f", firsts.max() ?? 0)) s at most")
        }
        out.append("")

        // where Lotus had to step in
        let goOns = infos.compactMap { $0["text"] as? String }.filter { $0.hasPrefix("↻") }
        let loops = results.compactMap { $0["text"] as? String }.filter { $0.contains("The same as before") || $0.contains("stopped the tools") }
        let refused = results.compactMap { $0["text"] as? String }.filter { $0.hasPrefix("Not written: it would replace") }
        let invalid = results.compactMap { $0["text"] as? String }.filter { $0.contains("not valid JSON") || $0.contains("left out") || $0.contains("no tool with this name") }
        let overthought = goOns.filter { $0.contains("thought for a long time") || $0.contains("went in circles") }
        out.append("═══ WHERE LOTUS STEPPED IN ═══")
        out.append("Let it go on: \(goOns.count)" + (goOns.isEmpty ? "" : " – " + Dictionary(grouping: goOns.map { String($0.dropFirst(2).split(separator: "–").first ?? "").trimmingCharacters(in: .whitespaces) }, by: { $0 })
                       .map { "\($0.key) ×\($0.value.count)" }.joined(separator: "; ")))
        out.append("Thinking stopped (too long or in circles): \(overthought.count) · steps repeated: \(loops.count) · "
                   + "files not cut short: \(refused.count) · broken tool calls: \(invalid.count)")
        out.append("")

        // what stands out
        out.append("═══ WHAT STANDS OUT ═══")
        var notes: [String] = []
        if slept >= 60 {
            notes.append("The Mac was asleep for \(Stats.duration(slept)) while the AI worked – nothing happens then. Lotus keeps it awake while "
                         + "it answers, but closing the lid on battery still puts it to sleep.")
        }
        if working > 0 && thought / working > 0.5 { notes.append("Thinking took \(Int(thought * 100 / working))% of the time – lower the thinking (/effort) or give smaller steps.") }
        let measured = models.filter { num($0["prompt"]) > 0 }
        if measured.count >= 2 {
            let hit = measured.map { max(0, num($0["cached"])) }.reduce(0, +) / max(1, measured.map { num($0["prompt"]) }.reduce(0, +))
            if hit < 0.2 { notes.append("The model reused only \(Int(hit * 100))% of its prompts from its cache – every step reads most of the conversation again.") }
        }
        if let slow = models.max(by: { num($0["first"]) < num($1["first"]) }), num(slow["first"]) > 20 {
            notes.append("The slowest start of a model request: \(String(format: "%.0f", num(slow["first"]))) s before the first token (prompt \(Int(num(slow["prompt"]))) tokens).")
        }
        if !loops.isEmpty { notes.append("The AI repeated steps \(loops.count) times – it went in circles.") }
        if !overthought.isEmpty { notes.append("Its thinking had to be stopped \(overthought.count) times.") }
        if !refused.isEmpty { notes.append("It tried \(refused.count) times to replace a long file with a few lines (write_file instead of edit_file).") }
        if !invalid.isEmpty { notes.append("\(invalid.count) tool calls were broken (invalid JSON, a missing argument or an unknown tool).") }
        let failed = results.filter { ($0["error"] as? Bool) == true }.count
        if tools.count >= 4 && failed * 3 > tools.count { notes.append("\(failed) of \(tools.count) steps failed.") }
        out.append(notes.isEmpty ? "Nothing unusual." : notes.map { "- " + $0 }.joined(separator: "\n"))
        out.append("")

        // the conversation, step by step
        out.append("═══ THE CONVERSATION ═══")
        for (i, m) in messages.enumerated() {
            let t = m["time"] as? Double ?? now
            if m["role"] as? String == "user" {
                let text = m["text"] as? String ?? ""
                out.append("")
                out.append("── [\(i + 1)] YOU · \(clock(t)) · \(text.count) characters")
                out.append(indent(cut(text, 6000, 2000), "   "))
                continue
            }
            let ev = m["events"] as? [[String: Any]] ?? []
            let sum = ev.last { $0["type"] as? String == "answer" }
            var head = "── [\(i + 1)] LOTUS AI" + ((m["ai"] as? String).map { $0.isEmpty ? "" : " (\($0))" } ?? "")
            if let s = sum {
                head += " · took \(Stats.duration(num(s["secs"]))) · thought \(Stats.duration(num(s["thought"]))) · \(Int(num(s["steps"]))) steps · \(s["outcome"] as? String ?? "")"
            } else if let last = ev.last {
                head += " · \(Stats.duration(num(last["t"])))"
            }
            out.append("")
            out.append(head)
            var model = 0
            for e in ev {
                let at = String(format: "%7.1fs  ", num(e["t"]))
                switch e["type"] as? String ?? "" {
                case "thinking":
                    let s = e["text"] as? String ?? ""
                    if !s.isEmpty { out.append(at + "thinking (\(s.count) characters):"); out.append(indent(cut(s, 1500, 1000), "            ")) }
                case "thought": out.append(at + "thought for \(Int(num(e["secs"])))s")
                case "text":
                    let s = e["text"] as? String ?? ""
                    if !s.isEmpty { out.append(at + "answer:"); out.append(indent(cut(s, 12000, 3000), "            ")) }
                case "tool": out.append(at + "STEP \(e["name"] as? String ?? "?") \((e["detail"] as? String ?? "").prefix(600))")
                case "result": out.append(at + "  → " + ((e["error"] as? Bool) == true ? "FAILED: " : "") + (e["text"] as? String ?? ""))
                case "lines":
                    let lines = (e["lines"] as? [String] ?? []).prefix(12)
                    for l in lines { out.append("              | " + l) }
                    if let more = e["more"] as? Int, more > 0 || (e["lines"] as? [String] ?? []).count > 12 {
                        out.append("              | … \(more + max(0, (e["lines"] as? [String] ?? []).count - 12)) more lines")
                    }
                case "plan":
                    for st in e["steps"] as? [[String: Any]] ?? [] {
                        let mark = ["done": "[x]", "doing": "[>]"][st["state"] as? String ?? ""] ?? "[ ]"
                        out.append("              | \(mark) \(st["text"] as? String ?? "")")
                    }
                case "file": break
                case "model":
                    model += 1
                    let prompt = Int(num(e["prompt"]))
                    let gen = num(e["secs"]) - num(e["first"])
                    let speed = gen > 0.5 ? String(format: " · %.1f tokens/s", num(e["wrote"]) / gen) : ""
                    out.append(at + "model request \(model): "
                               + (prompt >= 0 ? "prompt \(prompt) tokens (\(Int(num(e["cached"]))) from the cache) · " : "")
                               + "wrote \(Int(num(e["wrote"])))\((e["estimated"] as? Bool) == true ? " (about)" : "") · server answered after \(String(format: "%.1f", num(e["answered"])))s, "
                               + "first token after \(String(format: "%.1f", num(e["first"])))s · "
                               + "\(String(format: "%.1f", num(e["secs"])))s in all\(speed) · ended: \(e["finish"] as? String ?? "")")
                case "info": out.append(at + "LOTUS: \(e["text"] as? String ?? "")")
                case "error": out.append(at + "ERROR: \(e["title"] as? String ?? "") \(e["detail"] as? String ?? "")")
                case "ask": out.append(at + "ASKED: \(e["question"] as? String ?? "")")
                case "asked": out.append(at + "  answer: \(e["answer"] as? String ?? "")\((e["note"] as? String).map { $0.isEmpty ? "" : " – \($0)" } ?? "")")
                case "improved": out.append(at + "improved prompt:"); out.append(indent(cut(e["text"] as? String ?? "", 4000, 1000), "            "))
                case "status": out.append(at + "(\(e["text"] as? String ?? ""))")
                case "image": out.append(at + "screenshot: \(e["alt"] as? String ?? "")")
                case "answer", "end", "start", "done", "clock": break
                default: break
                }
            }
        }
        out.append("")

        // the Lotus log and the model server's log of that time
        out.append("═══ LOTUS LOG (this time) ═══")
        out.append(contentsOf: logLines(since: firstTime - 5))
        let server = modelLog(since: firstTime - 5)
        if !server.isEmpty {
            out.append("")
            out.append("═══ MODEL SERVER LOG (this time, without the progress lines) ═══")
            out.append(contentsOf: server)
        }
        out.append("")
        out.append("— end of report —")
        return out.joined(separator: "\n") + "\n"
    }

    // Lotus' own log lines of that time (lib/log.zsh: "date time<TAB>LEVEL<TAB>component<TAB>message")
    static func logLines(since: Double) -> [String] {
        let e = ProcessInfo.processInfo.environment
        guard let path = e["LOTUS_LOG"], let text = try? String(contentsOfFile: path, encoding: .utf8) else { return ["(no log)"] }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let start = f.string(from: Date(timeIntervalSince1970: since))
        let lines = text.split(separator: "\n").filter { $0.count >= 19 && String($0.prefix(19)) >= start }
        return lines.suffix(600).map { String($0.prefix(800)) }
    }

    // The model server's log (lotus ai local): errors and requests, not the progress lines
    static func modelLog(since: Double) -> [String] {
        let cache = ProcessInfo.processInfo.environment["LOTUS_CACHE"] ?? NSHomeDirectory() + "/.cache/lotus"
        guard let text = try? String(contentsOfFile: cache + "/llm/server.log", encoding: .utf8) else { return [] }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let start = f.string(from: Date(timeIntervalSince1970: since))
        var out: [String] = []
        var noTools = 0, ended = false
        for l in text.split(separator: "\n").suffix(20_000) {
            let s = String(l)
            // mlx says this on every request for gpt-oss: it does not read tool calls itself – Lotus does, from the text
            if s.contains("Received tools but model does not support tool calling") {
                if s.count < 19 || String(s.prefix(19)) >= start { noTools += 1 }
                continue
            }
            // a request that Lotus ended itself (stopped thinking, the stop button): the server could not write on
            if s.contains("BrokenPipeError") {
                if !ended { out.append("(BrokenPipeError: a request that Lotus ended itself – when it stopped a thinking or you pressed stop)") }
                ended = true
                continue
            }
            if s.contains("Prompt processing progress") || s.contains("Prompt Cache:") || s.hasPrefix("2") && s.contains(" - INFO - - ") { continue }
            if s.count >= 19, s.first?.isNumber == true, String(s.prefix(19)) < start { continue }
            if s.first?.isNumber != true && !s.contains("POST") && !s.contains("Error") && !s.contains("Traceback") { continue }
            if s.hasPrefix("Traceback") || s.contains("socketserver.py") || s.contains("mlx_lm/server.py\", line") { continue }
            out.append(String(s.prefix(400)))
        }
        if noTools > 0 {
            out.insert("(\(noTools)× \"Received tools but model does not support tool calling\" – not an error: mlx leaves the tool calls of gpt-oss to Lotus)", at: 0)
        }
        return Array(out.suffix(200))
    }

    // A file name for the report: lotus-performance-<title>-<date>.txt
    static func fileName(_ title: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let slug = title.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" }
            .reduce(into: "") { s, c in if !(c == "-" && s.hasSuffix("-")) { s.append(c) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "lotus-performance-" + (slug.isEmpty ? "" : String(slug.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-")) + "-") + f.string(from: Date()) + ".txt"
    }

    // /performance in the terminal: saved in Downloads → the file
    static func save(_ text: String, title: String) -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName(title))
        return FileManager.default.createFile(atPath: url.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) ? url : nil
    }
}
