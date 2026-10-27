// MeshChat – the chat itself: the mesh on a queue of its own, the screen and the keys on the main one, and the
// commands (/who, /nick, /status, /quit …). There is one chat – everyone nearby – and what is said in it goes into
// this Mac's history. Closing the chat says goodbye, stops Bluetooth and gives the terminal back – nothing keeps
// running.

import Foundation

final class ChatApp {
    private let store: Store?               // nil: the demo keeps nothing
    private let meshQueue = DispatchQueue(label: "meshchat.mesh")
    private var node: MeshNode!
    private var demo: DemoWorld?
    private var view = ChatViewState()
    private var seen = Set<UInt64>()
    private var keys: KeyReader?
    private var timer: DispatchSourceTimer?
    private var winch: DispatchSourceSignal?
    private var drawQueued = false
    private var screenOn = false
    private var quitting = false

    private init(store: Store?) { self.store = store }

    private func setUp(transport: LinkTransport, config: MeshConfig, nickname: String, signer: Signer) {
        node = MeshNode(transport: transport, config: config, nickname: nickname, signer: signer,
                        clock: { [weak world = demo] in world?.net.now ?? Date().timeIntervalSince1970 },
                        events: { [weak self] e in DispatchQueue.main.async { self?.handle(e) } })
        view.nickname = node.nickname
        view.fingerprint = signer.fingerprint
    }

    // ── Starting ──────────────────────────────────────────────

