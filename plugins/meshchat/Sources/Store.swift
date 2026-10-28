// MeshChat – what it keeps on this Mac, all of it in its data folder ($LOTUS_PLUGIN_DATA, by default
// ~/.local/share/lotus/plugins/meshchat). Folders 0700 and files 0600: only your user can read them here – what
// was said is public anyway, but what you keep of it is yours.
//   settings          NICKNAME=…, LINKS=8  (Lotus' plugin settings file – other lines in it are left alone)
//   identity          this Mac's secret its signing key comes from: 32 random bytes, hex
//   history.jsonl     what was said while the chat was open, one message per line (the last 2000)
//   events.log        links and errors, for lotus meshchat doctor – never keys, names or messages
// MeshChat 1 kept rooms in rooms/; MeshChat 2 has none and leaves that folder as it is (the doctor names it).

import Foundation

struct StoredMessage: Equatable {
    var id: UInt64
    var sent: TimeInterval
    var received: TimeInterval
    var nickname: String
    var fingerprint: String
    var text: String
    var hops: Int
    var mine: Bool

    init(_ m: ChatMessage) {
        id = m.id
        sent = m.sent
        received = m.received
        nickname = m.nickname
        fingerprint = m.fingerprint
        text = m.text
        hops = m.hops
        mine = m.mine
    }

    var message: ChatMessage {
        ChatMessage(id: id, nickname: nickname, fingerprint: fingerprint, text: text, sent: sent, received: received, hops: hops, mine: mine)
    }
}

final class Store {
    static let historyKeep = 2000
    let dir: URL
    private let fm = FileManager.default

    init(dir: URL) {
        self.dir = dir
        try? makeFolder(dir)
        // Lotus makes the folder with the usual rights; it holds this Mac's identity, so it is this user's alone
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }

