// MeshChat tests – the mesh on a simulated radio: Macs that find and link to each other, messages over several
// relays, each shown once, the hop limit, catching up after being out of range, hostile neighbours, other rooms,
// who is here, and Bluetooth switched off. The radio is simulated (SimTransport.swift), the mesh is the real one.

import Foundation

final class TestMesh {
    let net: SimNetwork
    let secret: RoomSecret
    private(set) var nodes: [String: MeshNode] = [:]
    private(set) var radios: [String: SimRadio] = [:]
    var events: [String: [MeshEvent]] = [:]

    init(secret: RoomSecret = .generate(), seed: UInt64 = 1) {
        net = SimNetwork(seed: seed)
        self.secret = secret
    }

    @discardableResult
    func add(_ name: String, maxFrame: Int = 182, config: MeshConfig = MeshConfig(), room: RoomSecret? = nil, roomName: String = "Test room",
             identity: Data = CryptoBackend.randomBytes(32), inRoom: Bool = true) -> MeshNode {
        let radio = net.radio(name, maxFrame: maxFrame)
        let net = self.net
        let node = MeshNode(transport: radio, config: config, nickname: name, clock: { net.now },
                            events: { [unowned self] e in self.events[name, default: []].append(e) })
        nodes[name] = node
        radios[name] = radio
        net.tickers.append { [weak node] in node?.tick() }
        node.start()
        if inRoom { try! node.enter(secret: room ?? secret, name: roomName, identity: identity) }
        return node
    }

    func node(_ name: String) -> MeshNode { nodes[name]! }
    func run(_ seconds: TimeInterval) { net.advance(seconds) }
    func say(_ name: String, _ text: String) { _ = try? nodes[name]!.send(text); net.pump() }

    func received(_ name: String) -> [ChatMessage] {
        (events[name] ?? []).compactMap { if case .message(let m) = $0, !m.mine { return m } else { return nil } }
    }
    func texts(_ name: String) -> [String] { received(name).map { $0.text } }
    func notices(_ name: String) -> [String] {
        (events[name] ?? []).compactMap { if case .notice(let n) = $0 { return n.text } else { return nil } }
    }
    func people(_ name: String) -> [Participant] { nodes[name]!.snapshot().participants }
    func person(_ who: String, seenBy name: String) -> Participant? { people(name).first { $0.nickname == who } }
    func linked(_ a: String, _ b: String) -> Bool { net.linkPairs.contains(a < b ? "\(a)|\(b)" : "\(b)|\(a)") }
    func stats(_ name: String) -> MeshStats { nodes[name]!.stats }
}

// A neighbour that sends whatever a test wants
final class Rogue: LinkTransportDelegate {
    let radio: SimRadio
    var link: Int?
    var received: [Data] = []
    var closed = false
    var opened = 0
    private var seq: UInt16 = 100

    init(_ net: SimNetwork, name: String = "rogue", maxFrame: Int = 512) {
        radio = net.radio(name, maxFrame: maxFrame)
        radio.delegate = self
        radio.start(token: 0)
    }

    func connect(to name: String, in net: SimNetwork, hello: Bool = true) {
        radio.connect(name)
        net.pump()
        if hello { send(.hello(Hello(session: CryptoBackend.randomBytes(8)))) }
        net.pump()
    }

    func send(_ f: LinkFrame) { sendRaw(f.encode()) }
    func sendRaw(_ d: Data) { if let l = link { radio.send(d, on: l) } }

    func sendPacket(_ p: MeshPacket) {
        seq &+= 1
        for f in try! Fragmenter.frames(for: p.encode(), seq: seq, maxFrame: 512) { sendRaw(f) }
    }

    func radio(stateChanged state: RadioState) {}
    func radio(sighted: Sighting) {}
    func radio(opened link: LinkInfo) {
        self.link = link.id
        opened += 1
    }
    func radio(closed link: Int, reason: String) { closed = true; self.link = nil }
    func radio(received frame: Data, on link: Int) { received.append(frame) }
    func radio(connectFailed endpoint: String, reason: String) {}
}

