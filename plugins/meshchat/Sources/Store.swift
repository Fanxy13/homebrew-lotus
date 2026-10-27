// MeshChat – what it keeps on this Mac, all of it in its data folder ($LOTUS_PLUGIN_DATA, by default
// ~/.local/share/lotus/plugins/meshchat). Folders 0700 and files 0600: only your user can read them, and nothing
// of it leaves this Mac.
//   settings                    NICKNAME=…, HOPS=5, LINKS=8, RELAY=off, LAST_ROOM=…  (Lotus' plugin settings file)
//   identity                    this Mac's secret for its signing keys: 32 random bytes, hex
//   rooms/<id>/room.json        a room: its name and its code – the code is the room's secret
//   rooms/<id>/history.jsonl    what was said in it, one message per line (the last 2000)
//   events.log                  links and errors, for lotus meshchat doctor – never codes, keys, names or messages
// Files of an older MeshChat are read as they are; a room file of a newer one is used but never rewritten.

import Foundation

struct SavedRoom: Equatable {
    static let format = 1

    var id: String
    var name: String
    var code: String
    var created: TimeInterval
    var opened: TimeInterval = 0
    var creator = false
    var format = SavedRoom.format

    var readOnly: Bool { format > SavedRoom.format }      // written by a newer MeshChat

    func secret() throws -> RoomSecret { try InviteCode.parse(code) }
}

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

enum StoreError: Error, CustomStringConvertible {
    case noRoom(String)
    case ambiguous(String, [String])
    case unreadable(String)
    case newer(String)

    var description: String {
        switch self {
        case .noRoom(let q): return "There is no room \"\(q)\" on this Mac – lotus meshchat rooms lists them."
        case .ambiguous(let q, let names): return "\"\(q)\" fits several rooms: \(names.joined(separator: ", ")) – give more of its name or its ID."
        case .unreadable(let what): return "Could not read \(what)."
        case .newer(let name): return "The room \"\(name)\" was saved by a newer MeshChat – it is left as it is. Update: lotus plugin update meshchat"
        }
    }
}

final class Store {
    static let historyKeep = 2000
    let dir: URL
    private let fm = FileManager.default

    init(dir: URL) {
        self.dir = dir
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Lotus makes the folder with the usual rights; it holds room codes, so it is this user's alone
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
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
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
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

    var hops: Int { Int(settings()["HOPS"] ?? "").map { max(1, min(Int(Proto.hopLimit), $0)) } ?? Proto.defaultHops }
    var maxLinks: Int { Int(settings()["LINKS"] ?? "").map { max(1, min(8, $0)) } ?? 8 }
    var relay: Bool { ["on", "yes", "1", "true"].contains((settings()["RELAY"] ?? "").lowercased()) }
    var lastRoom: String? { settings()["LAST_ROOM"].flatMap { $0.isEmpty ? nil : $0 } }

    // ── This Mac's identity ───────────────────────────────────
    // The secret the signing keys come from (one per room). Made once; a damaged file is replaced, and then the
    // others see a new fingerprint for you.

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

    // ── Rooms ─────────────────────────────────────────────────

    private func roomDir(_ id: String) -> URL { dir.appendingPathComponent("rooms").appendingPathComponent(id) }

    // The saved rooms, newest opened first, and what could not be read (it is left alone)
    func rooms() -> (rooms: [SavedRoom], problems: [String]) {
        let base = dir.appendingPathComponent("rooms")
        guard let ids = try? fm.contentsOfDirectory(atPath: base.path) else { return ([], []) }
        var out: [SavedRoom] = [], problems: [String] = []
        for id in ids.sorted() where !id.hasPrefix(".") {
            let url = roomDir(id).appendingPathComponent("room.json")
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                problems.append("rooms/\(id)/room.json is damaged – it is left as it is")
                continue
            }
            let format = Store.number(obj["format"]).map { Int($0) } ?? 1     // the first files had no format
            let code = obj["code"] as? String ?? ""
            guard let secret = try? InviteCode.parse(code) else {
                problems.append("rooms/\(id)/room.json has no valid room code – it is left as it is")
                continue
            }
            guard RoomKeys(secret: secret).id == id else {
                problems.append("rooms/\(id) holds the code of another room – it is left as it is")
                continue
            }
            let name = Sanitize.roomName(obj["name"] as? String ?? "")
            out.append(SavedRoom(id: id, name: name, code: InviteCode.make(secret), created: Store.number(obj["created"]) ?? 0,
                                 opened: Store.number(obj["opened"]) ?? 0, creator: obj["creator"] as? Bool ?? false, format: format))
            if format > SavedRoom.format { problems.append("the room \"\(name.isEmpty ? id : name)\" was saved by a newer MeshChat – it is used, but not changed") }
        }
        return (out.sorted { $0.opened != $1.opened ? $0.opened > $1.opened : $0.created > $1.created }, problems)
    }

    func save(_ room: SavedRoom) throws {
        guard !room.readOnly else { throw StoreError.newer(room.name) }
        let obj: [String: Any] = ["format": SavedRoom.format, "id": room.id, "name": room.name, "code": room.code,
                                  "created": room.created, "opened": room.opened, "creator": room.creator]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try write(data, to: roomDir(room.id).appendingPathComponent("room.json"))
    }

    // By its ID (or the start of it) or its name, in any case
    func room(_ query: String) throws -> SavedRoom {
        let all = rooms().rooms
        let q = query.lowercased()
        if let r = all.first(where: { $0.id == q }) { return r }
        if let r = all.first(where: { $0.name.lowercased() == q }) { return r }
        let fits = all.filter { $0.id.hasPrefix(q) || $0.name.lowercased().contains(q) }
        if fits.count == 1 { return fits[0] }
        if fits.isEmpty { throw StoreError.noRoom(query) }
        throw StoreError.ambiguous(query, fits.map { $0.name.isEmpty ? $0.id : "\($0.name) (\($0.id))" })
    }

    func delete(_ room: SavedRoom) throws {
        try fm.removeItem(at: roomDir(room.id))
        if lastRoom == room.id { set("LAST_ROOM", nil) }
    }

    // ── History ───────────────────────────────────────────────

    private func historyURL(_ id: String) -> URL { roomDir(id).appendingPathComponent("history.jsonl") }

    // The last messages, oldest first; damaged lines are skipped
    func history(_ roomID: String, last n: Int = 500) -> (messages: [StoredMessage], skipped: Int) {
        guard let text = try? String(contentsOf: historyURL(roomID), encoding: .utf8) else { return ([], 0) }
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

    func append(_ m: ChatMessage, room roomID: String) {
        let url = historyURL(roomID)
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
    func trimHistory(_ roomID: String) {
        let url = historyURL(roomID)
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
