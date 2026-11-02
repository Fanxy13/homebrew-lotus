// Lotus AI – Apple Intelligence: the on-device model through Apple's FoundationModels framework.
// Its window is small and fixed by Apple – 4096 tokens for the instructions, the tool definitions, the conversation, what
// the tools return and the answer together – so Lotus spends it carefully (the rules are in Small.swift): each request
// gets only the tools it needs, described briefly, and the conversation gets the room that is left. A bigger change is
// planned and done one step at a time, each step in a fresh session that is told what is done already, so a long task
// never fills the window. When the model stops answering, fills its window or starts repeating itself, Lotus goes on in a
// fresh session by itself – and when the agent lets it go on (App.swift), it goes on with the same task and its tools.

#if canImport(FoundationModels)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FoundationModels
import NaturalLanguage

// The language a message is written in, e.g. "German" – the small model needs to be told
func languageName(_ text: String) -> String? {
    guard text.split(separator: " ").count >= 3,
          let code = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue,
          let name = Locale(identifier: "en").localizedString(forLanguageCode: code) else { return nil }
    return name
}

// What the tools did in the task at hand: written by the tools as they run, read between the sessions
final class WorkJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func take() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let taken = lines
        lines = []
        return taken
    }
}

// What has been shown of the answer that is being written – kept when a session fails on the way, so nothing of it is lost
final class ShownText: @unchecked Sendable {
    private let lock = NSLock()
    private var parts: [String] = []
    private var current = ""

    func set(_ text: String) {
        lock.lock()
        current = text
        lock.unlock()
    }

    // after a tool call the model starts a new response: the text so far is one part
    func next() {
        lock.lock()
        if !current.isEmpty { parts.append(current) }
        current = ""
        lock.unlock()
    }

    func take() -> String {
        lock.lock()
        defer { lock.unlock() }
        let all = (parts + [current]).filter { !$0.isEmpty }.joined(separator: "\n\n")
        parts = []
        current = ""
        return all
    }
}

@available(macOS 26.0, *)
struct AppleTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let spec: ToolSpec
    let runner: ToolRunner
    let parameters: GenerationSchema
    let progress: Watchdog.Progress
    let journal: WorkJournal

    // The small model gets the tool described briefly (Small.swift)
    init(spec full: ToolSpec, runner: ToolRunner, progress: Watchdog.Progress, journal: WorkJournal) {
        let spec = SmallModel.shortened(full)
        self.spec = spec
        self.runner = runner
        self.progress = progress
        self.journal = journal
        let props = spec.params.map { p in
            DynamicGenerationSchema.Property(
                name: p.name, description: p.description,
                schema: p.isInt ? DynamicGenerationSchema(type: Int.self) : DynamicGenerationSchema(type: String.self),
                isOptional: !p.required)
        }
        let root = DynamicGenerationSchema(name: spec.name, description: spec.description, properties: props)
        self.parameters = (try? GenerationSchema(root: root, dependencies: []))
            ?? (try! GenerationSchema(root: DynamicGenerationSchema(name: spec.name, properties: []), dependencies: []))
    }

    var name: String { spec.name }
    var description: String { spec.description }

    func call(arguments: GeneratedContent) async throws -> String {
        let args = HTTP.parse(arguments.jsonString) ?? [:]
        progress.begin()
        let out = await runner.run(spec.name, args)
        progress.end()
        journal.add(SmallModel.logLine(spec.name, args, out.text, error: out.isError))
        return out.isError ? "Error: " + out.text : out.text
    }
}

@available(macOS 26.0, *)
final class AppleProvider: Provider, @unchecked Sendable {
    private let model = SystemLanguageModel.default
    private let effort: String
    private let toolProgress = Watchdog.Progress()
    private let journal = WorkJournal()
    private var tools: [AppleTool] = []        // every tool; a request gets those it needs (Small.swift)
    private var system = ""
    private var chatSystem = ""
    private var history: [Turn] = []
    private var task: Work?                    // the task of the last message: the agent may let it go on
    var continuing = false                     // set by the agent: this message lets the last task go on (App.swift)
    private(set) var stopped = Stop.done       // .stepLimit: a step did not get through – the agent lets it go on from there