// A packet as a member of the room makes it
private func memberPacket(_ m: TestMesh, text: String, from nickname: String = "Mallory", time: TimeInterval? = nil, id: UInt64 = 777,
                          signer: Signer? = nil, ttl: UInt8 = 5) throws -> MeshPacket {
    let keys = RoomKeys(secret: m.secret)
    let s = try signer ?? Signer(identity: CryptoBackend.randomBytes(32), room: keys)
    let inner = InnerMessage(kind: .chat, senderKey: s.publicKey, session: CryptoBackend.randomBytes(8), nickname: nickname, text: text)
    return try RoomCrypto(keys: keys, signer: s).seal(inner, ttl: ttl, messageID: id, timestamp: UInt64((time ?? m.net.now) * 1000))
}

func meshTests() {
    test("two Macs find each other, link once and chat") {
        let m = TestMesh()
        m.add("Ada")
        m.add("Bob")
        m.net.allInRange(["Ada", "Bob"])
        m.run(15)
        check(m.linked("Ada", "Bob"), "linked")
        checkEqual(m.net.linkCount, 1, "one link, not two")
        checkEqual(m.node("Ada").readyLinks, 1, "Ada has the link")
        m.say("Ada", "Hello, Bob!")
        checkEqual(m.texts("Bob"), ["Hello, Bob!"], "Bob reads it")
        checkEqual(m.received("Bob").first?.nickname, "Ada", "from Ada")
        checkEqual(m.received("Bob").first?.hops, 0, "straight from her")
        m.say("Bob", "Hi Ada")
        checkEqual(m.texts("Ada"), ["Hi Ada"], "and Ada his answer")
        let bob = m.person("Bob", seenBy: "Ada")
        check(bob?.direct == true, "Ada sees Bob as a neighbour")
        check(m.notices("Ada").contains { $0.contains("Bob is here") }, "and was told he is here")
    }

    test("multi-hop: A reaches C through B, though A and C cannot hear each other") {
        let m = TestMesh()
        for n in ["A", "B", "C"] { m.add(n) }
        m.net.setRange("A", "B", true)
        m.net.setRange("B", "C", true)
        m.run(40)
        check(m.linked("A", "B") && m.linked("B", "C"), "A–B and B–C are linked")
        check(!m.linked("A", "C"), "A–C cannot be")
        m.say("A", "over the hill")
        checkEqual(m.texts("C"), ["over the hill"], "C reads A's message")
        checkEqual(m.received("C").first?.hops, 1, "through one relay")
        checkEqual(m.texts("B"), ["over the hill"], "B reads it too")
        m.say("C", "got it")
        checkEqual(m.texts("A"), ["got it"], "and the answer comes back")
        let a = m.person("A", seenBy: "C")
        check(a != nil && a!.direct == false && a!.hops == 1, "C sees A one relay away")
        check(m.person("B", seenBy: "C")?.direct == true, "and B as its neighbour")
        check(m.stats("B").relayed >= 2, "B passed both on")
    }

    test("each message is shown once, however many paths it takes") {
        let m = TestMesh()
        let names = ["A", "B", "C", "D", "E"]
        for n in names { m.add(n) }
        m.net.allInRange(names)
        m.run(60)
        check(m.net.linkCount >= 7, "a dense mesh (\(m.net.linkCount) links)")
        for n in names { m.say(n, "from \(n)") }
        m.run(2)
        for n in names {
            let got = m.texts(n).sorted()
            checkEqual(got, names.filter { $0 != n }.map { "from \($0)" }.sorted(), "\(n) got each other message exactly once")
        }
        check(names.map { m.stats($0).duplicates }.reduce(0, +) > 0, "copies over other paths were recognized and dropped")
    }

    test("the hop limit: a message takes at most as many relays as its sender allows") {
        let m = TestMesh()
        var short = MeshConfig()
        short.hops = 2
        let chain = (0..<8).map { "N\($0)" }
        for (i, n) in chain.enumerated() { m.add(n, config: i == 0 ? short : MeshConfig()) }
        for i in 0..<7 { m.net.setRange(chain[i], chain[i + 1], true) }
        m.run(80)
        checkEqual(m.net.linkCount, 7, "a chain of 8 Macs")
        m.say("N0", "two relays only")
        m.run(2)
        let reached = chain.filter { m.texts($0).contains("two relays only") }
        checkEqual(reached, ["N1", "N2", "N3"], "hops 2: the neighbour and two relays")
        checkEqual(m.received("N3").first?.hops, 2, "N3 got it after two relays")
        m.say("N7", "five relays")
        m.run(2)
        let reached5 = chain.filter { m.texts($0).contains("five relays") }
        checkEqual(reached5, ["N1", "N2", "N3", "N4", "N5", "N6"], "the default of 5 relays ends at N1")
    }

    test("old messages, ones from the future and replays are refused") {
        let m = TestMesh()
        m.add("A")
        let rogue = Rogue(m.net)
        m.net.allInRange(["A", "rogue"])
        m.run(3)
        rogue.connect(to: "A", in: m.net)
        check(rogue.link != nil, "a member's Mac linked to A")
        rogue.sendPacket(try memberPacket(m, text: "stale", time: m.net.now - 20 * 60, id: 1))
        rogue.sendPacket(try memberPacket(m, text: "from the future", time: m.net.now + 30 * 60, id: 2))
        rogue.sendPacket(try memberPacket(m, text: "fresh", id: 3))
        m.net.pump()
        checkEqual(m.texts("A"), ["fresh"], "only the fresh one is shown")
        checkEqual(m.stats("A").expired, 2, "two refused for their time")
        check(m.notices("A").contains { $0.contains("clocks of the two Macs differ") }, "and A is told why")
        let replay = try memberPacket(m, text: "once", id: 4)
        rogue.sendPacket(replay)
        rogue.sendPacket(replay)
        m.net.pump()
        checkEqual(m.texts("A").filter { $0 == "once" }.count, 1, "a replayed packet is shown once")
    }

    test("forged or damaged packets are not shown, not passed on, and cannot block the real one") {
        let m = TestMesh()
        m.add("B")
        m.add("C")
        let rogue = Rogue(m.net)
        m.net.allInRange(["B", "C", "rogue"])
        m.run(15)
        rogue.connect(to: "B", in: m.net)
        let genuine = try memberPacket(m, text: "the real one", id: 99)
        var forged = genuine
        forged.sealed[5] ^= 0xFF
        rogue.sendPacket(forged)
        m.net.pump()
        checkEqual(m.stats("B").authFailed, 1, "B refuses the damaged copy")
        check(m.texts("B").isEmpty && m.texts("C").isEmpty, "nobody sees it")
        rogue.sendPacket(genuine)
        m.net.pump()
        checkEqual(m.texts("B"), ["the real one"], "the real one with the same ID gets through after it")
        checkEqual(m.texts("C"), ["the real one"], "and is passed on")
        let keys = RoomKeys(secret: m.secret)
        let alice = try Signer(identity: CryptoBackend.randomBytes(32), room: keys)
        let mallory = try Signer(identity: CryptoBackend.randomBytes(32), room: keys)
        let lie = InnerMessage(kind: .chat, senderKey: alice.publicKey, session: Data(count: 8), nickname: "Alice", text: "I am Alice")
        rogue.sendPacket(try RoomCrypto(keys: keys, signer: mallory).seal(lie, ttl: 5, messageID: 5, timestamp: UInt64(m.net.now * 1000)))
        m.net.pump()
        check(!m.texts("B").contains("I am Alice"), "a message signed with another key than its sender's is refused")
        checkEqual(m.stats("B").authFailed, 2, "counted")
    }

    test("broken frames and floods: refused, counted, and the chat goes on") {
        let m = TestMesh()
        m.add("A")
        m.add("B")
        let rogue = Rogue(m.net)
        m.net.allInRange(["A", "B", "rogue"])
        m.run(15)
        rogue.connect(to: "A", in: m.net, hello: false)
        rogue.send(.data(seq: 1, index: 0, count: 1, payload: Data("before hello".utf8)))
        m.net.pump()
        check(m.stats("A").malformed >= 1, "data before the handshake is refused")
        rogue.send(.hello(Hello(session: CryptoBackend.randomBytes(8))))
        var gen = SeededGenerator(seed: 42)
        for i in 0..<200 {
            var noise = Data((0..<Int.random(in: 2...60, using: &gen)).map { _ in UInt8.random(in: 0...255, using: &gen) })
            if i % 2 == 0 { noise[0] = 1 }          // half of it looks like this version's frames …
            if noise[0] == 1 && noise[1] == LinkKind.bye.rawValue { noise[1] = 0x77 }   // … but a goodbye would end the link
            rogue.sendRaw(noise)
        }
        rogue.sendRaw(Data([1, 2, 0, 1, 0, 1]) + Data(count: 600))
        var bad = try memberPacket(m, text: "x", id: 8).encode()
        bad[3] = 7
        bad[4] = 1          // ttl + hops = 8
        rogue.send(.data(seq: 2, index: 0, count: 1, payload: bad))
        m.net.pump()
        check(m.stats("A").malformed > 100, "random bytes are refused (\(m.stats("A").malformed))")
        check(m.stats("A").incompatible < 20, "noise is not taken for a newer MeshChat (\(m.stats("A").incompatible))")
        for i in 0..<400 { rogue.send(.data(seq: UInt16(1000 + i), index: 0, count: 2, payload: Data(count: 10))) }
        m.net.pump()
        check(m.stats("A").rateLimited > 0, "a flood is cut off (\(m.stats("A").rateLimited) frames)")
        m.run(2)
        m.say("B", "still working?")
        checkEqual(m.texts("A"), ["still working?"], "A still chats with B")
    }

    test("other rooms: not shown, not passed on – unless a Mac relays for everyone") {
        let other = RoomSecret.generate()
        let m = TestMesh()
        m.add("A")
        m.add("B", room: other)
        m.add("C")
        m.net.setRange("A", "B", true)
        m.net.setRange("B", "C", true)
        m.run(40)
        m.say("A", "for room X")
        m.run(2)
        check(m.texts("B").isEmpty, "B, in another room, cannot read it")
        check(m.texts("C").isEmpty, "and does not pass it on")
        check(m.stats("B").foreign >= 1, "B counted a packet of another room")

        let r = TestMesh()
        var relay = MeshConfig()
        relay.relayForeign = true
        r.add("A")
        r.add("B", config: relay, inRoom: false)
        r.add("C")
        r.net.setRange("A", "B", true)
        r.net.setRange("B", "C", true)
        r.run(40)
        r.say("A", "through a relay")
        r.run(2)
        checkEqual(r.texts("C"), ["through a relay"], "a Mac in relay mode passes it on")
        check(r.texts("B").isEmpty, "without reading it")
        checkEqual(r.received("C").first?.hops, 1, "one relay")
    }

    test("out of range and back: links come again, missed messages arrive, nothing twice") {
        let m = TestMesh()
        for n in ["A", "B", "C"] { m.add(n) }
        m.net.setRange("A", "B", true)
        m.net.setRange("B", "C", true)
        m.run(40)
        m.say("A", "before")
        checkEqual(m.texts("C"), ["before"], "C has the first message")
        m.net.setRange("B", "C", false)
        m.net.pump()
        check(!m.linked("B", "C"), "C is out of range")
        check(m.notices("B").contains { $0.contains("link to C ended") }, "B is told the link to C ended")
        m.run(5)
        m.say("A", "while you were away")
        check(!m.texts("C").contains("while you were away"), "C misses it while away")
        m.run(30)
        m.net.setRange("B", "C", true)
        m.run(30)
        check(m.linked("B", "C"), "C linked again")
        checkEqual(m.texts("C"), ["before", "while you were away"], "C caught up – each message once")
        check(m.stats("B").caughtUp > 0, "B sent C what it missed")
        m.say("C", "back")
        checkEqual(m.texts("A").filter { $0 == "back" }.count, 1, "and C is heard again")
    }

    test("a Mac that connects but never answers is tried less and less, not forever") {
        let m = TestMesh()
        m.add("A")
        let rogue = Rogue(m.net)
        rogue.radio.setAdvertising(true)        // found and connected to – and it never says hello
        m.net.allInRange(["A", "rogue"])
        m.run(600)
        check(rogue.opened >= 3, "A tried again (\(rogue.opened) times)")
        check(rogue.opened <= 12, "but not every few seconds: \(rogue.opened) attempts in 10 minutes")
        check(m.stats("A").connectFailures >= 3, "each one a failed connection")
        checkEqual(m.node("A").readyLinks, 0, "and no link")
    }

    test("two Macs that connect to each other at once keep one link") {
        let m = TestMesh()
        var eager = MeshConfig()
        eager.initiatorGrace = 0         // neither waits for the other
        m.add("A", config: eager)
        m.add("B", config: eager)
        m.net.allInRange(["A", "B"])
        m.run(60)
        checkEqual(m.node("A").readyLinks, 1, "A keeps one link")
        checkEqual(m.node("B").readyLinks, 1, "B keeps one link")
        checkEqual(m.net.linkCount, 1, "the second link was closed")
        m.say("A", "once")
        checkEqual(m.texts("B"), ["once"], "messages go once")
    }

    test("a Mac with another protocol version is named, not linked") {
        let m = TestMesh()
        m.add("A")
        let rogue = Rogue(m.net)
        m.net.allInRange(["A", "rogue"])
        m.run(3)
        rogue.connect(to: "A", in: m.net, hello: false)
        rogue.send(.hello(Hello(minVersion: 2, maxVersion: 3, session: CryptoBackend.randomBytes(8))))
        m.net.pump()
        check(m.notices("A").contains { $0.contains("newer MeshChat") }, "A says a newer MeshChat is nearby")
        check(rogue.received.contains(LinkFrame.bye(ByeReason.incompatible.rawValue).encode()), "and tells it why it ends the link")
        checkEqual(m.node("A").readyLinks, 0, "no link")
        let r2 = Rogue(m.net, name: "rogue2")
        m.net.allInRange(["A", "rogue2"])
        r2.connect(to: "A", in: m.net, hello: false)
        r2.sendRaw(Data([2, 1, 9, 9]))
        m.net.pump()
        check(m.notices("A").contains { $0.contains("link protocol 2") }, "a newer link format is named too")
    }

    test("who is here: neighbours, people further away, goodbyes and silence") {
        let m = TestMesh()
        for n in ["A", "B", "C"] { m.add(n) }
        m.net.setRange("A", "B", true)
        m.net.setRange("B", "C", true)
        m.run(45)
        let people = m.people("A").map { $0.nickname }
        checkEqual(people, ["B", "C"], "A knows B and C without them writing anything")
        check(m.person("B", seenBy: "A")?.direct == true, "B is A's neighbour")
        check(m.person("C", seenBy: "A")?.direct == false && m.person("C", seenBy: "A")?.hops == 1, "C is one relay away")
        checkEqual(m.person("C", seenBy: "A")?.links, 1, "C said it has one link")
        m.node("C").goodbye()
        m.net.pump()
        m.node("C").stop()
        check(m.person("C", seenBy: "A")?.left == true, "C said goodbye")
        check(m.notices("A").contains("C left the chat."), "and A was told")
        m.radios["B"]!.setPower(false)
        m.run(100)
        check(m.person("B", seenBy: "A")?.away == true, "B is away after 80 silent seconds")
        check(m.notices("A").contains { $0.contains("B has not been heard") }, "and A was told")
        m.run(600)
        check(m.person("B", seenBy: "A") == nil, "after 10 minutes B is off the list")
    }

    test("a room's name reaches those who joined with only its code") {
        let m = TestMesh()
        m.add("A", roomName: "Bike trip")
        m.add("B", roomName: "")
        m.net.allInRange(["A", "B"])
        m.run(20)
        checkEqual(m.node("B").roomName, "Bike trip", "B learned the name")
        check((m.events["B"] ?? []).contains { if case .roomName("Bike trip") = $0 { return true } else { return false } }, "and told the app")
    }

    test("Bluetooth switched off and on again") {
        let m = TestMesh()
        m.add("A")
        m.add("B")
        m.net.allInRange(["A", "B"])
        m.run(15)
        check(m.linked("A", "B"), "linked")
        m.radios["B"]!.setPower(false)
        m.net.pump()
        checkEqual(m.node("B").snapshot().radio, .off, "B's radio is off")
        checkEqual(m.node("A").readyLinks, 0, "A lost the link")
        m.run(10)
        m.radios["B"]!.setPower(true)
        m.run(30)
        check(m.linked("A", "B"), "linked again once it is on")
        m.say("B", "I'm back")
        checkEqual(m.texts("A"), ["I'm back"], "and chatting")
    }

    test("long messages over the smallest links, frames that come twice") {
        let m = TestMesh()
        m.add("A", maxFrame: 20)
        m.add("B", maxFrame: 20)
        m.net.allInRange(["A", "B"])
        m.run(15)
        let long = String(repeating: "Ünïcödé 🌸 ", count: 60)
        let sent = Sanitize.text(Sanitize.cut(long, characters: Int.max, bytes: 990))
        m.say("A", sent)
        checkEqual(m.texts("B"), [Sanitize.text(sent)], "a long message over 20-byte frames arrives whole")
        m.net.duplicateRate = 0.5
        for i in 0..<10 { m.say("B", "dup \(i)") }
        m.run(2)
        checkEqual(m.texts("A"), (0..<10).map { "dup \($0)" }, "doubled frames: each message once, in order")
        m.net.duplicateRate = 0
        m.net.lossRate = 0.3
        for i in 0..<10 { m.say("A", "lossy \(i)") }
        m.run(20)
        m.net.lossRate = 0
        let arrived = m.texts("B").filter { $0.hasPrefix("lossy") }
        check(arrived.allSatisfy { t in (0..<10).contains { "lossy \($0)" == t } }, "lost frames never make a wrong message (\(arrived.count) of 10 arrived)")
    }

    test("at most as many links as allowed, and the mesh still reaches everyone") {
        let m = TestMesh()
        var two = MeshConfig()
        two.maxLinks = 2
        let names = ["A", "B", "C", "D", "E", "F"]
        for n in names { m.add(n, config: n == "A" ? two : MeshConfig()) }
        m.net.allInRange(names)
        m.run(90)
        check(m.node("A").readyLinks <= 2, "A has at most 2 links (\(m.node("A").readyLinks))")
        m.say("A", "to all")
        m.run(2)
        for n in names.dropFirst() { checkEqual(m.texts(n), ["to all"], "\(n) got it") }
    }

    test("a Mac that restarts gets its own old messages back as its own") {
        let m = TestMesh()
        let identity = CryptoBackend.randomBytes(32)
        m.add("A", identity: identity)
        m.add("B")
        m.net.allInRange(["A", "B"])
        m.run(15)
        m.say("A", "before the restart")
        m.node("A").stop()
        m.run(5)
        let again = TestMesh.Restarted(m, name: "A", identity: identity)
        m.run(30)
        let mine = again.messages.filter { $0.mine }.map { $0.text }
        check(mine.contains("before the restart"), "it comes back marked as A's own")
        check(!m.node("A2").snapshot().participants.contains { $0.nickname == "A" }, "A is not listed as someone else")
    }
}

extension TestMesh {
    // A second MeshNode for the same Mac (same identity), as after a restart
    final class Restarted {
        var messages: [ChatMessage] = []
        init(_ m: TestMesh, name: String, identity: Data) {
            let radio = m.net.radio(name + "2")
            let net = m.net
            let node = MeshNode(transport: radio, nickname: name, clock: { net.now }, events: { [unowned self] e in
                if case .message(let msg) = e { self.messages.append(msg) }
            })
            m.adopt(node, radio: radio, as: name + "2")
            node.start()
            try! node.enter(secret: m.secret, name: "Test room", identity: identity)
            for other in m.nodes.keys where other != name + "2" { m.net.setRange(name + "2", other, true) }
        }
    }

    func adopt(_ node: MeshNode, radio: SimRadio, as name: String) {
        nodes[name] = node
        radios[name] = radio
        net.tickers.append { [weak node] in node?.tick() }
    }
}
