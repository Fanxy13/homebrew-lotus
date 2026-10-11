// Lotus AI – the models: Claude API, Ollama and OpenAI-compatible APIs (Apple Intelligence is in Apple.swift).
// Each provider keeps the conversation in its own format and runs the tool loop for one message.

import Foundation

struct Turn: Codable {
    var role: String      // "user" or "assistant"
    var text: String
}

struct AIError: Error {
    let title: String
    var detail = ""
}

struct ContextFull: Error {}

// Why an answer ended – the agent lets the AI go on when it stopped before it was done (App.swift)
enum Stop { case done, ranOut, thoughtsOnly, empty, stepLimit }

protocol Provider: AnyObject {
    var label: String { get }
    var budget: Int { get }              // tokens the conversation may use before it is compacted
    var usedTokens: Int { get }
    var isSmall: Bool { get }            // small context: shorter prompts and tool output
    func reset(system: String, history: [Turn])
    // Small models get separate instructions for conversation without tools
    func reset(system: String, chatSystem: String, history: [Turn])
    // One user message, including all tool steps. Streams to the Renderer, returns the answer text.
    func send(_ text: String, tools: ToolRunner?) async throws -> String
    // A single answer without tools or output, e.g. for summaries
    func complete(system: String, prompt: String) async throws -> String
    // Like complete, but quick – little or no thinking: rewriting a message (/enhance, Enhance.swift)
    func rewrite(system: String, prompt: String) async throws -> String
    // Why the last send ended, and the thoughts of a reply that had nothing else
    var stopped: Stop { get }
    var lastThoughts: String { get }
    // The next sends think briefly: going on after the AI ran out of room
    var briefThinking: Bool { get set }
}

extension Provider {
    func reset(system: String, chatSystem: String, history: [Turn]) {
        reset(system: system, history: history)
    }

    func rewrite(system: String, prompt: String) async throws -> String {
        try await complete(system: system, prompt: prompt)
    }

    var stopped: Stop { .done }
    var lastThoughts: String { "" }
    var briefThinking: Bool { get { false } set {} }
}

func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let u = error as? URLError, u.code == .cancelled { return true }
    return (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled
}

// ── HTTP ──────────────────────────────────────────────────────

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 600
        c.timeoutIntervalForResource = 7200
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
    }

    static func parse(_ s: String) -> [String: Any]? {
        guard let d = s.data(using: .utf8) else { return nil }
        if let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { return j }
        // models on this Mac often write a long file into the arguments with real line breaks and tabs, or
        // with \' – not JSON, but clear: repaired, the call works instead of failing
        guard let fixed = repair(s).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: fixed)) as? [String: Any]
    }

    // Control characters inside strings escaped, escapes JSON does not know ("\'", "\ ") made plain
    static func repair(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count + 64)
        var inString = false
        var escaped = false
        for ch in s {
            if escaped {
                escaped = false
                if "\"\\/bfnrtu".contains(ch) { out.append("\\"); out.append(ch) } else { out.append(ch) }
                continue
            }
            guard inString else {
                if ch == "\"" { inString = true }
                out.append(ch)
                continue
            }
            switch ch {
            case "\\": escaped = true
            case "\"": inString = false; out.append(ch)
            case "\n": out += "\\n"
            case "\r", "\r\n": out += ch == "\r" ? "\\r" : "\\n"
            case "\t": out += "\\t"
            default:
                if let v = ch.unicodeScalars.first?.value, v < 0x20, ch.unicodeScalars.count == 1 {
                    out += String(format: "\\u%04x", v)
                } else {
                    out.append(ch)
                }
            }
        }
        return out
    }

    static func request(_ url: URL, body: Data, headers: [String: String]) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.httpBody = body
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }

    // Opens a streaming request; non-2xx answers come back as (status, body)
    static func open(_ req: URLRequest) async throws -> (URLSession.AsyncBytes, Int, String) {
        let (bytes, response) = try await session.bytes(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return (bytes, status, "") }
        var body = Data()
        for try await b in bytes {
            body.append(b)
            if body.count > 100_000 { break }
        }
        let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after") ?? ""
        return (bytes, status, String(decoding: body, as: UTF8.self) + (retryAfter.isEmpty ? "" : "\u{0}\(retryAfter)"))
    }

    static func errorMessage(_ body: String) -> String {
        let clean = body.components(separatedBy: "\u{0}").first ?? body
        if let j = parse(clean) {
            if let e = j["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let m = j["error"] as? String { return m }
            if let m = j["message"] as? String { return m }
        }
        return String(clean.prefix(300))
    }

    static func retryDelay(_ body: String, attempt: Int) -> Double {
        let parts = body.components(separatedBy: "\u{0}")
        if parts.count > 1, let s = Double(parts[1].trimmingCharacters(in: .whitespaces)) { return min(max(s, 1), 30) }
        return Double(2 << attempt)
    }

    static func connectionError(_ error: Error, _ service: String) -> AIError {
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return AIError(title: "No internet connection", detail: "\(service) needs the internet. Check the connection and try again.")
            case .cannotConnectToHost, .cannotFindHost:
                return AIError(title: "\(service) is not reachable", detail: u.localizedDescription)
            case .timedOut:
                return AIError(title: "\(service) took too long to answer", detail: "Try again in a moment.")
            default: break
            }
        }
        return AIError(title: "\(service) could not be reached", detail: error.localizedDescription)
    }
}

