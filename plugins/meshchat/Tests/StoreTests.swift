// MeshChat tests – what is kept on the Mac: settings next to others' lines, the identity, rooms of this version, of
// the first one and of a newer one, damaged files left alone, history with broken lines, and private permissions.

import Foundation

private func tempStore() -> Store {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("meshchat-test-\(UUID().uuidString)")
    return Store(dir: dir)
}

private func mode(_ path: String) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

func storeTests() {
    test("settings: one key changed, the other lines kept, values checked") {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        try Data("OTHER=from a pack\nHOPS=3\n# a comment\n".utf8).write(to: s.dir.appendingPathComponent("settings"))
        checkEqual(s.hops, 3, "HOPS read")
        s.set("NICKNAME", "Ada")
        s.set("HOPS", "99")
        checkEqual(s.nickname, "Ada", "NICKNAME written")
        checkEqual(s.hops, 7, "HOPS over 7 is 7")
        checkEqual(s.settings()["OTHER"], "from a pack", "a line of someone else stays")
        s.set("NICKNAME", "evil\u{1B}[31m\nname")
        checkEqual(s.nickname, "evil[31m name", "a nickname from the file is made safe")
        s.set("HOPS", nil)
        checkEqual(s.hops, Proto.defaultHops, "removed: the default")
        checkEqual(s.maxLinks, 8, "8 links by default")
        check(!s.relay, "relaying for other rooms is off by default")
    }

    test("identity: made once, kept, private; a damaged one is replaced") {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let a = s.identity()
        checkEqual(a.count, 32, "32 bytes")
        checkEqual(s.identity(), a, "the same next time")
        checkEqual(mode(s.dir.appendingPathComponent("identity").path), 0o600, "only readable by this user")
        checkEqual(mode(s.dir.path), 0o700, "the data folder too")
        try Data("not hex".utf8).write(to: s.dir.appendingPathComponent("identity"))
        let b = s.identity()
        check(b.count == 32 && b != a, "a damaged identity is replaced")
    }

    test("rooms: saved, found by name or ID, deleted with their history") {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let secret = RoomSecret.generate()
        let id = RoomKeys(secret: secret).id
        let room = SavedRoom(id: id, name: "Bike trip", code: InviteCode.make(secret), created: 1000, opened: 2000, creator: true)
        try s.save(room)
        checkEqual(mode(s.dir.appendingPathComponent("rooms/\(id)/room.json").path), 0o600, "the room file is private")
        let (rooms, problems) = s.rooms()
        checkEqual(rooms, [room], "read back")
        check(problems.isEmpty, "no problems")
        checkEqual(try s.room("bike TRIP"), room, "by name, any case")
        checkEqual(try s.room(String(id.prefix(3))), room, "by the start of its ID")
        let other = RoomSecret.generate()
        try s.save(SavedRoom(id: RoomKeys(secret: other).id, name: "Bike club", code: InviteCode.make(other), created: 3000))
        checkThrows("\"bike\" fits two rooms") { try s.room("bike") }
        checkThrows("a room that is not there") { try s.room("nothing") }
        s.append(ChatMessage(id: 1, nickname: "Ada", fingerprint: "abcd", text: "hi", sent: 1, received: 1, hops: 0, mine: true), room: id)
        try s.delete(room)
        check(!FileManager.default.fileExists(atPath: s.dir.appendingPathComponent("rooms/\(id)").path), "deleted with its history")
    }

    test("rooms of other versions, and damaged ones") {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        func put(_ id: String, _ json: String) throws {
            let d = s.dir.appendingPathComponent("rooms/\(id)")
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: d.appendingPathComponent("room.json"))
        }
        let old = RoomSecret.generate(), newer = RoomSecret.generate(), moved = RoomSecret.generate()
        let oldID = RoomKeys(secret: old).id, newerID = RoomKeys(secret: newer).id
        try put(oldID, #"{"name":"From the first version","code":"\#(InviteCode.make(old).lowercased())","created":5}"#)
        try put(newerID, #"{"format":2,"name":"From a newer one","code":"\#(InviteCode.make(newer))","created":6,"extra":{"x":1}}"#)
        try put("broken12", "{ not json")
        try put("nocode12", #"{"format":1,"name":"No code"}"#)
        try put("wrongdir", #"{"format":1,"code":"\#(InviteCode.make(moved))"}"#)
        let (rooms, problems) = s.rooms()
        checkEqual(Set(rooms.map { $0.name }), ["From the first version", "From a newer one"], "both good rooms are read")
        check(rooms.first { $0.id == oldID }?.readOnly == false, "a room without a format is the first version's – it can be updated")
        let n = rooms.first { $0.id == newerID }!
        check(n.readOnly, "a newer one is read-only")
        checkThrows("and never written") { try s.save(n) }
        checkEqual(problems.count, 4, "the damaged, the code-less, the misplaced and the newer room are named (\(problems))")
        check(FileManager.default.fileExists(atPath: s.dir.appendingPathComponent("rooms/broken12/room.json").path), "a damaged file is left alone")
    }

    test("history: written as it comes, read back, damaged lines skipped, kept short") {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let id = "abcdefgh"
        for i in 0..<5 {
            s.append(ChatMessage(id: UInt64(i + 1), nickname: "Ada", fingerprint: "k3f9", text: "message \(i)", sent: Double(i), received: Double(i),
                                 hops: i % 2, mine: i == 0), room: id)
        }
        let url = s.dir.appendingPathComponent("rooms/\(id)/history.jsonl")
        let h = try FileHandle(forWritingTo: url)
        _ = try h.seekToEnd()
        try h.write(contentsOf: Data("{broken\n{\"v\":9,\"id\":\"0000000000000063\",\"t\":99000,\"text\":\"from a newer version\",\"future\":true}\n".utf8))
        try h.close()
        s.append(ChatMessage(id: 3, nickname: "Ada", fingerprint: "k3f9", text: "message 2", sent: 2, received: 2, hops: 0, mine: false), room: id)
        let (messages, skipped) = s.history(id)
        checkEqual(messages.map { $0.text }, ["message 0", "message 1", "message 2", "message 3", "message 4", "from a newer version"], "in order, each once")
        checkEqual(skipped, 1, "the damaged line is skipped")
        checkEqual(messages[0].mine, true, "mine")
        checkEqual(messages[1].hops, 1, "hops")
        checkEqual(mode(url.path), 0o600, "the history is private")
        for i in 0..<2500 {
            s.append(ChatMessage(id: UInt64(1000 + i), nickname: "B", fingerprint: "x", text: "n\(i)", sent: 0, received: 0, hops: 0, mine: false), room: id)
        }
        s.trimHistory(id)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        checkEqual(lines.count, Store.historyKeep, "trimmed to the last 2000")
        checkEqual(s.history(id, last: 3).messages.map { $0.text }, ["n2497", "n2498", "n2499"], "the newest stay")
    }

    test("one chat at a time on a Mac") {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        check(s.lock(), "the first one gets the lock")
        let other = Store(dir: s.dir)
        check(!other.lock(), "a second one does not")
    }
}
