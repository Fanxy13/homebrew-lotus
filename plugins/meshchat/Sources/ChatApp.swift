// MeshChat – the chat itself: the mesh on a queue of its own, the screen and the keys on the main one, and the
// commands (/who, /invite, /nick, /join, /create, /leave, /quit …). What is said goes into the room's history.
// Closing the chat says goodbye to the room, stops Bluetooth and gives the terminal back – nothing keeps running.

import Foundation

final class ChatApp {
    private let store: Store?               // nil: the demo keeps nothing
    private let meshQueue = DispatchQueue(label: "meshchat.mesh")
    private var node: MeshNode!
    private var demo: DemoWorld?
    private var room: SavedRoom?
    private var identity = Data()
    private var view = ChatViewState()
    private var seen = Set<UInt64>()
    private var keys: KeyReader?
    private var timer: DispatchSourceTimer?
    private var winch: DispatchSourceSignal?
    private var drawQueued = false
    private var screenOn = false
    private var quitting = false
    private var farewell = ""

    private init(store: Store?) { self.store = store }

    private func setUp(transport: LinkTransport, config: MeshConfig, nickname: String) {
        node = MeshNode(transport: transport, config: config, nickname: nickname,
                        clock: { [weak world = demo] in world?.net.now ?? Date().timeIntervalSince1970 },
                        events: { [weak self] e in DispatchQueue.main.async { self?.handle(e) } })
        view.nickname = node.nickname
        view.hops = config.hops
    }

    // ── Starting ──────────────────────────────────────────────

    #if canImport(CoreBluetooth)
    // A room over Bluetooth. Bluetooth starts before the screen changes: should macOS end the process for want of
    // a permission, the terminal is still as it was.
    static func bluetooth(store: Store, room: SavedRoom, config: MeshConfig, terminal: TerminalApp?) -> Never {
        let app = ChatApp(store: store)
        app.identity = store.identity()
        app.view.terminalApp = terminal?.name ?? ""
        let radio = BLETransport(queue: app.meshQueue)
        radio.onLog = { store.log($0) }
        app.setUp(transport: radio, config: config, nickname: store.nickname ?? "anon")
        store.trimLog()
        store.log("chat started – MeshChat \(Proto.software), \(config.hops) hops, \(config.maxLinks) links")
        do {
            try app.open(room)
        } catch {
            print(Theme.red("  ✗ ") + "\(error)")
            exit(1)
        }
        app.meshQueue.sync { app.node.start() }
        var state = RadioState.starting
        let deadline = Date().addingTimeInterval(2.5)
        repeat {
            usleep(100_000)
            state = app.meshQueue.sync { radio.state }
        } while state == .starting && Date() < deadline
        let who = terminal?.name ?? "your terminal app"
        switch state {
        case .unauthorized:
            print(Theme.red("  ✗ ") + "MeshChat may not use Bluetooth: the permission of \(who) is off.")
            print(Theme.dim("    Turn it on: System Settings › Privacy & Security › Bluetooth › \(who). Then start MeshChat again."))
            exit(1)
        case .unsupported:
            print(Theme.red("  ✗ ") + "This Mac has no Bluetooth Low Energy – MeshChat cannot run on it.")
            exit(1)
        default:
            break
        }
        app.run()
    }
    #endif

    // The demo: two simulated people, nothing over Bluetooth, nothing saved
    static func demo(nickname: String) -> Never {
        let app = ChatApp(store: nil)
        let world = DemoWorld(queue: app.meshQueue)
        app.demo = world
        app.view.demo = true
        var config = MeshConfig()
        config.presenceInterval = 20
        // the simulated people must not have your name
        let name = world.botNames.contains(nickname) ? "\(nickname) (you)" : nickname
        app.setUp(transport: world.userRadio(), config: config, nickname: name)
        app.identity = CryptoBackend.randomBytes(32)
        app.view.roomName = "Demo room"
        app.view.roomID = RoomKeys(secret: world.secret).id
        app.meshQueue.sync {
            try? app.node.enter(secret: world.secret, name: "Demo room", identity: app.identity)
            app.view.fingerprint = app.node.fingerprint ?? ""
            app.node.start()
            world.start()
        }
        app.notice("This is a demo: Ada and Grace are simulated on this Mac, nothing goes over Bluetooth. Write something!")
        app.run()
    }