// Shared by the HTTP providers: what a tool call looks like once it has arrived
struct PendingCall {
    let id: String
    let name: String
    let args: [String: Any]?
    let raw: String
}

func runCalls(_ calls: [PendingCall], _ tools: ToolRunner) async -> [(PendingCall, ToolOutcome)] {
    var results: [(PendingCall, ToolOutcome)] = []
    for call in calls {
        if Task.isCancelled {
            results.append((call, ToolOutcome(text: "The user interrupted this.", isError: true)))
            continue
        }
        guard let args = call.args else {
            Renderer.shared.toolHeader(call.name, "")
            Renderer.shared.toolResult("The model sent arguments that are not valid JSON – it tries again", error: true)
            let start = String(call.raw.prefix(300))
            results.append((call, ToolOutcome(text: "INVALID_JSON: the arguments of \(call.name) were not valid JSON, so nothing happened. "
                + "Call \(call.name) again with valid JSON (escape quotes and line breaks in strings). For a long file, write it in "
                + "two or three parts: write_file with the first part, then edit_file to add the rest. They began with: \(start)", isError: true)))
            continue
        }
        results.append((call, await tools.run(call.name, args)))
    }
    return results
}

// ── Claude API ────────────────────────────────────────────────

final class ClaudeProvider: Provider {
    let model: String
    private let key: String
    private let effort: String
    private var system = ""
    private var messages: [[String: Any]] = []
    private var pendingToolIDs: [String] = []
    private var lastTokens = 0
    private(set) var stopped = Stop.done
    var briefThinking = false

    init(model: String, key: String, effort: String) {
        self.model = model.isEmpty ? "claude-opus-5-5" : model
        self.key = key
        self.effort = effort
    }

    static func name(_ id: String) -> String {
        // claude-opus-5-5 → Claude Opus 5.5
        let parts = id.split(separator: "-").map(String.init)
        guard parts.count >= 3, parts[0] == "claude" else { return id }
        let family = parts[1].prefix(1).uppercased() + parts[1].dropFirst()
        let version = parts.dropFirst(2).filter { $0.count <= 2 && Int($0) != nil }.joined(separator: ".")
        return "Claude \(family)\(version.isEmpty ? "" : " " + version)"
    }

    var label: String { ClaudeProvider.name(model) }
    var budget: Int { model.contains("haiku") ? 160_000 : 200_000 }
    var usedTokens: Int { lastTokens }
    var isSmall: Bool { false }

    // Claude 4.6 and newer think adaptively and take an effort level (Haiku from 5.5 on)
    private var adaptive: Bool {
        !(model.contains("-4-5") || model.contains("-4-1") || model.hasSuffix("-4-0") || model.contains("claude-3"))
    }

    // Lotus' levels as Claude's: xhigh came with Opus 4.7, so the 4.6 models get max for maximum
    private func claudeEffort(_ effort: String) -> String {
        let xhigh = model.contains("-4-6") ? "max" : "xhigh"
        return ["low": "low", "medium": "medium", "high": "high", "max": xhigh, "ultra": "max"][effort] ?? "high"
    }

    private var withFallbacks: Bool {
        ["claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-fable-5"].contains(model)
    }

    func reset(system: String, history: [Turn]) {
        self.system = system
        messages = []
        pendingToolIDs = []
        lastTokens = 0
        for t in history where !t.text.isEmpty {
            appendText(role: t.role, t.text)
        }
        if messages.first?["role"] as? String == "assistant" { messages.removeFirst() }
    }

    private func blocks(_ content: Any?) -> [[String: Any]] {
        if let s = content as? String { return [["type": "text", "text": s]] }
        return content as? [[String: Any]] ?? []
    }

    // A new message from the same side joins the last one (keeps the history append-only)
    private func appendText(role: String, _ text: String) {
        if let last = messages.last, last["role"] as? String == role {
            var content = blocks(last["content"])
            content.append(["type": "text", "text": text])
            messages[messages.count - 1]["content"] = content
        } else {
            messages.append(["role": role, "content": [["type": "text", "text": text]]])
        }
    }

