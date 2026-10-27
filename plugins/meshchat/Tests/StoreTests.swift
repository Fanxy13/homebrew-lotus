// MeshChat tests – what is kept on the Mac: settings next to others' lines, the identity, the history with broken
// lines, MeshChat 1's rooms left alone, and private permissions.

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
        try Data("OTHER=from a pack\nHOPS=3\nLINKS=3\n# a comment\n".utf8).write(to: s.dir.appendingPathComponent("settings"))
        checkEqual(s.maxLinks, 3, "LINKS read")
        s.set("NICKNAME", "Ada")
        s.set("LINKS", "99")
        checkEqual(s.nickname, "Ada", "NICKNAME written")
        checkEqual(s.maxLinks, 8, "LINKS over 8 is 8")
        checkEqual(s.settings()["OTHER"], "from a pack", "a line of someone else stays")
        checkEqual(s.settings()["HOPS"], "3", "and one of MeshChat 1, no longer used")
        s.set("NICKNAME", "evil\u{1B}[31m\nname")
        checkEqual(s.nickname, "evil[31m name", "a nickname from the file is made safe")
        s.set("LINKS", nil)
        checkEqual(s.maxLinks, 8, "removed: 8 links, the default")
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

    test("MeshChat 1's rooms are named and left alone") {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        check(s.oldRooms == nil, "none: nothing to say")
        let old = s.dir.appendingPathComponent("rooms/k7q2m9ab")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data(#"{"name":"Bike trip","code":"MC1-…"}"#.utf8).write(to: old.appendingPathComponent("room.json"))
        checkEqual(s.oldRooms, s.dir.appendingPathComponent("rooms").path, "the folder is named")
        _ = s.history()
        s.append(ChatMessage(id: 1, nickname: "Ada", fingerprint: "abcd", text: "hi", sent: 1, received: 1, hops: 0, mine: true))
        check(FileManager.default.fileExists(atPath: old.appendingPathComponent("room.json").path), "and nothing in it is touched")
    }

    test("history: written as it comes, read back, damaged lines skipped, kept short") {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        for i in 0..<5 {
            s.append(ChatMessage(id: UInt64(i + 1), nickname: "Ada", fingerprint: "k3f9", text: "message \(i)", sent: Double(i), received: Double(i),
                                 hops: i % 2, mine: i == 0))
        }
        let url = s.dir.appendingPathComponent("history.jsonl")
        let h = try FileHandle(forWritingTo: url)
        _ = try h.seekToEnd()
        try h.write(contentsOf: Data("{broken\n{\"v\":9,\"id\":\"0000000000000063\",\"t\":99000,\"text\":\"from a newer version\",\"future\":true}\n".utf8))
        try h.close()
        s.append(ChatMessage(id: 3, nickname: "Ada", fingerprint: "k3f9", text: "message 2", sent: 2, received: 2, hops: 0, mine: false))
        let (messages, skipped) = s.history()
        checkEqual(messages.map { $0.text }, ["message 0", "message 1", "message 2", "message 3", "message 4", "from a newer version"], "in order, each once")
        checkEqual(skipped, 1, "the damaged line is skipped")
        checkEqual(messages[0].mine, true, "mine")
        checkEqual(messages[1].hops, 1, "hops")
        checkEqual(mode(url.path), 0o600, "the history is private")
        for i in 0..<2500 {
            s.append(ChatMessage(id: UInt64(1000 + i), nickname: "B", fingerprint: "x", text: "n\(i)", sent: 0, received: 0, hops: 0, mine: false))
        }
        s.trimHistory()
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        checkEqual(lines.count, Store.historyKeep, "trimmed to the last 2000")
        checkEqual(s.history(last: 3).messages.map { $0.text }, ["n2497", "n2498", "n2499"], "the newest stay")
    }

    test("one chat at a time on a Mac") {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        check(s.lock(), "the first one gets the lock")
        let other = Store(dir: s.dir)
        check(!other.lock(), "a second one does not")
    }
}
