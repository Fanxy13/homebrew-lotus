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
}

extension Provider {
    func reset(system: String, chatSystem: String, history: [Turn]) {
        reset(system: system, history: history)
    }
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
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
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
            let bad = String(decoding: HTTP.json(["INVALID_JSON": call.raw]), as: UTF8.self)
            results.append((call, ToolOutcome(text: bad, isError: true)))
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

    // Claude 4.6 and newer think adaptively and take an effort level
    private var adaptive: Bool {
        !(model.contains("haiku") || model.contains("-4-5") || model.contains("-4-1") || model.hasSuffix("-4-0") || model.contains("claude-3"))
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
            let level = ["low": "low", "medium": "medium", "high": "high", "max": "xhigh"][effort] ?? "high"
            b["output_config"] = ["effort": level]
        } else if effort != "low" {
            b["thinking"] = ["type": "enabled", "budget_tokens": effort == "max" ? 32000 : effort == "high" ? 16000 : 6000]
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
                        let n = ToolCatalog.displayNames[b["name"] as? String ?? ""] ?? "tool"
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
        for step in 0..<60 {
            let reply = try await stream(body(tools: tools != nil), render: true)
            if reply.stop == "refusal" {
                Renderer.shared.endBlock()
                if step == 0 && messages.count - 1 == firstIndex { messages.removeLast() }
                throw AIError(title: "Claude declined this request", detail: reply.refusal.isEmpty ? "Try asking differently." : "Reason: \(reply.refusal)")
            }
            if !reply.content.isEmpty { messages.append(["role": "assistant", "content": reply.content]) }
            if !reply.text.isEmpty { answer.append(reply.text) }
            guard let tools = tools, !reply.calls.isEmpty else { break }
            pendingToolIDs = reply.calls.map(\.id)
            var results: [(PendingCall, ToolOutcome)]
            if reply.stop == "max_tokens" {
                results = reply.calls.map { ($0, ToolOutcome(text: "The input was cut off because the answer got too long. Split the work into smaller steps.", isError: true)) }
            } else {
                results = await runCalls(reply.calls, tools)
            }
            let content: [[String: Any]] = results.map { call, out in
                ["type": "tool_result", "tool_use_id": call.id, "content": out.text, "is_error": out.isError]
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
        for t in history where !t.text.isEmpty { messages.append(["role": t.role, "content": t.text]) }
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
                    if let t = m["thinking"] as? String, !t.isEmpty, render { Renderer.shared.thinkingDelta(t) }
                    if let t = m["content"] as? String, !t.isEmpty {
                        reply.text += t
                        if render { Renderer.shared.textDelta(t) }
                    }
                    if let c = m["tool_calls"] as? [[String: Any]] { reply.calls += c }
                }
                if j["done"] as? Bool == true {
                    lastTokens = (j["prompt_eval_count"] as? Int ?? 0) + (j["eval_count"] as? Int ?? 0)
                }
            }
            if Task.isCancelled { throw CancellationError() }
            return reply
        }
    }

    func send(_ text: String, tools: ToolRunner?) async throws -> String {
        messages.append(["role": "user", "content": text])
        var answer: [String] = []
        for _ in 0..<40 {
            let reply = try await stream(messages, tools: tools != nil, think: true, render: true)
            var assistant: [String: Any] = ["role": "assistant", "content": reply.text]
            if !reply.calls.isEmpty { assistant["tool_calls"] = reply.calls }
            messages.append(assistant)
            if !reply.text.isEmpty { answer.append(reply.text) }
            guard let tools = tools, !reply.calls.isEmpty else { break }
            let calls: [PendingCall] = reply.calls.enumerated().map { i, c in
                let f = c["function"] as? [String: Any] ?? [:]
                var args = f["arguments"] as? [String: Any]
                if args == nil, let s = f["arguments"] as? String { args = HTTP.parse(s) }
                return PendingCall(id: c["id"] as? String ?? "call_\(i)", name: f["name"] as? String ?? "", args: args ?? [:], raw: "")
            }
            Renderer.shared.endBlock()
            for (call, out) in await runCalls(calls, tools) {
                messages.append(["role": "tool", "content": out.isError ? "Error: " + out.text : out.text, "tool_name": call.name])
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

    init(model: String, base: String, key: String) {
        self.model = model.isEmpty ? "gpt-4o-mini" : model
        self.base = base.hasSuffix("/") ? String(base.dropLast()) : base
        self.key = key
    }

    var label: String { "\(model) · \(URL(string: base)?.host ?? base)" }
    var budget: Int { 100_000 }
    var usedTokens: Int { messages.reduce(0) { $0 + "\($1["content"] ?? "")".count } / 4 }
    var isSmall: Bool { false }

    func reset(system: String, history: [Turn]) {
        messages = [["role": "system", "content": system]]
        for t in history where !t.text.isEmpty { messages.append(["role": t.role, "content": t.text]) }
    }

    private struct Reply {
        var text = ""
        var calls: [PendingCall] = []
        var rawCalls: [[String: Any]] = []
    }

    private func stream(_ msgs: [[String: Any]], tools: Bool, render: Bool) async throws -> Reply {
        guard let url = URL(string: base + "/chat/completions") else { throw AIError(title: "The AI URL is not valid", detail: base) }
        while true {
            var b: [String: Any] = ["model": model, "messages": msgs, "stream": true]
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
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let j = HTTP.parse(payload), let choice = (j["choices"] as? [[String: Any]])?.first,
                      let d = choice["delta"] as? [String: Any] else { continue }
                if let r = (d["reasoning_content"] ?? d["reasoning"]) as? String, !r.isEmpty, render { Renderer.shared.thinkingDelta(r) }
                if let t = d["content"] as? String, !t.isEmpty {
                    reply.text += t
                    if render { Renderer.shared.textDelta(t) }
                }
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
            if Task.isCancelled { throw CancellationError() }
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
        for _ in 0..<40 {
            let reply = try await stream(messages, tools: tools != nil, render: true)
            var assistant: [String: Any] = ["role": "assistant", "content": reply.text]
            if !reply.rawCalls.isEmpty { assistant["tool_calls"] = reply.rawCalls }
            messages.append(assistant)
            if !reply.text.isEmpty { answer.append(reply.text) }
            guard let tools = tools, !reply.calls.isEmpty else { break }
            Renderer.shared.endBlock()
            for (call, out) in await runCalls(reply.calls, tools) {
                messages.append(["role": "tool", "tool_call_id": call.id, "content": out.isError ? "Error: " + out.text : out.text])
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
}