    private func body(tools: Bool, system sys: String? = nil, messages msgs: [[String: Any]]? = nil, maxTokens: Int = 64000, effort level: String? = nil) -> [String: Any] {
        let effort = level ?? self.effort
        var b: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": [["type": "text", "text": sys ?? system]],
            "messages": msgs ?? messages,
            "cache_control": ["type": "ephemeral"],
        ]
        if tools {
            b["tools"] = ToolCatalog.all.map {
                ["name": $0.name, "description": $0.description, "input_schema": $0.jsonSchema, "eager_input_streaming": true] as [String: Any]
            }
        }
        if adaptive {
            b["thinking"] = ["type": "adaptive", "display": "summarized"]
            b["output_config"] = ["effort": claudeEffort(effort)]
            if effort == "ultra" && maxTokens == 64000 { b["max_tokens"] = 128_000 }      // room for the longest thinking
        } else if effort != "low" {
            b["thinking"] = ["type": "enabled", "budget_tokens": ["ultra": 48000, "max": 32000, "high": 16000][effort] ?? 6000]
        }
        if withFallbacks { b["fallbacks"] = "default" }
        return b
    }

    private var headers: [String: String] {
        var h = ["x-api-key": key, "anthropic-version": "2023-06-01"]
        if withFallbacks { h["anthropic-beta"] = "server-side-fallback-2026-07-01" }
        return h
    }

    private struct Reply {
        var content: [[String: Any]] = []
        var calls: [PendingCall] = []
        var text = ""
        var stop = ""
        var refusal = ""
    }

    private func stream(_ body: [String: Any], render: Bool) async throws -> Reply {
        let url = URL(string: ProcessInfo.processInfo.environment["LOTUS_AI_CLAUDE_URL"] ?? "https://api.anthropic.com/v1/messages")!
        var attempt = 0
        while true {
            let req = HTTP.request(url, body: HTTP.json(body), headers: headers)
            let bytes: URLSession.AsyncBytes, status: Int, errBody: String
            do {
                (bytes, status, errBody) = try await HTTP.open(req)
            } catch {
                if isCancellation(error) { throw CancellationError() }
                throw HTTP.connectionError(error, "The Claude API")
            }
            if status == 429 || status == 529 || status >= 500 {
                if attempt < 3 {
                    let wait = HTTP.retryDelay(errBody, attempt: attempt)
                    Spinner.shared.setLabel(status == 429 ? "Waiting for the rate limit" : "Claude is busy, trying again")
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    attempt += 1
                    continue
                }
            }
            if status != 200 { throw claudeError(status, HTTP.errorMessage(errBody)) }
            return try await read(bytes, render: render)
        }
    }

    private func claudeError(_ status: Int, _ message: String) -> AIError {
        switch status {
        case 401: return AIError(title: "The Claude API key was not accepted", detail: "Connect a new key with /login (or in the shell: lotus ai login)")
        case 403: return AIError(title: "This Claude API key may not use \(label)", detail: message)
        case 404: return AIError(title: "\(model) was not found", detail: "Choose another model with /model.  (\(message))")
        case 413: return AIError(title: "The conversation is too long", detail: "Use /compact or /clear.")
        case 429: return AIError(title: "Too many requests to the Claude API", detail: message)
        case 529: return AIError(title: "Claude is overloaded right now", detail: "Try again in a minute.")
        default: return AIError(title: "The Claude API answered with an error (\(status))", detail: message)
        }
    }

    private func read(_ bytes: URLSession.AsyncBytes, render: Bool) async throws -> Reply {
        var reply = Reply()
        var blocks: [Int: [String: Any]] = [:]
        var json: [Int: String] = [:]
        var inputTokens = 0, outputTokens = 0
        for try await line in bytes.lines {
            guard line.hasPrefix("data:"), let ev = HTTP.parse(String(line.dropFirst(5))) else { continue }
            switch ev["type"] as? String {
            case "message_start":
                if let m = ev["message"] as? [String: Any], let u = m["usage"] as? [String: Any] {
                    inputTokens = (u["input_tokens"] as? Int ?? 0) + (u["cache_read_input_tokens"] as? Int ?? 0) + (u["cache_creation_input_tokens"] as? Int ?? 0)
                }
            case "content_block_start":
                guard let i = ev["index"] as? Int, let b = ev["content_block"] as? [String: Any] else { break }
                blocks[i] = b
                if b["type"] as? String == "tool_use" {
                    json[i] = ""
                    if render {
                        let n = ToolCatalog.label(b["name"] as? String ?? "")
                        Renderer.shared.endBlock()
                        Spinner.shared.start(n == "Write" || n == "Edit" ? "Writing" : "Preparing \(n)")
                    }
                }
            case "content_block_delta":
                guard let i = ev["index"] as? Int, let d = ev["delta"] as? [String: Any] else { break }
                switch d["type"] as? String {
                case "text_delta":
                    let t = d["text"] as? String ?? ""
                    let before = blocks[i]?["text"] as? String ?? ""
                    blocks[i]?["text"] = before + t
                    reply.text += t
                    if render { Renderer.shared.textDelta(t) }
                case "thinking_delta":
                    let t = d["thinking"] as? String ?? ""
                    let before = blocks[i]?["thinking"] as? String ?? ""
                    blocks[i]?["thinking"] = before + t
                    if render { Renderer.shared.thinkingDelta(t) }
                case "signature_delta":
                    let before = blocks[i]?["signature"] as? String ?? ""
                    blocks[i]?["signature"] = before + (d["signature"] as? String ?? "")
                case "input_json_delta":
                    json[i] = (json[i] ?? "") + (d["partial_json"] as? String ?? "")
                default: break
                }
            case "content_block_stop":
                guard let i = ev["index"] as? Int, let raw = json[i] else { break }
                let parsed = raw.trimmingCharacters(in: .whitespaces).isEmpty ? [:] : HTTP.parse(raw)
                blocks[i]?["input"] = parsed ?? [:]
                blocks[i]?["_raw"] = raw
                blocks[i]?["_ok"] = parsed != nil
            case "message_delta":
                if let d = ev["delta"] as? [String: Any] {
                    reply.stop = d["stop_reason"] as? String ?? reply.stop
                    if let sd = d["stop_details"] as? [String: Any] { reply.refusal = sd["category"] as? String ?? "" }
                }
                if let u = ev["usage"] as? [String: Any] { outputTokens = u["output_tokens"] as? Int ?? outputTokens }
            case "error":
                let e = ev["error"] as? [String: Any]
                throw AIError(title: "The Claude API stopped with an error", detail: e?["message"] as? String ?? "")
            default: break
            }
        }
        if Task.isCancelled { throw CancellationError() }
        lastTokens = inputTokens + outputTokens

        // After a mid-answer fallback, model-internal blocks before the switch are not sent back
        let ordered = blocks.keys.sorted().compactMap { blocks[$0] }
        let lastFallback = ordered.lastIndex { $0["type"] as? String == "fallback" }
        for (i, b) in ordered.enumerated() {
            let type = b["type"] as? String ?? ""
            if type == "fallback" { continue }
            if let f = lastFallback, i < f, type != "text" { continue }
            var clean = b
            clean.removeValue(forKey: "_raw")
            clean.removeValue(forKey: "_ok")
            if type == "text", (clean["text"] as? String ?? "").isEmpty { continue }
            reply.content.append(clean)
            if type == "tool_use" {
                let ok = b["_ok"] as? Bool ?? true
                reply.calls.append(PendingCall(id: b["id"] as? String ?? "", name: b["name"] as? String ?? "",
                                               args: ok ? b["input"] as? [String: Any] : nil, raw: b["_raw"] as? String ?? ""))
            }
        }
        return reply
    }

    func send(_ text: String, tools: ToolRunner?) async throws -> String {
        appendText(role: "user", text)
        let firstIndex = messages.count - 1
        var answer: [String] = []
        defer { closePending() }
        stopped = .stepLimit
        for step in 0..<60 {
            let reply = try await stream(body(tools: tools != nil, effort: briefThinking ? "low" : nil), render: true)
            if reply.stop == "refusal" {
                Renderer.shared.endBlock()
                if step == 0 && messages.count - 1 == firstIndex { messages.removeLast() }
                throw AIError(title: "Claude declined this request", detail: reply.refusal.isEmpty ? "Try asking differently." : "Reason: \(reply.refusal)")
            }
            if !reply.content.isEmpty { messages.append(["role": "assistant", "content": reply.content]) }
            if !reply.text.isEmpty { answer.append(reply.text) }
            guard let tools = tools, !reply.calls.isEmpty else {
                stopped = reply.stop == "max_tokens" ? .ranOut : reply.text.isEmpty && answer.isEmpty ? .empty : .done
                break
            }
            pendingToolIDs = reply.calls.map(\.id)
            var results: [(PendingCall, ToolOutcome)]
            if reply.stop == "max_tokens" {
                results = reply.calls.map { ($0, ToolOutcome(text: "The input was cut off because the answer got too long. Split the work into smaller steps.", isError: true)) }
            } else {
                results = await runCalls(reply.calls, tools)
            }
            let content: [[String: Any]] = results.map { call, out in
                // a screenshot goes along, so Claude sees the page it built (view_page)
                guard let image = out.image else {
                    return ["type": "tool_result", "tool_use_id": call.id, "content": out.text, "is_error": out.isError]
                }
                return ["type": "tool_result", "tool_use_id": call.id, "is_error": out.isError, "content": [
                    ["type": "text", "text": out.text],
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]],
                ] as [[String: Any]]]
            }
            messages.append(["role": "user", "content": content])
            pendingToolIDs = []
            if Task.isCancelled { throw CancellationError() }
            Spinner.shared.start("Thinking")
        }
        return answer.joined(separator: "\n\n")
    }

    // An interrupted tool step still gets its results, so the next request is valid
    private func closePending() {
        guard !pendingToolIDs.isEmpty else { return }
        let content: [[String: Any]] = pendingToolIDs.map {
            ["type": "tool_result", "tool_use_id": $0, "content": "The user interrupted this.", "is_error": true]
        }
        messages.append(["role": "user", "content": content])
        pendingToolIDs = []
    }

    func complete(system sys: String, prompt: String) async throws -> String {
        let msgs: [[String: Any]] = [["role": "user", "content": [["type": "text", "text": prompt]]]]
        let reply = try await stream(body(tools: false, system: sys, messages: msgs, maxTokens: 16000, effort: "medium"), render: false)
        return reply.text
    }

    func rewrite(system sys: String, prompt: String) async throws -> String {
        let msgs: [[String: Any]] = [["role": "user", "content": [["type": "text", "text": prompt]]]]
        return try await stream(body(tools: false, system: sys, messages: msgs, maxTokens: 4000, effort: "low"), render: false).text
    }
}