    // A task: the request, what it needs, its plan, how far it got and what was done
    private struct Work {
        let request: String
        let earlier: String                    // the exchange before it, briefly – a short follow-up needs it
        let kind: SmallModel.Kind
        let steps: [String]
        let language: String?
        var done = 0
        var log: [String] = []
    }

    // What one request in a session gave: the text, whether it was cut for going in circles, what the tools did – and
    // whether it did not get through even in fresh sessions
    private struct Outcome {
        var text: String
        var circled: Bool
        var lines: [String]
        var unfinished = false
    }

    init(effort: String, runner: ToolRunner?) {
        self.effort = effort
        if let runner = runner {
            runner.outputLimit = 1400
            // Lotus plans the steps for Apple Intelligence (below) – the plan tool is for the bigger models
            tools = ToolCatalog.all.filter { $0.name != "plan" }.map { spec in
                AppleTool(spec: spec, runner: runner, progress: toolProgress, journal: journal)
            }
        }
    }

    static func availability() -> String {
        switch SystemLanguageModel.default.availability {
        case .available: return "available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "unavailable: this Mac does not support Apple Intelligence"
            case .appleIntelligenceNotEnabled: return "unavailable: turn on Apple Intelligence in System Settings"
            case .modelNotReady: return "unavailable: the model is still downloading – try again later"
            @unknown default: return "unavailable: \(reason)"
            }
        }
    }

    var label: String { "Apple Intelligence" }
    var budget: Int { SmallModel.window }
    // The conversation as it would have to fit into the window – beyond three quarters the agent sums it up (App.swift)
    var usedTokens: Int { SmallModel.tokens(system) + history.reduce(0) { $0 + SmallModel.tokens($1.text) } }
    var isSmall: Bool { true }

    func reset(system: String, history: [Turn]) {
        reset(system: system, chatSystem: system, history: history)
    }

    func reset(system: String, chatSystem: String, history: [Turn]) {
        self.system = system
        self.chatSystem = chatSystem
        self.history = history
        task = nil
    }

    // A session for one request: the instructions, only the tools it needs and – for a conversation – as much of the
    // conversation as fits beside them, the newest first
    private func session(_ kind: SmallModel.Kind, request: String, conversation: Bool) -> LanguageModelSession {
        let names = SmallModel.toolNames(kind, request: request, lotus: ToolCatalog.lotus.map(\.name))
        let picked = tools.filter { names.contains($0.spec.name) }
        let instructions = picked.isEmpty ? chatSystem : system
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [.text(Transcript.TextSegment(content: instructions))],
                                                  toolDefinitions: picked.map { Transcript.ToolDefinition(tool: $0) }))
        ]
        if conversation {
            let room = SmallModel.historyRoom(instructions: SmallModel.tokens(instructions), tools: SmallModel.toolTokens(picked.map(\.spec)),
                                              work: !picked.isEmpty)
            for t in SmallModel.recent(history, room: room) {
                let seg: [Transcript.Segment] = [.text(Transcript.TextSegment(content: t.text))]
                entries.append(t.role == "user" ? .prompt(Transcript.Prompt(segments: seg)) : .response(Transcript.Response(assetIDs: [], segments: seg)))
            }
        }
        let use: [any Tool] = picked
        return LanguageModelSession(model: model, tools: use, transcript: Transcript(entries: entries))
    }

    // The last exchange, briefly: a short follow-up ("make it blue") needs it
    private func earlier() -> String {
        guard let u = history.last(where: { $0.role == "user" }), let a = history.last(where: { $0.role == "assistant" }) else { return "" }
        return "\(clip(u.text.replacingOccurrences(of: "\n", with: " "), 200)) – \(clip(a.text.replacingOccurrences(of: "\n", with: " "), 300))"
    }

    // Decides what the message needs (a fixed choice – reliable on the small model), then plans the work in plain text
    private func triage(_ text: String, earlier: String, language: String?) async -> (kind: SmallModel.Kind, steps: [String]) {
        let context = earlier.isEmpty ? "" : "Earlier conversation: \(earlier)\n\n"
        let sorter = LanguageModelSession(model: model, instructions: """
            You sort requests to an assistant in the macOS terminal that can use files and commands.
            change: the request needs files or folders to be created, changed or deleted, or a command to be run.
            look: the request needs files or folders on this computer to be read, listed or searched, without changing them.
            lotus: the request asks Lotus to do something for the user: open or install an app, the weather, play or pause music, change the theme, open the clock, keep the Mac awake, turn a Lotus feature on or off, Minecraft servers.
            web: the request needs current information from the internet – news, the newest versions, prices, weather, results, anything recent – or asks to search or look something up online.
            chat: anything that can be answered with words alone – questions, timeless facts, explanations, stories, texts, small talk.
            A request that names a file (such as main.py or notes.txt), a folder or "this folder" is never chat.
            Use the earlier conversation to understand short follow-ups.
            Examples: "what is a closure in Swift?" chat · "write a poem about autumn" chat · "what is in this folder?" look · \
            "what does main.py do?" look · "make a website about cats" change · "rename the .txt files to .md" change · \
            "what is the newest version of Node.js?" web · "news about Apple today" web · "play some music" lotus · "open Safari" lotus
            """)
        let choice = DynamicGenerationSchema(type: String.self, guides: [.anyOf(["chat", "look", "change", "web", "lotus"])])
        let root = DynamicGenerationSchema(name: "Decision", properties: [
            DynamicGenerationSchema.Property(name: "kind", description: "chat, look, change, web or lotus", schema: choice)
        ])
        var kind = SmallModel.Kind.chat
        if let schema = try? GenerationSchema(root: root, dependencies: []) {
            let request = context + "Request: " + text
            let picked = try? await Watchdog.run(idle: 8) { progress -> String in
                var last: GeneratedContent?
                for try await snap in sorter.streamResponse(to: request, schema: schema, options: GenerationOptions(sampling: .greedy)) {
                    last = snap.rawContent
                    progress.tick()
                }
                return (try? last?.value(String.self, forProperty: "kind")) ?? "chat"
            }
            kind = picked.flatMap(SmallModel.Kind.init(rawValue:)) ?? .chat
        }
        // "turn on caffeine", "open Safari", "play music": Lotus itself
        if kind == .chat, !ToolCatalog.lotus.isEmpty, text.range(of: AppleProvider.lotusWords, options: [.regularExpression, .caseInsensitive]) != nil {
            kind = .lotus
        }
        // "search the web", "the newest …", "today": the internet, also when the sorter thought it was a chat
        if kind == .chat, text.range(of: AppleProvider.webWords, options: [.regularExpression, .caseInsensitive]) != nil {
            kind = .web
        }
        // A file name or path in the message: the AI may at least look
        if kind == .chat, text.range(of: #"(~/|\./|/Users/|\b[\w-]+\.(py|js|ts|tsx|jsx|html|css|md|txt|json|swift|sh|zsh|rb|go|rs|java|kt|c|cpp|h|m|yml|yaml|toml|csv|xml|php|sql|ini|cfg|log)\b)"#, options: .regularExpression) != nil {
            kind = .look
        }
        Log.write("DEBUG", "Apple Intelligence sorted the request as \(kind.rawValue)")
        guard kind == .look || kind == .change, ["high", "max", "ultra"].contains(effort) else { return (kind, []) }

        let planner = LanguageModelSession(model: model, instructions: """
            You plan work for an assistant in the macOS terminal that can list, read, create and edit files and run commands. \
            Reply with 2 to 5 numbered steps for the request, one per line, in the right order. Each step is one thing the \
            assistant does with one or two tool calls, at most 14 words, and names the file or the command – for example \
            "Write index.html with the sections of the page". Only what the user asked for; when it is quick, the last step \
            checks the result (read the file back, run the program). No code, no other text.
            """)
        let lang = language.map { "\n(Write the steps in \($0).)" } ?? ""
        let request = context + "Request: " + text + lang
        let reply = try? await Watchdog.run(idle: 8) { progress -> String in
            var last = ""
            for try await snap in planner.streamResponse(to: request, options: GenerationOptions(temperature: 0.2)) {
                last = snap.content
                progress.tick()
            }
            return last
        }
        var steps: [String] = []
        for line in (reply ?? "").split(separator: "\n") {
            var l = line.trimmingCharacters(in: .whitespaces)
            guard let first = l.first, first.isNumber || first == "-" || first == "•" else { continue }
            l = String(l.drop(while: { $0.isNumber || $0 == "." || $0 == ")" || $0 == "-" || $0 == "•" || $0 == " " }))
            if !l.isEmpty { steps.append(l) }
        }
        return (kind, Array(steps.prefix(5)))
    }

    // "Merk dir, dass mein Lieblingsessen Pizza ist" → "The user's favourite food is pizza."
    private func factToRemember(_ text: String) async -> String? {
        let session = LanguageModelSession(model: model, instructions: """
            The user wants something remembered. Write it as one short fact about the user, in the user's language, \
            in the third person ("The user …" / "Der Nutzer …"). Only the fact, nothing else.
            """)
        let root = DynamicGenerationSchema(name: "Memory", properties: [
            DynamicGenerationSchema.Property(name: "fact", description: "the fact, one sentence", schema: DynamicGenerationSchema(type: String.self))
        ])
        guard let schema = try? GenerationSchema(root: root, dependencies: []) else { return nil }
        let fact = try? await Watchdog.run(idle: 8) { progress -> String in
            var last: GeneratedContent?
            for try await snap in session.streamResponse(to: text, schema: schema, options: GenerationOptions(sampling: .greedy)) {
                last = snap.rawContent
                progress.tick()
            }
            return (try? last?.value(String.self, forProperty: "fact")) ?? ""
        }
        let f = (fact ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return f.count >= 3 ? f : nil
    }

    static let lotusWords = #"\b(open (the )?(app|clock)|install|theme|clock|keep (my mac |the mac )?awake|caffeine|stay awake|play|pause|skip|next song|music|minecraft|turn (on|off)|feature|öffne|installier\w*|uhr|wach|musik|spiel\w*|ouvre|installe|horloge|musique|abre|instala|reloj|música)\b"#
    static let webWords = #"\b(search|google|look (it )?up|online|internet|web|latest|newest|current|today|news|price|weather|recherch\w*|such\w*|im (netz|internet|web)|neueste\w*|aktuell\w*|heute|nachrichten|preis\w*|wetter|cherche\w*|dernière?s?|busca\w*|último\w*)\b"#
    static let rememberWords = #"\b(remember|don't forget|merk (dir|es)|merke|vergiss nicht|souviens|retiens|recuerda|no olvides)\b"#

    static func answerIn(_ language: String?) -> String {
        language.map { "Answer in \($0)." } ?? "Answer in the language of the user's request."
    }

    // What the tools did (ToolRunner's actions): something changed – a file written or edited, a command run – or a change
    // the user or the settings did not allow. Reading and looking count as neither.
    static func changed(_ actions: ArraySlice<String>) -> Bool {
        actions.contains { $0.hasPrefix("Created") || $0.hasPrefix("Updated") || $0.hasPrefix("Edited") || $0.hasPrefix("Ran") }
    }
    static func refused(_ actions: ArraySlice<String>) -> Bool {
        actions.contains { $0.hasPrefix("The user declined") || $0.hasPrefix("Did not run") || $0.hasPrefix("Not allowed by the settings") }
    }

    // ── Asking the model ──────────────────────────────────────

    // One request to a session, streamed to the screen; a text that goes in circles is cut there. What was shown is kept
    // in `shown` as it comes, so a session that fails on the way loses nothing of it.
    private func stream(_ session: LanguageModelSession, _ request: String, temperature: Double, shown: ShownText) async throws -> (text: String, circled: Bool) {
        try await Watchdog.run(idle: 60, shared: toolProgress) { progress -> (text: String, circled: Bool) in
            var printed = ""
            var checked = 0
            for try await snapshot in session.streamResponse(to: request, options: GenerationOptions(temperature: temperature)) {
                progress.tick()
                let content = snapshot.content
                if content.hasPrefix(printed) {
                    Renderer.shared.textDelta(String(content.dropFirst(printed.count)))
                } else {
                    shown.next()
                    Renderer.shared.endBlock()
                    Renderer.shared.textDelta(content)
                }
                printed = content
                shown.set(content)
                // the same words again and again: cut after the first time, the rest is not waited for
                if content.utf8.count - checked >= 240 {
                    checked = content.utf8.count
                    if let cut = SmallModel.circles(content) {
                        shown.set(String(content[..<cut]))
                        return (shown.take(), true)
                    }
                }
            }
            return (shown.take(), false)
        }
    }

    // A request in a session, and what Lotus does when it goes wrong: when the model stops answering (a minute without a
    // word) or fills its window, a fresh session that is told how far the task got goes on – twice at most. A conversation
    // that does not fit is left to the agent, which sums it up and asks again (ContextFull, App.swift).
    private func generate(_ prompt: String, kind: SmallModel.Kind, request: String, conversation: Bool, temperature: Double,
                          log: [String], answerIn: String) async throws -> Outcome {
        var session = self.session(kind, request: request, conversation: conversation)
        var ask = prompt
        var said: [String] = []
        var lines: [String] = []
        var fresh = 0
        while true {
            let shown = ShownText()
            do {
                let r = try await stream(session, ask, temperature: temperature, shown: shown)
                said.append(r.text)
                lines += journal.take()
                return Outcome(text: said.filter { !$0.isEmpty }.joined(separator: "\n\n"), circled: r.circled, lines: lines)
            } catch {
                if Task.isCancelled || isCancellation(error) { throw error }
                let stalled = error is Watchdog.Stalled
                var full = false
                if let e = error as? LanguageModelSession.GenerationError, case .exceededContextWindowSize = e { full = true }
                if full && kind == .chat { throw ContextFull() }
                guard stalled || full else { throw error }
                said.append(shown.take())
                lines += journal.take()
                // twice in a fresh session did not get through: what it did is kept, and the agent lets it go on from there
                guard fresh < 2 else {
                    if kind == .chat { throw error }
                    return Outcome(text: said.filter { !$0.isEmpty }.joined(separator: "\n\n"), circled: false, lines: lines, unfinished: true)
                }
                fresh += 1
                Log.write("INFO", "Apple Intelligence \(stalled ? "stopped answering" : "filled its window") – a fresh session goes on (\(fresh)/2)")
                Renderer.shared.info(stalled
                    ? "↻ Apple Intelligence stopped answering – Lotus goes on in a fresh session (\(fresh)/2)"
                    : "↻ Apple Intelligence's window is full – Lotus goes on in a fresh session that knows what is done (\(fresh)/2)")
                Spinner.shared.start("Working")
                let sofar = said.filter { !$0.isEmpty }.joined(separator: " ").replacingOccurrences(of: "\n", with: " ")
                ask = SmallModel.continuePrompt(request: request, log: log + lines + (sofar.isEmpty ? [] : ["- you wrote: " + clip(sofar, 400)]),
                                                why: stalled ? "The last session stopped answering." : "The last session ran out of room.",
                                                answerIn: answerIn)
                session = self.session(kind, request: request, conversation: kind == .chat)
            }
        }
    }

    // ── One message ───────────────────────────────────────────

    func send(_ text: String, tools runner: ToolRunner?) async throws -> String {
        let goingOn = continuing
        continuing = false
        stopped = .done
        _ = journal.take()
        do {
            if goingOn, let w = task {
                let answer = try await goOn(w, why: text, runner: runner)
                // the request stays in the conversation once: what it said going on belongs to its answer
                if let last = history.indices.last, history[last].role == "assistant" {
                    history[last].text += "\n\n" + answer
                } else {
                    history.append(Turn(role: "assistant", text: answer))
                }
                return answer
            }
            let answer = try await answerNew(text, runner: runner)
            history.append(Turn(role: "user", text: text))
            history.append(Turn(role: "assistant", text: answer))
            return answer
        } catch is Watchdog.Stalled {
            throw AIError(title: "Apple Intelligence stopped responding",
                          detail: "Lotus went on in a fresh session twice. Send the message again, or say \"go on\".")
        } catch let error as LanguageModelSession.GenerationError {
            if isCancellation(error) || Task.isCancelled { throw CancellationError() }
            throw Self.explain(error)
        } catch {
            if isCancellation(error) || Task.isCancelled { throw CancellationError() }
            if error is AIError || error is ContextFull { throw error }
            throw AIError(title: "Apple Intelligence could not answer", detail: error.localizedDescription)
        }
    }

    // A new message: what it needs, its plan, the answer – and once more when it did not do what it said
    private func answerNew(_ text: String, runner: ToolRunner?) async throws -> String {
        let language = languageName(text)
        let answerIn = Self.answerIn(language)
        let before = earlier()
        var kind = SmallModel.Kind.chat
        var steps: [String] = []
        let canWork = runner != nil && !tools.isEmpty
        if canWork {
            Spinner.shared.setLabel("Planning")
            let t = await triage(text, earlier: before, language: language)
            if Task.isCancelled { throw CancellationError() }
            kind = t.kind
            steps = t.steps
        }
        task = Work(request: text, earlier: before, kind: kind, steps: steps, language: language)
        // a bigger change: Lotus carries out the plan one step at a time
        if kind == .change, let r = runner, steps.count >= 2 {
            return try await runSteps(r, answerIn: answerIn)
        }
        var prompt = text
        if kind == .look && steps.count >= 2 {
            Renderer.shared.endBlock()
            var out = "\(Style.dim)✻ Plan\(Style.reset)\n"
            for (i, s) in steps.enumerated() { out += "  \(Style.dim)\(i + 1). \(s)\(Style.reset)\n" }
            emit(out + "\n")
            Spinner.shared.start("Working")
            prompt += "\n\nSteps – do each one by calling a tool, do not just describe it:\n"
                + steps.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
                + "\nThen answer the request. " + answerIn
        }
        if canWork {
            switch kind {
            case .lotus where !ToolCatalog.lotus.isEmpty:
                prompt += "\n\n(Use the Lotus tool that fits. Say it is done only when the tool reported success; if it says the user has to decide, ask them.)"
            case .web:
                prompt += "\n\n(Search the web with web_search first – do not answer from memory. Look at all results: for the newest or latest of something, pick the highest version and the newest date. Read the best page with fetch_url if the snippets are not enough. Answer briefly and name the source.)"
            case .chat:
                if let r = runner, text.range(of: AppleProvider.rememberWords, options: [.regularExpression, .caseInsensitive]) != nil,
                   let fact = await factToRemember(text) {
                    // the small model's own tool call is unreliable here: Lotus keeps the fact itself, the model confirms
                    let saved = await r.run("remember", ["fact": fact])
                    prompt += saved.isError
                        ? "\n\n(Lotus could not keep this: \(saved.text) Tell the user in one sentence.)"
                        : "\n\n(Lotus has kept this for later conversations: \"\(fact)\". Tell the user in one short sentence that you will remember it – speak to them directly, as \"you\".)"
                }
            default:
                break
            }
        }
        if !prompt.contains(answerIn), let l = language, l != "English" { prompt += "\n\n(\(answerIn))" }
        let work = kind == .look || kind == .change
        Spinner.shared.setLabel(kind == .web ? "Searching the web" : work ? "Working" : "Thinking")
        let actionsBefore = runner?.actions.count ?? 0
        var out = try await generate(prompt, kind: kind, request: text, conversation: true, temperature: work ? 0.3 : 0.6, log: [], answerIn: answerIn)
        task?.log += out.lines
        if out.unfinished { stopped = .stepLimit }
        guard let r = runner, !Task.isCancelled, !out.unfinished else { return out.text }
        let new = r.actions.dropFirst(actionsBefore)
        if kind == .change && !Self.changed(new) && !Self.refused(new) {
            // the small model sometimes says it changed something without doing it: once more, in a fresh session that
            // knows what it did
            Renderer.shared.endBlock()
            emit("\(Style.dim)✻ Checking the work\(Style.reset)\n\n")
            Spinner.shared.start("Working")
            let log = task?.log ?? []
            let check = try await generate(SmallModel.continuePrompt(request: text, log: log,
                                                                     why: "Nothing has been changed yet, so the work is not done. Do every step that is still missing now, with write_file, edit_file or run_command.",
                                                                     answerIn: answerIn, earlier: before),
                                           kind: .change, request: text, conversation: false, temperature: 0.1, log: log, answerIn: answerIn)
            task?.log += check.lines
            out.text += "\n\n" + check.text
        } else if out.circled && work {
            // it went in circles: once more, told so
            Renderer.shared.info("↻ Apple Intelligence started repeating itself – Lotus cut it off and lets it go on")
            Spinner.shared.start("Working")
            let log = task?.log ?? []
            let again = try await generate(SmallModel.continuePrompt(request: text, log: log, why: "You started repeating yourself and were stopped.",
                                                                     answerIn: answerIn, earlier: before),
                                           kind: kind, request: text, conversation: false, temperature: 0.5, log: log, answerIn: answerIn)
            task?.log += again.lines
            out.text += "\n\n" + again.text
        } else if out.circled {
            Renderer.shared.info("✻ Apple Intelligence started repeating itself – Lotus cut it off there")
        }
        return out.text
    }

    // A bigger change, one step of the plan at a time: each step in a fresh session that knows the request, the plan and
    // what is done – so the window never fills up, and a step that ends early does not end the task
    private func runSteps(_ runner: ToolRunner, answerIn: String) async throws -> String {
        guard var w = task else { return "" }
        if w.done == 0 {
            Renderer.shared.toolHeader("Plan", "\(w.steps.count) steps")
            Renderer.shared.plan(w.steps.enumerated().map { (text: $1, state: $0 == 0 ? "doing" : "open") })
        }
        var said: [String] = []
        while w.done < w.steps.count {
            if Task.isCancelled { throw CancellationError() }
            let i = w.done
            let step = w.steps[i]
            Spinner.shared.start("Step \(i + 1) of \(w.steps.count)")
            let before = runner.actions.count
            var out = try await generate(SmallModel.stepPrompt(request: w.request, steps: w.steps, index: i, log: w.log, answerIn: answerIn, earlier: w.earlier),
                                         kind: .change, request: w.request + "\n" + step, conversation: false, temperature: 0.2, log: w.log, answerIn: answerIn)
            if out.unfinished {
                // the step did not get through even in fresh sessions: what is done is the answer for now, and the agent
                // lets it go on with this step (App.swift)
                w.log += out.lines
                task = w
                stopped = .stepLimit
                if !out.text.isEmpty { said.append(out.text) }
                return said.joined(separator: "\n\n")
            }
            // a step that should change something and changed nothing: once more, told so
            let first = runner.actions.dropFirst(before)
            if !Self.changed(first) && !Self.refused(first) && SmallModel.changes(step) && !Task.isCancelled {
                Renderer.shared.info("↻ Nothing was changed for this step yet – Lotus lets Apple Intelligence do it")
                Spinner.shared.start("Step \(i + 1) of \(w.steps.count)")
                let again = try await generate(SmallModel.stepAgain(request: w.request, step: step, log: w.log + out.lines, answerIn: answerIn),
                                               kind: .change, request: w.request + "\n" + step, conversation: false, temperature: 0.1,
                                               log: w.log + out.lines, answerIn: answerIn)
                out.text = [out.text, again.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
                out.lines += again.lines
            }
            let declined = Self.refused(runner.actions.dropFirst(before))
            w.log.append("Step \(i + 1) – \(step):" + (out.lines.isEmpty ? " " + clip(out.text.replacingOccurrences(of: "\n", with: " "), 160) : ""))
            w.log += out.lines
            w.done += 1
            task = w
            Renderer.shared.plan(w.steps.enumerated().map { (text: $1, state: $0 < w.done ? "done" : $0 == w.done ? "doing" : "open") }, update: true)
            if !out.text.isEmpty { said.append(out.text) }
            // the user (or the settings) said no to a change: the rest of the plan waits for them
            if declined && w.done < w.steps.count {
                w.log.append("A change was not allowed – the remaining steps were not done.")
                task = w
                break
            }
        }
        // the end: what was done, in a few sentences – the work is done even when this does not get through
        Renderer.shared.endBlock()
        Spinner.shared.start("Thinking")
        do {
            let summary = try await generate(SmallModel.summaryPrompt(request: w.request, log: w.log, answerIn: answerIn), kind: .chat,
                                             request: w.request, conversation: false, temperature: 0.3, log: [], answerIn: answerIn)
            said.append(summary.text)
        } catch {
            if Task.isCancelled || isCancellation(error) { throw error }
            Log.write("INFO", "Apple Intelligence did not sum up the work: \(error)")
        }
        return said.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    // Going on with the task of the last message, because the agent says so (it stopped too early, App.swift): the open
    // steps of its plan, or a fresh session told what is done and why it goes on – with the task's tools, not sorted again
    private func goOn(_ w: Work, why: String, runner: ToolRunner?) async throws -> String {
        let answerIn = Self.answerIn(w.language)
        if w.kind == .change, let r = runner, w.done < w.steps.count {
            return try await runSteps(r, answerIn: answerIn)
        }
        Spinner.shared.setLabel("Working")
        let out = try await generate(SmallModel.continuePrompt(request: w.request, log: w.log, why: why, answerIn: answerIn, earlier: w.earlier),
                                     kind: w.kind, request: w.request, conversation: w.kind == .chat, temperature: 0.3, log: w.log, answerIn: answerIn)
        task?.log += out.lines
        if out.unfinished { stopped = .stepLimit }
        return out.text
    }

    static func explain(_ error: LanguageModelSession.GenerationError) -> Error {
        switch error {
        case .exceededContextWindowSize:
            return ContextFull()
        case .guardrailViolation:
            return AIError(title: "Apple's safety filter stopped this answer", detail: "Try other words. /login connects Claude, which can answer instead.")
        case .refusal:
            return AIError(title: "Apple Intelligence declined this request", detail: "Try asking differently.")
        case .unsupportedLanguageOrLocale:
            return AIError(title: "Apple Intelligence does not support this language yet", detail: "Try English, or another provider in /model.")
        case .assetsUnavailable:
            return AIError(title: "The Apple Intelligence model is not ready", detail: "It may still be downloading. Try again later.")
        case .rateLimited, .concurrentRequests:
            return AIError(title: "Apple Intelligence is busy", detail: "Try again in a moment.")
        default:
            return AIError(title: "Apple Intelligence could not answer", detail: error.localizedDescription)
        }
    }

    func complete(system: String, prompt: String) async throws -> String {
        let s = LanguageModelSession(model: model, instructions: system)
        do {
            return try await s.respond(to: String(prompt.suffix(7000)), options: GenerationOptions(temperature: 0.3)).content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.explain(error)
        }
    }
}
#endif
