// lotus-ai – the AI terminal of Lotus. Built once on this Mac by lib/cmd/ai.zsh.
//
//   lotus-ai --tui            the full AI terminal (what /ai opens)
//   lotus-ai --once <text>    one message with memory and tools, then back to the shell
//   lotus-ai --task <text>    one answer without memory or tools (instructions: $LOTUS_AI_INSTRUCTIONS)
//   lotus-ai --plain <text>   like --task, plain text only (for other commands to read)
//   lotus-ai --check          is Apple Intelligence available?
//   lotus-ai --serve <port>   the web chat in the browser (Server.swift, started by lotus ai server start)
//   lotus-ai --port-check <port> [lan]   "free" or "used"
//
// The provider, model, keys and colors come from environment variables set by lib/cmd/ai.zsh.
// Keys are never written to disk by this program.

import Foundation

struct Config {
    var provider: String
    var model: String
    var effort: String
    var claudeKey: String
    let openaiKey: String
    let openaiURL: String
    let stateDir: URL
    let available: [String]
    let localLabel: String      // the model on this Mac (lotus ai local), if there is one
    let name: String
    let root: String
    let version: String

    static func fromEnvironment() -> Config {
        let e = ProcessInfo.processInfo.environment
        let state = e["LOTUS_AI_STATE"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/lotus/ai")
        try? FileManager.default.createDirectory(at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let effort = e["LOTUS_AI_EFFORT"] ?? "high"
        return Config(
            provider: e["LOTUS_AI_PROVIDER"] ?? "apple",
            model: e["LOTUS_AI_MODEL"] ?? "",
            effort: ["low", "medium", "high", "max"].contains(effort) ? effort : "high",
            claudeKey: e["LOTUS_AI_CLAUDE_KEY"] ?? "",
            openaiKey: e["LOTUS_AI_OPENAI_KEY"] ?? "",
            openaiURL: e["LOTUS_AI_URL"] ?? "",
            stateDir: state,
            available: (e["LOTUS_AI_AVAILABLE"] ?? "").split(separator: ",").map(String.init),
            localLabel: e["LOTUS_AI_LOCAL_LABEL"] ?? "",
            name: e["LOTUS_NAME"] ?? "",
            root: e["LOTUS_ROOT"] ?? "",
            version: e["LOTUS_VERSION"] ?? "")
    }
}

// ── Memory ────────────────────────────────────────────────────

final class Conversation {
    var turns: [Turn] = []
    var summary = ""
    var updated = Date()
    private let file: URL?          // nil: kept by someone else (the web chat keeps its own conversations)
    static let keepFor: TimeInterval = 3600

    private struct Stored: Codable {
        var turns: [Turn]
        var summary: String
        var updated: Double
    }

    init(file: URL?) {
        self.file = file
        guard let file = file, let data = try? Data(contentsOf: file),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        let when = Date(timeIntervalSince1970: s.updated)
        guard Date().timeIntervalSince(when) < Conversation.keepFor else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        turns = s.turns
        summary = s.summary
        updated = when
    }

    var isEmpty: Bool { turns.isEmpty && summary.isEmpty }

    func save() {
        updated = Date()
        guard let file = file else { return }
        let s = Stored(turns: turns, summary: summary, updated: updated.timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: file, options: .atomic)
        chmod(file.path, 0o600)
    }

    func clear() {
        turns = []
        summary = ""
        if let file = file { try? FileManager.default.removeItem(at: file) }
    }

    func asText(limit: Int) -> String {
        var out = summary.isEmpty ? "" : "Summary of the earlier conversation:\n\(summary)\n\n"
        for t in turns { out += (t.role == "user" ? "User: " : "Assistant: ") + t.text + "\n\n" }
        return out.count > limit ? "…" + String(out.suffix(limit)) : out
    }
}

// ── The agent: one provider, the memory and the tools ─────────

final class Agent {
    var config: Config
    var provider: Provider
    var conversation: Conversation
    let runner: ToolRunner
    let interaction: Interaction
    let keys: KeyQueue?
    let cwd: URL
    var usesTools: Bool              // false: the AI only talks (switched off in the permissions)
    var lastAnswer = ""
    var restartForLocal = false      // /model chose the model on this Mac: Lotus starts it, then /ai opens again
    var browser = false              // the web chat: the instructions say where the user reads the answers
    var enhanceMode: String          // off · on · ask: improve a message before the AI sees it (Enhance.swift)
    private var currentWork: Task<String, Error>?

    init(config: Config, keys: KeyQueue?, memory: Bool, tools: Bool = true) throws {
        self.config = config
        self.keys = keys
        usesTools = tools && Permissions(environment: ProcessInfo.processInfo.environment).tools
        let mode = (ProcessInfo.processInfo.environment["LOTUS_AI_ENHANCE"] ?? "").lowercased()
        enhanceMode = Enhance.modes.contains(mode) ? mode : "off"
        cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        interaction = Interaction(keys: keys)
        runner = ToolRunner(cwd: cwd, ui: interaction, outputLimit: 30_000)
        conversation = Conversation(file: config.stateDir.appendingPathComponent(memory ? "conversation.json" : "scratch.json"))
        if !memory { conversation.clear() }
        provider = try Agent.makeProvider(config, runner: runner, tools: tools)
        resetProvider()
    }

    static func makeProvider(_ c: Config, runner: ToolRunner, tools: Bool) throws -> Provider {
        runner.outputLimit = 30_000
        switch c.provider {
        case "claude":
            guard !c.claudeKey.isEmpty else { throw AIError(title: "No Claude API key yet", detail: "Connect it with /login (or in the shell: lotus ai login)") }
            return ClaudeProvider(model: c.model, key: c.claudeKey, effort: c.effort)
        case "ollama":
            guard !c.model.isEmpty else { throw AIError(title: "No Ollama model found", detail: "Download one, e.g.: ollama pull qwen3") }
            runner.outputLimit = 8000
            return OllamaProvider(model: c.model, effort: c.effort)
        case "openai":
            guard !c.openaiURL.isEmpty, !c.openaiKey.isEmpty else { throw AIError(title: "The OpenAI-compatible API is not set up", detail: "Set the URL in /settings and the key with: lotus ai key openai") }
            return OpenAIProvider(model: c.model, base: c.openaiURL, key: c.openaiKey)
        default:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let state = AppleProvider.availability()
                guard state == "available" else {
                    throw AIError(title: "Apple Intelligence is not available", detail: state.replacingOccurrences(of: "unavailable: ", with: ""))
                }
                return AppleProvider(effort: c.effort, runner: tools ? runner : nil)
            }
            #endif
            throw AIError(title: "Apple Intelligence needs macOS 26 or newer", detail: "Use Claude, Ollama or another provider instead: /settings → AI")
        }
    }

    // The instructions for the model, written once per conversation
    // The instructions come from one file for every provider: data/ai/system.md
    static let promptSections: [String: String] = {
        let root = ProcessInfo.processInfo.environment["LOTUS_ROOT"] ?? ""
        guard let text = try? String(contentsOfFile: root + "/data/ai/system.md", encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        var name: String?
        var lines: [String] = []
        func flush() { if let n = name { out[n] = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) } }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { flush(); name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces); lines = [] }
            else if name != nil { lines.append(line) }
        }
        flush()
        return out
    }()

    func systemPrompt(tools: Bool) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short)
        let home = NSHomeDirectory()
        let dir = cwd.path == home ? "~" : cwd.path.hasPrefix(home + "/") ? "~/" + cwd.path.dropFirst(home.count + 1) : cwd.path
        let lotusTools = ToolCatalog.lotus.map(\.name).joined(separator: ", ")
        let off = ToolCatalog.lotusOff.isEmpty ? "" : " Switched off in Lotus: \(ToolCatalog.lotusOff.joined(separator: ", ")). When the user asks for one of these, tell them how to turn it on."
        let fill: (String) -> String = { t in
            t.replacingOccurrences(of: "{{os}}", with: "\(os.majorVersion).\(os.minorVersion)")
                .replacingOccurrences(of: "{{folder}}", with: dir)
                .replacingOccurrences(of: "{{date}}", with: date)
                .replacingOccurrences(of: "{{name}}", with: self.config.name.isEmpty ? "" : " The user's name is \(self.config.name).")
                .replacingOccurrences(of: "{{lotus_tools}}", with: lotusTools)
                .replacingOccurrences(of: "{{off}}", with: off)
        }
        let s = Agent.promptSections
        var parts: [String]
        if provider.isSmall {
            parts = ["small"] + (tools ? ["small-work"] : []) + (tools && !ToolCatalog.lotus.isEmpty ? ["small-lotus"] : [])
        } else {
            parts = ["identity"] + (tools ? ["work"] + (ToolCatalog.lotus.isEmpty ? [] : ["lotus"]) + ["web", "memory"] : []) + ["answer"]
        }
        if browser { parts.append("browser") }
        var p = parts.compactMap { s[$0] }.map(fill).joined(separator: "\n\n")
        if p.isEmpty {
            // the file is missing: still a sensible start
            p = "You are Lotus AI, a helpful assistant in the user's macOS terminal. Working folder: \(dir). Today: \(date). Answer in the user's language."
        }
        // what the AI kept from earlier conversations, and the notes of this folder (LOTUS.md, AGENTS.md, CLAUDE.md)
        let facts = Memory.facts()
        if !facts.isEmpty {
            let room = provider.isSmall ? 900 : 6000
            var list = ""
            for f in facts.reversed() where list.count + f.count < room { list = "- \(f)\n" + list }
            p += "\n\nWhat you remember about the user from earlier conversations:\n\(list)"
        }
        if tools, let notes = folderNotes() {
            let room = provider.isSmall ? 1200 : 8000
            p += "\n\nNotes for this folder (\(notes.name)) – follow them:\n\(String(notes.text.prefix(room)))"
        }
        if !conversation.summary.isEmpty {
            p += "\n\nSummary of the earlier part of this conversation:\n\(conversation.summary)"
        }
        return p
    }

    // LOTUS.md, AGENTS.md or CLAUDE.md in the working folder: how to work on this project
    func folderNotes() -> (name: String, text: String)? {
        guard runner.permissions.read != .never else { return nil }
        for name in ["LOTUS.md", "AGENTS.md", "CLAUDE.md"] {
            let url = cwd.appendingPathComponent(name)
            guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 0, size < 200_000,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            return (name, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func resetProvider() {
        provider.reset(system: systemPrompt(tools: usesTools), chatSystem: systemPrompt(tools: false), history: conversation.turns)
    }

    var contextPercent: Int {
        min(99, provider.usedTokens * 100 / max(1, provider.budget))
    }

    var statusText: String {
        "\(provider.label) · \(contextPercent)% context"
    }

    var autoMode: Bool { usesTools && runner.permissions.auto }

    // ⇧⇥ in the input box: auto mode on or off, kept in the settings
    func toggleAuto() {
        guard usesTools else { return }
        let value = runner.permissions.auto ? "ask" : "auto"
        runner.permissions.set("LOTUS_AI_PERM_MODE", value)
        runner.resetAllowances()
        saveSetting("LOTUS_AI_PERM_MODE", value)
    }

    // Reads keys while the AI works: questions get them, esc stops the answer
    private func watch(_ keys: KeyQueue, _ work: Task<String, Error>) async {
        while !Task.isCancelled {
            let k = await keys.next()
            if k == .cancelled { return }
            if interaction.deliver(k) { continue }
            if k == .esc || k == .ctrlC {
                Spinner.shared.setLabel("Stopping")
                work.cancel()
            }
        }
    }

    // One message from the user, with all tool steps. `improve`: the message may be improved first (/enhance)
    func ask(_ text: String, tools: Bool = true, improve: Bool = true) async {
        var text = text
        if improve && enhanceMode != "off" {
            if let why = Enhance.skip(text) {
                Log.write("DEBUG", "Improve prompt: sent as typed (\(why))")
            } else {
                guard let better = await improvePrompt(text) else { return }    // stopped: nothing is sent
                text = better
            }
        }
        if !conversation.turns.isEmpty && provider.usedTokens > provider.budget * 3 / 4 {
            await compact(automatic: true)
        }
        var retried = false
        while true {
            Spinner.shared.start("Thinking")
            let runner = tools && usesTools ? self.runner : nil
            let provider = self.provider
            let work = Task { try await provider.send(text, tools: runner) }
            currentWork = work
            let watcher = keys.map { k in Task { await self.watch(k, work) } }
            let result = await work.result
            currentWork = nil
            watcher?.cancel()
            Spinner.shared.stop()
            Renderer.shared.endBlock()
            switch result {
            case .success(let answer):
                remember(text, answer)
                return
            case .failure(let error):
                if error is ContextFull && !retried {
                    retried = true
                    await compact(automatic: true)
                    continue
                }
                if isCancellation(error) {
                    Renderer.shared.info("⎿  Stopped")
                    emit("\n")
                    remember(text, "(The user stopped this answer.)")
                    return
                }
                if error is ContextFull {
                    Renderer.shared.error("This is too long for \(provider.label)", "Try a shorter message, /clear, or a provider with more room (/model).")
                } else if let e = error as? AIError {
                    Renderer.shared.error(e.title, e.detail)
                } else {
                    Renderer.shared.error("Something went wrong", error.localizedDescription)
                }
                _ = self.runner.takeActions()
                return
            }
        }
    }

    // Stops the answer that is being written (the web chat's stop button; the terminal uses esc)
    func stop() { currentWork?.cancel() }

    // The message rewritten into a clear prompt (data/ai/system.md "## enhance") – or the original when that
    // fails or takes longer than 30 seconds; nil when the user stopped it (esc) or chose not to send it
    private func improvePrompt(_ original: String) async -> String? {
        guard let instructions = Agent.promptSections["enhance"], !instructions.isEmpty else { return original }
        Spinner.shared.start("Improving your prompt")
        let provider = self.provider
        let request = Enhance.request(original, after: conversation.turns)
        let late = Enhance.Late()
        let work = Task { try await provider.rewrite(system: instructions, prompt: request) }
        currentWork = work
        let timer = Task {
            try? await Task.sleep(nanoseconds: Enhance.timeout * 1_000_000_000)
            if !Task.isCancelled { late.set(); work.cancel() }
        }
        let watcher = keys.map { k in Task { await self.watch(k, work) } }
        let result = await work.result
        currentWork = nil
        timer.cancel()
        watcher?.cancel()
        Spinner.shared.stop()
        let improved: String
        switch result {
        case .success(let reply):
            guard let s = Enhance.clean(reply, original: original) else {
                Log.write("DEBUG", "Improve prompt: nothing better came back – sent as typed")
                return original
            }
            improved = s
        case .failure(let error):
            if late.isSet {
                Log.write("DEBUG", "Improve prompt: took longer than \(Enhance.timeout) s – sent as typed")
                return original
            }
            if isCancellation(error) {
                Renderer.shared.info("Stopped – nothing was sent.")
                emit("\n")
                return nil
            }
            Log.write("DEBUG", "Improve prompt failed – sent as typed: \((error as? AIError)?.title ?? error.localizedDescription)")
            return original
        }
        Log.write("DEBUG", "Improve prompt: \(original.count) → \(improved.count) characters")
        if enhanceMode == "ask" { return await choosePrompt(improved, original) }
        Renderer.shared.improvedPrompt(improved)
        return improved
    }

    // Ask mode: the web chat shows it in the page; the terminal shows it and waits for a key
    private func choosePrompt(_ improved: String, _ original: String) async -> String? {
        let choice: String
        if let choose = interaction.promptChooser {
            choice = await choose(improved)
        } else if let keys = keys {
            Renderer.shared.improvedPrompt(improved, asking: true)
            Out.shared.write("  \(Style.key)enter\(Style.reset) send it  \(Style.key)o\(Style.reset) send yours as typed  \(Style.key)esc\(Style.reset) cancel")
            var picked: String?
            while picked == nil {
                switch await keys.next() {
                case .enter: picked = "improved"
                case .char("o"), .char("O"): picked = "original"
                case .esc, .ctrlC, .ctrlD, .cancelled: picked = "cancel"
                default: continue
                }
            }
            Out.shared.write("\r\u{1B}[2K")
            choice = picked!
        } else {
            return original           // nobody to ask: as typed
        }
        switch choice {
        case "improved":
            return improved
        case "original":
            Renderer.shared.info("Sent as you typed it.")
            emit("\n")
            return original
        default:
            Renderer.shared.info("Not sent.")
            emit("\n")
            return nil
        }
    }

    private func remember(_ question: String, _ answer: String) {
        let actions = runner.takeActions()
        var text = answer.isEmpty ? "(no text answer)" : answer
        if !actions.isEmpty { text += "\n\n[Done in this step: " + actions.joined(separator: "; ") + "]" }
        conversation.turns.append(Turn(role: "user", text: question))
        conversation.turns.append(Turn(role: "assistant", text: text))
        conversation.save()
        lastAnswer = answer
    }

    // Summarizes older messages so the conversation fits again
    func compact(automatic: Bool) async {
        guard !conversation.turns.isEmpty else {
            Renderer.shared.info("Nothing to compact yet.")
            return
        }
        Spinner.shared.start("Compacting the conversation")
        let small = provider.isSmall
        let instructions = """
            Summarize the conversation below so it can be continued without it. Keep the user's goals and preferences, \
            decisions, important facts and numbers, file names and paths that were read or changed, commands that were run \
            and their results, and what is still open. Write compact notes, at most \(small ? 120 : 400) words.
            """
        do {
            let summary = try await provider.complete(system: instructions, prompt: conversation.asText(limit: small ? 7000 : 300_000))
            Spinner.shared.stop()
            if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { conversation.summary = summary }
        } catch {
            Spinner.shared.stop()
        }
        conversation.turns = Array(conversation.turns.suffix(2))
        conversation.save()
        resetProvider()
        Renderer.shared.info(automatic ? "✻ The conversation got long – older messages are now kept as a summary." : "✻ Compacted – older messages are now kept as a summary.")
        emit("\n")
    }

    // The first permission: work on this Mac at all, or only talk
    func applyTools(_ on: Bool) {
        usesTools = on
        try? switchTo(provider: config.provider, model: config.model)
    }

    func switchTo(provider kind: String, model: String) throws {
        var c = config
        c.provider = kind
        c.model = model
        let p = try Agent.makeProvider(c, runner: runner, tools: usesTools)
        config = c
        provider = p
        resetProvider()
    }

    // Saves a choice into the Lotus settings file, through Lotus itself
    func saveSetting(_ key: String, _ value: String) {
        let known = ["LOTUS_AI_PROVIDER", "LOTUS_AI_MODEL", "LOTUS_AI_EFFORT", "LOTUS_AI_ENHANCE"] + Permissions.items.map(\.key)
        guard known.contains(key), !config.root.isEmpty else { return }
        let script = #"setopt extendedglob; source "$1/lib/core.zsh" && lotus_load && typeset -g "$2=$3" && lotus_save"#
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-fc", script, "lotus", config.root, key, value]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}

// ── Who can answer ────────────────────────────────────────────
// The same list for /model in the terminal and the web chat's settings

struct ModelChoice {
    let label: String
    let kind: String          // apple · local · claude · ollama · openai
    let model: String
}

extension Agent {
    // the model on this Mac (lotus ai local) answers through its own server, as an OpenAI-compatible AI
    var onThisMac: Bool { config.provider == "openai" && !(ProcessInfo.processInfo.environment["LOTUS_AI_LABEL"] ?? "").isEmpty }

    func modelChoices() async -> [ModelChoice] {
        var options: [ModelChoice] = []
        let have = Set(config.available)
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleProvider.availability() == "available" {
            options.append(ModelChoice(label: "Apple Intelligence – on this Mac, private, free", kind: "apple", model: ""))
        }
        #endif
        // The model on this Mac (lotus ai local) runs as a server that Lotus starts before /ai opens
        if have.contains("local") {
            let name = config.localLabel.isEmpty ? "Model on this Mac" : config.localLabel
            options.append(ModelChoice(label: "\(name) – on this Mac, private, free", kind: "local", model: ""))
        }
        if !config.claudeKey.isEmpty {
            options.append(ModelChoice(label: "Claude Opus 5.5 – the best for most work", kind: "claude", model: "claude-opus-5-5"))
            options.append(ModelChoice(label: "Claude Sonnet 5.5 – fast and strong", kind: "claude", model: "claude-sonnet-5-5"))
            options.append(ModelChoice(label: "Claude Haiku 4.5 – quickest and cheapest", kind: "claude", model: "claude-haiku-4-5"))
            options.append(ModelChoice(label: "Claude Fable 5.1 – the most capable, costs more", kind: "claude", model: "claude-fable-5-1"))
        }
        for m in await OllamaProvider.installedModels() {
            options.append(ModelChoice(label: "Ollama · \(m) – on this Mac", kind: "ollama", model: m))
        }
        if have.contains("openai") && !config.openaiURL.isEmpty {
            let host = URL(string: config.openaiURL)?.host ?? config.openaiURL
            options.append(ModelChoice(label: "\(config.model.isEmpty ? "gpt-4o-mini" : config.model) · \(host)", kind: "openai",
                                       model: config.provider == "openai" ? config.model : ""))
        }
        return options
    }

    func isCurrent(_ c: ModelChoice) -> Bool {
        onThisMac ? c.kind == "local" : c.kind == config.provider && (c.model == config.model || c.kind == "apple")
    }
}

// ── The AI terminal ───────────────────────────────────────────

enum TUI {
    static let commands = [
        SlashCommand(name: "/help", help: "what you can do here"),
        SlashCommand(name: "/model", help: "choose the AI (Apple, Claude, this Mac, Ollama …)"),
        SlashCommand(name: "/login", help: "connect Claude with an API key"),
        SlashCommand(name: "/effort", help: "how hard the AI thinks"),
        SlashCommand(name: "/enhance", help: "improve your prompts before the AI sees them – off, on or ask"),
        SlashCommand(name: "/permissions", help: "what the AI may do on this Mac – ask first or auto"),
        SlashCommand(name: "/auto", help: "auto mode on or off – it asks only when unsure (also ⇧⇥)"),
        SlashCommand(name: "/clear", help: "start a new conversation"),
        SlashCommand(name: "/compact", help: "summarize the conversation to free up room"),
        SlashCommand(name: "/context", help: "how full the memory is"),
        SlashCommand(name: "/memory", help: "what I remember about you – /memory clear forgets it"),
        SlashCommand(name: "/copy", help: "copy the last answer"),
        SlashCommand(name: "/exit", help: "back to the shell"),
    ]

    static let effortNames = ["low": "quick", "medium": "balanced", "high": "thorough", "max": "maximum"]

    static func welcome(_ agent: Agent) {
        let width = min(max(40, Term.width - 1), 76)
        let home = NSHomeDirectory()
        let path = agent.cwd.path.hasPrefix(home) ? "~" + agent.cwd.path.dropFirst(home.count) : agent.cwd.path
        let thinks = "\(agent.provider.label) \(Style.dim)· thinks \(effortNames[agent.config.effort] ?? agent.config.effort)\(Style.reset)"
        var rows: [String]
        if let pet = Pet.current {
            // the pet sits on the left, like a little mascot
            let artWidth = pet.art.map { cellWidth($0) }.max() ?? 0
            let text = [
                "\(Style.bold)Lotus AI\(Style.reset)",
                thinks,
                "\(Style.dim)\(clip(String(path), max(10, width - artWidth - 12)))\(Style.reset)",
                "\(Style.dim)\(pet.name) keeps you company\(Style.reset)",
            ]
            rows = [""]
            for i in 0..<max(pet.art.count, text.count) {
                let a = i < pet.art.count ? pet.art[i] : ""
                let pad = String(repeating: " ", count: max(0, artWidth - cellWidth(a)))
                rows.append(" " + pet.color + a + Style.reset + pad + "   " + (i < text.count ? text[i] : ""))
            }
            rows.append("")
        } else {
            rows = [
                "\(Style.logo)✻\(Style.reset) \(Style.bold)Lotus AI\(Style.reset)",
                "",
                "  " + thinks,
                "  \(Style.dim)\(clip(String(path), width - 8))\(Style.reset)",
            ]
        }
        var out = "\n" + frame(rows, width: width)
        if agent.usesTools {
            out += "  \(Style.dim)Ask anything, or let me work in this folder: create files, change code, run commands.\(Style.reset)\n"
            out += agent.runner.permissions.auto
                ? "  \(Style.dim)Auto mode: I work on my own and ask only when I am unsure (⇧⇥ or /permissions). /help shows more.\(Style.reset)\n"
                : "  \(Style.dim)I ask before I change anything (⇧⇥ auto mode, /permissions). /help shows what else you can do.\(Style.reset)\n"
        } else {
            out += "  \(Style.dim)Ask me anything. Chat only for now – /permissions lets me work on this Mac again.\(Style.reset)\n"
        }
        if agent.enhanceMode != "off" {
            out += "  \(Style.dim)Your prompts are improved before the AI sees them\(agent.enhanceMode == "ask" ? " – you choose each time" : "") (/enhance).\(Style.reset)\n"
        }
        if agent.config.claudeKey.isEmpty {
            out += "  \(Style.dim)Tip:\(Style.reset) \(Style.logo)/login\(Style.reset) \(Style.dim)connects Claude – the strongest AI for code and longer work.\(Style.reset)\n"
        }
        if !agent.conversation.isEmpty {
            let mins = max(1, Int(Date().timeIntervalSince(agent.conversation.updated) / 60))
            let n = agent.conversation.turns.count / 2
            out += "  \(Style.logo)↺\(Style.reset) \(Style.dim)Continuing our conversation from \(mins) min ago (\(n) \(n == 1 ? "message" : "messages")) · /clear starts fresh\(Style.reset)\n"
        }
        Out.shared.write(out + "\n")
    }

    static func run(_ config: Config) async -> Int32 {
        guard Term.isTTY else {
            FileHandle.standardError.write(Data("The AI terminal needs an interactive terminal.\n".utf8))
            return 1
        }
        let keys = KeyQueue()
        RawMode.enable()
        KeyReader(queue: keys).start()
        defer { RawMode.disable() }

        let agent: Agent
        do {
            agent = try Agent(config: config, keys: keys, memory: true)
        } catch let e as AIError {
            Renderer.shared.error(e.title, e.detail)
            return 1
        } catch {
            Renderer.shared.error("The AI could not start", error.localizedDescription)
            return 1
        }
        welcome(agent)
        let box = InputBox(keys: keys, commands: commands, historyFile: config.stateDir.appendingPathComponent("history"))
        box.status = { agent.statusText }
        box.autoMode = { agent.autoMode }
        box.onBacktab = { agent.toggleAuto() }

        while true {
            guard let line = await box.read() else { break }
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if text.hasPrefix("/"), let word = text.split(separator: " ").first, !word.dropFirst().contains("/") {
                if await command(String(word).lowercased(), String(text.dropFirst(word.count)).trimmingCharacters(in: .whitespaces), agent, keys) { break }
                continue
            }
            await agent.ask(line)
            keys.clear()
        }
        if agent.restartForLocal {
            Out.shared.write("  \(Style.dim)Starting the model on this Mac – this conversation continues there.\(Style.reset)\n")
            return 75
        }
        Out.shared.write("  \(Style.dim)See you. /ai brings me back – I remember this conversation for an hour.\(Style.reset)\n")
        return 0
    }

    // Returns true when the user wants to leave
    static func command(_ cmd: String, _ arg: String, _ agent: Agent, _ keys: KeyQueue) async -> Bool {
        switch cmd {
        case "/exit", "/quit", "/q", "/bye":
            return true
        case "/help", "/?":
            var out = "  \(Style.bold)Commands\(Style.reset)\n"
            for c in commands { out += "  \(Style.logo)\(c.name.padding(toLength: 10, withPad: " ", startingAt: 0))\(Style.reset) \(c.help)\n" }
            out += "\n  \(Style.bold)Keys\(Style.reset)\n"
            out += "  \(Style.dim)enter send · option+enter or \\ then enter: new line · ↑↓ earlier messages\(Style.reset)\n"
            out += "  \(Style.dim)esc stops an answer · ctrl-c clears the line · ctrl-d leaves\(Style.reset)\n"
            out += "\n  \(Style.bold)What I can do\(Style.reset)\n"
            out += "  \(Style.dim)Read, search, create and change files in this folder and run commands – I always ask first.\(Style.reset)\n"
            out += "  \(Style.dim)I remember the conversation; when it gets long, older parts become a summary.\(Style.reset)\n\n"
            Out.shared.write(out)
        case "/clear", "/new", "/reset":
            agent.conversation.clear()
            agent.resetProvider()
            agent.lastAnswer = ""
            Out.shared.write("\u{1B}[2J\u{1B}[H")
            welcome(agent)
        case "/compact":
            await agent.compact(automatic: false)
        case "/memory":
            if arg.lowercased() == "clear" {
                Renderer.shared.info(Memory.clear() ? "Forgotten – I start fresh." : "The memory is not available here.")
                agent.resetProvider()
                emit("\n")
                return false
            }
            let facts = Memory.facts()
            var out = "  \(Style.bold)What I remember\(Style.reset)  \(Style.dim)from earlier conversations\(Style.reset)\n"
            if facts.isEmpty {
                out += "  \(Style.dim)Nothing yet. Tell me things worth knowing – \"remember that I …\" – or I keep them myself.\(Style.reset)\n"
            } else {
                for f in facts { out += "  \(Style.logo)·\(Style.reset) \(clip(f, max(20, Term.width - 6)))\n" }
            }
            if let p = Memory.path {
                let home = NSHomeDirectory()
                out += "  \(Style.dim)\(p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p) · edit it freely · /memory clear forgets everything\(Style.reset)\n"
            }
            if let notes = agent.folderNotes() { out += "  \(Style.dim)This folder: I follow \(notes.name).\(Style.reset)\n" }
            Out.shared.write(out + "\n")
        case "/context":
            let used = agent.provider.usedTokens, budget = agent.provider.budget
            var out = "  \(Style.bold)Memory\(Style.reset)  \(agent.provider.label)\n"
            let barWidth = 30
            let filled = min(barWidth, used * barWidth / max(1, budget))
            out += "  \(Style.logo)" + String(repeating: "■", count: filled) + Style.dim + String(repeating: "·", count: barWidth - filled) + Style.reset
            out += "  \(agent.contextPercent)%  \(Style.dim)(about \(used) of \(budget) tokens)\(Style.reset)\n"
            let n = agent.conversation.turns.count / 2
            out += "  \(Style.dim)\(n) \(n == 1 ? "message" : "messages")\(agent.conversation.summary.isEmpty ? "" : " + a summary of earlier ones") · compacts itself at 75%\(Style.reset)\n\n"
            Out.shared.write(out)
        case "/copy":
            guard !agent.lastAnswer.isEmpty else { Renderer.shared.info("No answer to copy yet."); break }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
            let pipe = Pipe()
            p.standardInput = pipe
            try? p.run()
            pipe.fileHandleForWriting.write(Data(agent.lastAnswer.utf8))
            try? pipe.fileHandleForWriting.close()
            p.waitUntilExit()
            Renderer.shared.info("Copied the last answer.")
            emit("\n")
        case "/effort":
            let levels = ["low", "medium", "high", "max"]
            var pick = levels.firstIndex(of: arg.lowercased())
            if pick == nil {
                let items = ["Quick – short answers, fast", "Balanced", "Thorough – thinks before it answers", "Maximum – takes the most time"]
                pick = await menu("How hard should the AI think?", items, selected: levels.firstIndex(of: agent.config.effort) ?? 2, keys: keys)
            }
            if let i = pick {
                agent.config.effort = levels[i]
                try? agent.switchTo(provider: agent.config.provider, model: agent.config.model)
                agent.saveSetting("LOTUS_AI_EFFORT", levels[i])
                Renderer.shared.info("The AI now thinks \(effortNames[levels[i]] ?? levels[i]).")
                emit("\n")
            }
        case "/enhance", "/improve":
            let modes = Enhance.modes
            var pick = modes.firstIndex(of: arg.lowercased())
            if pick == nil {
                let items = ["Off – messages go as you type them",
                             "On – improved into a clear prompt, shown and sent",
                             "Ask – improved and shown first: enter sends it, o yours, esc nothing"]
                pick = await menu("Improve your prompts before the AI sees them?", items, selected: modes.firstIndex(of: agent.enhanceMode) ?? 0, keys: keys)
            }
            if let i = pick {
                agent.enhanceMode = modes[i]
                agent.saveSetting("LOTUS_AI_ENHANCE", modes[i])
                Renderer.shared.info(["off": "Messages go as you type them.",
                                      "on": "Messages are improved into a clear prompt first – short ones (3 words or fewer) and commands go as typed.",
                                      "ask": "Messages are improved first, and you decide each time: enter sends the improved one, o yours."][modes[i]] ?? "")
                emit("\n")
            }
        case "/permissions", "/perms", "/allow":
            await permissionsMenu(agent, keys)
        case "/auto":
            guard agent.usesTools else {
                Renderer.shared.info("Working on this Mac is off – /permissions turns it on first.")
                emit("\n")
                break
            }
            if (arg == "on" && !agent.autoMode) || (arg == "off" && agent.autoMode) || arg.isEmpty { agent.toggleAuto() }
            Renderer.shared.info(agent.autoMode
                ? "Auto mode: I work on my own and ask only when I am unsure – deleting, pushing, installing, other folders, private files."
                : "Ask first: I ask before I change anything.")
            emit("\n")
        case "/model", "/models", "/provider":
            await chooseModel(agent, keys)
            return agent.restartForLocal
        case "/login", "/connect", "/key":
            await login(agent, keys)
        default:
            let known = commands.map(\.name)
            let close = known.first { $0.hasPrefix(String(cmd.prefix(3))) }
            Renderer.shared.info("Unknown command \(cmd).\(close.map { " Did you mean \($0)?" } ?? "") /help lists all.")
            emit("\n")
        }
        return false
    }

    // What the AI may do on this Mac: enter changes the choice of the line, the settings keep it
    static func permissionsMenu(_ agent: Agent, _ keys: KeyQueue) async {
        var sel = 0
        while true {
            var items = Permissions.items.map { item in
                item.label.padding(toLength: 40, withPad: " ", startingAt: 0) + Permissions.words(agent.runner.permissions.value(item.key), item.key, auto: agent.runner.permissions.auto)
            }
            items.append("Done")
            guard let i = await menu("What may the AI do on this Mac?", items, selected: sel, keys: keys),
                  i < Permissions.items.count else { break }
            sel = i
            let key = Permissions.items[i].key
            let value = agent.runner.permissions.next(key)
            agent.runner.permissions.set(key, value)
            agent.runner.resetAllowances()
            agent.saveSetting(key, value)
            if key == "LOTUS_AI_TOOLS" { agent.applyTools(value != "0") }
        }
        Renderer.shared.info(agent.runner.permissions.auto
            ? "Auto mode: I ask only when unsure – deleting, pushing, installing, other folders, private files. ⇧⇥ switches."
            : "Dangerous commands and private files (keys, .env) always ask first. ⇧⇥ switches to auto mode.")
        emit("\n")
    }

    // Connects Claude: opens the key page, takes the pasted key (hidden), checks it and keeps it in the Keychain
    static func login(_ agent: Agent, _ keys: KeyQueue) async {
        var out = "  \(Style.bold)Connect Claude\(Style.reset)\n"
        out += "  \(Style.dim)1\(Style.reset)  Sign in at console.anthropic.com and click \"Create Key\" (any name, e.g. Lotus).\n"
        out += "  \(Style.dim)2\(Style.reset)  Copy the key and paste it here. Lotus checks it and keeps it in your Keychain.\n"
        out += "  \(Style.dim)Claude is paid per use by Anthropic – a typical question costs well under one cent.\(Style.reset)\n\n"
        out += "  Open the key page in your browser? \(Style.dim)[Y/n]\(Style.reset) "
        Out.shared.write(out)
        let answer = await keys.next()
        let open = !(answer == .char("n") || answer == .char("N") || answer == .esc || answer == .ctrlC)
        Out.shared.write(open ? "yes\n" : "no\n")
        if open {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["https://console.anthropic.com/settings/keys"]
            try? p.run()
        }
        for _ in 0..<3 {
            guard let key = await readSecret("  Paste your key \(Style.dim)(hidden, enter when done)\(Style.reset): ", keys) else {
                Renderer.shared.info("Cancelled.")
                emit("\n")
                return
            }
            guard key.hasPrefix("sk-ant-"), key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                Out.shared.write("  \(Style.red)That is not a Claude API key – they start with sk-ant-.\(Style.reset)\n")
                continue
            }
            Spinner.shared.hint = "one moment"
            Spinner.shared.start("Checking the key with Claude")
            let status = await checkClaudeKey(key)
            Spinner.shared.stop()
            Spinner.shared.hint = "esc to stop"
            if status == 401 || status == 403 {
                Out.shared.write("  \(Style.red)Claude did not accept this key. Copy it again (all of it) or create a new one.\(Style.reset)\n")
                continue
            }
            if status != 200 {
                Out.shared.write("  \(Style.dim)Claude could not be reached to check the key – it is saved anyway.\(Style.reset)\n")
            }
            guard saveClaudeKey(key) else {
                Renderer.shared.error("The key could not be saved in the Keychain", "Try again, or set ANTHROPIC_API_KEY in your ~/.zshrc.")
                return
            }
            agent.config.claudeKey = key
            do {
                try agent.switchTo(provider: "claude", model: agent.config.model.hasPrefix("claude-") ? agent.config.model : "")
                agent.saveSetting("LOTUS_AI_PROVIDER", "claude")
                Out.shared.write("  \(Style.key)✓\(Style.reset) Claude is connected – now answering: \(Style.bold)\(agent.provider.label)\(Style.reset). The conversation continues.\n")
                Out.shared.write("  \(Style.dim)/model switches between Opus, Sonnet and Haiku.\(Style.reset)\n\n")
            } catch let e as AIError {
                Renderer.shared.error(e.title, e.detail)
            } catch {}
            return
        }
    }

    static func readSecret(_ prompt: String, _ keys: KeyQueue) async -> String? {
        var text = ""
        func draw() {
            let shown = text.isEmpty ? "" : String(repeating: "•", count: min(12, text.count)) + String(text.suffix(4))
            Out.shared.write("\r\u{1B}[2K" + prompt + Style.dim + shown + Style.reset)
        }
        draw()
        while true {
            switch await keys.next() {
            case .char(let c): if !c.isWhitespace { text.append(c) }
            case .paste(let s): text += s.filter { !$0.isWhitespace }
            case .backspace: if !text.isEmpty { text.removeLast() }
            case .ctrlU: text = ""
            case .enter:
                Out.shared.write("\n")
                let clean = text.filter { !$0.isWhitespace }
                return clean.isEmpty ? nil : clean
            case .esc, .ctrlC, .ctrlD, .cancelled:
                Out.shared.write("\n")
                return nil
            default: break
            }
            draw()
        }
    }

    static func checkClaudeKey(_ key: String) async -> Int {
        let messages = ProcessInfo.processInfo.environment["LOTUS_AI_CLAUDE_URL"] ?? "https://api.anthropic.com/v1/messages"
        var req = URLRequest(url: URL(string: messages.replacingOccurrences(of: "/v1/messages", with: "/v1/models"))!)
        req.timeoutInterval = 20
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        guard let (_, response) = try? await HTTP.session.data(for: req) else { return 0 }
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    // Through the security tool's stdin, so the key never shows up on a command line
    static func saveClaudeKey(_ key: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["-i"]
        let pipe = Pipe()
        p.standardInput = pipe
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let account = ProcessInfo.processInfo.environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? "lotus"
        pipe.fileHandleForWriting.write(Data("add-generic-password -U -s lotus-ai-claude -a \(account) -w \(key)\n".utf8))
        try? pipe.fileHandleForWriting.close()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func chooseModel(_ agent: Agent, _ keys: KeyQueue) async {
        var options = await agent.modelChoices()
        if agent.config.claudeKey.isEmpty {
            options.append(ModelChoice(label: "Claude – connect now (paste an API key)", kind: "login", model: ""))
        }
        guard !options.isEmpty else {
            Renderer.shared.info("No other AI found. Install Ollama or add a Claude key.")
            emit("\n")
            return
        }
        let onThisMac = agent.onThisMac
        let current = options.firstIndex { agent.isCurrent($0) } ?? 0
        guard let i = await menu("Which AI should answer?", options.map(\.label), selected: current, keys: keys) else { return }
        let o = options[i]
        if o.kind == "login" {
            await login(agent, keys)
            return
        }
        if o.kind == "local" {
            if onThisMac {
                Renderer.shared.info("Already answering: \(agent.provider.label).")
                emit("\n")
                return
            }
            agent.saveSetting("LOTUS_AI_PROVIDER", "local")
            agent.restartForLocal = true
            return
        }
        do {
            try agent.switchTo(provider: o.kind, model: o.model)
            agent.saveSetting("LOTUS_AI_PROVIDER", o.kind)
            agent.saveSetting("LOTUS_AI_MODEL", o.model)
            Renderer.shared.info("Now answering: \(agent.provider.label). The conversation continues.")
        } catch let e as AIError {
            Renderer.shared.error(e.title, e.detail)
        } catch {}
        emit("\n")
    }
}

// ── Entry ─────────────────────────────────────────────────────

@main
struct LotusAI {
    static func readPrompt(_ args: [String]) -> String {
        var prompt = args.joined(separator: " ")
        if prompt == "-" || prompt.isEmpty {
            prompt = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        return prompt
    }

    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        var args = Array(CommandLine.arguments.dropFirst())
        let mode = args.first ?? "--tui"
        if mode.hasPrefix("--") { args.removeFirst() }
        let config = Config.fromEnvironment()

        switch mode {
        case "--check":
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                print(AppleProvider.availability())
                return
            }
            #endif
            print("unavailable: needs macOS 26")

        case "--tui":
            exit(await TUI.run(config))

        case "--serve":
            guard let port = args.first.flatMap({ Int($0) }), (1024...65535).contains(port) else {
                FileHandle.standardError.write(Data("Usage: lotus-ai --serve <port 1024–65535>\n".utf8))
                exit(2)
            }
            exit(await WebServer.run(config, port: port))

        case "--port-check":
            guard let port = args.first.flatMap({ Int($0) }), (1...65535).contains(port) else { exit(2) }
            print(Net.isFree(port, lan: args.dropFirst().first == "1") ? "free" : "used")

        case "--once":
            let prompt = readPrompt(args)
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { exit(1) }
            let interactive = Term.isTTY
            let keys: KeyQueue? = interactive ? KeyQueue() : nil
            if let k = keys {
                RawMode.enable()
                KeyReader(queue: k).start()
            }
            defer { RawMode.disable() }
            do {
                let agent = try Agent(config: config, keys: keys, memory: true)
                emit("\n")
                await agent.ask(prompt)
            } catch let e as AIError {
                Renderer.shared.error(e.title, e.detail)
                RawMode.disable()
                exit(1)
            } catch {
                exit(1)
            }

        case "--task", "--plain":
            let prompt = readPrompt(args)
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { exit(1) }
            let plain = mode == "--plain"
            Renderer.shared.quiet = plain
            Spinner.shared.hint = "ctrl-c to stop"
            do {
                let agent = try Agent(config: config, keys: nil, memory: false, tools: false)
                if let custom = ProcessInfo.processInfo.environment["LOTUS_AI_INSTRUCTIONS"], !custom.isEmpty {
                    agent.provider.reset(system: custom + "\nAnswer in the user's language.", history: [])
                } else {
                    agent.provider.reset(system: agent.systemPrompt(tools: false), history: [])
                }
                if !plain { emit("\n") }
                if plain {
                    // Output for other programs: no spinner, no colors
                    do {
                        _ = try await agent.provider.send(prompt, tools: nil)
                        print("")
                    } catch let e as AIError {
                        FileHandle.standardError.write(Data("\(e.title)\n\(e.detail)\n".utf8))
                        exit(1)
                    }
                } else {
                    await agent.ask(prompt, tools: false, improve: false)
                }
            } catch let e as AIError {
                if plain { FileHandle.standardError.write(Data("\(e.title)\n\(e.detail)\n".utf8)) } else { Renderer.shared.error(e.title, e.detail) }
                exit(1)
            } catch {
                exit(1)
            }

        default:
            FileHandle.standardError.write(Data("Unknown option \(mode)\n".utf8))
            exit(2)
        }
    }
}