// ── Ollama ────────────────────────────────────────────────────

final class OllamaProvider: Provider {
    let model: String
    private let effort: String
    private let base = OllamaProvider.baseURL

    static var baseURL: URL {
        URL(string: ProcessInfo.processInfo.environment["LOTUS_AI_OLLAMA_URL"] ?? "http://localhost:11434") ?? URL(string: "http://localhost:11434")!
    }
    private var messages: [[String: Any]] = []
    private var toolsWork = true
    private var thinkingWorks = true
    private var lastTokens = 0
    private(set) var stopped = Stop.done
    private(set) var lastThoughts = ""
    var briefThinking = false
    let contextSize = 16384

    init(model: String, effort: String) {
        self.model = model
        self.effort = effort
    }

    var label: String { "Ollama · \(model)" }
    var budget: Int { contextSize }
    var usedTokens: Int { lastTokens }
    var isSmall: Bool { true }

    static func installedModels() async -> [String] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 2
        guard let (data, _) = try? await HTTP.session.data(for: req),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let models = j["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    func reset(system: String, history: [Turn]) {
        messages = [["role": "system", "content": system]]
        for t in history where !t.text.isEmpty {
            messages.append(["role": t.role, "content": t.role == "assistant" ? ChannelSplit.answer(t.text) : t.text])
        }
        lastTokens = (system.count + history.reduce(0) { $0 + $1.text.count }) / 4
    }