    private func run() -> Never {
        Screen.enter()
        screenOn = true
        let reader = KeyReader { [weak self] k in self?.key(k) }
        keys = reader
        reader.start()
        let t = DispatchSource.makeTimerSource(queue: meshQueue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            if let d = self.demo { d.tick() } else { self.node.tick() }
        }
        t.resume()
        timer = t
        signal(SIGWINCH, SIG_IGN)
        let w = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        w.setEventHandler { [weak self] in self?.draw() }
        w.resume()
        winch = w
        draw()
        dispatchMain()
    }

    // A saved room: its history on the screen, the mesh in it
    private func open(_ saved: SavedRoom) throws {
        guard let store = store else { return }
        let secret = try saved.secret()
        var r = saved
        r.opened = Date().timeIntervalSince1970
        if !r.readOnly { try? store.save(r) }
        store.set("LAST_ROOM", r.id)
        store.trimHistory(r.id)
        room = r
        view.lines.removeAll()
        view.pending.removeAll()
        view.scroll = 0
        seen.removeAll()
        let (history, skipped) = store.history(r.id, last: 300)
        for m in history {
            view.add(.message(m.message), order: min(m.sent, m.received))
            seen.insert(m.id)
        }
        if !history.isEmpty { view.add(.divider("earlier messages above"), order: (view.lines.last?.order ?? 0) + 0.001) }
        if skipped > 0 { notice("\(skipped) damaged line\(skipped == 1 ? "" : "s") in the history skipped.", .warning) }
        view.roomName = r.name
        view.roomID = r.id
        let recent = history.filter { Date().timeIntervalSince1970 - $0.sent < 1800 }.map { $0.id }
        var fingerprint = ""
        try meshQueue.sync {
            node.markSeen(recent)
            try node.enter(secret: secret, name: r.name, identity: identity)
            fingerprint = node.fingerprint ?? ""
        }
        view.fingerprint = fingerprint
    }

    // ── Events of the mesh ────────────────────────────────────

    private func handle(_ e: MeshEvent) {
        switch e {
        case .message(let m):
            guard seen.insert(m.id).inserted else { return }
            view.add(.message(m), order: min(m.sent, m.received))
            if let r = room { store?.append(m, room: r.id) }
        case let .sent(id, links):
            if links == 0 { view.pending.insert(id) } else { view.pending.remove(id) }
        case .notice(let n):
            view.add(.notice(n), order: Date().timeIntervalSince1970)
        case .roomName(let name):
            view.roomName = name
            if var r = room, r.name.isEmpty, !r.readOnly {
                r.name = name
                room = r
                try? store?.save(r)
            }
        case .snapshot(let s):
            view.snapshot = s
        case .log(let text):
            store?.log(text)
        }
        scheduleDraw()
    }

    private func notice(_ text: String, _ level: Notice.Level = .info) {
        view.add(.notice(Notice(level: level, text: text)), order: Date().timeIntervalSince1970)
        scheduleDraw()
    }

    // ── Drawing ───────────────────────────────────────────────