    #if canImport(CoreBluetooth)
    // The chat over Bluetooth. Bluetooth starts before the screen changes: should macOS end the process for want of
    // a permission, the terminal is still as it was.
    static func bluetooth(store: Store, config: MeshConfig, terminal: TerminalApp?) -> Never {
        let app = ChatApp(store: store)
        let signer: Signer
        do {
            signer = try Signer(identity: store.identity())
        } catch {
            print(Theme.red("  ✗ ") + "Could not make this Mac's signing key: \(error)")
            exit(1)
        }
        let who = terminal?.name ?? "your terminal app"
        app.view.terminalApp = terminal?.name ?? ""
        if BluetoothProbe.authorization() == "not-determined" {
            print(Theme.dim("  macOS will ask whether \(who) may use Bluetooth – choose Allow, so MeshChat can reach the Macs around you."))
        }
        let radio = BLETransport(queue: app.meshQueue)
        radio.onLog = { store.log($0) }
        app.setUp(transport: radio, config: config, nickname: store.nickname ?? "anon", signer: signer)
        store.trimLog()
        store.log("chat started – MeshChat \(Proto.software), \(config.maxLinks) links")
        app.openChat()
        app.meshQueue.sync { app.node.start() }
        var state = RadioState.starting
        let deadline = Date().addingTimeInterval(2.5)
        repeat {
            usleep(100_000)
            state = app.meshQueue.sync { radio.state }
        } while state == .starting && Date() < deadline
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
        // a random identity: the demo is not you, and keeps nothing (Signer only refuses a seed of the wrong size)
        app.setUp(transport: world.userRadio(), config: config, nickname: name, signer: try! Signer(identity: CryptoBackend.randomBytes(32)))
        app.meshQueue.sync {
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

    // The history on the screen; messages in it that come again are not shown twice
    private func openChat() {
        guard let store = store else { return }
        store.trimHistory()
        let (history, skipped) = store.history(last: 300)
        for m in history {
            view.add(.message(m.message), order: min(m.sent, m.received))
            seen.insert(m.id)
        }
        if !history.isEmpty { view.add(.divider("earlier messages above"), order: (view.lines.last?.order ?? 0) + 0.001) }
        if skipped > 0 { notice("\(skipped) damaged line\(skipped == 1 ? "" : "s") in the history skipped.", .warning) }
        let recent = history.filter { Date().timeIntervalSince1970 - $0.sent < 1800 }.map { $0.id }
        meshQueue.sync { node.markSeen(recent) }
    }

    // ── Events of the mesh ────────────────────────────────────

    private func handle(_ e: MeshEvent) {
        switch e {
        case .message(let m):
            guard seen.insert(m.id).inserted else { return }
            view.add(.message(m), order: min(m.sent, m.received))
            store?.append(m)
        case let .sent(id, links):
            if links == 0 { view.pending.insert(id) } else { view.pending.remove(id) }
        case .notice(let n):
            view.add(.notice(n), order: Date().timeIntervalSince1970)
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

    static let commands = ["/help", "/who", "/where", "/nick", "/status", "/clear", "/quit"]

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
        case "/where", "/far", "/distance": whereIs(arg)
        case "/status", "/mesh", "/info": status()
        case "/nick", "/name": rename(arg)
        case "/clear": view.lines.removeAll()
        case "/quit", "/exit", "/q", "/bye": quit()
        case "/join", "/create", "/new", "/invite", "/code", "/leave", "/rooms", "/room", "/open":
            notice("There are no rooms: everyone nearby with MeshChat is in this one chat, and everything in it is public.", .warning)
        default: notice("There is no \(cmd) – /help lists the commands. To send a line starting with /, write //.", .warning)
        }
    }

    private func help() {
        for line in [
            "Everything you write goes to every Mac nearby with MeshChat, and each one passes it on – as far as the mesh reaches. It is public.",
            "/who – who is here, and how: ● a direct Bluetooth link, ⇢2 two relays away, ○ not heard for a while",
            "/where <name> – how far someone is: from the signal strength, and the way through the mesh (/where alone: everyone)",
            "/nick <name> – your name · /status – Bluetooth and the mesh · /clear – an empty screen",
            "/quit (ctrl-c, ctrl-d) – close the chat · PgUp/PgDn scroll · ↑ your last lines · //text sends a line that starts with /",
        ] { notice(line) }
    }

    private func ago(_ t: TimeInterval) -> String {
        let s = Int(max(0, Date().timeIntervalSince1970 - t))
        return s < 90 ? "\(s) s ago" : s < 5400 ? "\(s / 60) min ago" : "\(s / 3600) h ago"
    }

    private func who() {
        let people = view.snapshot.participants
        let here = people.filter { !$0.left }.count
        notice("Nearby: you and \(here) other\(here == 1 ? "" : "s") – you are \(view.nickname)·\(view.fingerprint), with \(view.snapshot.links) link\(view.snapshot.links == 1 ? "" : "s")")
        for p in people {
            let how: String
            if p.left { how = "left the chat" }
            else if p.away { how = "away – last heard \(ago(p.lastSeen))" }
            else if p.direct { how = "a neighbour: a direct Bluetooth link" + (p.signal.map { ", " + Distance.label(Distance.metres($0)) } ?? "") }
            else { how = "\(p.hops) relay\(p.hops == 1 ? "" : "s") away\(p.via.isEmpty ? "" : " through \(p.via)"), heard \(ago(p.lastSeen))" }
            notice("  \(p.nickname)·\(p.fingerprint) – \(how)\(p.links > 0 && !p.left ? " · \(p.links) link\(p.links == 1 ? "" : "s")" : "")")
        }
        if people.isEmpty { notice("  No one else yet. On the other Macs: lotus meshchat") }
        if Set(people.map { $0.nickname }).count < people.count {
            notice("  Two people have the same name – the four letters after the dot tell them apart.", .warning)
        }
    }

    // How far someone is: a neighbour from its signal, anyone else along the way through the mesh
    private func whereIs(_ query: String) {
        let people = view.snapshot.participants.filter { !$0.left }
        if people.isEmpty { return notice("No one else is here yet – nobody to measure.") }
        let q = query.lowercased()
        let fits = q.isEmpty ? people : people.filter { $0.nickname.lowercased().hasPrefix(q) || $0.fingerprint == q }
        if fits.isEmpty { return notice("No one called \(query) is here – /who lists who is.", .warning) }
        for p in fits {
            let route = meshQueue.sync { node.route(to: p.key) }
            notice("\(p.nickname)·\(p.fingerprint) – " + ChatApp.describe(p, route: route))
            if q.isEmpty { continue }
            if let route = route, route.count > 1 {
                var way = "  you"
                for leg in route { way += " → \(leg.name) " + (leg.rssi.map { Distance.label(Distance.metres($0)) } ?? "(not measured)") }
                notice(way)
            }
        }
        notice("Estimated from Bluetooth signal strength – walls, bodies and how a Mac is turned make it twice or half as far.")
    }

    static func describe(_ p: Participant, route: [RouteLeg]?) -> String {
        if p.direct || p.hops == 0, let rssi = p.signal ?? route?.first?.rssi {
            let m = Distance.metres(rssi)
            return "\(Distance.label(m)) from you, \(Distance.closeness(m)) (signal \(rssi) dBm)"
        }
        if p.direct { return "a neighbour – its signal is not measured yet" }
        let hops = "\(p.hops) relay\(p.hops == 1 ? "" : "s") away"
        guard let route = route, !route.isEmpty else {
            return hops + (p.via.isEmpty ? "" : ", through \(p.via)") + " – the way further is not known yet"
        }
        let measured = route.compactMap { $0.rssi }
        let through = route.dropLast().map { $0.name }.joined(separator: ", ")
        if measured.count == route.count {
            let total = measured.map { Distance.metres($0) }.reduce(0, +)
            return hops + (through.isEmpty ? "" : " through \(through)") + " – about \(Distance.label(total).replacingOccurrences(of: "≈ ", with: "")) along the way"
        }
        return hops + (through.isEmpty ? "" : " through \(through)") + " – not every leg is measured yet"
    }

    private func status() {
        let s = view.snapshot, st = s.stats
        notice("Bluetooth \(s.radio.label) · \(s.links) link\(s.links == 1 ? "" : "s")\(s.connecting > 0 ? " · connecting to \(s.connecting)" : "") · \(s.scanning ? "scanning" : "not scanning") · \(s.advertising ? "advertising" : "not advertising")")
        notice("Messages shown \(st.delivered) · passed on \(st.relayed) · copies dropped \(st.duplicates) · caught up \(st.caughtUp)")
        notice("Refused: \(st.forged) forged or damaged · \(st.expired) too old or from the future · \(st.malformed) broken · \(st.rateLimited) too many · \(st.incompatible) another version")
        notice("Your messages go up to \(Proto.hopLimit) relays far – as far as there are Macs to pass them on. You are \(view.nickname)·\(view.fingerprint).")
        if st.connectFailures > 0 { notice("Connections that failed: \(st.connectFailures) – lotus meshchat doctor shows the last ones") }
        if let store = store { notice("History: \(store.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))/history.jsonl") }
    }

    private func rename(_ name: String) {
        let clean = Sanitize.nickname(name)
        guard !clean.isEmpty else { return notice("You are \(view.nickname). A new name: /nick <name> (up to 24 characters)") }
        store?.set("NICKNAME", clean)
        view.nickname = clean
        meshQueue.async { [weak self] in self?.node.rename(clean) }
        notice("You are now \(clean).")
    }

    // ── Closing ───────────────────────────────────────────────

    // Goodbye to everyone and the neighbours, a moment for it to go out, then Bluetooth off and the terminal back
    private func quit() {
        guard !quitting else { return }
        quitting = true
        meshQueue.sync { node.goodbye() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            self.timer?.cancel()
            self.meshQueue.sync { self.node.stop() }
            self.screenOn = false
            Screen.leave()
            if self.demo != nil {
                print("  That was the demo. The real chat: " + Theme.key("lotus meshchat"))
            } else {
                print("  MeshChat closed – " + Theme.key("lotus meshchat") + " opens it again.")
            }
            self.store?.log("chat closed")
            self.store?.flushLog()
            exit(0)
        }
    }

    // ── Relay mode ────────────────────────────────────────────

    #if canImport(CoreBluetooth)
    // No chat on the screen: this Mac only passes on what Macs nearby send, so that it reaches further. It says
    // nothing itself, shows nothing and keeps nothing.
    static func relay(store: Store, config: MeshConfig) -> Never {
        var config = config
        config.silent = true
        let queue = DispatchQueue(label: "meshchat.relay")
        let radio = BLETransport(queue: queue)
        radio.onLog = { store.log($0) }
        var latest = MeshSnapshot()
        // a relay never signs anything, so it needs no lasting identity (Signer only refuses a seed of the wrong size)
        let node = MeshNode(transport: radio, config: config, nickname: "relay", signer: try! Signer(identity: CryptoBackend.randomBytes(32)),
                            events: { e in
                                if case .snapshot(let s) = e { latest = s }
                                if case .log(let t) = e { store.log(t) }
                            })
        print("")
        print("  " + Theme.bold(Theme.accent("lotus")) + Theme.dim(" / ") + Theme.bold("MeshChat relay") + Theme.dim("  passes on what MeshChat Macs nearby send"))
        print(Theme.dim("  It shows nothing and keeps nothing. Ctrl-C stops it."))
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
