import Foundation

// ── The internet ──────────────────────────────────────────────
// web_search finds pages (DuckDuckGo; Wikipedia when DuckDuckGo does not answer), fetch_url reads one
// as plain text. Only http(s) on the public internet – nothing on this Mac or in the local network,
// so a page cannot make the AI talk to the router or to the model server on 127.0.0.1.

enum Web {
    static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 Lotus"
    static let maxBytes = 2_500_000

    struct Result { let title: String; let url: String; let snippet: String }
    struct Page { let url: URL; let title: String; let text: String; let links: [(text: String, url: String)]; let bytes: Int }
    struct Failure: Error { let message: String }

    // ── Search ──

    static func search(_ query: String) async throws -> (results: [Result], source: String) {
        // a short hiccup of the network: one more try
        for attempt in 0..<2 {
            if let r = try? await duckDuckGo(query), !r.isEmpty { return (r, "DuckDuckGo") }
            if let r = try? await wikipedia(query) { return (r, "Wikipedia") }
            if attempt == 0 { try await Task.sleep(nanoseconds: 1_500_000_000) }
        }
        throw Failure(message: "The search did not answer – is this Mac online?")
    }

    private static func duckDuckGo(_ query: String) async throws -> [Result] {
        var req = URLRequest(url: URL(string: "https://html.duckduckgo.com/html/")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue(agent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "q", value: query)]
        req.httpBody = (form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: "DuckDuckGo did not answer") }
        let html = String(decoding: data, as: UTF8.self)
        let links = matches(#"(?is)<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, html)
            + matches(#"(?is)<a[^>]*href="([^"]+)"[^>]*class="result__a"[^>]*>(.*?)</a>"#, html)
        let snippets = matches(#"(?is)<a[^>]*class="result__snippet"[^>]*>(.*?)</a>"#, html).map { $0[0] }
        var out: [Result] = []
        for (i, m) in links.enumerated() {
            var href = decode(m[0])
            if href.hasPrefix("//") { href = "https:" + href }
            // duckduckgo.com/l/?uddg=<the real address>; ads go through y.js
            if let c = URLComponents(string: href), c.host?.hasSuffix("duckduckgo.com") == true {
                guard let real = c.queryItems?.first(where: { $0.name == "uddg" })?.value else { continue }
                href = real
            }
            guard href.hasPrefix("http"), !out.contains(where: { $0.url == href }) else { continue }
            out.append(Result(title: clean(m[1]), url: href, snippet: i < snippets.count ? clean(snippets[i]) : ""))
            if out.count == 8 { break }
        }
        return out
    }

    private static func wikipedia(_ query: String) async throws -> [Result] {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        var results: [Result] = []
        for l in lang == "en" ? ["en"] : [lang, "en"] {
            var c = URLComponents(string: "https://\(l).wikipedia.org/w/api.php")!
            c.queryItems = [URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "list", value: "search"),
                            URLQueryItem(name: "srsearch", value: query), URLQueryItem(name: "format", value: "json"),
                            URLQueryItem(name: "srlimit", value: "6")]
            var req = URLRequest(url: c.url!, timeoutInterval: 15)
            req.setValue("Lotus/\(ProcessInfo.processInfo.environment["LOTUS_VERSION"] ?? "2") (https://fanxy13.github.io/homebrew-lotus/)", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hits = (j["query"] as? [String: Any])?["search"] as? [[String: Any]] else { continue }
            for h in hits {
                guard let t = h["title"] as? String else { continue }
                let path = t.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? t
                results.append(Result(title: t + " – Wikipedia", url: "https://\(l).wikipedia.org/wiki/\(path)", snippet: clean(h["snippet"] as? String ?? "")))
            }
            if !results.isEmpty { break }
        }
        guard !results.isEmpty else { throw Failure(message: "The search did not answer – is this Mac online?") }
        return results
    }

    // ── Reading a page ──

    static func isPublic(_ url: URL) -> Bool { refusal(url) == nil }

    // Only the public internet: http(s), no user:password@, no local names or addresses.
    // nil: fine. Otherwise why not.
    static func refusal(_ url: URL) -> String? {
        let notPublic = "Lotus only opens pages on the public internet (http or https), nothing on this Mac or in the local network."
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil else { return notPublic }
        let local = ["localhost", ".localhost", ".local", ".internal", ".lan", ".home.arpa", ".home", ".corp", ".intranet"]
        if local.contains(where: { host == $0 || ($0.hasPrefix(".") && host.hasSuffix($0)) }) { return notPublic }
        if !host.contains(".") && !host.contains(":") { return notPublic }
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return "Could not find \(host) – is this Mac online?" }
        defer { freeaddrinfo(first) }
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let a = p {
            if a.pointee.ai_family == AF_INET, let sa = a.pointee.ai_addr {
                let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                if !publicV4(ip) { return notPublic }
            } else if a.pointee.ai_family == AF_INET6, let sa = a.pointee.ai_addr {
                let b = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { s in withUnsafeBytes(of: s.pointee.sin6_addr) { Array($0) } }
                if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff {
                    if !publicV4(UInt32(b[12]) << 24 | UInt32(b[13]) << 16 | UInt32(b[14]) << 8 | UInt32(b[15])) { return notPublic }
                } else if b.allSatisfy({ $0 == 0 }) || (b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1)
                            || (b[0] == 0xfe && b[1] & 0xc0 == 0x80) || b[0] & 0xfe == 0xfc || b[0] == 0xff {
                    return notPublic
                }
            }
            p = a.pointee.ai_next
        }
        return nil
    }

    private static func publicV4(_ ip: UInt32) -> Bool {
        let a = ip >> 24, b = (ip >> 16) & 0xff
        return !(a == 0 || a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
                 || (a == 169 && b == 254) || (a == 100 && (64...127).contains(b)) || a >= 224)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)      // every hop is checked by fetch itself
        }
    }
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }()

    static func fetch(_ start: URL) async throws -> Page {
        if let docs = try? await appleDocs(start) { return docs }
        var url = start
        for _ in 0..<6 {
            if let why = refusal(url) { throw Failure(message: why) }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue(agent, forHTTPHeaderField: "User-Agent")
            req.setValue("text/html,application/xhtml+xml,text/plain,application/json;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
            req.setValue(Locale.preferredLanguages.prefix(2).joined(separator: ",") + ",en;q=0.5", forHTTPHeaderField: "Accept-Language")
            let (bytes, response) = try await session.bytes(for: req)
            guard let http = response as? HTTPURLResponse else { throw Failure(message: "No answer from \(url.host ?? "the page")") }
            if (300...399).contains(http.statusCode), let loc = http.value(forHTTPHeaderField: "Location"), let next = URL(string: loc, relativeTo: url)?.absoluteURL {
                url = next
                continue
            }
            guard (200...299).contains(http.statusCode) else { throw Failure(message: "The page answered with \(http.statusCode)") }
            let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if type.contains("pdf") { throw Failure(message: "That is a PDF – Lotus reads web pages and text, not PDFs from the web.") }
            if !type.isEmpty && !(type.hasPrefix("text/") || type.contains("json") || type.contains("xml") || type.contains("javascript")) {
                throw Failure(message: "That is not a page or text (\(type.split(separator: ";").first ?? ""))")
            }
            var data = Data()
            data.reserveCapacity(min(maxBytes, Int(max(0, http.expectedContentLength))))
            for try await b in bytes {
                data.append(b)
                if data.count >= maxBytes { break }
            }
            let raw = String(decoding: data, as: UTF8.self)
            if type.contains("html") || type.isEmpty && raw.prefix(500).lowercased().contains("<html") {
                var r = readable(raw, base: url)
                if r.text.count < 200 {
                    // built by JavaScript: at least what the page says about itself
                    let meta = matches(#"(?is)<meta[^>]*(?:name|property)=["'](?:og:)?description["'][^>]*content=["']([^"']*)["']"#, raw).first.map { clean($0[0]) } ?? ""
                    r.text = (meta.isEmpty ? "" : meta + "\n\n") + r.text
                        + "\n\n[This page is built by JavaScript in the browser, so only this much of it could be read.]"
                }
                return Page(url: url, title: r.title, text: r.text, links: r.links, bytes: data.count)
            }
            return Page(url: url, title: url.lastPathComponent, text: raw, links: [], bytes: data.count)
        }
        throw Failure(message: "Too many redirects")
    }

    // ── Apple's documentation ──
    // developer.apple.com/documentation is built in the browser; the same text comes as JSON

    private static func appleDocs(_ url: URL) async throws -> Page? {
        guard url.host == "developer.apple.com", url.path.hasPrefix("/documentation/") else { return nil }
        let json = URL(string: "https://developer.apple.com/tutorials/data" + url.path.lowercased().replacingOccurrences(of: "/$", with: "", options: .regularExpression) + ".json")!
        var req = URLRequest(url: json, timeoutInterval: 20)
        req.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let refs = j["references"] as? [String: [String: Any]] ?? [:]
        func inline(_ v: Any?) -> String {
            (v as? [[String: Any]] ?? []).map { i -> String in
                switch i["type"] as? String {
                case "text": return i["text"] as? String ?? ""
                case "codeVoice": return "`\(i["code"] as? String ?? "")`"
                case "reference": return refs[i["identifier"] as? String ?? ""]?["title"] as? String ?? ""
                case "link": return i["title"] as? String ?? ""
                default: return inline(i["inlineContent"])
                }
            }.joined()
        }
        func blocks(_ v: Any?) -> [String] {
            (v as? [[String: Any]] ?? []).flatMap { b -> [String] in
                switch b["type"] as? String {
                case "heading": return ["", "# " + (b["text"] as? String ?? "")]
                case "paragraph": return [inline(b["inlineContent"])]
                case "codeListing": return ["```" + (b["syntax"] as? String ?? "")] + (b["code"] as? [String] ?? []) + ["```"]
                case "unorderedList", "orderedList": return (b["items"] as? [[String: Any]] ?? []).map { "- " + blocks($0["content"]).joined(separator: " ") }
                case "aside": return ["Note: " + blocks(b["content"]).joined(separator: " ")]
                default: return blocks(b["content"])
                }
            }
        }
        let title = (j["metadata"] as? [String: Any])?["title"] as? String ?? url.lastPathComponent
        var lines = ["# " + title, inline(j["abstract"])]
        for sec in j["primaryContentSections"] as? [[String: Any]] ?? [] {
            switch sec["kind"] as? String {
            case "declarations":
                for d in sec["declarations"] as? [[String: Any]] ?? [] {
                    lines += ["", "```swift", (d["tokens"] as? [[String: Any]] ?? []).map { $0["text"] as? String ?? "" }.joined(), "```"]
                }
            case "parameters":
                lines += ["", "# Parameters"] + (sec["parameters"] as? [[String: Any]] ?? []).map { "- \($0["name"] as? String ?? ""): " + blocks($0["content"]).joined(separator: " ") }
            case "content":
                lines += blocks(sec["content"])
            default:
                break
            }
        }
        var links: [(text: String, url: String)] = []
        for sec in j["topicSections"] as? [[String: Any]] ?? [] {
            lines += ["", "# " + (sec["title"] as? String ?? "Topics")]
            for id in sec["identifiers"] as? [String] ?? [] {
                guard let r = refs[id] else { continue }
                let t = r["title"] as? String ?? ""
                lines.append("- \(t)" + { let a = inline(r["abstract"]); return a.isEmpty ? "" : ": " + a }())
                if let u = r["url"] as? String, links.count < 25 { links.append((t, "https://developer.apple.com" + u)) }
            }
        }
        return Page(url: url, title: title + " | Apple Developer Documentation", text: lines.joined(separator: "\n"), links: links, bytes: data.count)
    }

    // ── HTML to text ──

    // A tag with its attributes – attributes may hold ">" in quotes
    private static let attrs = #"(?:[^>"']|"[^"]*"|'[^']*')*"#

    static func readable(_ html: String, base: URL) -> (title: String, text: String, links: [(text: String, url: String)]) {
        let title = matches(#"(?is)<title[^>]*>(.*?)</title>"#, html).first.map { clean($0[0]) } ?? ""
        var h = html
        // Wikipedia: the article itself, without menus and the list of languages
        if let r = h.range(of: #"id="mw-content-text""#) { h = "<div " + h[r.lowerBound...] }
        h = replace(#"(?s)<!--.*?-->"#, h, " ")
        for tag in ["script", "style", "noscript", "svg", "template", "iframe", "head", "nav", "footer", "form", "aside", "button", "select", "canvas"] {
            h = replace(#"(?is)<"# + tag + #"\b"# + attrs + #">.*?</"# + tag + #"\s*>"#, h, " ")
        }
        // the page's own content, when it marks it (a README on GitHub, a blog post)
        if let article = matches(#"(?is)<article\b[^>]*>(.*)</article>"#, h).first?[0], article.count > 1000 {
            h = article
        } else if let main = matches(#"(?is)<main\b[^>]*>(.*)</main>"#, h).first?[0], main.count > 400 {
            h = main
        }
        var links: [(text: String, url: String)] = []
        for m in matches(#"(?is)<a\b[^>]*href\s*=\s*["']([^"'#][^"']*)["'][^>]*>(.*?)</a>"#, h) {
            let text = clean(m[1])
            guard text.count >= 3, text.count <= 80, let u = URL(string: decode(m[0]), relativeTo: base)?.absoluteURL,
                  u.scheme?.hasPrefix("http") == true, !links.contains(where: { $0.url == u.absoluteString }) else { continue }
            links.append((text, u.absoluteString))
            if links.count == 25 { break }
        }
        h = replace(#"(?i)<h[1-3]\b"# + attrs + #">"#, h, "\n\n# ")
        h = replace(#"(?i)<h[4-6]\b"# + attrs + #">"#, h, "\n\n## ")
        h = replace(#"(?i)</h[1-6]>"#, h, "\n\n")
        h = replace(#"(?i)<li\b"# + attrs + #">"#, h, "\n- ")
        h = replace(#"(?i)<br\s*/?>"#, h, "\n")
        h = replace(#"(?i)<pre\b"# + attrs + #">"#, h, "\n```\n")
        h = replace(#"(?i)</pre>"#, h, "\n```\n")
        h = replace(#"(?i)</?(p|div|section|tr|table|ul|ol|dl|dt|dd|blockquote|header|figure|figcaption|details|summary)\b"# + attrs + #">"#, h, "\n")
        h = replace(#"(?i)<t[dh]\b"# + attrs + #">"#, h, " ")
        h = replace(#"<"# + attrs + #">"#, h, "")
        h = decode(h)
        // tidy: no runs of spaces, no piles of empty lines
        var lines: [String] = []
        var inCode = false
        for line in h.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces) == "```" { inCode.toggle(); lines.append("```"); continue }
            let l = inCode ? line : line.replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if l.isEmpty && (lines.last?.isEmpty ?? true) { continue }
            if l == "-" || l == "#" || l == "##" { continue }
            lines.append(l)
        }
        // long runs of tiny list items are menus (languages, categories): one line instead
        var tidy: [String] = []
        var run: [String] = []
        func endRun() {
            if run.count >= 12 { tidy.append("[a menu of \(run.count) short links]") } else { tidy += run }
            run = []
        }
        for l in lines {
            if l.hasPrefix("- ") && l.count <= 28 { run.append(l) } else { endRun(); tidy.append(l) }
        }
        endRun()
        return (title, tidy.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), links)
    }

    // Text without tags and entities, on one line
    static func clean(_ s: String) -> String {
        decode(replace(#"<[^>]+>"#, s, "")).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "mdash": "—", "ndash": "–", "hellip": "…",
        "rsquo": "’", "lsquo": "‘", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»", "copy": "©", "reg": "®", "trade": "™",
        "euro": "€", "pound": "£", "middot": "·", "bull": "•", "times": "×", "deg": "°", "auml": "ä", "ouml": "ö", "uuml": "ü",
        "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß", "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç", "rarr": "→",
        "larr": "←", "zwj": "", "zwnj": "", "shy": "",
    ]

    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let re = try! NSRegularExpression(pattern: #"&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z]{2,8});"#)
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let name = ns.substring(with: m.range(at: 1))
            var rep: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") { rep = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } }
            else if name.hasPrefix("#") { rep = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) } }
            else { rep = entities[name] }
            out += rep ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    // ── Regular expressions ──

    static func matches(_ pattern: String, _ s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<max(1, m.numberOfRanges)).map { i in m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        }
    }

    static func replace(_ pattern: String, _ s: String, _ with: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: NSRegularExpression.escapedTemplate(for: with))
    }
}
