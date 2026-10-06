// lotus-ai – the AI terminal of Lotus. Built once on this Mac by lib/cmd/ai.zsh.
//
//   lotus-ai --tui            the full AI terminal (what /ai opens)
//   lotus-ai --once <text>    one message with memory and tools, then back to the shell
//   lotus-ai --task <text>    one answer without memory or tools (instructions: $LOTUS_AI_INSTRUCTIONS)
//   lotus-ai --plain <text>   like --task, plain text only (for other commands to read)
//   lotus-ai --check          is Apple Intelligence available?
//
// The provider, model, keys and colors come from environment variables set by lib/cmd/ai.zsh.
// Keys are never written to disk by this program.

import Foundation

struct Config {
    var provider: String
    var model: String
    var effort: String
    let claudeKey: String
    let openaiKey: String
    let openaiURL: String
    let stateDir: URL
    let available: [String]
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
    private let file: URL
    static let keepFor: TimeInterval = 3600

    private struct Stored: Codable {
        var turns: [Turn]
        var summary: String
        var updated: Double
    }

    init(file: URL) {
        self.file = file
        guard let data = try? Data(contentsOf: file),
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
        let s = Stored(turns: turns, summary: summary, updated: updated.timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: file, options: .atomic)
        chmod(file.path, 0o600)
    }