    private func body(_ msgs: [[String: Any]], tools: Bool, think: Bool) -> [String: Any] {
        var b: [String: Any] = ["model": model, "messages": msgs, "stream": true, "keep_alive": "15m",
                                "options": ["num_ctx": contextSize]]
        if tools && toolsWork {
            b["tools"] = ToolCatalog.all.map {
                ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.jsonSchema]] as [String: Any]
            }
        }
        if think && thinkingWorks && effort != "low" { b["think"] = true }
        return b
    }

    private struct Reply {
        var text = ""
        var thoughts = ""
        var finish = ""
        var calls: [[String: Any]] = []
    }

    private func stream(_ msgs: [[String: Any]], tools: Bool, think: Bool, render: Bool) async throws -> Reply {
        let url = base.appendingPathComponent("api/chat")
        while true {
            let req = HTTP.request(url, body: HTTP.json(body(msgs, tools: tools, think: think)), headers: [:])
            let bytes: URLSession.AsyncBytes, status: Int, errBody: String
            do {
                (bytes, status, errBody) = try await HTTP.open(req)
            } catch {
                if isCancellation(error) { throw CancellationError() }
                throw AIError(title: "Ollama is not running", detail: "Open the Ollama app, then try again.")
            }
            if status != 200 {
                let msg = HTTP.errorMessage(errBody)
                if msg.contains("does not support tools") && toolsWork {
                    toolsWork = false
                    if render { Renderer.shared.info("\(model) cannot use tools, so it can only talk. For file access choose another model with /model (e.g. qwen3).") }
                    continue
                }
                if msg.contains("does not support thinking") && thinkingWorks {
                    thinkingWorks = false
                    continue
                }
                if status == 404 { throw AIError(title: "Ollama does not have the model \(model)", detail: "Download it with: ollama pull \(model)") }
                throw AIError(title: "Ollama answered with an error", detail: msg)
            }
            var reply = Reply()
            for try await line in bytes.lines {
                guard let j = HTTP.parse(line) else { continue }
                if let e = j["error"] as? String { throw AIError(title: "Ollama stopped with an error", detail: e) }
                if let m = j["message"] as? [String: Any] {
                    if let t = m["thinking"] as? String, !t.isEmpty {
                        reply.thoughts += t
                        if render { Renderer.shared.thinkingDelta(t) }
                    }
                    if let t = m["content"] as? String, !t.isEmpty {
                        reply.text += t
                        if render { Renderer.shared.textDelta(t) }
                    }
                    if let c = m["tool_calls"] as? [[String: Any]] { reply.calls += c }
                }
                if j["done"] as? Bool == true {
                    lastTokens = (j["prompt_eval_count"] as? Int ?? 0) + (j["eval_count"] as? Int ?? 0)
                    reply.finish = j["done_reason"] as? String ?? ""
                }
            }
            if Task.isCancelled { throw CancellationError() }
            return reply
        }
    }

    func send(_ text: String, tools: ToolRunner?) async throws -> String {
        messages.append(["role": "user", "content": text])
        var answer: [String] = []
        stopped = .stepLimit
        lastThoughts = ""
        var acted = false          // a tool call that worked – then a quiet end is the end
        for _ in 0..<40 {
            let reply = try await stream(messages, tools: tools != nil, think: !briefThinking, render: true)
            guard let tools = tools, !reply.calls.isEmpty else {
                // the end of this message – done, or it stopped too early (the agent lets it go on)
                stopped = EmptyReply.stop(finish: reply.finish, text: reply.text, thoughts: reply.thoughts, said: acted || !answer.isEmpty)
                lastThoughts = reply.thoughts
                if !reply.text.isEmpty {
                    messages.append(["role": "assistant", "content": reply.text])
                    answer.append(reply.text)
                }
                break
            }
            messages.append(["role": "assistant", "content": reply.text, "tool_calls": reply.calls])
            if !reply.text.isEmpty { answer.append(reply.text) }
            let calls: [PendingCall] = reply.calls.enumerated().map { i, c in
                let f = c["function"] as? [String: Any] ?? [:]
                var args = f["arguments"] as? [String: Any]
                if args == nil, let s = f["arguments"] as? String { args = HTTP.parse(s) }
                return PendingCall(id: c["id"] as? String ?? "call_\(i)", name: f["name"] as? String ?? "", args: args ?? [:], raw: "")
            }
            Renderer.shared.endBlock()
            for (call, out) in await runCalls(calls, tools) {
                messages.append(["role": "tool", "content": out.isError ? "Error: " + out.text : out.text, "tool_name": call.name])
                if !out.isError { acted = true }
            }
            if Task.isCancelled { throw CancellationError() }
            Spinner.shared.start("Thinking")
        }
        return answer.joined(separator: "\n\n")
    }

    func complete(system: String, prompt: String) async throws -> String {
        let msgs: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
        return try await stream(msgs, tools: false, think: false, render: false).text
    }
}

// ── OpenAI-compatible APIs ────────────────────────────────────

final class OpenAIProvider: Provider {
    let model: String
    private let base: String
    private let key: String
    private var messages: [[String: Any]] = []
    private var toolsWork = true
    private(set) var stopped = Stop.done
    private(set) var lastThoughts = ""
    var briefThinking = false
    private let effort: String

    init(model: String, base: String, key: String, effort: String = "high") {
        self.model = model.isEmpty ? "gpt-4o-mini" : model
        self.base = base.hasSuffix("/") ? String(base.dropLast()) : base
        self.key = key
        self.effort = effort
    }

