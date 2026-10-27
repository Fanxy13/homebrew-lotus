// MeshChat – the command: lotus meshchat [create|join|rooms|open|invite|leave|history|nick|set|relay|doctor|demo].
// meshchat.zsh builds this program once and runs it; `lotus meshchat help` lists everything.

import Foundation

@main
struct MeshChatCommand {
    static func main() {
        umask(0o077)            // what MeshChat writes is readable by this user only
        exit(CLI(Array(CommandLine.arguments.dropFirst())).run())
    }
}

struct CLI {
    private var words: [String] = []
    private var flags: Set<String> = []
    private var values: [String: String] = [:]
    private let store = Store.standard()

    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let a = args[i]
            if ["--hops", "--links", "-n"].contains(a), i + 1 < args.count {
                values[a] = args[i + 1]
                i += 2
                continue
            }
            if a.hasPrefix("--") || a == "-y" { flags.insert(a == "-y" ? "--yes" : a) } else { words.append(a) }
            i += 1
        }
    }

    private var rest: String { words.dropFirst().joined(separator: " ") }

    func run() -> Int32 {
        switch (words.first ?? "chat").lowercased() {
        case "chat", "open": return chat(rest)
        case "create", "new": return create(rest)
        case "join": return join(rest)
        case "rooms", "list", "ls": return rooms()
        case "invite", "code": return invite(rest)
        case "leave", "forget": return leave(rest)
        case "history": return history(rest)
        case "nick", "name": return nick(rest)
        case "set": return set()
        case "doctor": return Doctor.run(store: store)
        case "probe-bluetooth": return probe()
        case "demo": return demo()
        case "relay": return relay()
        case "version", "--version", "-v":
            print("MeshChat \(Proto.software.replacingOccurrences(of: "meshchat/", with: "")) – protocol \(Proto.version), crypto \(CryptoBackend.name)")
            return 0
        case "help", "-h", "--help":
            help()
            return 0
        default:
            fail("There is no \"lotus meshchat \(words[0])\"", "lotus meshchat help lists what it can do")
            return 2
        }
    }

    // ── Saying things ─────────────────────────────────────────

    private func fail(_ text: String, _ hint: String = "") {
        print("")
        print("  " + Theme.red("✗ " + text))
        if !hint.isEmpty { print("    " + Theme.dim(hint)) }
        print("")
    }

    private func ok(_ text: String) { print("  " + Theme.bold(Theme.key("✓")) + " " + text) }
    private func kv(_ key: String, _ value: String) { print("    " + Theme.dim(key.padding(toLength: 12, withPad: " ", startingAt: 0)) + value) }

    private func header(_ subtitle: String) {
        print("")
        print("  " + Theme.bold(Theme.accent("lotus")) + Theme.dim(" / ") + Theme.bold("MeshChat") + Theme.dim("  " + subtitle))
        print("")
    }

    private func ask(_ question: String) -> String? {
        guard Term.isTTY else { return nil }
        print("  " + question + " ", terminator: "")
        fflush(stdout)
        return readLine()?.trimmingCharacters(in: .whitespaces)
    }

    private func help() {
        header("chat with Macs nearby over Bluetooth – no internet, no server")
        for (c, d) in [
            ("lotus meshchat", "the chat – your last room (the first time: make or join one)"),
            ("lotus meshchat create [name]", "a new room – it shows the code to give to the others"),
            ("lotus meshchat join <code>", "join a room with its code"),
            ("lotus meshchat rooms", "your rooms · open <room> · invite [room] · leave [room]"),
            ("lotus meshchat history [room]", "what was said (-n 50: the last 50)"),
            ("lotus meshchat nick <name>", "your name in the chat"),
            ("lotus meshchat set hops 1–7", "how many relays your messages may take (5)"),
            ("lotus meshchat set links 1–8", "Bluetooth links at most (8)"),
            ("lotus meshchat set relay on|off", "also pass on other rooms' messages, unread (off)"),
            ("lotus meshchat relay", "only pass on what Macs nearby send – a Mac in between, for range"),
            ("lotus meshchat doctor", "why Bluetooth, its permission or the build do not work"),
            ("lotus meshchat demo", "try the chat with two simulated people – no Bluetooth"),
            ("lotus meshchat selftest", "the protocol tests, on this Mac"),
        ] {
            print("    " + Theme.key(c.padding(toLength: 34, withPad: " ", startingAt: 0)) + Theme.dim(d))
        }
        print("")
        print("  " + Theme.dim("In the chat: /who /invite /nick /room /status /rooms /open /join /create /leave /quit /help"))
        print("  " + Theme.dim("Everyone with a room's code can read that room – and only they can. Macs only: MeshChat on both."))
        print("")
    }

    // ── The chat ──────────────────────────────────────────────

    private func config() -> MeshConfig {
        var c = MeshConfig()
        c.hops = Int(values["--hops"] ?? "").map { max(1, min(Int(Proto.hopLimit), $0)) } ?? store.hops
        c.maxLinks = Int(values["--links"] ?? "").map { max(1, min(8, $0)) } ?? store.maxLinks
        c.relayForeign = store.relay
        return c
    }

    private func ensureNickname() -> Bool {
        if store.nickname != nil { return true }
        let suggestion = Sanitize.nickname(URL(fileURLWithPath: NSHomeDirectory()).lastPathComponent.capitalized)
        guard let answer = ask("Your name in the chat\(suggestion.isEmpty ? "" : " [\(suggestion)]"):") else { return false }
        let name = Sanitize.nickname(answer.isEmpty ? suggestion : answer)
        guard !name.isEmpty else { return false }
        store.set("NICKNAME", name)
        return true
    }

    private func chat(_ query: String) -> Int32 {
        guard Term.isTTY else {
            fail("The chat needs a terminal window", "Without one: lotus meshchat rooms, history, invite – or lotus meshchat help")
            return 1
        }
        let (rooms, _) = store.rooms()
        var room: SavedRoom?
        if !query.isEmpty {
            do { room = try store.room(query) } catch {
                fail("\(error)")
                return 1
            }
        } else if let last = store.lastRoom, let r = rooms.first(where: { $0.id == last }) {
            room = r
        } else {
            room = rooms.first
        }
        guard let r = room else { return welcome() }
        return start(r)
    }

    private func welcome() -> Int32 {
        header("chat with Macs nearby over Bluetooth")
        print("  No room yet. A room is a group chat; its code lets others in.")
        print("")
        print("    " + Theme.key("c") + "  create a room          " + Theme.key("j") + "  join one with its code")
        print("    " + Theme.key("d") + "  try the demo first     " + Theme.key("q") + "  not now")
        print("")
        switch (ask("Which one?") ?? "q").lowercased() {
        case "c", "create": return create("")
        case "j", "join":
            guard let code = ask("The room code:"), !code.isEmpty else { return 1 }
            return join(code)
        case "d", "demo": return demo()
        default: return 0
        }
    }

    private func start(_ room: SavedRoom) -> Int32 {
        #if canImport(CoreBluetooth)
        guard store.lock() else {
            fail("MeshChat is open already in another window", "One chat at a time on a Mac – close the other one first")
            return 1
        }
        let terminal = Doctor.terminalApp()
        if let app = terminal, app.declaresBluetooth == false, !flags.contains("--force") {
            fail("\(app.name) does not declare Bluetooth use – macOS would end MeshChat as soon as it starts Bluetooth",
                 "Open MeshChat in Terminal (Applications › Utilities) or iTerm2. More: lotus meshchat doctor · try anyway: --force")
            return 1
        }
        guard ensureNickname() else { return 1 }
        ChatApp.bluetooth(store: store, room: room, config: config(), terminal: terminal)
        #else
        fail("The chat needs macOS – Bluetooth comes from Apple's CoreBluetooth", "Try the chat without Bluetooth: lotus meshchat demo")
        return 1
        #endif
    }

    // ── Rooms ─────────────────────────────────────────────────

    private func create(_ name: String) -> Int32 {
        var title = Sanitize.roomName(name)
        if title.isEmpty, let answer = ask("A name for the room (others see it):") { title = Sanitize.roomName(answer) }
        if title.isEmpty { title = "\(store.nickname ?? "My")'s room" }
        let secret = RoomSecret.generate()
        let room = SavedRoom(id: RoomKeys(secret: secret).id, name: title, code: InviteCode.make(secret), created: Date().timeIntervalSince1970, creator: true)
        do { try store.save(room) } catch {
            fail("Could not save the room", "\(error)")
            return 1
        }
        store.set("LAST_ROOM", room.id)
        print("")
        ok("The room \"\(title)\" is ready  " + Theme.dim("#\(room.id)"))
        print("")
        kv("Room code", Theme.bold(Theme.key(room.code)))
        kv("", Theme.dim("Give it to the people who should be in the room – anyone with it can read and write in it."))
        kv("They join", "lotus meshchat join \(room.code)")
        print("")
        if flags.contains("--no-chat") || !Term.isTTY { return 0 }
        return start(room)
    }

    private func join(_ code: String) -> Int32 {
        let secret: RoomSecret
        do { secret = try InviteCode.parse(code) } catch let e as InviteError {
            fail("Not a room code", e.description)
            return 2
        } catch {
            fail("\(error)")
            return 2
        }
        let id = RoomKeys(secret: secret).id
        var room = (try? store.room(id)) ?? SavedRoom(id: id, name: "", code: InviteCode.make(secret), created: Date().timeIntervalSince1970)
        let already = (try? store.room(id)) != nil
        if !already {
            do { try store.save(room) } catch {
                fail("Could not save the room", "\(error)")
                return 1
            }
        }
        room = (try? store.room(id)) ?? room
        store.set("LAST_ROOM", id)
        print("")
        ok(already ? "You are in this room already  " + Theme.dim("#\(id)") : "Joined the room  " + Theme.dim("#\(id) – its name comes from the others once you meet"))
        print("")
        if flags.contains("--no-chat") || !Term.isTTY { return 0 }
        return start(room)
    }

    private func rooms() -> Int32 {
        let (list, problems) = store.rooms()
        header("your rooms")
        if list.isEmpty {
            print("  No rooms yet – " + Theme.key("lotus meshchat create") + " or " + Theme.key("lotus meshchat join <code>"))
        }
        let last = store.lastRoom
        for r in list {
            let count = store.history(r.id, last: 100_000).messages.count
            let mark = r.id == last ? Theme.accent("›") : " "
            print("  \(mark) " + Theme.key((r.name.isEmpty ? "(no name yet)" : r.name).padding(toLength: 24, withPad: " ", startingAt: 0))
                  + Theme.dim("#\(r.id)  \(count) message\(count == 1 ? "" : "s")\(r.creator ? " · you made it" : "")\(r.readOnly ? " · from a newer MeshChat" : "")"))
        }
        for p in problems { print("    " + Theme.yellow("! ") + p) }
        print("")
        if !list.isEmpty { print("  " + Theme.dim("lotus meshchat open <room> · invite <room> · leave <room>")) }
        print("")
        return 0
    }

    private func pick(_ query: String) -> SavedRoom? {
        do {
            if !query.isEmpty { return try store.room(query) }
            if let last = store.lastRoom { return try store.room(last) }
            if let first = store.rooms().rooms.first { return first }
            fail("You have no rooms yet", "lotus meshchat create · lotus meshchat join <code>")
        } catch {
            fail("\(error)")
        }
        return nil
    }

    private func invite(_ query: String) -> Int32 {
        guard let r = pick(query) else { return 1 }
        print("")
        kv("Room", (r.name.isEmpty ? "(no name yet)" : r.name) + Theme.dim("  #\(r.id)"))
        kv("Room code", Theme.bold(Theme.key(r.code)))
        kv("", Theme.dim("Anyone with it can read and write in the room – give it only to the people who should."))
        print("")
        return 0
    }

    private func leave(_ query: String) -> Int32 {
        guard let r = pick(query) else { return 1 }
        let name = r.name.isEmpty ? "#\(r.id)" : r.name
        if !flags.contains("--yes") {
            guard let answer = ask("Leave \"\(name)\" and delete its code and history from this Mac? [y/N]") else {
                fail("Leaving needs a yes", "Without a terminal: lotus meshchat leave \(r.id) --yes")
                return 1
            }
            guard answer.lowercased().hasPrefix("y") else {
                print("  " + Theme.dim("You stay in the room."))
                return 1
            }
        }
        do { try store.delete(r) } catch {
            fail("Could not delete the room", "\(error)")
            return 1
        }
        ok("You left \"\(name)\" – its code and history are deleted from this Mac")
        print("    " + Theme.dim("What you wrote stays on the Macs that received it."))
        return 0
    }

    private func history(_ query: String) -> Int32 {
        guard let r = pick(query) else { return 1 }
        let n = Int(values["-n"] ?? "") ?? 50
        let (messages, skipped) = store.history(r.id, last: max(1, n))
        header((r.name.isEmpty ? "#\(r.id)" : r.name) + " – the last \(messages.count) message\(messages.count == 1 ? "" : "s")")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        for m in messages {
            let who = m.mine ? Theme.accent(m.nickname) : Theme.person(m.fingerprint, m.nickname)
            print("  " + Theme.dim(f.string(from: Date(timeIntervalSince1970: m.sent))) + "  " + who + Theme.dim("·\(m.fingerprint)") + "  " + m.text
                  + (m.hops > 0 ? Theme.dim(" ⇢\(m.hops)") : ""))
        }
        if messages.isEmpty { print("  " + Theme.dim("Nothing said yet.")) }
        if skipped > 0 { print("  " + Theme.yellow("! ") + "\(skipped) damaged line\(skipped == 1 ? "" : "s") skipped") }
        print("")
        return 0
    }

    // ── Settings ──────────────────────────────────────────────

    private func nick(_ name: String) -> Int32 {
        if name.isEmpty {
            print("  " + (store.nickname.map { "You are \(Theme.accent($0)) in the chat." } ?? "No name yet – lotus meshchat nick <name>"))
            return 0
        }
        let clean = Sanitize.nickname(name)
        guard !clean.isEmpty else {
            fail("That name has nothing visible in it")
            return 2
        }
        store.set("NICKNAME", clean)
        ok("You are \(clean) in the chat" + (clean != name.trimmingCharacters(in: .whitespaces) ? Theme.dim("  (made fit: at most 24 characters, no control characters)") : ""))
        return 0
    }

    private func set() -> Int32 {
        guard words.count >= 3 else {
            print("  hops \(store.hops) · links \(store.maxLinks) · relay \(store.relay ? "on" : "off")" + Theme.dim("  – lotus meshchat set hops|links|relay <value>"))
            return words.count == 1 ? 0 : 2
        }
        let value = words[2].lowercased()
        switch words[1].lowercased() {
        case "hops":
            guard let n = Int(value), (1...Int(Proto.hopLimit)).contains(n) else {
                fail("hops is a number from 1 to \(Proto.hopLimit)", "How many relays a message of yours may take – each one reaches further, and costs the others battery")
                return 2
            }
            store.set("HOPS", String(n))
            ok("Your messages may take up to \(n) relay\(n == 1 ? "" : "s")")
        case "links":
            guard let n = Int(value), (1...8).contains(n) else {
                fail("links is a number from 1 to 8")
                return 2
            }
            store.set("LINKS", String(n))
            ok("At most \(n) Bluetooth link\(n == 1 ? "" : "s")")
        case "relay":
            guard ["on", "off"].contains(value) else {
                fail("relay is on or off")
                return 2
            }
            store.set("RELAY", value)
            ok(value == "on" ? "This Mac passes on other rooms' messages too – unread, it cannot read them" : "Only this room's messages are passed on")
        default:
            fail("There is no setting \"\(words[1])\"", "hops, links or relay")
            return 2
        }
        return 0
    }

    // ── Doctor, demo, relay ───────────────────────────────────

    private func probe() -> Int32 {
        #if canImport(CoreBluetooth)
        for (k, v) in BluetoothProbe().run(timeout: 6).sorted(by: { $0.key < $1.key }) { print("\(k)=\(v)") }
        return 0
        #else
        print("central=not available")
        return 0
        #endif
    }

    private func demo() -> Int32 {
        guard Term.isTTY else {
            fail("The demo needs a terminal window")
            return 1
        }
        ChatApp.demo(nickname: store.nickname ?? "You")
    }

    private func relay() -> Int32 {
        #if canImport(CoreBluetooth)
        if let app = Doctor.terminalApp(), app.declaresBluetooth == false, !flags.contains("--force") {
            fail("\(app.name) does not declare Bluetooth use", "Run the relay in Terminal. More: lotus meshchat doctor")
            return 1
        }
        guard store.lock() else {
            fail("MeshChat is open already in another window")
            return 1
        }
        ChatApp.relay(store: store, config: config())
        #else
        fail("The relay needs macOS – Bluetooth comes from Apple's CoreBluetooth")
        return 1
        #endif
    }
}