    // Only the folders that are missing, the innermost last. Lotus' sandbox refuses mkdir anywhere in the home
    // folder outside the plugin's data folder – even for folders that exist, which is what mkdir -p would try.
    private func makeFolder(_ url: URL) throws {
        var missing: [URL] = []
        var u = url.standardizedFileURL
        while !fm.fileExists(atPath: u.path) && u.path != "/" && missing.count < 32 {
            missing.append(u)
            u = u.deletingLastPathComponent()
        }
        for d in missing.reversed() {
            try fm.createDirectory(at: d, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
    }

    // Lotus says where: LOTUS_PLUGIN_DATA. Started by hand, the same place.
    static func standard() -> Store {
        let env = ProcessInfo.processInfo.environment
        if let d = env["LOTUS_PLUGIN_DATA"], !d.isEmpty { return Store(dir: URL(fileURLWithPath: d)) }
        let base = env["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? (NSHomeDirectory() + "/.local/share")
        return Store(dir: URL(fileURLWithPath: base + "/lotus/plugins/meshchat"))
    }

    var path: String { dir.path }

    private func file(_ name: String) -> URL { dir.appendingPathComponent(name) }

    // Written whole or not at all, readable only by this user
    private func write(_ data: Data, to url: URL) throws {
        try makeFolder(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // ── Settings ──────────────────────────────────────────────
    // One KEY=value per line, as Lotus keeps plugin settings (a pack can set them). Read line by line, never run.

    func settings() -> [String: String] {
        guard let text = try? String(contentsOf: file("settings"), encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "="), !line.hasPrefix("#") else { continue }
            let k = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty else { continue }
            out[k] = String(line[line.index(after: eq)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        }
        return out
    }

    // One key changed (nil: removed), the other lines kept as they are
    func set(_ key: String, _ value: String?) {
        let url = file("settings")
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        lines.removeAll { $0.hasPrefix(key + "=") }
        if let v = value { lines.append("\(key)=\(v.replacingOccurrences(of: "\n", with: " "))") }
        try? write(Data((lines.joined(separator: "\n") + "\n").utf8), to: url)
    }

    var nickname: String? {
        let n = Sanitize.nickname(settings()["NICKNAME"] ?? "")
        return n.isEmpty ? nil : n
    }

    var maxLinks: Int { Int(settings()["LINKS"] ?? "").map { max(1, min(8, $0)) } ?? 8 }

    // ── This Mac's identity ───────────────────────────────────
    // The secret the signing key comes from. Made once; a damaged file is replaced, and then the others see a new
    // fingerprint for you.

    func identity() -> Data {
        let url = file("identity")
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let d = Hex.decode(text.trimmingCharacters(in: .whitespacesAndNewlines)), d.count == 32 {
            return d
        }
        let d = CryptoBackend.randomBytes(32)
        try? write(Data((Hex.encode(d) + "\n").utf8), to: url)
        return d
    }

    // The rooms folder of MeshChat 1, when it is still there – nil when not
    var oldRooms: String? {
        let path = dir.appendingPathComponent("rooms").path
        return fm.fileExists(atPath: path) ? path : nil
    }

    // ── History ───────────────────────────────────────────────

    private var historyURL: URL { file("history.jsonl") }

    // The last messages, oldest first; damaged lines are skipped
    func history(last n: Int = 500) -> (messages: [StoredMessage], skipped: Int) {
        guard let text = try? String(contentsOf: historyURL, encoding: .utf8) else { return ([], 0) }
        var out: [StoredMessage] = []
        var skipped = 0
        for line in text.split(separator: "\n").suffix(max(n * 2, n + 100)) {
            guard let m = Store.decode(Data(line.utf8)) else {
                skipped += 1
                continue
            }
            out.append(m)
        }
        // in the order they were written, the same message once
        var seen = Set<UInt64>()
        out = out.filter { seen.insert($0.id).inserted }
        return (Array(out.suffix(n)), skipped)
    }

    func append(_ m: ChatMessage) {
        let url = historyURL
        guard let line = Store.encode(m) else { return }
        if !fm.fileExists(atPath: url.path) {
            try? write(Data(), to: url)
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: line + Data("\n".utf8))
        try? h.close()
    }

    // Keeps the last 2000 when there are many more
    func trimHistory() {
        let url = historyURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")
        guard lines.count > Store.historyKeep + Store.historyKeep / 5 else { return }
        try? write(Data((lines.suffix(Store.historyKeep).joined(separator: "\n") + "\n").utf8), to: url)
    }

    static func encode(_ m: ChatMessage) -> Data? {
        let obj: [String: Any] = ["v": 1, "id": Hex.u64(m.id), "t": Int64(m.sent * 1000), "rx": Int64(m.received * 1000),
                                  "nick": m.nickname, "fp": m.fingerprint, "text": m.text, "hops": m.hops, "me": m.mine]
        return try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    static func decode(_ data: Data) -> StoredMessage? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let idHex = o["id"] as? String, let idData = Hex.decode(idHex), idData.count == 8,
              let t = number(o["t"]), let text = o["text"] as? String else { return nil }
        let id = idData.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let clean = Sanitize.text(text)
        guard !clean.isEmpty else { return nil }
        let rx = number(o["rx"]) ?? t
        let m = ChatMessage(id: id, nickname: Sanitize.nickname(o["nick"] as? String ?? "?"), fingerprint: Sanitize.nickname(o["fp"] as? String ?? ""),
                            text: clean, sent: t / 1000, received: rx / 1000, hops: number(o["hops"]).map { Int($0) } ?? 0,
                            mine: (o["me"] as? Bool) ?? false)
        return StoredMessage(m)
    }

    // A number from JSON: NSNumber on macOS, Int or Double elsewhere
    static func number(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let i as Int: return Double(i)
        default: return nil
        }
    }

    // ── One chat at a time ────────────────────────────────────
    // Two MeshChats on one Mac would advertise the same service twice. The lock goes with the process.

    private var lockFD: Int32 = -1

    func lock() -> Bool {
        let fd = open(file("chat.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true }          // no lock file: do not stand in the way
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFD = fd
        return true
    }

    // ── Diagnostics ───────────────────────────────────────────

    private let logQueue = DispatchQueue(label: "meshchat.log")

    func log(_ text: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let url = file("events.log")
        logQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.fm.fileExists(atPath: url.path) { try? self.write(Data(), to: url) }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data("\(stamp) \(text)\n".utf8))
            try? h.close()
        }
    }

    func flushLog() { logQueue.sync {} }

    func trimLog() {
        let url = file("events.log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")
        if lines.count > 600 { try? write(Data((lines.suffix(400).joined(separator: "\n") + "\n").utf8), to: url) }
    }

    func recentLog(_ n: Int) -> [String] {
        guard let text = try? String(contentsOf: file("events.log"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").suffix(n).map(String.init)
    }
}