    func clear() {
        turns = []
        summary = ""
        try? FileManager.default.removeItem(at: file)
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
    let conversation: Conversation
    let runner: ToolRunner
    let interaction: Interaction
    let keys: KeyQueue?
    let cwd: URL
    let usesTools: Bool
    var lastAnswer = ""

    init(config: Config, keys: KeyQueue?, memory: Bool, tools: Bool = true) throws {
        self.config = config
        self.keys = keys
        usesTools = tools
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
            guard !c.claudeKey.isEmpty else { throw AIError(title: "No Claude API key yet", detail: "Add one with: lotus ai key claude") }
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
    func systemPrompt(tools: Bool) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short)
        let home = NSHomeDirectory()
        let dir = cwd.path == home ? "~" : cwd.path.hasPrefix(home + "/") ? "~/" + cwd.path.dropFirst(home.count + 1) : cwd.path
        var p: String
        if provider.isSmall {
            p = """
                You are Lotus AI, a helpful assistant\(tools ? " and coding agent" : "") in the user's macOS terminal.
                Working folder: \(dir). Today: \(date).\(config.name.isEmpty ? "" : " The user's name: \(config.name).")
                \(tools ? "Use the tools to look at files, create and change files, and run commands. The user approves every change and command. When asked to make or change something, really do it with the tools – do not only describe it. Write real, complete file content in the right language for the file type: HTML for .html, Python for .py, and so on." : "")
                Think step by step. Give complete, correct answers and complete code without placeholders. \
                When asked for a long text, write all of it. Answer in the user's language. Write in short paragraphs; use '-' lists only for real lists and fenced code blocks for code. No emoji.
                """
        } else {
            p = """
                You are Lotus AI, a capable assistant and coding agent inside the user's macOS terminal (the Lotus app).

                Environment: macOS \(os.majorVersion).\(os.minorVersion), shell zsh, working folder \(dir), today is \(date).\
                \(config.name.isEmpty ? "" : " The user's name is \(config.name).")

                """
            if tools {
                p += """
                    You can work on this Mac with tools: list_directory, read_file, search_files, write_file, edit_file and run_command. \
                    Reading in the working folder happens right away; the user approves every change and every command before it runs.

                    How to work:
                    - Take the time to think the task through. For anything beyond a quick question, work out the steps first, then carry them out one by one.
                    - When the user asks you to create, fix or change something, do it with the tools instead of only describing it.
                    - Look before you change: list folders and read the files you work on. Prefer edit_file for small changes and write_file for new files.
                    - Check your work when it is quick and safe: read the result back, run the program or the tests.
                    - Write complete, working code. Never leave placeholders such as "..." or "TODO: implement".
                    - Before a tool call, say in one short sentence what you are about to do. At the end, summarize what you did and how to use it.
                    - Do not delete or overwrite the user's work unless asked. Never use sudo: show the command and let the user run it.

                    """
            }
            p += """
                How to answer:
                - Be thorough and precise; answer the actual question, with the reasoning where it helps.
                - Answer in the language the user writes in.
                - This is a terminal: write short paragraphs, use '-' lists only for real lists, and fenced code blocks with a language for code. No tables, no emoji.
                """
        }
        if !conversation.summary.isEmpty {
            p += "\n\nSummary of the earlier part of this conversation:\n\(conversation.summary)"
        }
        return p
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

    // One message from the user, with all tool steps
    func ask(_ text: String, tools: Bool = true) async {
        if !conversation.turns.isEmpty && provider.usedTokens > provider.budget * 3 / 4 {
            await compact(automatic: true)
        }
        var retried = false
        while true {
            Spinner.shared.start("Thinking")
            let runner = tools && usesTools ? self.runner : nil
            let provider = self.provider
            let work = Task { try await provider.send(text, tools: runner) }
            let watcher = keys.map { k in Task { await self.watch(k, work) } }
            let result = await work.result
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
        guard ["LOTUS_AI_PROVIDER", "LOTUS_AI_MODEL", "LOTUS_AI_EFFORT"].contains(key), !config.root.isEmpty else { return }
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

// ── The AI terminal ───────────────────────────────────────────

enum TUI {
    static let commands = [
        SlashCommand(name: "/help", help: "what you can do here"),
        SlashCommand(name: "/model", help: "choose the AI (Apple, Claude, Ollama …)"),
        SlashCommand(name: "/effort", help: "how hard the AI thinks"),
        SlashCommand(name: "/clear", help: "start a new conversation"),
        SlashCommand(name: "/compact", help: "summarize the conversation to free up room"),
        SlashCommand(name: "/context", help: "how full the memory is"),
        SlashCommand(name: "/copy", help: "copy the last answer"),
        SlashCommand(name: "/exit", help: "back to the shell"),
    ]

    static let effortNames = ["low": "quick", "medium": "balanced", "high": "thorough", "max": "maximum"]

    static func welcome(_ agent: Agent) {
        let width = min(max(40, Term.width - 1), 76)
        let home = NSHomeDirectory()
        let path = agent.cwd.path.hasPrefix(home) ? "~" + agent.cwd.path.dropFirst(home.count) : agent.cwd.path
        let rows = [
            "\(Style.logo)✻\(Style.reset) \(Style.bold)Lotus AI\(Style.reset)",
            "",
            "  \(agent.provider.label) \(Style.dim)· thinks \(effortNames[agent.config.effort] ?? agent.config.effort)\(Style.reset)",
            "  \(Style.dim)\(clip(String(path), width - 8))\(Style.reset)",
        ]
        var out = "\n" + frame(rows, width: width)
        out += "  \(Style.dim)Ask anything, or let me work in this folder: create files, change code, run commands.\(Style.reset)\n"
        out += "  \(Style.dim)I ask before I change anything. /help shows what else you can do.\(Style.reset)\n"
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
        case "/model", "/models", "/provider":
            await chooseModel(agent, keys)
        default:
            let known = commands.map(\.name)
            let close = known.first { $0.hasPrefix(String(cmd.prefix(3))) }
            Renderer.shared.info("Unknown command \(cmd).\(close.map { " Did you mean \($0)?" } ?? "") /help lists all.")
            emit("\n")
        }
        return false
    }

    static func chooseModel(_ agent: Agent, _ keys: KeyQueue) async {
        var options: [(label: String, kind: String, model: String)] = []
        let have = Set(agent.config.available)
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleProvider.availability() == "available" {
            options.append(("Apple Intelligence – on this Mac, private, free", "apple", ""))
        }
        #endif
        if !agent.config.claudeKey.isEmpty {
            options.append(("Claude Opus 5.5 – the best for most work", "claude", "claude-opus-5-5"))
            options.append(("Claude Sonnet 5.5 – fast and strong", "claude", "claude-sonnet-5-5"))
            options.append(("Claude Haiku 4.5 – quickest and cheapest", "claude", "claude-haiku-4-5"))
            options.append(("Claude Fable 5.1 – the most capable, costs more", "claude", "claude-fable-5-1"))
        }
        for m in await OllamaProvider.installedModels() {
            options.append(("Ollama · \(m) – on this Mac", "ollama", m))
        }
        if have.contains("openai") && !agent.config.openaiURL.isEmpty {
            let host = URL(string: agent.config.openaiURL)?.host ?? agent.config.openaiURL
            options.append(("\(agent.config.model.isEmpty ? "gpt-4o-mini" : agent.config.model) · \(host)", "openai", agent.config.provider == "openai" ? agent.config.model : ""))
        }
        if agent.config.claudeKey.isEmpty {
            Renderer.shared.info("Claude: add a key with  lotus ai key claude  (in a normal terminal), then /model again.")
        }
        guard !options.isEmpty else {
            Renderer.shared.info("No other AI found. Install Ollama or add a Claude key.")
            emit("\n")
            return
        }
        let current = options.firstIndex { $0.kind == agent.config.provider && ($0.model == agent.config.model || $0.kind == "apple") } ?? 0
        guard let i = await menu("Which AI should answer?", options.map(\.label), selected: current, keys: keys) else { return }
        let o = options[i]
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
                    await agent.ask(prompt, tools: false)
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
