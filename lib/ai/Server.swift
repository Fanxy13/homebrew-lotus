// Lotus AI – the web chat: one page in the browser, served by this program on this Mac.
//
//   lotus-ai --serve <port>          started by lib/cmd/aiserver.zsh (lotus ai server start)
//   lotus-ai --port-check <port>     "free" or "used"
//
// It is the same AI as /ai – the same providers, instructions (data/ai/system.md), tools and permissions.
// Questions before a change are asked in the browser. From the web every command asks, one by one, and
// tools that need the terminal stay in the terminal. API keys never leave this program.
//
// Safety: it listens on 127.0.0.1 only, unless the user turned on other devices (LOTUS_AI_SERVER_LAN=1).
// Every request must name this server as its Host (a page elsewhere that points its own name at this Mac
// is refused). The page and the API need the access key – a cookie, set once from the link that
// lotus ai server open opens. Every API call needs this run's token in a header, which a page on another
// site cannot send, and a request that changes something must come from this page (Origin).

import Foundation
import Darwin

// ── Sockets ───────────────────────────────────────────────────

enum Net {
    // Something already answers on 127.0.0.1:port (a server on every address answers there too)
    static func answers(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = address(port, any: false)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if r == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&p, 1, 700) > 0 else { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }

    static func address(_ port: Int, any: Bool) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = in_port_t(UInt16(port).bigEndian)
        a.sin_addr.s_addr = any ? in_addr_t(0) : inet_addr("127.0.0.1")
        return a
    }

    // A listening socket → (fd, 0), or (-1, errno)
    static func listen(_ port: Int, lan: Bool) -> (Int32, Int32) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return (-1, errno) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = address(port, any: lan)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if bound != 0 || Darwin.listen(fd, 64) != 0 {
            let e = errno
            close(fd)
            return (-1, e)
        }
        return (fd, 0)
    }

    static func isFree(_ port: Int, lan: Bool) -> Bool {
        if answers(port) { return false }
        let (fd, _) = listen(port, lan: lan)
        if fd < 0 { return false }
        close(fd)
        return true
    }
}

// One browser connection: one request, one answer (Connection: close)
final class Conn {
    let fd: Int32
    private(set) var open = true

    init(fd: Int32) {
        self.fd = fd
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var t = timeval(tv_sec: 15, tv_usec: 0)    // a request that does not arrive is dropped
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &t, socklen_t(MemoryLayout<timeval>.size))
        var s = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &s, socklen_t(MemoryLayout<timeval>.size))
    }

    @discardableResult
    func write(_ data: Data) -> Bool {
        guard open else { return false }
        guard !data.isEmpty else { return true }
        let ok = data.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> Bool in
            var sent = 0
            while sent < p.count {
                let n = Darwin.send(fd, p.baseAddress! + sent, p.count - sent, 0)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
        if !ok { open = false }
        return ok
    }

    @discardableResult
    func write(_ s: String) -> Bool { write(Data(s.utf8)) }

    func close() { Darwin.close(fd) }
}

struct Request {
    var method = ""
    var path = ""
    var query: [String: String] = [:]
    var headers: [String: String] = [:]     // names in lower case
    var body = Data()

    func header(_ name: String) -> String { headers[name] ?? "" }

    var cookies: [String: String] {
        var out: [String: String] = [:]
        for part in header("cookie").split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    var json: [String: Any]? { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] }

    enum Failure: Error { case bad, tooLarge, closed }

    static let maxHead = 16_384
    static let maxBody = 1_000_000

