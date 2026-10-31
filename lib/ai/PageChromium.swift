// Lotus AI – view_page where there is no WebKit (Linux, Windows): the page is rendered by a Chromium-based browser
// (Chromium, Chrome, Edge, Brave) in headless mode and Lotus reports what a person would notice – the same as
// Page.swift does with WebKit on a Mac:
//   lotus-ai --render <page> <width> <folder> <screenshot.jpg | -> [<css selector>]
//
// The browser is driven over the DevTools protocol on a pipe (--remote-debugging-pipe): no port is opened, nothing
// else can talk to it. The page is served from its folder through the protocol itself (Fetch.fulfillRequest) as
// http://lotus-page.test/… – nothing outside the folder, never private files. Scripts, styles, fonts and images may
// come from the internet; everything that could send something away (fetch, XHR, WebSockets, beacons, forms,
// navigation) is blocked while the page is looked at.

#if !canImport(WebKit)
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum PageView {
    static let scheme = "lotus-page"

    // A smaller copy of a screenshot: the browser already makes it at most 1000 px wide
    static func smaller(_ data: Data, maxWidth: Int) -> Data? { nil }

    static func run(_ args: [String]) -> Never {
        guard args.count >= 4, let width = Int(args[1]), (200...3000).contains(width) else {
            print(#"{"ok":false,"error":"usage: lotus-ai --render <page> <width> <folder> <screenshot.jpg|-> [selector]"}"#)
            exit(2)
        }
        ChromiumProbe(page: URL(fileURLWithPath: args[0]).standardizedFileURL,
                      root: URL(fileURLWithPath: args[2]).standardizedFileURL,
                      width: width, shot: args[3] == "-" ? nil : args[3], selector: args.count > 4 ? args[4] : "").go()
    }

    // The browser Lotus uses: LOTUS_BROWSER if set, else the first Chromium-based one found
    static func browser() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let chosen = env["LOTUS_BROWSER"], !chosen.isEmpty {
            if chosen.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: chosen) ? chosen : nil }
            return Host.which(chosen)
        }
        for name in ["chromium", "chromium-browser", "google-chrome", "google-chrome-stable", "chrome",
                     "microsoft-edge", "microsoft-edge-stable", "brave-browser", "brave"] {
            if let p = Host.which(name) { return p }
        }
        return nil
    }
}

// The DevTools protocol on a pipe: JSON messages, each ended by a zero byte
final class DevTools: @unchecked Sendable {
    private let fdOut: Int32       // to the browser
    private let fdIn: Int32        // from the browser
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var nextID = 0
    private var waiting: [Int: DispatchSemaphore] = [:]
    private var answers: [Int: [String: Any]] = [:]
    private(set) var closed = false
    // method, parameters, session – called on the reading thread: it may post(), never call()
    var onEvent: ((String, [String: Any], String) -> Void)?

    init(out: Int32, in fdIn: Int32) {
        fdOut = out
        self.fdIn = fdIn
        Thread.detachNewThread { self.readLoop() }
    }

    private func readLoop() {
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fdIn, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { break }
            pending.append(contentsOf: buffer[0..<n])
            while let zero = pending.firstIndex(of: 0) {
                let message = Data(pending[pending.startIndex..<zero])
                pending = Data(pending[pending.index(after: zero)...])
                handle(message)
            }
        }
        lock.lock()
        closed = true
        let all = Array(waiting.values)
        lock.unlock()
        all.forEach { $0.signal() }
    }

    private func handle(_ data: Data) {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let id = j["id"] as? Int {
            lock.lock()
            answers[id] = j
            let s = waiting[id]
            lock.unlock()
            s?.signal()
        } else if let method = j["method"] as? String {
            onEvent?(method, j["params"] as? [String: Any] ?? [:], j["sessionId"] as? String ?? "")
        }
    }

    @discardableResult
    private func send(_ method: String, _ params: [String: Any], _ session: String, wait: DispatchSemaphore?) -> Int {
        lock.lock()
        nextID += 1
        let id = nextID
        if let w = wait { waiting[id] = w }
        lock.unlock()
        var message: [String: Any] = ["id": id, "method": method, "params": params]
        if !session.isEmpty { message["sessionId"] = session }
        var data = HTTP.json(message)
        data.append(0)
        writeLock.lock()
        data.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            var sent = 0
            while sent < b.count {
                let n = write(fdOut, b.baseAddress! + sent, b.count - sent)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break }
                sent += n
            }
        }
        writeLock.unlock()
        return id
    }

    // Sends and does not wait for the answer
    func post(_ method: String, _ params: [String: Any] = [:], session: String = "") {
        send(method, params, session, wait: nil)
    }

    // Sends and waits for the answer: the whole message ("result" or "error"), nil when none came
    func call(_ method: String, _ params: [String: Any] = [:], session: String = "", timeout: TimeInterval = 15) -> [String: Any]? {
        let s = DispatchSemaphore(value: 0)
        let id = send(method, params, session, wait: s)
        _ = s.wait(timeout: .now() + timeout)
        lock.lock()
        let answer = answers.removeValue(forKey: id)
        waiting.removeValue(forKey: id)
        lock.unlock()
        return answer
    }
}

