// Lotus AI – view_page: the AI looks at the web pages it builds. The page is rendered in WebKit (the
// engine of Safari) without a window, and Lotus reports what a person would notice.
//   lotus-ai --render <page> <width> <folder> <screenshot.jpg | -> [<css selector>]
//   → one JSON line: title, structure, console errors, files that did not load, what is wider than the
//     screen, images without alt text, form fields without a label, the elements asked for
// ToolRunner.viewPage runs this as a process of its own, at desktop and at phone width.
// The page is served from its folder as lotus-page://site/… – nothing outside the folder, never private
// files (.env, keys). Scripts, styles, fonts and images may come from the internet; everything that
// could send something away (fetch, XHR, WebSockets, beacons) is blocked while the page is looked at.

import AppKit
import UniformTypeIdentifiers
import WebKit

enum PageView {
    static let scheme = "lotus-page"

    // A smaller copy of a screenshot (for the web chat, which keeps it with the conversation)
    static func smaller(_ data: Data, maxWidth: Int) -> Data? {
        guard let image = NSImage(data: data), image.size.width > CGFloat(maxWidth) else { return nil }
        return PageProbe.jpeg(image, maxWidth: maxWidth)
    }

    static func run(_ args: [String]) -> Never {
        guard args.count >= 4, let width = Int(args[1]), (200...3000).contains(width) else {
            print(#"{"ok":false,"error":"usage: lotus-ai --render <page> <width> <folder> <screenshot.jpg|-> [selector]"}"#)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let probe = PageProbe(page: URL(fileURLWithPath: args[0]).standardizedFileURL,
                              root: URL(fileURLWithPath: args[2]).standardizedFileURL,
                              width: width, shot: args[3] == "-" ? nil : args[3], selector: args.count > 4 ? args[4] : "")
        probe.start()
        app.run()
        exit(0)
    }
}

final class PageProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKURLSchemeHandler {
    let page: URL
    let root: URL
    let realRoot: String
    let width: Int
    let shot: String?
    let selector: String
    private var web: WKWebView!
    private var console: [String] = []
    private var missing: [String] = []
    private var refused: [String] = []
    private var served: [String: Int] = [:]     // styles and scripts of the folder, with their size
    private var finished = false

    init(page: URL, root: URL, width: Int, shot: String?, selector: String) {
        self.page = page
        self.root = root
        self.realRoot = root.resolvingSymlinksInPath().path
        self.width = width
        self.shot = shot
        self.selector = selector
    }