    static func read(_ c: Conn) throws -> Request {
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        let end = Data("\r\n\r\n".utf8)
        var headEnd: Range<Data.Index>?
        while headEnd == nil {
            let n = recv(c.fd, &chunk, chunk.count, 0)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { throw buf.isEmpty ? Failure.closed : Failure.bad }
            buf.append(chunk, count: n)
            headEnd = buf.range(of: end)
            if headEnd == nil && buf.count > maxHead { throw Failure.tooLarge }
        }
        guard let he = headEnd, let head = String(data: buf[buf.startIndex..<he.lowerBound], encoding: .utf8) else { throw Failure.bad }
        var r = Request()
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, first[2].hasPrefix("HTTP/1.") else { throw Failure.bad }
        r.method = String(first[0])
        let target = String(first[1])
        guard target.hasPrefix("/"), target.count < 4096 else { throw Failure.bad }
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        r.path = String(parts[0])
        if parts.count == 2 {
            for item in parts[1].split(separator: "&") {
                let kv = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let k = String(kv[0]).removingPercentEncoding ?? ""
                let v = kv.count > 1 ? (String(kv[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "") : ""
                if !k.isEmpty { r.query[k] = v }
            }
        }
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw Failure.bad }
            r.headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if !r.header("transfer-encoding").isEmpty { throw Failure.bad }      // bodies come with a length
        let length = Int(r.header("content-length")) ?? 0
        guard length >= 0 else { throw Failure.bad }
        guard length <= maxBody else { throw Failure.tooLarge }
        r.body = Data(buf[he.upperBound...])
        while r.body.count < length {
            let n = recv(c.fd, &chunk, min(chunk.count, length - r.body.count), 0)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { throw Failure.bad }
            r.body.append(chunk, count: n)
        }
        if r.body.count > length { r.body = r.body.prefix(length) }
        return r
    }
}

// ── The conversations of the web chat ─────────────────────────
// One JSON file per conversation, readable only by the user:
//   turns/summary   what the AI gets as the conversation (like /ai's conversation.json)
//   messages        what the browser shows: the user's text, and per answer the events it was made of

final class ChatStore: @unchecked Sendable {
    let dir: URL
    private let lock = NSLock()
    private var index: [String: (title: String, updated: Double)] = [:]
    static let keep = 200

    init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".json") {
            let id = String(name.dropLast(5))
            if let c = read(id) { index[id] = (c["title"] as? String ?? "", c["updated"] as? Double ?? 0) }
        }
    }

    static func valid(_ id: String) -> Bool {
        id.count == 12 && id.unicodeScalars.allSatisfy { ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x30 && $0.value <= 0x39) }
    }

    private func file(_ id: String) -> URL { dir.appendingPathComponent(id + ".json") }

    private func read(_ id: String) -> [String: Any]? {
        guard ChatStore.valid(id), let data = try? Data(contentsOf: file(id)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func load(_ id: String) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return read(id)
    }

    func save(_ chat: [String: Any]) {
        guard let id = chat["id"] as? String, ChatStore.valid(id),
              let data = try? JSONSerialization.data(withJSONObject: chat) else { return }
        lock.lock(); defer { lock.unlock() }
        let url = file(id)
        try? data.write(to: url, options: .atomic)
        chmod(url.path, 0o600)
        index[id] = (chat["title"] as? String ?? "", chat["updated"] as? Double ?? 0)
    }

    func create() -> [String: Any] {
        let now = Date().timeIntervalSince1970
        let chat: [String: Any] = ["id": WebServer.random(12), "title": "", "created": now, "updated": now,
                                   "summary": "", "turns": [[String: String]](), "messages": [[String: Any]]()]
        save(chat)
        // only the newest conversations are kept
        lock.lock()
        let old = index.sorted { $0.value.updated > $1.value.updated }.dropFirst(ChatStore.keep).map(\.key)
        lock.unlock()
        for id in old { delete(id) }
        return chat
    }

    func delete(_ id: String) {
        guard ChatStore.valid(id) else { return }
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: file(id))
        index.removeValue(forKey: id)
    }

    func list() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return index.sorted { $0.value.updated > $1.value.updated }.map { ["id": $0.key, "title": $0.value.title, "updated": $0.value.updated] }
    }
}

// ── One answer that is being written ──────────────────────────
// The events of the answer are kept, so a browser that reloads or loses the connection can attach
// again and see all of it. Questions wait here for the browser's answer.

final class Run: @unchecked Sendable {
    let chat: String
    private let cond = NSCondition()
    private var events: [[String: Any]] = []
    private(set) var done = false
    private var stopped = false
    private var lastStatus = ""
    // open questions: how to go on, the answers that are allowed, and the one that counts on stop or timeout
    private var questions: [String: (wait: CheckedContinuation<(String, String), Never>, words: Set<String>, fallback: String)] = [:]

    init(chat: String) { self.chat = chat }

