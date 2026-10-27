// MeshChat tests – the bytes: link frames, mesh packets, the messages in them, and texts from other Macs.

import Foundation

func codecTests() {
    test("bytes: writer and reader agree, the reader never reads past the end") {
        var w = ByteWriter()
        w.u8(7)
        w.u16(0xBEEF)
        w.u64(0x0102030405060708)
        try w.str8("Grüße 👋")
        try w.str16(String(repeating: "x", count: 300))
        var r = ByteReader(w.data)
        checkEqual(try r.u8(), 7, "u8")
        checkEqual(try r.u16(), 0xBEEF, "u16")
        checkEqual(try r.u64(), 0x0102030405060708, "u64")
        checkEqual(try r.str8(max: 64), "Grüße 👋", "str8 with UTF-8")
        checkEqual(try r.str16(max: 1000).count, 300, "str16")
        check(r.isAtEnd, "nothing left")
        checkThrows("reading past the end") { try r.u8() }
        var short = ByteReader(Data([0, 5, 65]))
        _ = try short.u8()
        checkThrows("a length longer than the rest") { try short.str8(max: 255) }
        var bad = ByteReader(Data([2, 0xC3, 0x28]))
        checkThrows("invalid UTF-8") { try bad.str8(max: 255) }
        var long = ByteReader(Data([10] + Array(repeating: 65, count: 10)))
        checkThrows("a text over its limit") { try long.str8(max: 5) }
    }

    test("hex and base32") {
        checkEqual(Hex.encode(Data([0, 0xAB, 0xFF])), "00abff", "hex")
        checkEqual(Hex.decode("00ABff"), Data([0, 0xAB, 0xFF]), "hex back, any case")
        check(Hex.decode("abc") == nil && Hex.decode("zz") == nil, "not hex")
        checkEqual(Hex.u64(255), "00000000000000ff", "a 64-bit ID as 16 digits")
        checkEqual(Base32.encode(Data([0xFF])), "ZW", "base32 bits in order")
        checkEqual(Base32.encode(Data("f".utf8)), "CR", "Crockford's alphabet")
        checkEqual(Base32.encode(CryptoBackend.randomBytes(32)).count, 52, "32 bytes are 52 characters")
        check(!Base32.alphabet.contains { "ILOU".contains($0) }, "no I, L, O or U to mistake for others")
    }

    test("link frames: every kind round trips") {
        let session = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let frames: [LinkFrame] = [
            .hello(Hello(session: session)),
            .hello(Hello(minVersion: 1, maxVersion: 3, session: session, maxPacket: 999, flags: 1, software: "meshchat/9")),
            .data(seq: 65535, index: 3, count: 4, payload: Data("part".utf8)),
            .ping, .pong, .bye(ByeReason.leaving.rawValue),
        ]
        for f in frames {
            checkEqual(try LinkFrame.decode(f.encode()), f, "frame \(f)")
        }
        checkEqual(LinkFrame.ping.encode(), Data([1, 3]), "a ping is two bytes: version 1, kind 3")
    }

    test("link frames: broken or hostile ones are refused, not crashed on") {
        checkThrows("empty") { try LinkFrame.decode(Data()) }
        checkThrows("only a version") { try LinkFrame.decode(Data([1])) }
        checkThrows("an unknown kind") { try LinkFrame.decode(Data([1, 99])) }
        do {
            _ = try LinkFrame.decode(Data([2, 3]))
            check(false, "a newer link version is reported as such")
        } catch WireError.unsupportedVersion(let v) {
            checkEqual(v, 2, "a newer link version is reported as such")
        } catch {
            check(false, "a newer link version is reported as such: \(error)")
        }
        checkThrows("a hello cut short") { try LinkFrame.decode(LinkFrame.hello(Hello(session: Data(count: 8))).encode().prefix(6)) }
        checkThrows("a hello with lowest > highest version") { try LinkFrame.decode(Data([1, 1, 3, 2] + Array(repeating: 0, count: 12))) }
        checkThrows("fragment index ≥ count") { try LinkFrame.decode(Data([1, 2, 0, 1, 4, 4, 65])) }
        checkThrows("fragment count 0") { try LinkFrame.decode(Data([1, 2, 0, 1, 0, 0, 65])) }
        checkThrows("data without payload") { try LinkFrame.decode(Data([1, 2, 0, 1, 0, 1])) }
        checkThrows("a frame over 512 bytes") { try LinkFrame.decode(Data([1, 3]) + Data(count: 600)) }
        var hostile = Data([1, 1, 1, 1]) + Data(count: 8) + Data([0, 10, 0, 5]) + Data("a\u{1B}[2Jb".utf8)
        hostile.append(contentsOf: [0, 0])
        if case .hello(let h)? = try? LinkFrame.decode(hostile) {
            check(!h.software.contains("\u{1B}"), "no escape sequence gets through a hello")
        } else {
            check(false, "a hello with control characters in its name is still read")
        }
        // nothing at all may crash the decoder
        var gen = SeededGenerator(seed: 7)
        for n in 0..<2000 {
            var d = Data((0..<Int.random(in: 0...40, using: &gen)).map { _ in UInt8.random(in: 0...255, using: &gen) })
            if n % 2 == 0 && !d.isEmpty { d[0] = 1 }
            _ = try? LinkFrame.decode(d)
            _ = try? MeshPacket.decode(d)
            _ = try? InnerMessage.decode(d)
        }
        check(true, "2000 random frames decoded without a crash")
    }

    test("mesh packets: round trip, the signed header without ttl and hops, relaying") {
        let p = MeshPacket(ttl: 16, hops: 0, messageID: 0x1122334455667788, timestamp: 1_700_000_000_123, payload: Data(repeating: 1, count: 80))
        let bytes = p.encode()
        checkEqual(bytes.count, Proto.headerLength + 80, "a header of 21 bytes")
        checkEqual(Proto.headerLength, 21, "version, type, flags, ttl, hops, ID and time")
        checkEqual(try MeshPacket.decode(bytes), p, "decoded again")
        let r = p.relayed()!
        checkEqual(r.ttl, 15, "a relay takes one from ttl")
        checkEqual(r.hops, 1, "and adds one to hops")
        checkEqual(r.signedHeader, p.signedHeader, "what is signed does not change on the way")
        var other = p
        other.messageID ^= 1
        check(other.signedHeader != p.signedHeader, "but it covers the message ID")
        other = p
        other.timestamp += 1
        check(other.signedHeader != p.signedHeader, "and the time")
        var last = p
        last.ttl = 0
        check(last.relayed() == nil, "ttl 0 is not relayed")
    }

    test("mesh packets: hop limit, version and size are enforced") {
        var p = MeshPacket(ttl: 16, hops: 0, messageID: 1, timestamp: 0, payload: Data(count: 65))
        check((try? MeshPacket.decode(p.encode())) != nil, "ttl 16, hops 0 is allowed – every message starts so")
        p.ttl = 10
        p.hops = 7
        checkThrows("ttl + hops over 16") { try MeshPacket.decode(p.encode()) }
        p.ttl = 17
        p.hops = 0
        checkThrows("ttl over 16") { try MeshPacket.decode(p.encode()) }
        p.ttl = 1
        for (v, what) in [(UInt8(3), "a newer version is named as such"), (UInt8(1), "and MeshChat 1's packets too")] {
            var other = p.encode()
            other[0] = v
            do {
                _ = try MeshPacket.decode(other)
                check(false, what)
            } catch WireError.unsupportedVersion(let got) {
                checkEqual(got, Int(v), what)
            } catch {
                check(false, "\(what): \(error)")
            }
        }
        var noise = p.encode()
        noise[0] = 200
        do {
            _ = try MeshPacket.decode(noise)
            check(false, "a version byte of 200 is noise")
        } catch WireError.unsupportedVersion {
            check(false, "a version byte of 200 is noise, not a version")
        } catch {
            check(true, "a version byte of 200 is noise, not a version")
        }
        var type = p.encode()
        type[1] = 9
        checkThrows("an unknown packet type") { try MeshPacket.decode(type) }
        checkThrows("only a signature, no message") { try MeshPacket.decode(p.encode().prefix(Proto.headerLength + 64)) }
        checkThrows("a packet over 2048 bytes") { try MeshPacket.decode(p.encode() + Data(count: 2100)) }
    }

    test("inside: every kind round trips, with its signature at the end") {
        let key = Data(repeating: 3, count: 32), session = Data(repeating: 4, count: 8)
        let msgs = [
            InnerMessage(kind: .chat, senderKey: key, session: session, nickname: "Ada", text: "Hello, mesh! 🌸"),
            InnerMessage(kind: .presence, flags: InnerMessage.requestFlag, senderKey: key, session: session, nickname: "Grace", links: 3),
            InnerMessage(kind: .bye, senderKey: key, session: session, nickname: "Linus"),
        ]
        for m in msgs {
            let body = try m.body()
            let sig = Data(repeating: 0xEE, count: 64)
            let (back, b, s) = try InnerMessage.decode(body + sig)
            checkEqual(back, m, "\(m.kind)")
            checkEqual(b, body, "the signed part")
            checkEqual(s, sig, "the signature")
        }
        let long = InnerMessage(kind: .chat, senderKey: key, session: session, nickname: "A", text: String(repeating: "x", count: 1001))
        checkThrows("a message over 1000 bytes is not made") { try long.body() }
        var empty = InnerMessage(kind: .chat, senderKey: key, session: session, nickname: "A", text: "ok")
        empty.text = "\u{1B}\u{7}"
        checkThrows("a message of control characters only is refused") { try InnerMessage.decode(try empty.body() + Data(count: 64)) }
        let noName = InnerMessage(kind: .chat, senderKey: key, session: session, nickname: "\u{202E}", text: "hi")
        checkThrows("a nickname of nothing visible is refused") { try InnerMessage.decode(try noName.body() + Data(count: 64)) }
    }

    test("texts from other Macs cannot change the terminal") {
        checkEqual(Sanitize.text("hi\u{1B}[2J\u{1B}]0;pwned\u{7}there"), "hi[2J]0;pwnedthere", "escape sequences lose their ESC and BEL")
        checkEqual(Sanitize.text("a\nb\r\nc\td"), "a b c d", "line breaks and tabs become spaces")
        checkEqual(Sanitize.text("  many    spaces  "), "many spaces", "spaces collapsed and trimmed")
        checkEqual(Sanitize.nickname("evil\u{202E}txt.exe"), "eviltxt.exe", "no direction overrides")
        checkEqual(Sanitize.nickname("zero\u{200B}width\u{FEFF}"), "zerowidth", "no invisible characters")
        checkEqual(Sanitize.nickname("\u{9B}31m"), "31m", "no 8-bit control characters (CSI)")
        checkEqual(Sanitize.nickname(String(repeating: "ab", count: 40)).count, Proto.maxNicknameCharacters, "nicknames are cut to 24 characters")
        checkEqual(Sanitize.nickname("👩‍👩‍👧‍👦 family"), "👩‍👩‍👧‍👦 family", "emoji with joiners stay whole")
        let cut = Sanitize.cut("äöü", characters: 10, bytes: 5)
        checkEqual(cut, "äö", "cut on characters, never inside one")
    }
}
