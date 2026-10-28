// MeshChat – the command: lotus meshchat [history|nick|set|relay|doctor|demo|help]. Without a word: the chat.
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
            if ["--links", "-n"].contains(a), i + 1 < args.count {
                values[a] = args[i + 1]
                i += 2
                continue
            }
            if a.hasPrefix("--") { flags.insert(a) } else { words.append(a) }
            i += 1
        }
    }

    private var rest: String { words.dropFirst().joined(separator: " ") }

    func run() -> Int32 {
        switch (words.first ?? "chat").lowercased() {
        case "chat", "open": return chat()
        case "history": return history()
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
        case "create", "new", "join", "rooms", "list", "ls", "invite", "code", "leave", "forget":
            fail("MeshChat has no rooms any more", "Everyone nearby with MeshChat is in one chat, and it is public: lotus meshchat")
            return 2
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
        header("one chat with everyone nearby, over Bluetooth – no internet, no server")
        for (c, d) in [
            ("lotus meshchat", "the chat – everything in it goes to every Mac with MeshChat nearby"),
            ("lotus meshchat history", "what was said while your chat was open (-n 50: the last 50)"),
            ("lotus meshchat nick <name>", "your name in the chat"),
            ("lotus meshchat set links 1–8", "Bluetooth links at most (8)"),
            ("lotus meshchat relay", "only pass on what Macs nearby send – a Mac in between, for range"),
            ("lotus meshchat doctor", "why Bluetooth, its permission or the build do not work"),
            ("lotus meshchat demo", "try the chat with two simulated people – no Bluetooth"),
            ("lotus meshchat selftest", "the protocol tests, on this Mac"),
        ] {
            print("    " + Theme.key(c.padding(toLength: 30, withPad: " ", startingAt: 0)) + Theme.dim(d))
        }
        print("")
        print("  " + Theme.dim("In the chat: /who /nick /status /clear /quit /help"))
        print("  " + Theme.dim("Every Mac passes each message on, up to \(Proto.hopLimit) relays far. It is public: anyone nearby can read it."))
        print("  " + Theme.dim("Signed, so no one can write in your name. Macs only – MeshChat on each."))
        print("")
    }

    // ── The chat ──────────────────────────────────────────────

    private func config() -> MeshConfig {
        var c = MeshConfig()
        c.maxLinks = Int(values["--links"] ?? "").map { max(1, min(8, $0)) } ?? store.maxLinks
        return c
    }

    // The first time: what MeshChat is, and a name
    private func ensureNickname() -> Bool {
        if store.nickname != nil { return true }
        header("one chat with everyone nearby")
        print("  What you write goes to every Mac with MeshChat around you, and each one passes it on – no internet,")
        print("  no server. It is public: anyone nearby can read it. Signed, so no one can write in your name.")
        print("")
        let suggestion = Sanitize.nickname(URL(fileURLWithPath: NSHomeDirectory()).lastPathComponent.capitalized)
        guard let answer = ask("Your name in the chat\(suggestion.isEmpty ? "" : " [\(suggestion)]"):") else { return false }
        let name = Sanitize.nickname(answer.isEmpty ? suggestion : answer)
        guard !name.isEmpty else { return false }
        store.set("NICKNAME", name)
        return true
    }

    private func chat() -> Int32 {
        guard Term.isTTY else {
            fail("The chat needs a terminal window", "Without one: lotus meshchat history – or lotus meshchat help")
            return 1
        }
        #if canImport(CoreBluetooth)
        guard store.lock() else {
            fail("MeshChat is open already in another window", "One chat at a time on a Mac – close the other one first")
            return 1
        }
        let terminal = Doctor.terminalApp()
        guard bluetoothAllowed(terminal) else { return 1 }
        guard ensureNickname() else { return 1 }
        ChatApp.bluetooth(store: store, config: config(), terminal: terminal)
        #else
        fail("The chat needs macOS – Bluetooth comes from Apple's CoreBluetooth", "Try the chat without Bluetooth: lotus meshchat demo")
        return 1
        #endif
    }

    // Would macOS end MeshChat as it starts Bluetooth? Terminals known to be fine are not asked; any other is tried
    // in a process of its own first, so that MeshChat can say what to do instead of just vanishing.
    private func bluetoothAllowed(_ app: TerminalApp?) -> Bool {
        if app?.mayAsk == true { return true }
        guard let sig = Doctor.probeBluetooth(timeout: 5, quick: true).killedBySignal else { return true }
        fail("macOS ended MeshChat's Bluetooth check (signal \(sig)) – \(app?.name ?? "this terminal") cannot ask for Bluetooth",
             "Open MeshChat in \(bluetoothTerminals). More: lotus meshchat doctor")
        return false
    }

    // ── History, settings ─────────────────────────────────────

    private func history() -> Int32 {
        let n = Int(values["-n"] ?? "") ?? 50
        let (messages, skipped) = store.history(last: max(1, n))
        header(messages.isEmpty ? "history" : "the last \(messages.count) message\(messages.count == 1 ? "" : "s")")
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
            print("  links \(store.maxLinks)" + Theme.dim("  – lotus meshchat set links <1–8>"))
            return words.count == 1 ? 0 : 2
        }
        let value = words[2].lowercased()
        switch words[1].lowercased() {
        case "links":
            guard let n = Int(value), (1...8).contains(n) else {
                fail("links is a number from 1 to 8")
                return 2
            }
            store.set("LINKS", String(n))
            ok("At most \(n) Bluetooth link\(n == 1 ? "" : "s")")
        case "hops", "relay":
            fail("\(words[1].lowercased()) is no longer a setting",
                 "Every Mac with MeshChat passes every message on, as far as the mesh reaches (up to \(Proto.hopLimit) relays)")
            return 2
        default:
            fail("There is no setting \"\(words[1])\"", "links")
            return 2
        }
        return 0
    }

    // ── Doctor, demo, relay ───────────────────────────────────

    private func probe() -> Int32 {
        #if canImport(CoreBluetooth)
        for (k, v) in BluetoothProbe().run(timeout: flags.contains("--quick") ? 1.5 : 6).sorted(by: { $0.key < $1.key }) { print("\(k)=\(v)") }
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
        guard store.lock() else {
            fail("MeshChat is open already in another window")
            return 1
        }
        guard bluetoothAllowed(Doctor.terminalApp()) else { return 1 }
        ChatApp.relay(store: store, config: config())
        #else
        fail("The relay needs macOS – Bluetooth comes from Apple's CoreBluetooth")
        return 1
        #endif
    }
}