    func add(_ type: String, _ data: [String: Any] = [:]) {
        cond.lock()
        defer { cond.unlock() }
        if done { return }
        if type == "status" {
            let text = data["text"] as? String ?? ""
            if text == lastStatus { return }
            lastStatus = text
        }
        var e = data
        e["type"] = type
        events.append(e)
        cond.broadcast()
    }

    func finish() {
        cond.lock()
        done = true
        cond.broadcast()
        cond.unlock()
    }

    // The events after the first `from`, waiting up to `timeout` for new ones → (events, finished)
    func next(after from: Int, timeout: TimeInterval) -> ([[String: Any]], Bool) {
        cond.lock()
        defer { cond.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while events.count <= from && !done {
            if !cond.wait(until: deadline) { break }
        }
        return (from < events.count ? Array(events[from...]) : [], done)
    }

    // What the conversation keeps: everything but the passing status lines
    var kept: [[String: Any]] {
        cond.lock(); defer { cond.unlock() }
        return events.filter { $0["type"] as? String != "status" }
    }

    var waiting: Bool {
        cond.lock(); defer { cond.unlock() }
        return !questions.isEmpty
    }

    // A question for the browser → (answer, note); no answer within 15 minutes counts as the fallback
    private func question(_ type: String, _ data: [String: Any], words: Set<String>, fallback: String) async -> (String, String) {
        let id = WebServer.random(10)
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 900 * 1_000_000_000)
            self?.resolve(id, fallback, "")
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<(String, String), Never>) in
                cond.lock()
                if stopped || Task.isCancelled {
                    cond.unlock()
                    c.resume(returning: (fallback, ""))
                    return
                }
                questions[id] = (c, words, fallback)
                cond.unlock()
                var d = data
                d["id"] = id
                add(type, d)
            }
        } onCancel: {
            self.resolve(id, fallback, "")
        }
    }

    // A permission: yes, yes and don't ask again (when offered), or no with what to do instead
    func ask(_ question: String, always: Bool) async -> Interaction.Answer {
        let (word, note) = await self.question("ask", ["question": question, "always": always],
                                               words: always ? ["yes", "always", "no"] : ["yes", "no"], fallback: "no")
        switch word {
        case "yes": return .yes
        case "always": return .always
        default: return .no(note)
        }
    }

    // The improved prompt (ask mode of /enhance) → "improved", "original" or "cancel"
    func choosePrompt(_ text: String) async -> String {
        await question("improve", ["text": text], words: ["improved", "original", "cancel"], fallback: "cancel").0
    }

    enum Resolved { case done, unknown, notAllowed }

    @discardableResult
    func resolve(_ id: String, _ word: String, _ note: String) -> Resolved {
        cond.lock()
        guard let q = questions[id] else { cond.unlock(); return .unknown }
        guard q.words.contains(word) else { cond.unlock(); return .notAllowed }
        questions.removeValue(forKey: id)
        cond.unlock()
        add("asked", ["id": id, "answer": word, "note": note])
        q.wait.resume(returning: (word, note))
        return .done
    }

    // The stop button: open questions get their fallback (no, or not sent)
    func stop() {
        cond.lock()
        stopped = true
        let open = questions.map { ($0.key, $0.value.fallback) }
        cond.unlock()
        for (id, fallback) in open { resolve(id, fallback, "") }
    }
}

// ── The server ────────────────────────────────────────────────

final class WebServer: @unchecked Sendable {
    let port: Int
    let lan: Bool
    let key: String              // the access key (cookie), kept by lotus ai server in a file only the user can read
    let token: String            // this run's token for API calls
    let agent: Agent
    let store: ChatStore
    let root: String
    private let lock = NSLock()
    private var active: Run?
    private var agentChat: String?     // the conversation the agent holds right now
    private var connections = 0
    private static var signals: [DispatchSourceSignal] = []

    init(port: Int, lan: Bool, key: String, agent: Agent, store: ChatStore, root: String) {
        self.port = port
        self.lan = lan
        self.key = key
        self.token = WebServer.random(32)
        self.agent = agent
        self.store = store
        self.root = root
    }