final class ChromiumProbe: @unchecked Sendable {
    static let host = "lotus-page.test"

    let page: URL
    let root: URL
    let realRoot: String
    let width: Int
    let shot: String?
    let selector: String

    private let lock = NSLock()
    private var console: [String] = []
    private var missing: [String] = []
    private var refused: [String] = []
    private var served: [String: Int] = [:]
    private var kinds: [String: (url: String, type: String)] = [:]       // request id → what it asked for
    private var finished = false
    private let loaded = DispatchSemaphore(value: 0)
    private var tools: DevTools?
    private var browserPid: pid_t = 0
    private var profile = ""
    private var session = ""

    init(page: URL, root: URL, width: Int, shot: String?, selector: String) {
        self.page = page
        self.root = root
        self.realRoot = root.resolvingSymlinksInPath().path
        self.width = width
        self.shot = shot
        self.selector = selector
    }

    // Everything a page could use to send something away that the Fetch domain does not see
    static let blockers = #"""
        (() => {
          const blocked = (what) => function () { throw new Error(what + ' is blocked while Lotus looks at the page'); };
          try { window.WebSocket = blocked('WebSocket'); } catch (e) {}
          try { window.EventSource = blocked('EventSource'); } catch (e) {}
          try { navigator.sendBeacon = function () { return false; }; } catch (e) {}
        })();
        """#

    // ── Start ──

    func go() -> Never {
        let watchdog = DispatchQueue(label: "lotus.page.watchdog")
        watchdog.asyncAfter(deadline: .now() + 25) { self.finish(["timedOut": true]) }
        guard let browser = PageView.browser() else {
            finish(["ok": false, "error": "view_page needs a Chromium-based browser on this system (Chromium, Chrome or Edge) – none was found"])
        }
        profile = NSTemporaryDirectory() + "lotus-page-\(getpid())-\(UInt32.random(in: 0...UInt32.max))"
        mkdir(profile, 0o700)

        // the browser reads its commands on its descriptor 3 and writes to us on 4
        var toBrowser: [Int32] = [-1, -1], fromBrowser: [Int32] = [-1, -1]
        guard pipe(&toBrowser) == 0, pipe(&fromBrowser) == 0 else { finish(["ok": false, "error": "No pipe for the browser"]) }
        for f in toBrowser + fromBrowser { _ = fcntl(f, F_SETFD, FD_CLOEXEC) }
        var flags = ["--headless=new", "--remote-debugging-pipe", "--user-data-dir=" + profile, "--disable-gpu", "--no-first-run",
                     "--no-default-browser-check", "--disable-extensions", "--disable-background-networking", "--disable-component-update",
                     "--disable-sync", "--disable-dev-shm-usage", "--mute-audio", "--hide-scrollbars", "--force-color-profile=srgb",
                     "--window-size=\(width),900", "about:blank"]
        let env = ProcessInfo.processInfo.environment
        // the browser's own sandbox stays on. It cannot start as root, and in some containers it cannot start at all:
        // there it is turned off only when the user says so.
        if geteuid() == 0 || env["LOTUS_PAGE_NOSANDBOX"] == "1" { flags.insert("--no-sandbox", at: 1) }
        var clean = env
        for k in clean.keys where k.hasPrefix("LOTUS_AI_") { clean.removeValue(forKey: k) }
        guard let child = spawnProgram(browser, flags, env: clean, ownGroup: true,
                                       fdMap: [(toBrowser[0], 3), (fromBrowser[1], 4)], logTo: profile + "/browser.log") else {
            finish(["ok": false, "error": "The browser could not be started (\(browser))"])
        }
        browserPid = child.pid
        close(toBrowser[0])
        close(fromBrowser[1])
        let dt = DevTools(out: toBrowser[1], in: fromBrowser[0])
        tools = dt
        dt.onEvent = { [unowned self] method, params, sid in self.event(method, params, sid) }

        guard dt.call("Browser.getVersion", timeout: 20)?["result"] != nil else {
            var why = ((try? String(contentsOfFile: profile + "/browser.log", encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init).first { !$0.isEmpty } ?? ""
            if why.lowercased().contains("sandbox") || why.lowercased().contains("namespace") {
                why = "the browser's own sandbox cannot start here (this system does not allow it for a normal user). Set LOTUS_PAGE_NOSANDBOX=1 to look at pages without the sandbox."
            }
            finish(["ok": false, "error": "The browser did not start" + (why.isEmpty ? "" : ": " + why)])
        }

        // the page the browser opened by itself
        var targetID = ""
        if let infos = (dt.call("Target.getTargets")?["result"] as? [String: Any])?["targetInfos"] as? [[String: Any]] {
            targetID = infos.first { $0["type"] as? String == "page" }?["targetId"] as? String ?? ""
        }
        if targetID.isEmpty {
            targetID = ((dt.call("Target.createTarget", ["url": "about:blank"])?["result"] as? [String: Any])?["targetId"] as? String) ?? ""
        }
        guard !targetID.isEmpty,
              let sid = (dt.call("Target.attachToTarget", ["targetId": targetID, "flatten": true])?["result"] as? [String: Any])?["sessionId"] as? String
        else { finish(["ok": false, "error": "The browser has no page to open"]) }
        session = sid

        for method in ["Page.enable", "Runtime.enable", "Network.enable"] { _ = dt.call(method, session: sid) }
        _ = dt.call("Browser.setDownloadBehavior", ["behavior": "deny"])
        _ = dt.call("Network.setBlockedURLs", ["urls": ["ws://*", "wss://*"]], session: sid)
        _ = dt.call("Emulation.setDeviceMetricsOverride", ["width": width, "height": 900, "deviceScaleFactor": 1, "mobile": false], session: sid)
        _ = dt.call("Page.addScriptToEvaluateOnNewDocument", ["source": ChromiumProbe.blockers], session: sid)
        // without the interception the page could send things away: then it is not opened at all
        guard dt.call("Fetch.enable", ["patterns": [["urlPattern": "*"]]], session: sid)?["error"] == nil else {
            finish(["ok": false, "error": "The browser could not block sending – the page was not opened"])
        }

        let rel = page.path.hasPrefix(root.path + "/") ? String(page.path.dropFirst(root.path.count + 1)) : page.lastPathComponent
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        let url = "http://\(ChromiumProbe.host)/" + (rel.addingPercentEncoding(withAllowedCharacters: allowed) ?? rel)
        let nav = dt.call("Page.navigate", ["url": url], session: sid)
        if let why = (nav?["result"] as? [String: Any])?["errorText"] as? String { finish(["ok": false, "error": why]) }
        guard nav != nil else { finish(["ok": false, "error": "The browser did not answer"]) }
        _ = loaded.wait(timeout: .now() + 20)
        Thread.sleep(forTimeInterval: 0.7)            // scripts that build the page after loading get a moment
        inspect()
    }

    // ── What is on the page ──

    private func inspect() -> Never {
        guard let dt = tools else { finish(["ok": false, "error": "The browser is gone"]) }
        let sel = String(decoding: (try? JSONSerialization.data(withJSONObject: [selector])) ?? Data("[\"\"]".utf8), as: UTF8.self)
        let expression = "(\(PageSurvey.script))(\(sel)[0])"
        let answer = dt.call("Runtime.evaluate", ["expression": expression, "returnByValue": true], session: session)
        let value = ((answer?["result"] as? [String: Any])?["result"] as? [String: Any])?["value"] as? String
        let info: [String: Any] = value.flatMap { HTTP.parse($0) }
            ?? ["scriptError": ((answer?["result"] as? [String: Any])?["exceptionDetails"] as? [String: Any])?["text"] as? String ?? "no answer"]
        var out: [String: Any] = ["ok": true, "info": info]
        if let shot = shot {
            // the whole page, up to 2400 px high
            let height = min(max(info["height"] as? Int ?? 900, 300), 2400)
            _ = dt.call("Emulation.setDeviceMetricsOverride", ["width": width, "height": height, "deviceScaleFactor": 1, "mobile": false], session: session)
            Thread.sleep(forTimeInterval: 0.4)
            let clip: [String: Any] = ["x": 0, "y": 0, "width": width, "height": height, "scale": min(1.0, 1000.0 / Double(width))]
            let cap = dt.call("Page.captureScreenshot", ["format": "jpeg", "quality": 72, "clip": clip], session: session)
            if let b64 = (cap?["result"] as? [String: Any])?["data"] as? String, let data = Data(base64Encoded: b64),
               (try? data.write(to: URL(fileURLWithPath: shot))) != nil {
                out["shot"] = shot
            }
        }
        finish(out)
    }

    // ── What the browser tells ──

    private func note(_ list: ReferenceWritableKeyPath<ChromiumProbe, [String]>, _ line: String) {
        lock.lock()
        if self[keyPath: list].count < 60 && !self[keyPath: list].contains(line) { self[keyPath: list].append(line) }
        lock.unlock()
    }

    private func event(_ method: String, _ p: [String: Any], _ sid: String) {
        switch method {
        case "Page.loadEventFired":
            loaded.signal()
        case "Page.javascriptDialogOpening":
            tools?.post("Page.handleJavaScriptDialog", ["accept": false], session: sid)
        case "Runtime.consoleAPICalled":
            let type = p["type"] as? String ?? ""
            guard type == "error" || type == "warning" || type == "assert" else { return }
            let parts = (p["args"] as? [[String: Any]] ?? []).map { a -> String in
                if let s = a["value"] as? String { return s }
                if let d = a["description"] as? String { return d }
                return a["value"].map { "\($0)" } ?? ""
            }
            note(\.console, "\(type == "warning" ? "warn" : "error"): " + String(parts.joined(separator: " ").prefix(500)))
        case "Runtime.exceptionThrown":
            let d = p["exceptionDetails"] as? [String: Any] ?? [:]
            let description = ((d["exception"] as? [String: Any])?["description"] as? String) ?? (d["text"] as? String) ?? "Error"
            var text = description.components(separatedBy: "\n").first ?? "Error"
            if text.hasPrefix("Uncaught ") { text = String(text.dropFirst(9)) }
            let file = (d["url"] as? String).flatMap { URL(string: $0)?.lastPathComponent } ?? ""
            let line = (d["lineNumber"] as? Int).map { $0 + 1 } ?? 0
            note(\.console, "error: " + String(text.prefix(400)) + (file.isEmpty ? "" : " (\(file):\(line))"))
        case "Network.requestWillBeSent":
            if let id = p["requestId"] as? String, let url = (p["request"] as? [String: Any])?["url"] as? String {
                lock.lock(); kinds[id] = (url, p["type"] as? String ?? ""); lock.unlock()
            }
        case "Network.loadingFailed":
            lock.lock(); let k = (p["requestId"] as? String).flatMap { kinds[$0] }; lock.unlock()
            if let k = k, k.url.hasPrefix("http"), !k.url.contains(ChromiumProbe.host), ChromiumProbe.assetTypes.contains(k.type),
               p["canceled"] as? Bool != true {
                note(\.console, "missing: \(k.url)")
            }
        case "Network.responseReceived":
            let r = p["response"] as? [String: Any] ?? [:]
            let url = r["url"] as? String ?? ""
            if (r["status"] as? Int ?? 0) >= 400, url.hasPrefix("http"), !url.contains(ChromiumProbe.host),
               ChromiumProbe.assetTypes.contains(p["type"] as? String ?? "") {
                note(\.console, "missing: \(url)")
            }
        case "Fetch.requestPaused":
            paused(p, sid)
        default:
            break
        }
    }

    static let assetTypes: Set<String> = ["Stylesheet", "Script", "Image", "Font", "Media"]

    // Every request of the page passes here: its own files come from the folder, assets may come from the internet,
    // everything else is refused
    private func paused(_ p: [String: Any], _ sid: String) {
        guard let id = p["requestId"] as? String, let req = p["request"] as? [String: Any],
              let urlString = req["url"] as? String, let url = URL(string: urlString) else { return }
        let type = p["resourceType"] as? String ?? ""
        if url.host == ChromiumProbe.host {
            if url.path == "/favicon.ico" && type != "Image" && type != "Stylesheet" { return reply(id, 204, Data(), "image/x-icon", sid) }
            return serve(id, url, sid)
        }
        let web = url.scheme == "http" || url.scheme == "https"
        if web && ChromiumProbe.assetTypes.contains(type) && (req["method"] as? String ?? "GET") == "GET" {
            tools?.post("Fetch.continueRequest", ["requestId": id], session: sid)
        } else {
            tools?.post("Fetch.failRequest", ["requestId": id, "errorReason": "BlockedByClient"], session: sid)
        }
    }

    private func serve(_ id: String, _ url: URL, _ sid: String) {
        var rel = String((url.path.removingPercentEncoding ?? url.path).drop(while: { $0 == "/" }))
        if rel.isEmpty || rel.hasSuffix("/") { rel += "index.html" }
        var file = root.appendingPathComponent(rel).standardizedFileURL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), isDir.boolValue { file.appendPathComponent("index.html") }
        let real = file.resolvingSymlinksInPath().path
        guard real == realRoot || real.hasPrefix(realRoot + "/") else {
            note(\.refused, "\(rel) (outside the folder)")
            return reply(id, 403, Data(), "text/plain", sid)
        }
        if ToolRunner.isPrivate(file) {
            note(\.refused, "\(rel) (private)")
            return reply(id, 403, Data(), "text/plain", sid)
        }
        guard let data = FileManager.default.contents(atPath: file.path) else {
            note(\.missing, rel)
            return reply(id, 404, Data("Not found".utf8), "text/plain", sid)
        }
        let ext = file.pathExtension.lowercased()
        if ["css", "js", "mjs"].contains(ext) { lock.lock(); served[rel] = data.count; lock.unlock() }
        var type = ChromiumProbe.types[ext] ?? "application/octet-stream"
        if type.hasPrefix("text/") || type.contains("javascript") || type.contains("json") || type.contains("svg") { type += "; charset=utf-8" }
        reply(id, 200, data, type, sid)
    }

    private func reply(_ id: String, _ status: Int, _ data: Data, _ type: String, _ sid: String) {
        tools?.post("Fetch.fulfillRequest", ["requestId": id, "responseCode": status,
                                             "responseHeaders": [["name": "Content-Type", "value": type], ["name": "Cache-Control", "value": "no-store"]],
                                             "body": data.base64EncodedString()], session: sid)
    }

    static let types: [String: String] = [
        "html": "text/html", "htm": "text/html", "css": "text/css", "js": "text/javascript", "mjs": "text/javascript",
        "json": "application/json", "map": "application/json", "txt": "text/plain", "xml": "text/xml", "svg": "image/svg+xml",
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "avif": "image/avif",
        "ico": "image/x-icon", "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf",
        "wasm": "application/wasm", "mp4": "video/mp4", "webm": "video/webm", "mp3": "audio/mpeg", "wav": "audio/wav",
    ]

    // ── End ──

    private func finish(_ extra: [String: Any]) -> Never {
        lock.lock()
        if finished { lock.unlock(); while true { sleep(1) } }      // another thread is already finishing
        finished = true
        var out = extra
        out["width"] = width
        out["console"] = console
        out["missing"] = missing
        out["refused"] = refused
        out["served"] = served
        lock.unlock()
        if out["ok"] == nil { out["ok"] = false }
        print(String(decoding: HTTP.json(out), as: UTF8.self))
        fflush(stdout)
        // the browser and everything it started
        tools?.post("Browser.close")
        if browserPid > 0 {
            for _ in 0..<30 {
                var status: Int32 = 0
                if waitpid(browserPid, &status, WNOHANG) != 0 { break }
                usleep(50_000)
            }
            kill(-browserPid, SIGKILL)
            var status: Int32 = 0
            _ = waitpid(browserPid, &status, WNOHANG)
        }
        if !profile.isEmpty { try? FileManager.default.removeItem(atPath: profile) }
        exit(0)
    }
}
#endif