    private func scheduleDraw() {
        guard !drawQueued else { return }
        drawQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.drawQueued = false
            self?.draw()
        }
    }

    private func draw() {
        guard screenOn else { return }
        let (rows, cols) = Term.size()
        Term.write(ChatRender.frame(view, rows: rows, cols: cols))
    }

    // ── Keys ──────────────────────────────────────────────────

    private func key(_ k: Key) {
        guard !quitting else { return }
        if view.confirmLeave {
            view.confirmLeave = false
            if k == .char("y") || k == .char("Y") { return leaveRoom() }
            notice("You stay in the room.")
            return draw()
        }
        let page = max(1, Term.size().rows - 7)
        switch k {
        case .char(let c): view.editor.insert(String(c))
        case .paste(let s): view.editor.insert(s)
        case .enter: submit()
        case .backspace: view.editor.backspace()
        case .delete: view.editor.delete()
        case .left: view.editor.left()
        case .right: view.editor.right()
        case .home, .ctrlA: view.editor.home()
        case .end, .ctrlE: view.editor.end()
        case .wordLeft: view.editor.wordLeft()
        case .wordRight: view.editor.wordRight()
        case .wordBackspace, .ctrlW: view.editor.deleteWordBack()
        case .ctrlU: view.editor.killToStart()
        case .ctrlK: view.editor.killToEnd()
        case .up: view.editor.older()
        case .down: view.editor.newer()
        case .pageUp: view.scroll += page
        case .pageDown: view.scroll = max(0, view.scroll - page)
        case .ctrlL: Term.write("\u{1B}[2J")
        case .esc: if view.editor.isEmpty { view.scroll = 0 } else { view.editor.clear() }
        case .ctrlC: if view.editor.isEmpty { return quit() } else { view.editor.clear() }
        case .ctrlD: if view.editor.isEmpty { return quit() } else { view.editor.delete() }
        case .eof: return quit()
        case .ctrlZ: Screen.suspend { self.draw() }
        case .tab: complete()
        case .unknown: break
        }
        draw()
    }

    static let commands = ["/help", "/who", "/invite", "/nick", "/room", "/status", "/rooms", "/open", "/join", "/create",
                           "/clear", "/leave", "/quit"]

    private func complete() {
        let t = view.editor.text
        guard t.hasPrefix("/"), !t.contains(" ") else { return }
        let fits = ChatApp.commands.filter { $0.hasPrefix(t.lowercased()) }
        if fits.count == 1 {
            view.editor.clear()
            view.editor.insert(fits[0] + " ")
        } else if fits.count > 1 {
            notice(fits.joined(separator: "  "))
        }
    }

    private func submit() {
        let text = view.editor.commit().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        view.scroll = 0
        if text.hasPrefix("/") && !text.hasPrefix("//") { return command(text) }
        let message = text.hasPrefix("//") ? String(text.dropFirst()) : text      // //like this sends "/like this"
        meshQueue.async { [weak self] in
            do {
                _ = try self?.node.send(message)
            } catch {
                DispatchQueue.main.async { self?.notice("\(error)", .warning) }
            }
        }
    }

    // ── Commands ──────────────────────────────────────────────

    private func command(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        switch cmd {
        case "/help", "/h", "/?": help()
        case "/who", "/people", "/here": who()
        case "/invite", "/code": invite()
        case "/room", "/info": roomInfo()
        case "/status", "/mesh": status()
        case "/nick", "/name": rename(arg)
        case "/clear": view.lines.removeAll()
        case "/leave":
            if demo != nil { notice("The demo room cannot be left – ctrl-c ends the demo.") } else { view.confirmLeave = true }
        case "/quit", "/exit", "/q", "/bye": quit()
        case "/join": join(arg)
        case "/create", "/new": create(arg)
        case "/rooms": rooms()
        case "/open": openRoom(arg)
        default: notice("There is no \(cmd) – /help lists the commands. To send a line starting with /, write //.", .warning)
        }
    }

    private func help() {
        for line in [
            "/who – who is here, and how: ● a direct Bluetooth link, ⇢2 two relays away, ○ not heard for a while",
            "/invite – the room code to give to others (anyone with it can read and write here)",
            "/nick <name> – your name · /room – this room and you · /status – Bluetooth and the mesh",
            "/rooms – your rooms · /open <room> · /join <code> · /create <name>",
            "/leave – leave this room and delete its code and history from this Mac",
            "/quit (ctrl-c, ctrl-d) – close the chat; the room stays · PgUp/PgDn scroll · ↑ your last lines",
        ] { notice(line) }
    }

    private func ago(_ t: TimeInterval) -> String {
        let s = Int(max(0, Date().timeIntervalSince1970 - t))
        return s < 90 ? "\(s) s ago" : s < 5400 ? "\(s / 60) min ago" : "\(s / 3600) h ago"
    }

    private func who() {
        let people = view.snapshot.participants
        let here = people.filter { !$0.left }.count
        notice("In \(view.roomName.isEmpty ? "this room" : view.roomName): you and \(here) other\(here == 1 ? "" : "s") – you are \(view.nickname)·\(view.fingerprint), with \(view.snapshot.links) link\(view.snapshot.links == 1 ? "" : "s")")
        for p in people {
            let how: String
            if p.left { how = "left the chat" }
            else if p.away { how = "away – last heard \(ago(p.lastSeen))" }
            else if p.direct { how = "a neighbour: a direct Bluetooth link" }
            else { how = "\(p.hops) relay\(p.hops == 1 ? "" : "s") away, heard \(ago(p.lastSeen))" }
            notice("  \(p.nickname)·\(p.fingerprint) – \(how)\(p.links > 0 && !p.left ? " · \(p.links) link\(p.links == 1 ? "" : "s")" : "")")
        }
        if people.isEmpty { notice("  No one else yet. Give the others the room code: /invite") }
        if Set(people.map { $0.nickname }).count < people.count {
            notice("  Two people have the same name – the four letters after the dot tell them apart.", .warning)
        }
    }

    private func invite() {
        guard let r = room else { return notice("The demo room has no code – lotus meshchat create makes a real room.") }
        notice("Room code: \(r.code)", .warning)
        notice("Anyone with this code can read and write in this room – give it only to the people who should be in it. Others join with: lotus meshchat join <code>")
    }

    private func roomInfo() {
        notice("Room: \(view.roomName.isEmpty ? "(no name yet)" : view.roomName) · ID #\(view.roomID)\(room?.creator == true ? " · you made it" : "")")
        notice("You: \(view.nickname)·\(view.fingerprint) – the four letters after the dot come from your key in this room; others see the same")
        notice("Your messages may take up to \(view.hops) relays. Everyone with the room code can read the room; what you write is kept on the Macs that receive it.")
        if let store = store, let r = room { notice("History: \(store.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))/rooms/\(r.id)") }
    }

    private func status() {
        let s = view.snapshot, st = s.stats
        notice("Bluetooth \(s.radio.label) · \(s.links) link\(s.links == 1 ? "" : "s")\(s.connecting > 0 ? " · connecting to \(s.connecting)" : "") · \(s.scanning ? "scanning" : "not scanning") · \(s.advertising ? "advertising" : "not advertising")")
        notice("Messages shown \(st.delivered) · passed on \(st.relayed) · copies dropped \(st.duplicates) · caught up \(st.caughtUp)")
        notice("Refused: \(st.authFailed) failed the room's key or a signature · \(st.expired) too old or from the future · \(st.malformed) broken · \(st.rateLimited) too many · \(st.incompatible) another version · \(st.foreign) of other rooms")
        if st.connectFailures > 0 { notice("Connections that failed: \(st.connectFailures) – lotus meshchat doctor shows the last ones") }
    }

    private func rename(_ name: String) {
        let clean = Sanitize.nickname(name)
        guard !clean.isEmpty else { return notice("You are \(view.nickname). A new name: /nick <name> (up to 24 characters)") }
        store?.set("NICKNAME", clean)
        view.nickname = clean
        meshQueue.async { [weak self] in self?.node.rename(clean) }
        notice("You are now \(clean).")
    }

    private func switchTo(_ r: SavedRoom) {
        guard demo == nil else { return notice("The demo cannot switch rooms – close it (ctrl-c) and run lotus meshchat.") }
        do {
            try open(r)
            notice("Now in \(r.name.isEmpty ? "#\(r.id)" : r.name).")
        } catch {
            notice("\(error)", .error)
        }
    }

    private func join(_ code: String) {
        guard let store = store else { return notice("The demo cannot join rooms.") }
        do {
            let secret = try InviteCode.parse(code)
            let id = RoomKeys(secret: secret).id
            if id == room?.id { return notice("You are in that room already.") }
            let saved = (try? store.room(id)) ?? SavedRoom(id: id, name: "", code: InviteCode.make(secret), created: Date().timeIntervalSince1970)
            try store.save(saved)
            switchTo(saved)
        } catch let e as InviteError {
            notice(e.description, .warning)
        } catch {
            notice("\(error)", .error)
        }
    }

    private func create(_ name: String) {
        guard let store = store else { return notice("The demo cannot make rooms – lotus meshchat create does.") }
        let secret = RoomSecret.generate()
        let clean = Sanitize.roomName(name.isEmpty ? "\(view.nickname)'s room" : name)
        let r = SavedRoom(id: RoomKeys(secret: secret).id, name: clean, code: InviteCode.make(secret), created: Date().timeIntervalSince1970, creator: true)
        do {
            try store.save(r)
            switchTo(r)
            invite()
        } catch {
            notice("Could not save the room: \(error)", .error)
        }
    }

    private func rooms() {
        guard let store = store else { return notice("The demo has only its own room.") }
        let list = store.rooms().rooms
        if list.isEmpty { return notice("No rooms saved.") }
        for r in list {
            notice("\(r.id == room?.id ? "› " : "  ")\(r.name.isEmpty ? "(no name)" : r.name)  #\(r.id)\(r.creator ? " · yours" : "")")
        }
        notice("/open <name or ID> switches rooms.")
    }

    private func openRoom(_ query: String) {
        guard let store = store else { return notice("The demo has only its own room.") }
        guard !query.isEmpty else { return rooms() }
        do { switchTo(try store.room(query)) } catch { notice("\(error)", .warning) }
    }

    // ── Leaving ───────────────────────────────────────────────

    private func leaveRoom() {
        guard let r = room, let store = store else { return }
        meshQueue.sync { node.leaveRoom() }
        do {
            try store.delete(r)
            farewell = "You left \"\(r.name.isEmpty ? r.id : r.name)\" – its code and history are deleted from this Mac. To come back you need the code again."
        } catch {
            farewell = "You left \"\(r.name.isEmpty ? r.id : r.name)\", but its folder could not be deleted: \(error)"
        }
        room = nil
        quit()
    }

    // Goodbye to the room and the neighbours, a moment for it to go out, then Bluetooth off and the terminal back
    private func quit() {
        guard !quitting else { return }
        quitting = true
        meshQueue.sync { node.goodbye() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            self.timer?.cancel()
            self.meshQueue.sync { self.node.stop() }
            self.screenOn = false
            Screen.leave()
            if !self.farewell.isEmpty {
                print("  " + self.farewell)
            } else if self.demo != nil {
                print("  That was the demo. A real room: " + Theme.key("lotus meshchat create \"Room name\""))
            } else {
                let name = self.view.roomName.isEmpty ? "#\(self.view.roomID)" : self.view.roomName
                print("  Closed \(name) – " + Theme.key("lotus meshchat") + " opens it again.")
            }
            self.store?.log("chat closed")
            self.store?.flushLog()
            exit(0)
        }
    }

    // ── Relay mode ────────────────────────────────────────────

    #if canImport(CoreBluetooth)
    // No room: this Mac only passes on what Macs nearby send, unread, so that they reach further
    static func relay(store: Store, config: MeshConfig) -> Never {
        var config = config
        config.relayForeign = true
        let queue = DispatchQueue(label: "meshchat.relay")
        let radio = BLETransport(queue: queue)
        radio.onLog = { store.log($0) }
        var latest = MeshSnapshot()
        let node = MeshNode(transport: radio, config: config, nickname: "relay",
                            events: { e in
                                if case .snapshot(let s) = e { latest = s }
                                if case .log(let t) = e { store.log(t) }
                            })
        print("")
        print("  " + Theme.bold(Theme.accent("lotus")) + Theme.dim(" / ") + Theme.bold("MeshChat relay") + Theme.dim("  passes on what MeshChat Macs nearby send – without reading it"))
        print(Theme.dim("  It cannot read any room. It keeps nothing. Ctrl-C stops it."))
        print("")
        queue.sync { node.start() }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler {
            node.tick()
            let s = latest
            let line = "  \(s.radio == .on ? Theme.green("●") : Theme.yellow("●")) Bluetooth \(s.radio.label) · \(s.links) link\(s.links == 1 ? "" : "s") · \(s.stats.relayed) passed on · \(s.stats.duplicates) copies dropped"
            Term.write("\r\u{1B}[K" + line)
        }
        t.resume()
        signal(SIGINT, SIG_IGN)
        let stop = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        stop.setEventHandler {
            let relayed = queue.sync { () -> Int in
                node.stop()
                return latest.stats.relayed
            }
            print("\n  Relay stopped – \(relayed) messages passed on.")
            store.flushLog()
            exit(0)
        }
        stop.resume()
        withExtendedLifetime((t, stop)) { dispatchMain() }
    }
    #endif
}