    static func random(_ n: Int) -> String {
        let a = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<n).map { _ in a[Int(arc4random_uniform(UInt32(a.count)))] })
    }

    // Compares secrets in constant time
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count, !x.isEmpty else { return false }
        var d: UInt8 = 0
        for i in 0..<x.count { d |= x[i] ^ y[i] }
        return d == 0
    }

    static func fail(_ message: String, _ code: Int32) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        Log.write("ERROR", "Web chat: \(message)")
        return code
    }

    // Exit status: 0 stopped · 2 usage · 3 no AI · 4 no access key · 98 the port is in use · 1 other
    static func run(_ config: Config, port: Int, lan: Bool? = nil) async -> Int32 {
        let e = ProcessInfo.processInfo.environment
        signal(SIGPIPE, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        let lan = lan ?? (e["LOTUS_AI_SERVER_LAN"] == "1")
        guard let key = e["LOTUS_AI_SERVER_KEY"], key.count >= 32, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return fail("No access key – start the web chat with: lotus ai server start", 4)
        }
        if Net.answers(port) { return fail("Port \(port) is already in use", 98) }
        let (fd, err) = Net.listen(port, lan: lan)
        if fd < 0 {
            return err == EADDRINUSE ? fail("Port \(port) is already in use", 98) : fail("Port \(port): \(String(cString: strerror(err)))", 1)
        }
        let agent: Agent
        do {
            agent = try Agent(config: config, keys: nil, memory: false)
        } catch let e as AIError {
            close(fd)
            return fail("\(e.title) – \(e.detail)", 3)
        } catch {
            close(fd)
            return fail(error.localizedDescription, 3)
        }
        agent.conversation = Conversation(file: nil)
        agent.browser = true
        agent.runner.web = true
        agent.resetProvider()
        let chats = e["LOTUS_AI_CHATS"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? config.stateDir.appendingPathComponent("chats")
        let server = WebServer(port: port, lan: lan, key: key, agent: agent, store: ChatStore(dir: chats), root: config.root)

        // stop cleanly: the model on this Mac that Lotus started for the web chat stops too
        let child = Int32(e["LOTUS_AI_SERVER_CHILD"] ?? "") ?? 0
        for s in [SIGTERM, SIGINT] {
            signal(s, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: s, queue: .global())
            src.setEventHandler {
                Log.write("INFO", "Web chat stopped")
                if child > 1 { kill(child, SIGTERM) }
                exit(0)
            }
            src.resume()
            signals.append(src)
        }
        Log.write("INFO", "Web chat on \(lan ? "every address" : "127.0.0.1"):\(port) with \(agent.provider.label)")
        let t = Thread { server.accept(fd) }
        t.stackSize = 1 << 20
        t.start()
        while true { try? await Task.sleep(nanoseconds: 3_600_000_000_000) }
    }

    private func accept(_ listener: Int32) {
        while true {
            let fd = Darwin.accept(listener, nil, nil)
            if fd < 0 { if errno == EINTR || errno == ECONNABORTED { continue }; usleep(50_000); continue }
            lock.lock()
            let busy = connections >= 48
            if !busy { connections += 1 }
            lock.unlock()
            if busy { close(fd); continue }
            let t = Thread { [self] in
                let c = Conn(fd: fd)
                handle(c)
                c.close()
                lock.lock(); connections -= 1; lock.unlock()
            }
            t.stackSize = 1 << 20
            t.start()
        }
    }

    // ── Answers ──

    private static let statusText = [200: "OK", 204: "No Content", 303: "See Other", 400: "Bad Request", 401: "Unauthorized",
                                     403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict",
                                     413: "Payload Too Large", 421: "Misdirected Request", 500: "Internal Server Error"]

    private static let security = [
        "X-Content-Type-Options: nosniff",
        "X-Frame-Options: DENY",
        "Referrer-Policy: no-referrer",
        "Cross-Origin-Opener-Policy: same-origin",
        "Cross-Origin-Resource-Policy: same-origin",
        "Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    ]

    private func respond(_ c: Conn, _ status: Int, _ type: String, _ body: Data, _ extra: [String] = []) {
        var head = "HTTP/1.1 \(status) \(WebServer.statusText[status] ?? "Error")\r\n"
        head += "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for h in WebServer.security + extra { head += h + "\r\n" }
        c.write(head + "\r\n")
        c.write(body)
    }

    private func json(_ c: Conn, _ status: Int, _ object: Any) {
        respond(c, status, "application/json; charset=utf-8", HTTP.json(object))
    }

    private func problem(_ c: Conn, _ status: Int, _ message: String) {
        json(c, status, ["error": message])
    }

    // ── Who may ask ──

    // The Host header must be this server: 127.0.0.1 or localhost, or with other devices an IP address or a .local name.
    // A web page that points its own name at this Mac (DNS rebinding) is refused.
    private func hostOK(_ host: String) -> Bool {
        let h = host.lowercased()
        guard h.hasSuffix(":\(port)") else { return false }
        let name = String(h.dropLast(":\(port)".count))
        if name == "127.0.0.1" || name == "localhost" { return true }
        guard lan else { return false }
        let ip = name.split(separator: ".", omittingEmptySubsequences: false)
        if ip.count == 4 && ip.allSatisfy({ !$0.isEmpty && $0.count <= 3 && $0.allSatisfy(\.isNumber) }) { return true }
        return name.hasSuffix(".local") && name.dropLast(6).allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." } && name.count > 6
    }

    private func signedIn(_ r: Request) -> Bool {
        WebServer.same(r.cookies["lotus_ai_key"] ?? "", key)
    }

    // The API: signed in, this run's token in a header (another site cannot send one), and a request
    // that changes something comes from this page
    private func apiOK(_ r: Request) -> String? {
        guard signedIn(r) else { return "Not signed in – open the web chat from the terminal: lotus ai server open" }
        guard WebServer.same(r.header("x-lotus-token"), token) else { return "The page is out of date – reload it" }
        if r.header("sec-fetch-site") == "cross-site" { return "Requests from other sites are not allowed" }
        let origin = r.header("origin")
        if r.method != "GET" || !origin.isEmpty {
            guard origin.lowercased() == "http://" + r.header("host").lowercased() else { return "Requests from other sites are not allowed" }
        }
        return nil
    }

    // ── Requests ──

    private func handle(_ c: Conn) {
        let r: Request
        do {
            r = try Request.read(c)
        } catch Request.Failure.tooLarge {
            return problem(c, 413, "The request is too large")
        } catch Request.Failure.closed {
            return
        } catch {
            return problem(c, 400, "Bad request")
        }
        guard hostOK(r.header("host")) else { return problem(c, 421, "This server only answers as 127.0.0.1:\(port)") }

        if r.path == "/api/health" {
            return json(c, 200, ["ok": true, "app": "lotus-ai", "pid": Int(getpid())])
        }
        if r.path.hasPrefix("/api/") {
            if let why = apiOK(r) { return problem(c, r.header("x-lotus-token").isEmpty || !signedIn(r) ? 401 : 403, why) }
            return api(c, r)
        }
        guard r.method == "GET" else { return problem(c, 405, "Method not allowed") }
        switch r.path {
        case "/":
            page(c, r)
        case "/app.js":
            file(c, "app.js", "text/javascript; charset=utf-8")
        case "/app.css":
            file(c, "app.css", "text/css; charset=utf-8")
        case "/icon.svg":
            file(c, "icon.svg", "image/svg+xml")
        case "/theme.css":
            respond(c, 200, "text/css; charset=utf-8", Data(themeCSS().utf8))
        default:
            problem(c, 404, "Not found")
        }
    }

    private func webFile(_ name: String) -> Data? {
        FileManager.default.contents(atPath: root + "/lib/ai/web/" + name)
    }

    private func file(_ c: Conn, _ name: String, _ type: String) {
        guard let data = webFile(name) else { return problem(c, 404, "Not found") }
        respond(c, 200, type, data)
    }

    // The page – with the access key from the link it signs in (a cookie) and loads again without the key
    private func page(_ c: Conn, _ r: Request) {
        if let k = r.query["key"] {
            if WebServer.same(k, key) {
                return respond(c, 303, "text/plain", Data(), [
                    "Location: /",
                    "Set-Cookie: lotus_ai_key=\(key); Path=/; Max-Age=2592000; HttpOnly; SameSite=Strict",
                ])
            }
            return locked(c, "This link is not valid (any more). Open the web chat from the terminal again.")
        }
        guard signedIn(r) else { return locked(c, "Open it from the terminal – the link there signs you in.") }
        guard var html = webFile("index.html").flatMap({ String(data: $0, encoding: .utf8) }) else {
            return problem(c, 500, "The page is missing – reinstall Lotus")
        }
        html = html.replacingOccurrences(of: "{{token}}", with: token)
            .replacingOccurrences(of: "{{version}}", with: agent.config.version.filter { $0.isNumber || $0 == "." })
        respond(c, 200, "text/html; charset=utf-8", Data(html.utf8))
    }

    private func locked(_ c: Conn, _ why: String) {
        let html = """
            <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Lotus AI</title><link rel="icon" href="/icon.svg"><link rel="stylesheet" href="/theme.css"><link rel="stylesheet" href="/app.css"></head>
            <body class="locked"><main><img src="/icon.svg" alt="" width="56" height="56"><h1>Lotus AI</h1><p>\(why)</p>
            <pre><code>lotus ai server open</code></pre></main></body></html>
            """
        respond(c, 401, "text/html; charset=utf-8", Data(html.utf8))
    }

    // The colors of the user's Lotus theme (data/themes.tsv), read from the settings each time
    private func themeCSS() -> String {
        let e = ProcessInfo.processInfo.environment
        let theme = SettingsFile.read()["LOTUS_THEME"] ?? e["LOTUS_THEME"] ?? "matcha"
        let names = ["logo", "key", "accent", "key2", "salute", "border", "dim", "music"]
        var rows: [String: [String]] = [:]
        if let text = try? String(contentsOfFile: root + "/data/themes.tsv", encoding: .utf8) {
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                if f.count >= 10 { rows[f[0]] = Array(f[2..<10]) }
            }
        }
        let colors = rows[theme] ?? rows["matcha"] ?? []
        var css = ":root {\n"
        for (i, name) in names.enumerated() where i < colors.count {
            let rgb = colors[i].split(separator: ";").compactMap { Int($0) }.filter { (0...255).contains($0) }
            if rgb.count == 3 { css += "  --\(name): \(rgb[0]) \(rgb[1]) \(rgb[2]);\n" }
        }
        return css + "}\n"
    }

    // ── The API ──

    private func api(_ c: Conn, _ r: Request) {
        let parts = r.path.split(separator: "/").map(String.init)      // ["api", …]
        switch (r.method, Array(parts.dropFirst())) {
        case ("GET", ["state"]):
            json(c, 200, state())
        case ("GET", ["chats"]):
            json(c, 200, ["chats": store.list()])
        case ("POST", ["chats"]):
            let chat = store.create()
            json(c, 200, ["id": chat["id"] ?? ""])
        case ("GET", let p) where p.count == 2 && p[0] == "chats":
            guard ChatStore.valid(p[1]), let chat = store.load(p[1]) else { return problem(c, 404, "This conversation does not exist") }
            json(c, 200, ["id": p[1], "title": chat["title"] ?? "", "messages": chat["messages"] ?? [], "running": runningChat == p[1]])
        case ("DELETE", let p) where p.count == 2 && p[0] == "chats":
            guard ChatStore.valid(p[1]) else { return problem(c, 404, "This conversation does not exist") }
            guard runningChat != p[1] else { return problem(c, 409, "Lotus AI is answering in this conversation – stop it first") }
            store.delete(p[1])
            forget(p[1])
            json(c, 200, ["ok": true])
        case ("POST", let p) where p.count == 3 && p[0] == "chats" && p[2] == "clear":
            guard ChatStore.valid(p[1]), var chat = store.load(p[1]) else { return problem(c, 404, "This conversation does not exist") }
            guard runningChat != p[1] else { return problem(c, 409, "Lotus AI is answering in this conversation – stop it first") }
            chat["messages"] = [[String: Any]]()
            chat["turns"] = [[String: String]]()
            chat["summary"] = ""
            chat["title"] = ""
            chat["updated"] = Date().timeIntervalSince1970
            store.save(chat)
            forget(p[1])
            json(c, 200, ["ok": true])
        case ("POST", let p) where p.count == 3 && p[0] == "chats" && p[2] == "send":
            send(c, p[1], r)
        case ("GET", ["run"]):
            attach(c, r)
        case ("POST", ["answer"]):
            answer(c, r)
        case ("POST", ["stop"]):
            lock.lock()
            let run = active
            lock.unlock()
            guard let run = run, !run.done else { return json(c, 200, ["ok": true, "running": false]) }
            run.stop()
            agent.stop()
            json(c, 200, ["ok": true, "running": true])
        default:
            problem(c, parts.count >= 2 ? 404 : 400, "Unknown request")
        }
    }

    // The agent takes this conversation; false when it has to load it first
    private func take(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let holds = agentChat == id
        agentChat = id
        return holds
    }

    // The agent holds this conversation no more: the next message loads it again
    private func forget(_ id: String) {
        lock.lock()
        if agentChat == id { agentChat = nil }
        lock.unlock()
    }

    private var runningChat: String? {
        lock.lock(); defer { lock.unlock() }
        guard let r = active, !r.done else { return nil }
        return r.chat
    }

    private func state() -> [String: Any] {
        let home = NSHomeDirectory()
        let cwd = agent.cwd.path
        let folder = cwd == home ? "~" : cwd.hasPrefix(home + "/") ? "~/" + cwd.dropFirst(home.count + 1) : cwd
        let p = agent.runner.permissions
        return ["version": agent.config.version, "ai": agent.provider.label, "effort": TUI.effortNames[agent.config.effort] ?? agent.config.effort,
                "tools": agent.usesTools, "mode": p.auto ? "auto" : "ask", "folder": String(folder),
                "busy": runningChat ?? NSNull(), "lan": lan, "name": agent.config.name, "enhance": agent.enhanceMode]
    }

    // A message: the answer is written in the background and streamed as events (text/event-stream)
    private func send(_ c: Conn, _ id: String, _ r: Request) {
        guard ChatStore.valid(id) else { return problem(c, 404, "This conversation does not exist") }
        guard let text = r.json?["text"] as? String else { return problem(c, 400, "The message is missing") }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return problem(c, 400, "The message is empty") }
        guard clean.count <= 100_000 else { return problem(c, 413, "The message is too long (at most 100,000 characters)") }
        lock.lock()
        if let a = active, !a.done {
            lock.unlock()
            return problem(c, 409, "Lotus AI is still answering – wait for it or stop it first")
        }
        guard var chat = store.load(id) else {
            lock.unlock()
            return problem(c, 404, "This conversation does not exist")
        }
        let run = Run(chat: id)
        active = run
        lock.unlock()

        let now = Date().timeIntervalSince1970
        var messages = chat["messages"] as? [[String: Any]] ?? []
        messages.append(["role": "user", "text": clean, "time": now])
        chat["messages"] = messages
        if (chat["title"] as? String ?? "").isEmpty {
            let line = clean.split(whereSeparator: \.isNewline).first.map(String.init) ?? clean
            let words = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            chat["title"] = words.count > 60 ? String(words.prefix(59)) + "…" : words
        }
        chat["updated"] = now
        store.save(chat)
        run.add("start", ["chat": id, "title": chat["title"] ?? ""])
        Task.detached { await self.work(run, id, clean) }
        stream(c, run, from: 0)
    }

    private func work(_ run: Run, _ id: String, _ text: String) async {
        Renderer.shared.sink = { type, data in run.add(type, data) }
        Spinner.shared.onLabel = { run.add("status", ["text": $0]) }
        agent.interaction.asker = { q, always in await run.ask(q, always: always) }
        agent.interaction.promptChooser = { text in await run.choosePrompt(text) }
        if !take(id) {
            let chat = store.load(id) ?? [:]
            let conv = Conversation(file: nil)
            conv.turns = (chat["turns"] as? [[String: String]] ?? []).compactMap { t in
                guard let role = t["role"], let text = t["text"], role == "user" || role == "assistant" else { return nil }
                return Turn(role: role, text: text)
            }
            conv.summary = chat["summary"] as? String ?? ""
            agent.conversation = conv
            applySettings(reset: true)
        } else {
            applySettings(reset: false)
        }
        Log.write("INFO", "Web chat: message with \(agent.provider.label)")
        await agent.ask(text)
        Renderer.shared.endBlock()
        Renderer.shared.sink = nil
        Spinner.shared.onLabel = nil
        agent.interaction.asker = nil
        agent.interaction.promptChooser = nil

        if var chat = store.load(id) {
            chat["turns"] = agent.conversation.turns.map { ["role": $0.role, "text": $0.text] }
            chat["summary"] = agent.conversation.summary
            var messages = chat["messages"] as? [[String: Any]] ?? []
            messages.append(["role": "assistant", "events": run.kept, "ai": agent.provider.label, "time": Date().timeIntervalSince1970])
            chat["messages"] = messages
            chat["updated"] = Date().timeIntervalSince1970
            store.save(chat)
        } else {
            forget(id)            // deleted meanwhile
        }
        run.add("done")
        run.finish()
    }

    // The permissions as they are in the Lotus settings now (/settings or /permissions may have changed them)
    private func applySettings(reset: Bool) {
        let saved = SettingsFile.read()
        if let mode = saved["LOTUS_AI_ENHANCE"], Enhance.modes.contains(mode) { agent.enhanceMode = mode }
        var env = ProcessInfo.processInfo.environment
        for item in Permissions.items { if let v = saved[item.key] { env[item.key] = v } }
        let p = Permissions(environment: env)
        let changed = p.values != agent.runner.permissions.values
        if changed {
            agent.runner.permissions = p
            agent.runner.resetAllowances()
        }
        if p.tools != agent.usesTools {
            agent.applyTools(p.tools)          // builds the provider again, with the conversation
        } else if reset {
            agent.resetProvider()
        }
    }

    // A browser attaches to the answer that is being written (after a reload or a lost connection)
    private func attach(_ c: Conn, _ r: Request) {
        lock.lock()
        let run = active
        lock.unlock()
        guard let run = run, run.chat == r.query["chat"] else { return problem(c, 404, "No answer is being written in this conversation") }
        let from = Int(r.query["from"] ?? "0") ?? 0
        stream(c, run, from: max(0, from))
    }

    private func stream(_ c: Conn, _ run: Run, from: Int) {
        var head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n"
        for h in WebServer.security { head += h + "\r\n" }
        guard c.write(head + "\r\n") else { return }
        var cursor = from
        while true {
            let (events, finished) = run.next(after: cursor, timeout: 15)
            if events.isEmpty && !finished {
                if !c.write(": still here\n\n") { return }
                continue
            }
            var out = ""
            for e in events {
                var line = e
                line["seq"] = cursor
                cursor += 1
                out += "data: " + String(decoding: HTTP.json(line), as: UTF8.self) + "\n\n"
            }
            if !c.write(out) { return }
            if finished { return }
        }
    }

    private func answer(_ c: Conn, _ r: Request) {
        guard let j = r.json, let id = j["id"] as? String, id.count == 10, let word = j["answer"] as? String else {
            return problem(c, 400, "The answer is missing")
        }
        let note = String((j["note"] as? String ?? "").replacingOccurrences(of: "\n", with: " ").prefix(2000))
            .trimmingCharacters(in: .whitespaces)
        guard ["yes", "always", "no", "improved", "original", "cancel"].contains(word) else {
            return problem(c, 400, "Not an answer to this question")
        }
        lock.lock()
        let run = active
        lock.unlock()
        switch run?.resolve(id, word, word == "no" ? note : "") ?? .unknown {
        case .done: json(c, 200, ["ok": true])
        case .notAllowed: problem(c, 400, "Not an answer to this question")
        case .unknown: problem(c, 404, "This question was already answered")
        }
    }
}

// ── The Lotus settings file ───────────────────────────────────
// KEY='value' lines written by lotus_save – read again while the web chat runs, so it follows the settings

enum SettingsFile {
    static func read() -> [String: String] {
        guard let path = ProcessInfo.processInfo.environment["LOTUS_AI_SETTINGS"], path.hasPrefix("/"),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") where line.hasPrefix("LOTUS_") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            var v = String(line[line.index(after: eq)...])
            if v.count >= 2 && v.hasPrefix("'") && v.hasSuffix("'") {
                v = String(v.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
            }
            out[String(line[..<eq])] = v
        }
        return out
    }
}
