import Foundation
import Darwin

// ── Statistics: what the AI did ───────────────────────────────
// /stats in /ai and lotus ai stats show them, together with what the web chat is doing right now.
// One line per answer – from /ai and from the web chat – in $LOTUS_STATE/ai-stats.tsv, which only
// you can read:
//   started  where  ai  secs  thought  outcome  tools
// started: when (seconds since 1970) · where: terminal or web · ai: who answered · secs: how long it
// worked · thought: seconds of thinking · outcome: done, stopped or failed · tools: name:count,… or -
// Only counts and times – nothing of what was asked or answered.

enum Stats {
    struct Entry {
        let started: Double
        let place: String
        let ai: String
        let secs: Double
        let thought: Double
        let outcome: String
        let tools: [String: Int]
        var steps: Int { tools.values.reduce(0, +) }
    }

    private static let lock = NSLock()
    private static var begun: Date?
    private static var place = "terminal"
    private static var thought = 0.0
    private static var tools: [String: Int] = [:]

    // Lotus' state folder (lib/core.zsh), shared by /ai and the web chat; nil when Lotus did not start this program
    static var stateDir: URL? {
        guard let s = ProcessInfo.processInfo.environment["LOTUS_STATE"], s.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: s)
    }
    static var file: URL? { stateDir?.appendingPathComponent("ai-stats.tsv") }

    // ── Counting one answer ──

    static func begin(_ where: String) {
        lock.lock(); defer { lock.unlock() }
        begun = Date()
        place = `where`
        thought = 0
        tools = [:]
    }

    static func tool(_ name: String) {
        let known = ToolCatalog.all.contains { $0.name == name }
        lock.lock(); defer { lock.unlock() }
        guard begun != nil else { return }
        tools[known ? name : "other", default: 0] += 1
    }

    static func thinking(_ secs: Double) {
        lock.lock(); defer { lock.unlock() }
        if begun != nil { thought += max(0, secs) }
    }

    static func end(_ outcome: String, ai: String) {
        lock.lock()
        guard let start = begun else { lock.unlock(); return }
        begun = nil
        let line = [String(Int(start.timeIntervalSince1970)), place, clean(ai),
                    String(format: "%.1f", Date().timeIntervalSince(start)), String(format: "%.1f", thought), outcome,
                    tools.isEmpty ? "-" : tools.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")]
            .joined(separator: "\t") + "\n"
        lock.unlock()
        append(line)
    }

    private static func clean(_ s: String) -> String {
        let t = s.unicodeScalars.filter { $0.value >= 0x20 && $0 != "\t" }.prefix(80)
        return t.isEmpty ? "-" : String(String.UnicodeScalarView(t))
    }

    // Appended in one write, so /ai and the web chat can both add to it; kept below about 1 MB
    private static func append(_ line: String) {
        guard let url = file else { return }
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return }
        let size = lseek(fd, 0, SEEK_END)
        _ = line.withCString { Darwin.write(fd, $0, strlen($0)) }
        close(fd)
        if size > 1_000_000, let text = try? String(contentsOf: url, encoding: .utf8) {
            let keep = text.split(separator: "\n").suffix(8000).joined(separator: "\n") + "\n"
            let tmp = url.appendingPathExtension("new")
            if FileManager.default.createFile(atPath: tmp.path, contents: Data(keep.utf8), attributes: [.posixPermissions: 0o600]) {
                _ = rename(tmp.path, url.path)
            }
        }
    }

    static func load() -> [Entry] {
        guard let url = file, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [Entry] = []
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 7, let t = Double(f[0]), let secs = Double(f[3]), let th = Double(f[4]) else { continue }
            var tools: [String: Int] = [:]
            if f[6] != "-" {
                for pair in f[6].split(separator: ",") {
                    let p = pair.split(separator: ":")
                    if p.count == 2, let n = Int(p[1]), n > 0 { tools[String(p[0]), default: 0] += n }
                }
            }
            out.append(Entry(started: t, place: f[1], ai: f[2], secs: secs, thought: th, outcome: f[5], tools: tools))
        }
        return out
    }

    // ── The web chat right now ($LOTUS_STATE/ai-server.now, written by Server.swift) ──

    static var nowFile: URL? { stateDir?.appendingPathComponent("ai-server.now") }

    // What the running web chat says about itself; nil when it does not run
    static func server() -> [String: Any]? {
        guard let url = nowFile, let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = o["pid"] as? Int, pid > 1, kill(pid_t(pid), 0) == 0 else { return nil }
        return o
    }

    // An answer to the web chat's open question, from this terminal: the access key (a file only you can
    // read) in a header, to 127.0.0.1 – the web chat takes it from this Mac only
    static func answer(_ id: String, _ word: String, port: Int) async -> Bool {
        await post("/api/answer", ["id": id, "answer": word], port: port)
    }

    // x in the view: the answer stops (the stop button of the page)
    static func post(_ path: String, _ body: [String: String], port: Int) async -> Bool {
        guard let dir = stateDir,
              let key = try? String(contentsOf: dir.appendingPathComponent("ai-server.key"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty,
              let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "X-Lotus-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        guard let (_, res) = try? await URLSession(configuration: config).data(for: req) else { return false }
        return (res as? HTTPURLResponse)?.statusCode == 200
    }

    // ── The view ──

    static func duration(_ s: Double) -> String {
        let n = Int(s.rounded())
        if n < 60 { return "\(n)s" }
        if n < 3600 { return "\(n / 60)m \(String(format: "%02d", n % 60))s" }
        return "\(n / 3600)h \(String(format: "%02d", n % 3600 / 60))m"
    }

    private static func pad(_ s: String, _ n: Int, right: Bool = false) -> String {
        let w = visibleWidth(s)
        guard w < n else { return s }
        let fill = String(repeating: " ", count: n - w)
        return right ? fill + s : s + fill
    }

    // The keys a question takes in the view → (key, answer, label)
    static func choices(_ q: [String: Any]) -> [(Character, String, String)] {
        if q["kind"] as? String == "improve" {
            return [("s", "improved", "send the improved prompt"), ("o", "original", "send it as typed"), ("c", "cancel", "do not send")]
        }
        var c: [(Character, String, String)] = [("y", "yes", "yes")]
        if q["always"] as? Bool == true { c.append(("a", "always", "yes, don't ask again")) }
        c.append(("n", "no", "no"))
        return c
    }

    // All of it as lines – the live view draws them again every half second
    static func lines(width: Int, live: Bool, note: String = "") -> [String] {
        let w = max(44, min(width, 92))
        let now = Date().timeIntervalSince1970
        var out: [String] = []
        let head = "\(Style.logo)✻\(Style.reset) \(Style.bold)Lotus AI\(Style.reset) \(Style.dim)· statistics\(Style.reset)"
        let keys = live ? "\(Style.dim)q closes\(Style.reset)" : ""
        out.append(" " + pad(head, w - visibleWidth(keys) - 2) + keys)
        out.append("")

        // the web chat
        let label = pad("Web chat", 11)
        if let s = server() {
            let port = s["port"] as? Int ?? 0
            let watching = s["watching"] as? Int ?? 0
            // pages that follow the answer – a page with another conversation open does not count
            let browsers = watching == 0 ? "no page follows it – it works on anyway" : watching == 1 ? "1 page follows it" : "\(watching) pages follow it"
            if let run = s["run"] as? [String: Any] {
                let started = run["started"] as? Double ?? now
                let title = run["title"] as? String ?? ""
                let activity = (run["activity"] as? String ?? "Thinking").replacingOccurrences(of: "\n", with: " ")
                if let q = run["question"] as? [String: Any] {
                    out.append(" \(label)\(Style.accent)●\(Style.reset) \(Style.bold)waiting for your answer\(Style.reset) \(Style.dim)· \(duration(now - started))\(title.isEmpty ? "" : " · " + title)\(Style.reset)")
                    let text = (q["text"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
                    // the step it asks about, then the question
                    if q["kind"] as? String != "improve" { out.append(" " + pad("", 11) + "\(Style.key)⎿\(Style.reset) " + clip(activity, w - 15)) }
                    out.append(" " + pad("", 11) + Style.bold + clip(text, w - 13) + Style.reset)
                    let keys = choices(q).map { "\(Style.key)\($0.0)\(Style.reset) \($0.2)" }.joined(separator: " \(Style.dim)·\(Style.reset) ")
                    out.append(" " + pad("", 11) + keys)
                } else {
                    out.append(" \(label)\(Style.logo)●\(Style.reset) \(Style.bold)working\(Style.reset) \(Style.dim)· \(duration(now - started))\(title.isEmpty ? "" : " · " + title)\(Style.reset)")
                    let since = run["since"] as? Double ?? now
                    let took = duration(now - since)
                    out.append(" " + pad("", 11) + "\(Style.key)⎿\(Style.reset) " + clip(activity, w - 17 - took.count) + "  \(Style.dim)\(took)\(Style.reset)")
                }
                let steps = run["steps"] as? Int ?? 0
                let thought = run["thought"] as? Double ?? 0
                var bits = ["\(steps) \(steps == 1 ? "step" : "steps")"]
                if thought >= 1 { bits.append("thought \(duration(thought))") }
                bits.append(browsers)
                out.append(" " + pad("", 11) + "\(Style.dim)\(clip(bits.joined(separator: " · "), w - 13))\(Style.reset)")
                if live { out.append(" " + pad("", 11) + "\(Style.key)x\(Style.reset) \(Style.dim)stops the answer\(Style.reset)") }
            } else {
                let since = s["since"] as? Double ?? now
                let f = DateFormatter()
                f.dateFormat = now - since < 86400 ? "HH:mm" : "d MMM HH:mm"
                out.append(" \(label)\(Style.dim)○\(Style.reset) ready on http://127.0.0.1:\(port) \(Style.dim)· since \(f.string(from: Date(timeIntervalSince1970: since)))\(Style.reset)")
                if live { out.append(" " + pad("", 11) + "\(Style.dim)lotus ai server open opens it in your browser\(Style.reset)") }
            }
        } else {
            out.append(" \(label)\(Style.dim)off · lotus ai server start opens it in your browser\(Style.reset)")
        }
        if !note.isEmpty { out.append(" " + pad("", 11) + note) }
        out.append("")

        // the numbers: today, the last 7 days, all
        let all = load()
        guard !all.isEmpty else {
            out.append(" \(Style.dim)No answers counted yet – ask something in /ai or in the web chat.\(Style.reset)")
            return out
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date()).timeIntervalSince1970
        let week = today - 6 * 86400
        let groups = [all.filter { $0.started >= today }, all.filter { $0.started >= week }, all]
        let col = 11
        out.append(" " + pad("", 15) + ["today", "7 days", "all"].map { "\(Style.dim)" + pad($0, col, right: true) + Style.reset }.joined())
        func row(_ name: String, _ value: ([Entry]) -> String) {
            out.append(" " + pad(name, 15) + groups.map { pad(value($0), col, right: true) }.joined())
        }
        row("Answers") { "\($0.count)" }
        row("Working") { duration($0.reduce(0) { $0 + $1.secs }) }
        row("Thinking") { duration($0.reduce(0) { $0 + $1.thought }) }
        row("Steps") { "\($0.reduce(0) { $0 + $1.steps })" }
        row("Stopped") { "\($0.filter { $0.outcome == "stopped" }.count)" }
        row("Failed") { "\($0.filter { $0.outcome == "failed" }.count)" }
        out.append("")

        // the steps by tool
        var byTool: [String: Int] = [:]
        for e in all { for (k, v) in e.tools { byTool[ToolCatalog.label(k) == "tool" ? k : ToolCatalog.label(k), default: 0] += v } }
        if !byTool.isEmpty {
            out.append(" \(Style.bold)Steps\(Style.reset) \(Style.dim)by tool, all\(Style.reset)")
            let top = byTool.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(7)
            let most = top.first?.value ?? 1
            let barRoom = max(8, min(30, w - 30))
            for (name, n) in top {
                let filled = max(1, n * barRoom / max(1, most))
                out.append(" " + pad(clip(name, 14), 15) + Style.logo + String(repeating: "■", count: filled) + Style.reset
                           + String(repeating: " ", count: barRoom - filled) + "  " + pad("\(n)", 6, right: true))
            }
            out.append("")
        }

        // answers per day, the last 14 days
        var days = [Int](repeating: 0, count: 14)
        for e in all {
            let d = Int((today - cal.startOfDay(for: Date(timeIntervalSince1970: e.started)).timeIntervalSince1970) / 86400 + 0.5)
            if d >= 0 && d < 14 { days[13 - d] += 1 }
        }
        let peak = days.max() ?? 0
        if peak > 0 {
            let bars = Array("▁▂▃▄▅▆▇█")
            let spark = days.map { $0 == 0 ? "\(Style.dim)·\(Style.reset)" : "\(Style.logo)\(bars[min(7, ($0 * 8 - 1) / peak)])\(Style.reset)" }.joined(separator: " ")
            out.append(" " + pad("Last 14 days", 15) + spark + "  \(Style.dim)up to \(peak) a day\(Style.reset)")
        }

        // where and with which AI
        func shares(_ key: (Entry) -> String, _ name: (String) -> String) -> String {
            var c: [String: Int] = [:]
            for e in all { c[key(e), default: 0] += 1 }
            return c.sorted { $0.value > $1.value }.prefix(4).map { "\(name($0.key)) \($0.value * 100 / all.count)%" }
                .joined(separator: " \(Style.dim)·\(Style.reset) ")
        }
        out.append(" " + pad("Where", 15) + clip(shares({ $0.place }, { $0 == "web" ? "web chat" : $0 }), w - 17))
        out.append(" " + pad("AI", 15) + clip(shares({ $0.ai }, { $0 }), w - 17))
        return out
    }

    // Once, for lotus ai stats without a terminal (or piped)
    static func printOnce() {
        print(lines(width: Term.isTTY ? Term.width : 80, live: false).map { Term.isTTY ? fit($0, Term.width - 1) : ToolRunner.plain($0) }.joined(separator: "\n"))
    }

    // The live view: drawn again every half second until q, esc or enter. A question of the web chat
    // can be answered here – only the terminal has to be open.
    static func live(_ keys: KeyQueue) async {
        let pressed = KeyBox()
        let reader = Task {
            while !Task.isCancelled {
                let k = await keys.next()
                if k == .cancelled { return }
                pressed.push(k)
            }
        }
        Out.shared.write("\u{1B}[?1049h\u{1B}[?25l")
        defer {
            reader.cancel()
            Out.shared.write("\u{1B}[?25h\u{1B}[?1049l")
        }
        var note = ""
        var noteUntil = Date.distantPast
        while true {
            if Date() > noteUntil { note = "" }
            let rows = lines(width: Term.width, live: true, note: note)
            let room = max(1, Term.height - 1)
            Out.shared.write("\u{1B}[H" + rows.prefix(room).map { fit($0, Term.width - 1) + "\u{1B}[K" }.joined(separator: "\n") + "\u{1B}[J")
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if pressed.any { break }
            }
            for k in pressed.take() {
                switch k {
                case .esc, .enter, .ctrlC, .ctrlD, .char("q"), .char("Q"):
                    return
                case .char("x"), .char("X"):
                    guard let s = server(), s["run"] != nil, let port = s["port"] as? Int else { continue }
                    let ok = await post("/api/stop", [:], port: port)
                    note = ok ? "\(Style.green)Stopping the answer\(Style.reset)" : "\(Style.red)The web chat did not answer\(Style.reset)"
                    noteUntil = Date().addingTimeInterval(4)
                case .char(let c):
                    guard let s = server(), let run = s["run"] as? [String: Any], let q = run["question"] as? [String: Any],
                          let id = q["id"] as? String, let port = s["port"] as? Int,
                          let typed = c.lowercased().first, let pick = choices(q).first(where: { $0.0 == typed }) else { continue }
                    let ok = await answer(id, pick.1, port: port)
                    note = ok ? "\(Style.green)Answered: \(pick.2)\(Style.reset)" : "\(Style.red)The web chat did not take the answer – it may have been answered already\(Style.reset)"
                    noteUntil = Date().addingTimeInterval(4)
                default:
                    continue
                }
            }
        }
    }
}

// Cuts a line with color codes to a number of cells – the codes stay whole, the colors end with it
func fit(_ s: String, _ cells: Int) -> String {
    if visibleWidth(s) <= cells { return s }
    var out = ""
    var w = 0
    var inEscape = false
    for ch in s {
        if inEscape {
            out.append(ch)
            if let a = ch.asciiValue, a >= 0x40, a <= 0x7E, ch != "[" { inEscape = false }
            continue
        }
        if ch == "\u{1B}" { inEscape = true; out.append(ch); continue }
        let cw = cellWidth(ch)
        if w + cw > max(0, cells - 1) { break }
        out.append(ch)
        w += cw
    }
    return out + "…" + Style.reset
}

// Keys pressed while the live view waits
final class KeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [Key] = []
    func push(_ k: Key) { lock.lock(); keys.append(k); lock.unlock() }
    var any: Bool { lock.lock(); defer { lock.unlock() }; return !keys.isEmpty }
    func take() -> [Key] { lock.lock(); defer { lock.unlock() }; let k = keys; keys = []; return k }
}
