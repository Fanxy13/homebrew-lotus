// MeshChat tests – private messages (/tell): the message and the box key on the wire, the sealing (X25519 and
// ChaCha20-Poly1305 with their published test vectors, and that only the recipient opens it), a private message through
// the mesh – passed on by everyone, read by one – one that waits for the recipient's key, who /tell finds by name, and
// how it is kept and shown. As win/meshchat/MeshChat.Core/SelfTest/TellTests.cs.

import Foundation

// The packets a neighbour sent to a rogue, put together again and opened
private func opened(_ rogue: Rogue) -> [InnerMessage] {
    let r = Reassembler()
    var out: [InnerMessage] = []
    for f in rogue.received {
        guard case let .data(seq, index, count, payload)? = try? LinkFrame.decode(f),
              case .complete(let whole) = r.add(seq: seq, index: index, count: count, payload: payload, now: 0),
              let packet = try? MeshPacket.decode(whole), let inner = try? Signing.open(packet) else { continue }
        out.append(inner)
    }
    return out
}

private func privateMessages(_ m: TestMesh, _ name: String, mine: Bool) -> [ChatMessage] {
    (m.events[name] ?? []).compactMap { e in
        if case .message(let x) = e, x.privately, x.mine == mine { return x }
        return nil
    }
}