    private var onThisMac: Bool { ["127.0.0.1", "localhost", "::1"].contains(URL(string: base)?.host ?? "") }

    // The answer ended without an end: the server stopped in the middle. For lotus ai local, the error
    // from its log (written in the last minute) says why
    private func brokeOff() -> AIError {
        guard onThisMac else {
            return AIError(title: "The AI service stopped in the middle of its answer", detail: "Try again – or choose another AI with /model.")
        }
        let cache = ProcessInfo.processInfo.environment["LOTUS_CACHE"] ?? NSHomeDirectory() + "/.cache/lotus"
        let log = cache + "/llm/server.log"
        var why = ""
        if let changed = (try? FileManager.default.attributesOfItem(atPath: log))?[.modificationDate] as? Date, changed.timeIntervalSinceNow > -60,
           let text = try? String(contentsOfFile: log, encoding: .utf8) {
            why = text.split(separator: "\n").last { $0.range(of: #"^[A-Za-z]*(Error|Exception)\b"#, options: .regularExpression) != nil }.map(String.init) ?? ""
        }
        Log.write("ERROR", "The model server broke off\(why.isEmpty ? "" : ": " + why)")
        return AIError(title: "The model on this Mac stopped in the middle of its answer",
                       detail: (why.isEmpty ? "" : "\(why)\n") + "Start it again: end the web chat or /ai and start it again. Details: \(log)")
    }

    // A model server on this Mac takes the thinking per message, so a new level counts at once
    // (gpt-oss knows low, medium and high; others only thinking on or off)
    private var thinking: [String: Any] {
        guard onThisMac else { return [:] }
        if briefThinking || effort == "low" { return ["chat_template_kwargs": ["reasoning_effort": "low", "enable_thinking": false]] }
        return ["chat_template_kwargs": ["reasoning_effort": effort == "medium" ? "medium" : "high", "enable_thinking": true]]
    }

    // A model on this Mac (lotus ai local) brings its own name and context window
    var label: String {
        if let l = ProcessInfo.processInfo.environment["LOTUS_AI_LABEL"], !l.isEmpty { return l }
        return "\(model) · \(URL(string: base)?.host ?? base)"
    }
    var budget: Int { Int(ProcessInfo.processInfo.environment["LOTUS_AI_CONTEXT"] ?? "").map { max(4096, $0) } ?? 100_000 }
    var usedTokens: Int { messages.reduce(0) { $0 + "\($1["content"] ?? "")".count } / 4 }
    var isSmall: Bool { budget <= 16_384 }

    func reset(system: String, history: [Turn]) {
        messages = [["role": "system", "content": system]]
        for t in history where !t.text.isEmpty {
            messages.append(["role": t.role, "content": t.role == "assistant" ? ChannelSplit.answer(t.text) : t.text])
        }
    }

    private struct Reply {
        var text = ""
        var thoughts = ""
        var finish = ""
        var calls: [PendingCall] = []
        var rawCalls: [[String: Any]] = []
    }

    private func stream(_ msgs: [[String: Any]], tools: Bool, render: Bool, extra: [String: Any] = [:]) async throws -> Reply {
        guard let url = URL(string: base + "/chat/completions") else { throw AIError(title: "The AI URL is not valid", detail: base) }
        while true {
            var b: [String: Any] = ["model": model, "messages": msgs, "stream": true]
            b.merge(extra) { _, new in new }
            if tools && toolsWork {
                b["tools"] = ToolCatalog.all.map {
                    ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.jsonSchema]] as [String: Any]
                }
            }
            let req = HTTP.request(url, body: HTTP.json(b), headers: ["Authorization": "Bearer \(key)"])
            let bytes: URLSession.AsyncBytes, status: Int, errBody: String
            do {
                (bytes, status, errBody) = try await HTTP.open(req)
            } catch {
                if isCancellation(error) { throw CancellationError() }
                throw HTTP.connectionError(error, "The AI service")
            }
            if status != 200 {
                let msg = HTTP.errorMessage(errBody)
                if tools && toolsWork && status == 400 && msg.lowercased().contains("tool") {
                    toolsWork = false
                    if render { Renderer.shared.info("This model cannot use tools, so it can only talk.") }
                    continue
                }
                if status == 401 { throw AIError(title: "The API key was not accepted", detail: "Add a new key with: lotus ai key openai") }
                throw AIError(title: "The AI service answered with an error (\(status))", detail: msg)
            }
            var reply = Reply()
            var parts: [Int: (id: String, name: String, args: String)] = [:]
            let split = ChannelSplit()
            func take(_ pieces: [(Bool, String)]) {
                for (think, piece) in pieces {
                    if think { reply.thoughts += piece; if render { Renderer.shared.thinkingDelta(piece) } }
                    else { reply.text += piece; if render { Renderer.shared.textDelta(piece) } }
                }
            }
            var ended = false        // [DONE] or a finish reason – without either, the server broke off
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { ended = true; break }
                guard let j = HTTP.parse(payload), let choice = (j["choices"] as? [[String: Any]])?.first else { continue }
                if let f = choice["finish_reason"] as? String { reply.finish = f; ended = true }
                guard let d = choice["delta"] as? [String: Any] else { continue }
                if let r = (d["reasoning_content"] ?? d["reasoning"]) as? String, !r.isEmpty {
                    reply.thoughts += r
                    if render { Renderer.shared.thinkingDelta(r) }
                }
                if let t = d["content"] as? String, !t.isEmpty { take(split.feed(t)) }
                for tc in d["tool_calls"] as? [[String: Any]] ?? [] {
                    let i = tc["index"] as? Int ?? 0
                    var p = parts[i] ?? (id: "", name: "", args: "")
                    if let id = tc["id"] as? String { p.id = id }
                    if let f = tc["function"] as? [String: Any] {
                        if let n = f["name"] as? String { p.name += n }
                        if let a = f["arguments"] as? String { p.args += a }
                    }
                    parts[i] = p
                }
            }
            take(split.flush())
            if Task.isCancelled { throw CancellationError() }
            if !ended { throw brokeOff() }
            // gpt-oss writes its tool calls as text (see ChannelSplit)
            for c in split.calls {
                let id = "call_h\(reply.calls.count)"
                let args = c.args.trimmingCharacters(in: .whitespacesAndNewlines)
                let parsed = args.isEmpty ? [:] : HTTP.parse(args)
                reply.calls.append(PendingCall(id: id, name: c.name, args: parsed, raw: args))
                // the server reads these arguments as JSON again: a broken one would fail the next request
                reply.rawCalls.append(["id": id, "type": "function", "function": ["name": c.name, "arguments": args.isEmpty || parsed == nil ? "{}" : args]])
            }
            for i in parts.keys.sorted() {
                let p = parts[i]!
                let id = p.id.isEmpty ? "call_\(i)" : p.id
                let args = p.args.trimmingCharacters(in: .whitespaces).isEmpty ? [:] : HTTP.parse(p.args)
                reply.calls.append(PendingCall(id: id, name: p.name, args: args, raw: p.args))
                reply.rawCalls.append(["id": id, "type": "function", "function": ["name": p.name, "arguments": p.args.isEmpty ? "{}" : p.args]])
            }
            return reply
        }
    }

    func send(_ text: String, tools: ToolRunner?) async throws -> String {
        messages.append(["role": "user", "content": text])
        var answer: [String] = []
        stopped = .stepLimit
        lastThoughts = ""
        // going on after it ran out of room: a model on this Mac thinks briefly (see rewrite)
        let thinking = self.thinking
        var acted = false          // a tool call that worked – then a quiet end is the end
        for _ in 0..<40 {
            let reply = try await stream(messages, tools: tools != nil, render: true, extra: thinking)
            guard let tools = tools, !reply.calls.isEmpty else {
                // the end of this message – done, or it stopped too early (the agent lets it go on)
                stopped = EmptyReply.stop(finish: reply.finish, text: reply.text, thoughts: reply.thoughts, said: acted || !answer.isEmpty)
                lastThoughts = reply.thoughts
                if !reply.text.isEmpty {
                    messages.append(["role": "assistant", "content": reply.text])
                    answer.append(reply.text)
                }
                break
            }
            messages.append(["role": "assistant", "content": reply.text, "tool_calls": reply.rawCalls])
            if !reply.text.isEmpty { answer.append(reply.text) }
            Renderer.shared.endBlock()
            for (call, out) in await runCalls(reply.calls, tools) {
                messages.append(["role": "tool", "tool_call_id": call.id, "content": out.isError ? "Error: " + out.text : out.text])
                if !out.isError { acted = true }
            }
            if Task.isCancelled { throw CancellationError() }
            Spinner.shared.start("Thinking")
        }
        return answer.joined(separator: "\n\n")
    }

    func complete(system: String, prompt: String) async throws -> String {
        let msgs: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
        return try await stream(msgs, tools: false, render: false).text
    }

    // A model server on this Mac (lotus ai local, LM Studio, llama.cpp) thinks briefly for this and stops early:
    // gpt-oss would otherwise think for a minute, and a request that was given up keeps such a server busy.
    // Other APIs get the plain request – they may not know these fields.
    func rewrite(system: String, prompt: String) async throws -> String {
        let msgs: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
        var extra: [String: Any] = [:]
        if onThisMac {
            extra = ["max_tokens": 1500, "chat_template_kwargs": ["reasoning_effort": "low", "enable_thinking": false]]
        }
        return try await stream(msgs, tools: false, render: false, extra: extra).text
    }
}

