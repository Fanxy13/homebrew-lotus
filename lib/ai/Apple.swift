// Lotus AI – Apple Intelligence: the on-device model through Apple's FoundationModels framework.
// The model is small (a few thousand tokens of context), so Lotus plans first, keeps tool output
// short and compacts the conversation early.

#if canImport(FoundationModels)
import Foundation
import FoundationModels
import NaturalLanguage

// The language a message is written in, e.g. "German" – the small model needs to be told
func languageName(_ text: String) -> String? {
    guard text.split(separator: " ").count >= 3,
          let code = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue,
          let name = Locale(identifier: "en").localizedString(forLanguageCode: code) else { return nil }
    return name
}

@available(macOS 26.0, *)
struct AppleTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let spec: ToolSpec
    let runner: ToolRunner
    let onOutput: @Sendable (Int) -> Void
    let parameters: GenerationSchema
    let progress: Watchdog.Progress

    init(spec: ToolSpec, runner: ToolRunner, progress: Watchdog.Progress, onOutput: @escaping @Sendable (Int) -> Void) {
        self.spec = spec
        self.runner = runner
        self.progress = progress
        self.onOutput = onOutput
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
        let text = out.isError ? "Error: " + out.text : out.text
        onOutput(text.count)
        return text
    }
}

@available(macOS 26.0, *)
final class AppleProvider: Provider, @unchecked Sendable {
    private let model = SystemLanguageModel.default
    private var tools: [any Tool] = []
    private let effort: String
    private var system = ""
    private var chatSystem = ""
    private var history: [Turn] = []
    private var chars = 0
    private let counter = NSLock()
    private let toolProgress = Watchdog.Progress()

    init(effort: String, runner: ToolRunner?) {
        self.effort = effort
        if let runner = runner {
            runner.outputLimit = 1400
            tools = ToolCatalog.all.map { spec in
                AppleTool(spec: spec, runner: runner, progress: toolProgress) { [weak self] n in self?.add(n) }
            }
        }
    }