    // Everything a page could use to send something away; scripts, styles, fonts and images still load
    static let rules = #"""
        [{"trigger": {"url-filter": "^https?://", "resource-type": ["raw", "fetch", "websocket", "ping", "other", "popup"]}, "action": {"type": "block"}},
         {"trigger": {"url-filter": "^wss?://"}, "action": {"type": "block"}}]
        """#

    // Console errors and warnings, uncaught errors and files from the internet that did not load
    static let capture = #"""
        (() => {
          const post = (kind, text) => { try { window.webkit.messageHandlers.lotus.postMessage(kind + '\u0001' + String(text).slice(0, 500)); } catch (e) {} };
          const show = (x) => { try { return typeof x === 'string' ? x : x instanceof Error ? x.name + ': ' + x.message : JSON.stringify(x); } catch (e) { return String(x); } };
          for (const kind of ['error', 'warn']) {
            const orig = console[kind];
            console[kind] = function (...a) { post(kind, a.map(show).join(' ')); return orig.apply(console, a); };
          }
          addEventListener('error', (e) => {
            const t = e.target;
            if (t && t !== window) { const u = t.src || t.href || ''; if (/^https?:/.test(u)) post('remote', u); return; }
            post('error', (e.message || 'Error') + (e.filename ? ' (' + String(e.filename).split('/').pop() + ':' + e.lineno + ')' : ''));
          }, true);
          addEventListener('unhandledrejection', (e) => post('error', 'Unhandled promise rejection: ' + show(e.reason)));
        })();
        """#

    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(self, forURLScheme: PageView.scheme)
        config.userContentController.addUserScript(WKUserScript(source: PageProbe.capture, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.add(self, name: "lotus")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 900), configuration: config)
        web.navigationDelegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { self.report(["timedOut": true]) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lotus-page-rules")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let store = WKContentRuleListStore(url: dir) else { return fail("WebKit could not set up its rules") }
        store.compileContentRuleList(forIdentifier: "lotus-page-v1", encodedContentRuleList: PageProbe.rules) { list, _ in
            // without the rules the page could send things away: then it is not opened at all
            guard let list = list else { return self.fail("WebKit could not block sending – the page was not opened") }
            config.userContentController.add(list)
            let rel = self.page.path.hasPrefix(self.root.path + "/") ? String(self.page.path.dropFirst(self.root.path.count + 1)) : self.page.lastPathComponent
            var c = URLComponents()
            c.scheme = PageView.scheme
            c.host = "site"
            c.path = "/" + rel
            guard let url = c.url else { return self.fail("Not a page Lotus can open") }
            self.web.load(URLRequest(url: url))
        }
    }

    // ── The page's files: only its folder, never private files ──

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var rel = String(url.path.drop(while: { $0 == "/" }))
        if rel.isEmpty || rel.hasSuffix("/") { rel += "index.html" }
        var file = root.appendingPathComponent(rel).standardizedFileURL
        func respond(_ status: Int, _ data: Data, _ type: String) {
            let headers = ["Content-Type": type, "Content-Length": String(data.count), "Cache-Control": "no-store"]
            guard let r = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
            task.didReceive(r)
            task.didReceive(data)
            task.didFinish()
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), isDir.boolValue { file.appendPathComponent("index.html") }
        let real = file.resolvingSymlinksInPath().path
        guard real == realRoot || real.hasPrefix(realRoot + "/") else {
            refused.append("\(rel) (outside the folder)")
            return respond(403, Data(), "text/plain")
        }
        if ToolRunner.isPrivate(file) {
            refused.append("\(rel) (private)")
            return respond(403, Data(), "text/plain")
        }
        guard let data = FileManager.default.contents(atPath: file.path) else {
            if !missing.contains(rel) { missing.append(rel) }
            return respond(404, Data("Not found".utf8), "text/plain")
        }
        if ["css", "js", "mjs"].contains(file.pathExtension.lowercased()) { served[rel] = data.count }
        var type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        if type.hasPrefix("text/") || type.contains("javascript") || type.contains("json") || type.contains("svg") { type += "; charset=utf-8" }
        respond(200, data, type)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard console.count < 60, let s = m.body as? String else { return }
        let parts = s.split(separator: "\u{1}", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let line = parts[0] == "remote" ? "missing: \(parts[1])" : "\(parts[0]): \(parts[1])"
        if !console.contains(line) { console.append(line) }
    }

    // ── Loading ──

    // Links and scripts may not lead the page away to the internet while it is looked at
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = action.request.url?.scheme ?? ""
        decisionHandler(scheme == PageView.scheme || scheme == "about" || scheme == "data" || scheme == "blob" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // scripts that build the page after loading get a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.inspect() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("The page crashed WebKit (it may use too much memory or loop forever)")
    }

    private func fail(_ why: String) {
        report(["ok": false, "error": why])
    }

    // ── What is on the page ──

    private func inspect() {
        let sel = String(decoding: (try? JSONSerialization.data(withJSONObject: [selector])) ?? Data("[\"\"]".utf8), as: UTF8.self)
        web.evaluateJavaScript("(\(PageProbe.survey))(\(sel)[0])") { result, error in
            let info = (result as? String).flatMap { HTTP.parse($0) } ?? ["scriptError": error?.localizedDescription ?? "no answer"]
            guard let shot = self.shot else { return self.report(["ok": true, "info": info]) }
            // the whole page, up to 2400 px high
            let height = min(max(info["height"] as? Int ?? 900, 300), 2400)
            self.web.frame = NSRect(x: 0, y: 0, width: self.width, height: height)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.web.takeSnapshot(with: nil) { image, _ in
                    var out: [String: Any] = ["ok": true, "info": info]
                    if let image = image, let jpeg = PageProbe.jpeg(image, maxWidth: 1000) {
                        if (try? jpeg.write(to: URL(fileURLWithPath: shot))) != nil { out["shot"] = shot }
                    }
                    self.report(out)
                }
            }
        }
    }

    static func jpeg(_ image: NSImage, maxWidth: Int) -> Data? {
        let scale = min(1, CGFloat(maxWidth) / max(1, image.size.width))
        let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
        guard w > 0, h > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }

    private func report(_ extra: [String: Any]) {
        guard !finished else { return }
        finished = true
        var out = extra
        out["width"] = width
        out["console"] = console
        out["missing"] = missing
        out["refused"] = refused
        out["served"] = served
        if out["ok"] == nil { out["ok"] = false }
        print(String(decoding: HTTP.json(out), as: UTF8.self))
        exit(0)
    }

    // Runs in the page: what a person would notice, and the elements asked for (a CSS selector)
    static let survey = #"""
        function (sel) {
          const text = (el) => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80);
          const name = (el) => {
            let s = el.tagName.toLowerCase();
            if (el.id) s += '#' + el.id;
            if (el.classList && el.classList.length) s += '.' + [...el.classList].slice(0, 2).join('.');
            return s;
          };
          const visible = (el) => {
            const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
            return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none' && cs.opacity !== '0';
          };
          const doc = document.documentElement;
          const view = window.innerWidth;
          // what sticks out sideways: the outermost elements that end right of the screen
          const wide = [];
          if (doc.scrollWidth > view + 1 && document.body) {
            for (const el of document.body.querySelectorAll('*')) {
              const r = el.getBoundingClientRect();
              if (r.width > 0 && r.right > view + 1 && !(el.parentElement && el.parentElement.getBoundingClientRect().right > view + 1 && el.parentElement !== document.body)) {
                wide.push(name(el) + ' (' + Math.round(r.width) + ' px wide, ends at ' + Math.round(r.right) + ' px)');
                if (wide.length >= 5) break;
              }
            }
          }
          const fields = [...document.querySelectorAll('input:not([type=hidden]):not([type=submit]):not([type=button]):not([type=reset]), select, textarea')];
          const unlabeled = fields.filter((f) => !(f.id && document.querySelector('label[for="' + CSS.escape(f.id) + '"]')) && !f.closest('label') && !f.getAttribute('aria-label') && !f.getAttribute('aria-labelledby'));
          let elements = null, selError = '';
          if (sel) {
            try {
              const all = [...document.querySelectorAll(sel)];
              elements = { count: all.length, items: all.slice(0, 8).map((el) => {
                const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
                return { el: name(el), box: [Math.round(r.left + scrollX), Math.round(r.top + scrollY), Math.round(r.width), Math.round(r.height)],
                  visible: visible(el), text: text(el), display: cs.display, position: cs.position, color: cs.color, background: cs.backgroundColor,
                  font: cs.fontSize + ' ' + cs.fontWeight + ' ' + cs.fontFamily.split(',')[0].replace(/["']/g, ''), margin: cs.margin, padding: cs.padding };
              }) };
            } catch (e) { selError = String(e.message || e); }
          }
          return JSON.stringify({
            title: document.title, lang: doc.lang || '', viewport: !!document.querySelector('meta[name="viewport"]'),
            view, scrollWidth: doc.scrollWidth, height: Math.max(doc.scrollHeight, document.body ? document.body.scrollHeight : 0), wide,
            landmarks: ['header', 'nav', 'main', 'footer'].filter((t) => document.querySelector(t)),
            headings: [...document.querySelectorAll('h1, h2, h3')].slice(0, 24).map((h) => h.tagName.toLowerCase() + ' "' + text(h) + '"'),
            h1: document.querySelectorAll('h1').length,
            links: document.querySelectorAll('a').length,
            deadLinks: [...document.querySelectorAll('a')].filter((a) => !a.getAttribute('href') || a.getAttribute('href') === '#').length,
            buttons: [...document.querySelectorAll('button, input[type=submit], input[type=button]')].slice(0, 10).map((b) => text(b) || b.value || b.getAttribute('aria-label') || '(no text)'),
            forms: document.forms.length, fields: fields.length, unlabeled: unlabeled.length,
            images: document.images.length,
            noAlt: [...document.images].filter((i) => !i.hasAttribute('alt')).slice(0, 8).map((i) => i.getAttribute('src') || '(inline)'),
            broken: [...document.images].filter((i) => i.complete && i.naturalWidth === 0 && i.getAttribute('src')).slice(0, 8).map((i) => i.getAttribute('src')),
            text: (document.body ? document.body.innerText : '').replace(/\s+/g, ' ').trim().slice(0, 900),
            elements, selError,
          });
        }
        """#
}