// The last reply of a message (no tool call): did the AI finish, or did it stop too early?
// The agent lets it go on, and says what happened when it still does not get there (App.swift)
enum EmptyReply {
    static func stop(finish: String, text: String, thoughts: String, said: Bool) -> Stop {
        if finish == "length" { return .ranOut }                 // cut off – by thinking or by a long answer
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .done }
        if !thoughts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .thoughtsOnly }
        return said ? .done : .empty
    }
}

// Models on this Mac write their thoughts into the answer: gpt-oss in its channels
// (<|channel|>analysis<|message|>… then <|channel|>final<|message|>…), Qwen in <think>…</think>.
// This splits the stream into thinking and the answer, also when a marker comes in pieces.
// It also finds the tools a model calls in its text:
//   gpt-oss  <|start|>assistant to=functions.NAME<|channel|>commentary json<|message|>{args}<|call|>
//   others   <tool_call>{"name": …, "arguments": {…}}</tool_call>  or  <tool_call><function=NAME><parameter=K>V</parameter></function></tool_call>
final class ChannelSplit {
    private var buf = ""
    private var thinking = false
    private var header: String?           // gpt-oss: the head of a message (who, which channel) until <|message|>
    private var callName: String?         // gpt-oss: the tool the message goes to; its arguments follow
    private var inToolCall = false        // inside <tool_call>…</tool_call>
    private var callArgs = ""
    private var started = false
    private(set) var calls: [(name: String, args: String)] = []
    private let marks = ["<think>", "</think>", "<tool_call>", "</tool_call>", "<|start|>", "<|end|>", "<|return|>",
                         "<|channel|>", "<|message|>", "<|constrain|>", "<|call|>"]