    private func add(_ n: Int) {
        counter.lock()
        chars += n
        counter.unlock()
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
    var budget: Int { 4096 }
    var usedTokens: Int { 600 + chars / 3 }
    var isSmall: Bool { true }

    func reset(system: String, history: [Turn]) {
        reset(system: system, chatSystem: system, history: history)
    }

    func reset(system: String, chatSystem: String, history: [Turn]) {
        self.system = system
        self.chatSystem = chatSystem
        self.history = history
        chars = system.count + recent().reduce(0) { $0 + $1.text.count }
    }

    // The newest messages that fit the small context
    private func recent() -> [Turn] {
        var picked: [Turn] = []
        var total = 0
        for t in history.reversed() {
            total += t.text.count
            if total > 3200 { break }
            picked.insert(t, at: 0)
        }
        while picked.first?.role == "assistant" { picked.removeFirst() }
        return picked
    }

    // A fresh session for this message: with tools for work, without for conversation
    private func session(work: Bool) -> LanguageModelSession {
        let use = work ? tools : []
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [.text(Transcript.TextSegment(content: work ? system : chatSystem))],
                                                  toolDefinitions: use.map { Transcript.ToolDefinition(tool: $0) }))
        ]
        for t in recent() {
            let seg: [Transcript.Segment] = [.text(Transcript.TextSegment(content: t.text))]
            entries.append(t.role == "user" ? .prompt(Transcript.Prompt(segments: seg)) : .response(Transcript.Response(assetIDs: [], segments: seg)))
        }
        return LanguageModelSession(model: model, tools: use, transcript: Transcript(entries: entries))
    }

    enum Kind { case chat, look, change }

    // Decides whether the message needs files or commands (a fixed choice – reliable on the small model),
    // then plans the work in plain text.
    private func triage(_ text: String, language: String?) async -> (kind: Kind, steps: [String]) {
        let context: String
        if let u = history.last(where: { $0.role == "user" }), let a = history.last(where: { $0.role == "assistant" }) {
            context = "Earlier conversation: \(u.text.prefix(200)) – \(a.text.prefix(300))\n\n"
        } else {
            context = ""
        }
        let sorter = LanguageModelSession(model: model, instructions: """
            You sort requests to an assistant in the macOS terminal that can use files and commands.
            change: the request needs files or folders to be created, changed or deleted, or a command to be run.
            look: the request needs files or folders on this computer to be read, listed or searched, without changing them.
            chat: anything that can be answered with words alone – questions, facts, explanations, stories, texts, small talk.
            A request that names a file (such as main.py or notes.txt), a folder or "this folder" is never chat.
            Use the earlier conversation to understand short follow-ups.
            """)
        let choice = DynamicGenerationSchema(type: String.self, guides: [.anyOf(["chat", "look", "change"])])
        let root = DynamicGenerationSchema(name: "Decision", properties: [
            DynamicGenerationSchema.Property(name: "kind", description: "chat, look or change", schema: choice)
        ])
        var kind = Kind.chat
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
            kind = picked == "change" ? .change : picked == "look" ? .look : .chat
        }
        // A file name or path in the message: the AI may at least look
        if kind == .chat, text.range(of: #"(~/|\./|/Users/|\b[\w-]+\.(py|js|ts|tsx|jsx|html|css|md|txt|json|swift|sh|zsh|rb|go|rs|java|kt|c|cpp|h|m|yml|yaml|toml|csv|xml|php|sql|ini|cfg|log)\b)"#, options: .regularExpression) != nil {
            kind = .look
        }
        guard kind != .chat, effort == "high" || effort == "max" else { return (kind, []) }

        let planner = LanguageModelSession(model: model, instructions: """
            You plan work for an assistant in the macOS terminal that can list, read, create and edit files and run commands. \
            Reply with 2 to 5 numbered steps for the request, one per line, at most 14 words each, in the right order. \
            Only steps the user asked for. No code, no other text.
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

    private func stream(_ session: LanguageModelSession, _ request: String, temperature: Double) async throws -> String {
        let toolProgress = self.toolProgress
        return try await Watchdog.run(idle: 60, shared: toolProgress) { progress -> String in
            var segments: [String] = []
            var printed = ""
            for try await snapshot in session.streamResponse(to: request, options: GenerationOptions(temperature: temperature)) {
                progress.tick()
                let content = snapshot.content
                if content.hasPrefix(printed) {
                    Renderer.shared.textDelta(String(content.dropFirst(printed.count)))
                } else {
                    if !printed.isEmpty { segments.append(printed) }
                    Renderer.shared.endBlock()
                    Renderer.shared.textDelta(content)
                }
                printed = content
            }
            segments.append(printed)
            return segments.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }

    func send(_ text: String, tools runner: ToolRunner?) async throws -> String {
        var prompt = text
        var kind = Kind.chat
        let language = languageName(text)
        let answerIn = language.map { "Answer in \($0)." } ?? "Answer in the language of my request."
        if runner != nil && !tools.isEmpty {
            Spinner.shared.setLabel("Planning")
            let t = await triage(text, language: language)
            if Task.isCancelled { throw CancellationError() }
            kind = t.kind
            if kind != .chat && (effort == "high" || effort == "max") && t.steps.count >= 2 {
                Renderer.shared.endBlock()
                var out = "\(Style.dim)✻ Plan\(Style.reset)\n"
                for (i, s) in t.steps.enumerated() { out += "  \(Style.dim)\(i + 1). \(s)\(Style.reset)\n" }
                emit(out + "\n")
                Spinner.shared.start("Working")
                prompt += "\n\nSteps – do each one by calling a tool, do not just describe it:\n"
                    + t.steps.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
                    + "\nWhen everything is done, say briefly what you changed. " + answerIn
            }
        }
        let work = kind != .chat
        if !prompt.contains(answerIn), let l = language, l != "English" { prompt += "\n\n(\(answerIn))" }
        Spinner.shared.setLabel(work ? "Working" : "Thinking")
        add(prompt.count)
        let session = self.session(work: work)
        let actionsBefore = runner?.actions.count ?? 0
        do {
            var answer = try await stream(session, prompt, temperature: work ? 0.3 : 0.6)
            // The small model sometimes says it changed something without doing it: check once
            if kind == .change, let r = runner, !Task.isCancelled {
                let new = r.actions.dropFirst(actionsBefore)
                let changed = new.contains { $0.hasPrefix("Created") || $0.hasPrefix("Updated") || $0.hasPrefix("Edited") || $0.hasPrefix("Ran") }
                let stopped = new.contains { $0.hasPrefix("The user declined") || $0.hasPrefix("Did not run") }
                if !changed && !stopped {
                    Renderer.shared.endBlock()
                    emit("\(Style.dim)✻ Checking the work\(Style.reset)\n\n")
                    Spinner.shared.start("Working")
                    let check = try await stream(session, """
                        Check yourself: nothing has been changed yet. Do every step that is still missing now, \
                        with write_file, edit_file or run_command. Then say in one or two sentences what you changed. \(answerIn)
                        """, temperature: 0.1)
                    answer += "\n\n" + check
                }
            }
            add(answer.count)
            history.append(Turn(role: "user", text: text))
            history.append(Turn(role: "assistant", text: answer))
            return answer
        } catch is Watchdog.Stalled {
            throw AIError(title: "Apple Intelligence stopped responding", detail: "Send the message again – it usually works the second time.")
        } catch let error as LanguageModelSession.GenerationError {
            if isCancellation(error) || Task.isCancelled { throw CancellationError() }
            throw Self.explain(error)
        } catch {
            if isCancellation(error) || Task.isCancelled { throw CancellationError() }
            if error is AIError || error is ContextFull { throw error }
            throw AIError(title: "Apple Intelligence could not answer", detail: error.localizedDescription)
        }
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