func tellTests() {
    test("private messages on the wire: the message and the box key round trip, older ones are still read") {
        let key = Data(repeating: 3, count: 32), session = Data(repeating: 4, count: 8)
        let tell = InnerMessage(kind: .tell, senderKey: key, session: session, nickname: "Ada", recipient: Data(repeating: 5, count: 32),
                                oneTimeKey: Data(repeating: 6, count: 32), nonce: Data(repeating: 7, count: 12), sealed: Data(repeating: 8, count: 40))
        let presence = InnerMessage(kind: .presence, senderKey: key, session: session, nickname: "Ada", links: 1,
                                    neighbours: [Neighbour(token: 9, rssi: -60)], boxKey: Data(repeating: 10, count: 32))
        for m in [tell, presence] {
            let body = try m.body()
            let (back, signed, _) = try InnerMessage.decode(body + Data(count: 64))
            checkEqual(back, m, "\(m.kind) round trips")
            checkEqual(signed, body, "\(m.kind): the signed part")
        }
        let old = InnerMessage(kind: .presence, senderKey: key, session: session, nickname: "Old", links: 1)
        check(try InnerMessage.decode(try old.body() + Data(count: 64)).0.boxKey == nil, "a presence without a box key (before 2.2) is read, without one")
        checkEqual(try presence.body().count - (try old.body().count), 5 + 32, "the box key is 32 bytes at the end")
        check(try InnerMessage.decode(try old.body() + Data(count: 10) + Data(count: 64)).0.boxKey == nil, "a shorter field there is skipped, as a newer one may be")
        var tooLong = tell
        tooLong.sealed = Data(count: Proto.maxTextBytes + Proto.tagLength + 1)
        checkThrows("a sealed text over 1000 bytes is not made") { try tooLong.body() }
        tooLong.sealed = Data(count: Proto.tagLength)
        checkThrows("nor one with no room for its tag") { try tooLong.body() }
        let cut = try tell.body().dropLast(5)
        checkThrows("a private message cut short is refused") { try InnerMessage.decode(Data(cut) + Data(count: 64)) }
    }

    test("X25519 (RFC 7748) and ChaCha20-Poly1305 (RFC 8439) give the published results") {
        let alice = hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
        let bob = hex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
        checkEqual(Hex.encode(try CryptoBackend.boxPublicKey(alice)), "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", "Alice's public key")
        checkEqual(Hex.encode(try CryptoBackend.boxPublicKey(bob)), "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f", "Bob's public key")
        let shared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
        checkEqual(Hex.encode(try CryptoBackend.sharedSecret(alice, try CryptoBackend.boxPublicKey(bob))), shared, "the secret they share")
        checkEqual(Hex.encode(try CryptoBackend.sharedSecret(bob, try CryptoBackend.boxPublicKey(alice))), shared, "the same from Bob's side")
        let key = hex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
        let nonce = hex("070000004041424344454647")
        let aad = hex("50515253c0c1c2c3c4c5c6c7")
        let text = Data("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".utf8)
        let sealedHex = "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116"
            + "1ae10b594f09e26a7e902ecbd0600691"
        checkEqual(Hex.encode(try CryptoBackend.seal(text, key: key, nonce: nonce, aad: aad)), sealedHex, "the sealed text and its tag")
        checkEqual(try CryptoBackend.open(hex(sealedHex), key: key, nonce: nonce, aad: aad), text, "opened again")
        var changed = hex(sealedHex)
        changed[3] ^= 1
        checkThrows("one byte changed: it does not open") { try CryptoBackend.open(changed, key: key, nonce: nonce, aad: aad) }
        checkThrows("other associated data: neither") { try CryptoBackend.open(hex(sealedHex), key: key, nonce: nonce, aad: hex("00")) }
    }

    test("a private message is sealed for one: the recipient opens it, no one else – and nothing changed opens") {
        let ada = try Signer(identity: CryptoBackend.randomBytes(32))
        let bob = try Signer(identity: CryptoBackend.randomBytes(32))
        let eve = try Signer(identity: CryptoBackend.randomBytes(32))
        let text = "Meet at the bridge 🌉"
        let s = try Sealing.seal(text, from: ada.publicKey, to: bob.publicKey, box: bob.boxKey)
        func message(_ sender: Data, _ recipient: Data, _ sealed: Data) -> InnerMessage {
            InnerMessage(kind: .tell, senderKey: sender, session: CryptoBackend.randomBytes(8), nickname: "Ada", recipient: recipient,
                         oneTimeKey: s.oneTimeKey, nonce: s.nonce, sealed: sealed)
        }
        checkEqual(Sealing.open(message(ada.publicKey, bob.publicKey, s.sealed), signer: bob), text, "Bob reads it")
        checkEqual(Sealing.open(message(ada.publicKey, bob.publicKey, s.sealed), signer: eve), nil, "Eve, who passes it on, cannot")
        checkEqual(Sealing.open(message(ada.publicKey, eve.publicKey, s.sealed), signer: eve), nil, "not even when she makes it one to herself")
        checkEqual(Sealing.open(message(eve.publicKey, bob.publicKey, s.sealed), signer: bob), nil, "nor can she pass it off as her own")
        var changed = s.sealed
        changed[2] ^= 0x40
        checkEqual(Sealing.open(message(ada.publicKey, bob.publicKey, changed), signer: bob), nil, "a changed byte: it does not open")
        check(!String(decoding: s.sealed, as: UTF8.self).contains("bridge"), "the text is not in it")
        let again = try Sealing.seal(text, from: ada.publicKey, to: bob.publicKey, box: bob.boxKey)
        check(again.sealed != s.sealed && again.oneTimeKey != s.oneTimeKey, "the same text twice: two different messages")
        let packet = try Signing.make(message(ada.publicKey, bob.publicKey, s.sealed), signer: ada, ttl: 16, messageID: 99, timestamp: 1_761_570_000_000)
        let back = try Signing.open(try MeshPacket.decode(packet.encode()))
        checkEqual(back.kind, .tell, "signed and checked like every packet")
        checkEqual(Sealing.open(back, signer: bob), text, "and it still opens for Bob")
        let id = CryptoBackend.randomBytes(32)
        checkEqual(try Signer(identity: id).boxKey, try Signer(identity: id).boxKey, "the same identity gives the same box key")
        check(bob.boxKey != bob.publicKey && bob.boxSeed != bob.seed, "a key of its own, not the signing key")
    }

    test("a private message through the mesh: everyone on the way passes it on, only the recipient reads it") {
        let m = TestMesh()
        for n in ["A", "B", "C"] { m.add(n) }
        m.net.setRange("A", "B", true)
        m.net.setRange("B", "C", true)
        m.run(40)
        guard let c = m.person("C", seenBy: "A") else { return check(false, "A knows C") }
        check(c.boxKey != nil, "A has C's box key – it came with C's presence")
        try m.node("A").sendPrivately("only for you, C", to: c.key)
        m.net.pump()
        m.run(1)
        let got = privateMessages(m, "C", mine: false)
        checkEqual(got.map { $0.text }, ["only for you, C"], "C reads it")
        check(got.count == 1 && got[0].hops == 1 && got[0].nickname == "A", "from A, through one relay")
        check(!m.received("B").contains { $0.privately || $0.text.contains("only for you") }, "B shows nothing of it")
        check(m.stats("B").relayed >= 1, "but passed it on")
        let mine = privateMessages(m, "A", mine: true).first
        check(mine?.to == "C" && mine?.text == "only for you, C", "A shows it as its own, to C")
        guard let a = m.person("A", seenBy: "C") else { return check(false, "C knows A") }
        try m.node("C").sendPrivately("got it", to: a.key)
        m.net.pump()
        m.run(1)
        checkEqual(privateMessages(m, "A", mine: false).map { $0.text }, ["got it"], "and the answer comes back, privately")
        checkThrows("to someone who is not there: it says so") { try m.node("A").sendPrivately("hello?", to: CryptoBackend.randomBytes(32)) }
    }

    test("a private message waits for the recipient's key – and is given up after a minute") {
        let m = TestMesh()
        m.add("A")
        let rogue = Rogue(m.net, name: "old")
        m.net.allInRange(["A", "old"])
        m.run(3)
        rogue.connect(to: "A", in: m.net)
        check(rogue.link != nil, "an older MeshChat linked to A")
        let old = try Signer(identity: CryptoBackend.randomBytes(32))
        let session = CryptoBackend.randomBytes(8)
        func presence(_ withBox: Bool, _ id: UInt64) throws -> MeshPacket {
            var inner = InnerMessage(kind: .presence, senderKey: old.publicKey, session: session, nickname: "Old", links: 1)
            if withBox { inner.boxKey = old.boxKey }
            return try Signing.make(inner, signer: old, ttl: 16, messageID: id, timestamp: UInt64(m.net.now * 1000))
        }
        rogue.sendPacket(try presence(false, 501))
        m.net.pump()
        guard let who = m.person("Old", seenBy: "A") else { return check(false, "A knows Old") }
        check(who.boxKey == nil, "A knows Old – an older MeshChat, without a box key")
        try m.node("A").sendPrivately("are you there?", to: who.key)
        m.net.pump()
        check(m.notices("A").contains { $0.contains("has not come yet") }, "the message waits, and A says so")
        check(privateMessages(m, "A", mine: true).isEmpty, "nothing is sent yet")
        check(opened(rogue).contains { $0.kind == .presence && $0.flags & InnerMessage.requestFlag != 0 }, "A asks who is here – for the key")
        rogue.sendPacket(try presence(true, 502))
        m.net.pump()
        let sent = privateMessages(m, "A", mine: true).first
        check(sent?.text == "are you there?" && sent?.to == "Old", "once the key comes, it is sent")
        let tells = opened(rogue).filter { $0.kind == .tell }
        check(tells.count == 1 && Sealing.open(tells[0], signer: old) == "are you there?", "sealed for Old – who opens it")
        let older = try Signer(identity: CryptoBackend.randomBytes(32))
        let olderPresence = InnerMessage(kind: .presence, senderKey: older.publicKey, session: CryptoBackend.randomBytes(8), nickname: "Older", links: 1)
        rogue.sendPacket(try Signing.make(olderPresence, signer: older, ttl: 16, messageID: 503, timestamp: UInt64(m.net.now * 1000)))
        m.net.pump()
        guard let olderOne = m.person("Older", seenBy: "A") else { return check(false, "A knows Older") }
        try m.node("A").sendPrivately("hello?", to: olderOne.key)
        m.run(62)
        check(m.notices("A").contains { $0.contains("was not sent") && $0.contains("Older") }, "a key that never comes: after a minute it says the message was not sent")
        checkEqual(privateMessages(m, "A", mine: true).count, 1, "and it never went out")
    }

    test("/tell finds who it is for: a name in any case, its beginning, the four letters or both – or says why not") {
        func person(_ nick: String, _ fp: String) -> Participant {
            Participant(key: CryptoBackend.randomBytes(32), fingerprint: fp, nickname: nick, session: CryptoBackend.randomBytes(8),
                        lastSeen: 0, hops: 0, links: 0)
        }
        let bob = person("Bob", "k3f9"), bob2 = person("Bob", "m2x1"), ada = person("Ada Lovelace", "a1b2"), grace = person("Grace", "g7h8")
        let people = [bob, ada, grace]
        checkEqual(ChatApp.addressee("bob hi there", among: people), .found(bob, "hi there"), "a name, in any case")
        checkEqual(ChatApp.addressee("Ada Lovelace see you", among: people), .found(ada, "see you"), "a name with a space in it")
        checkEqual(ChatApp.addressee("gr hello", among: people), .found(grace, "hello"), "the beginning of a name")
        checkEqual(ChatApp.addressee("g7h8 hello", among: people), .found(grace, "hello"), "the four letters")
        let two = [bob, bob2, ada]
        checkEqual(ChatApp.addressee("bob hi", among: two), .several([bob, bob2]), "two called Bob: it says so")
        checkEqual(ChatApp.addressee("bob.m2x1 hi", among: two), .found(bob2, "hi"), "Bob.m2x1: that one")
        checkEqual(ChatApp.addressee("Bob·k3f9 hi", among: two), .found(bob, "hi"), "Bob·k3f9 too")
        checkEqual(ChatApp.addressee("zed hi", among: people), .nobody("zed"), "no one called that")
        checkEqual(ChatApp.addressee("bob", among: people), .nothing(bob), "a name, and nothing to say")
        checkEqual(ChatApp.addressee("", among: people), .nobody(""), "nothing at all")
    }

    test("a private message is kept as it was read, and shown with who it is for") {
        let m = ChatMessage(id: 42, nickname: "Ada", fingerprint: "a1b2", text: "only for you", sent: 1_700_000_000, received: 1_700_000_001,
                            hops: 1, mine: true, privately: true, to: "Bob")
        guard let data = Store.encode(m) else { return check(false, "it is kept") }
        let line = String(decoding: data, as: UTF8.self)
        check(line.contains("\"pv\":true") && line.contains("\"to\":\"Bob\""), "the history says it was private, and to whom")
        let back = Store.decode(data)?.message
        check(back?.privately == true && back?.to == "Bob" && back?.text == "only for you" && back?.mine == true, "and reads it back")
        var plainOne = m
        plainOne.privately = false
        plainOne.to = ""
        let plain = Store.encode(plainOne).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(!plain.contains("\"pv\"") && !plain.contains("\"to\""), "a public message is kept as before")
        var s = ChatViewState()
        s.nickname = "Ada"
        s.fingerprint = "a1b2"
        s.add(.message(m), order: m.sent)
        s.add(.message(ChatMessage(id: 43, nickname: "Bob", fingerprint: "k3f9", text: "and only for you", sent: 1_700_000_002, received: 1_700_000_002,
                                   hops: 0, mine: false, privately: true)), order: 1_700_000_002)
        let rows = ChatRender.messageRows(s, width: 80, now: 1_700_000_100).map {
            $0.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        }
        check(rows.contains { $0.contains("Ada") && $0.contains("→ Bob: only for you") }, "mine: → Bob, first")
        check(rows.contains { $0.contains("Bob") && $0.contains("→ you: and only for you") }, "theirs: → you")
    }
}