    func feed(_ s: String) -> [(Bool, String)] {
        buf += s
        var out: [(Bool, String)] = []
        // The answer begins right after "<|start|>assistant": gpt-oss may start with " to=functions.NAME", a head
        if !started {
            let t = buf.drop(while: { $0 == " " || $0 == "\n" })
            if t.isEmpty || (t.count < 3 && "to=".hasPrefix(t)) { return out }
            started = true
            if t.hasPrefix("to=") { header = "" }
        }
        func text(_ t: String) {
            guard !t.isEmpty else { return }
            if header != nil { header! += t }
            else if callName != nil || inToolCall { callArgs += t }
            else { out.append((thinking, t)) }
        }
        while !buf.isEmpty {
            guard let lt = buf.firstIndex(of: "<") else { text(buf); buf = ""; break }
            text(String(buf[..<lt]))
            let rest = String(buf[lt...])
            if let m = marks.first(where: { rest.hasPrefix($0) }) {
                switch m {
                case "<think>": thinking = true
                case "</think>": thinking = false
                case "<tool_call>": endCall(); inToolCall = true; callArgs = ""
                case "</tool_call>": endToolCall()
                case "<|start|>": endCall(); header = ""
                case "<|channel|>": header = (header ?? "") + "\u{1}"
                case "<|message|>": if let h = header { header = nil; open(h) }
                case "<|constrain|>": if header != nil { header! += " " }   // "to=functions.read_file<|constrain|>json"
                case "<|call|>", "<|end|>", "<|return|>": endCall()
                default: break
                }
                buf = String(rest.dropFirst(m.count))
                continue
            }
            // the start of a marker that is not complete yet: wait for the next piece
            if marks.contains(where: { $0.hasPrefix(rest) }) { buf = rest; break }
            text("<")
            buf = String(rest.dropFirst())
        }
        return out
    }

    // A message begins: "assistant to=functions.NAME␁commentary json" is a tool call, "␁analysis" thinking,
    // "␁final" the answer
    private func open(_ h: String) {
        if let r = h.range(of: "to=") {
            let target = h[r.upperBound...].prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) })
            if !target.isEmpty && target != "assistant" {
                callName = target.hasPrefix("functions.") ? String(target.dropFirst(10)) : String(target)
                callArgs = ""
                return
            }
        }
        guard h.contains("\u{1}") else { thinking = false; return }
        thinking = !ChannelSplit.isVisible(String(h.split(separator: "\u{1}", omittingEmptySubsequences: false).last ?? ""))
    }

    // The answer, and the short notes before a tool call (commentary without a recipient), are for the user
    static func isVisible(_ channel: String) -> Bool {
        let c = channel.trimmingCharacters(in: .whitespaces)
        return c.hasPrefix("final") || (c.hasPrefix("commentary") && !c.contains("to="))
    }

    private func endCall() {
        if let n = callName { calls.append((n, callArgs.trimmingCharacters(in: .whitespacesAndNewlines))) }
        callName = nil
        if !inToolCall { callArgs = "" }
    }

    private func endToolCall() {
        defer { inToolCall = false; callArgs = "" }
        let body = callArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        if let j = HTTP.parse(body), let name = j["name"] as? String {
            let a = j["arguments"] ?? j["parameters"] ?? [String: Any]()
            let args = a as? String ?? (try? JSONSerialization.data(withJSONObject: a)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            calls.append((name, args))
            return
        }
        // <function=NAME><parameter=KEY>value</parameter>…</function>
        guard let f = body.range(of: "<function="), let close = body[f.upperBound...].firstIndex(of: ">") else { return }
        let name = String(body[f.upperBound..<close])
        var args: [String: Any] = [:]
        var rest = body[close...]
        while let p = rest.range(of: "<parameter="), let gt = rest[p.upperBound...].firstIndex(of: ">") {
            let key = String(rest[p.upperBound..<gt])
            let after = rest[rest.index(after: gt)...]
            let end = after.range(of: "</parameter>")?.lowerBound ?? after.endIndex
            var value = String(after[..<end])
            if value.hasPrefix("\n") { value.removeFirst() }
            if value.hasSuffix("\n") { value.removeLast() }
            args[key] = Int(value).map { $0 as Any } ?? (value == "true" || value == "false" ? (value == "true") as Any : value)
            rest = after[end...]
        }
        let data = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        calls.append((name, data))
    }

    func flush() -> [(Bool, String)] {
        defer { buf = "" }
        if callName != nil { callArgs += buf; endCall(); return [] }
        if inToolCall { callArgs += buf; endToolCall(); return [] }
        return buf.isEmpty || header != nil ? [] : [(thinking, buf)]
    }

    // Only the answer of a saved message (older versions kept the markers – a model refuses them)
    static func answer(_ text: String) -> String {
        guard text.contains("<|") || text.contains("<think>") else { return text }
        let s = ChannelSplit()
        let parts = s.feed(text) + s.flush()
        let out = parts.filter { !$0.0 }.map { $0.1 }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "…" : out
    }
}
