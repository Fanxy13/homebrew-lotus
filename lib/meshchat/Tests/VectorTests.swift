// MeshChat tests – the same bytes as the Windows app (win/meshchat). Tests/vectors.txt holds what fixed inputs must
// give; the Windows app made it and checks it byte for byte. Here CryptoKit checks it: the identity gives the same key,
// the HELLO and the messages are the same bytes, the Windows app's signatures verify, and the frames are cut alike.
// CryptoKit's own signatures differ every time, so this Mac's packets cannot be in the file: with MESHCHAT_VECTORS_OUT
// set (the CI), they are written there, and the Windows app's tests check them (meshchat-tests --verify-foreign).

import Foundation

private let vIdentity = Data((0..<32).map { UInt8($0) })
private let vSession = Data([0xA1, 0xB2, 0xC3, 0xD4, 0x05, 0x06, 0x07, 0x08])
private let vSoftware = "meshchat/2.0.0"
private let vSeq: UInt16 = 7
// a private message: to the recipient, sealed with these instead of random ones
private let vRecipientIdentity = Data((0x20..<0x40).map { UInt8($0) })
private let vOneTime = Data((0x40..<0x60).map { UInt8($0) })
private let vTellNonce = Data((0x60..<0x6C).map { UInt8($0) })
private let vTellText = "Only you can read this – Grüezi 🌸"

private struct VectorCase {
    let name: String
    let inner: InnerMessage
    let id: UInt64
    let time: UInt64
    let ttl: UInt8
}

// The same inputs as win/meshchat/MeshChat.Core/SelfTest/VectorTests.cs
private func vectorCases(_ s: Signer) throws -> [VectorCase] {
    let r = try Signer(identity: vRecipientIdentity)
    let sealed = try Sealing.seal(vTellText, from: s.publicKey, to: r.publicKey, box: r.boxKey, oneTime: vOneTime, nonce: vTellNonce)
    return [
        VectorCase(name: "chat", inner: InnerMessage(kind: .chat, senderKey: s.publicKey, session: vSession, nickname: "Ada",
                                                     text: "Grüezi – the same chat on Windows and on a Mac 🌸"),
                   id: 0x0123456789ABCDEF, time: 1_761_570_000_000, ttl: 16),
        VectorCase(name: "presence", inner: InnerMessage(kind: .presence, flags: InnerMessage.requestFlag, senderKey: s.publicKey, session: vSession,
                                                         nickname: "Ada", links: 2,
                                                         neighbours: [Neighbour(token: 0x00000007, rssi: Distance.unknown), Neighbour(token: 0xA1B2C3D4, rssi: -67)]),
                   id: 0x1111111111111111, time: 1_761_570_001_000, ttl: 16),
        VectorCase(name: "bye", inner: InnerMessage(kind: .bye, senderKey: s.publicKey, session: vSession, nickname: "Ada"),
                   id: 0xFEDCBA9876543210, time: 1_761_570_002_000, ttl: 16),
        // since MeshChat 2.2: a presence with its box key, and a private message
        VectorCase(name: "presence-box", inner: InnerMessage(kind: .presence, senderKey: s.publicKey, session: vSession, nickname: "Ada", links: 1,
                                                             neighbours: [Neighbour(token: 0xA1B2C3D4, rssi: -67)], boxKey: s.boxKey),
                   id: 0x2222222222222222, time: 1_761_570_003_000, ttl: 16),
        VectorCase(name: "tell", inner: InnerMessage(kind: .tell, senderKey: s.publicKey, session: vSession, nickname: "Ada", recipient: r.publicKey,
                                                     oneTimeKey: sealed.oneTimeKey, nonce: sealed.nonce, sealed: sealed.sealed),
                   id: 0x3333333333333333, time: 1_761_570_004_000, ttl: 16),
    ]
}

private func loadVectors() -> [String: String]? {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("vectors.txt")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    var d: [String: String] = [:]
    for line in text.split(separator: "\n") {
        guard !line.hasPrefix("#"), let r = line.range(of: " = ") else { continue }
        d[String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)] = String(line[r.upperBound...])
    }
    return d
}

func vectorTests() {
    test("the same bytes as Windows: the test vectors both check (Tests/vectors.txt)") {
        guard let v = loadVectors() else { return check(false, "Tests/vectors.txt is there") }
        let s = try Signer(identity: vIdentity)
        checkEqual(Hex.encode(s.seed), v["seed"] ?? "", "the identity gives the same key (HKDF)")
        checkEqual(Hex.encode(s.publicKey), v["public-key"] ?? "", "and the same public key (Ed25519)")
        checkEqual(s.fingerprint, v["fingerprint"] ?? "", "and the same fingerprint")
        checkEqual(Hex.encode(LinkFrame.hello(Hello(session: vSession, software: vSoftware)).encode()), v["hello"] ?? "", "a HELLO")
        checkEqual(Hex.encode(LinkFrame.ping.encode()), v["ping"] ?? "", "a PING")
        checkEqual(Hex.encode(LinkFrame.bye(ByeReason.leaving.rawValue).encode()), v["bye-frame"] ?? "", "a BYE")
        checkEqual(Hex.encode(s.boxKey), v["box-key"] ?? "", "the identity gives the same box key (HKDF, X25519)")
        let recipient = try Signer(identity: vRecipientIdentity)
        checkEqual(Hex.encode(recipient.boxKey), v["recipient.box-key"] ?? "", "and so does the recipient's")
        var out = ""
        for c in try vectorCases(s) {
            if c.inner.kind == .chat { checkEqual(c.inner.text, v["\(c.name).text"] ?? "", "the text of the chat message") }
            checkEqual(Hex.encode(try c.inner.body()), v["\(c.name).body"] ?? "", "\(c.name): the message")
            let mine = try Signing.make(c.inner, signer: s, ttl: c.ttl, messageID: c.id, timestamp: c.time)
            checkEqual(Hex.encode(mine.signedHeader), v["\(c.name).header"] ?? "", "\(c.name): the signed header")
            checkEqual(try Signing.open(mine), c.inner, "\(c.name): this Mac's own packet opens")
            out += "swift.\(c.name).packet = \(Hex.encode(mine.encode()))\n"
            guard let hex = v["\(c.name).packet"], let bytes = Hex.decode(hex) else {
                check(false, "\(c.name): the Windows app's packet is in the file")
                continue
            }
            let theirs = try MeshPacket.decode(bytes)
            checkEqual(try Signing.open(theirs), c.inner, "\(c.name): the Windows app's signature verifies with CryptoKit, and the message is the same")
            if c.inner.kind == .tell {
                checkEqual(Sealing.open(try Signing.open(theirs), signer: recipient), v["tell.text"], "tell: sealed on Windows, the recipient reads it with CryptoKit")
                checkEqual(Sealing.open(try Signing.open(theirs), signer: s), nil, "and no one else – not even its sender")
            }
            checkEqual(theirs.signedHeader, mine.signedHeader, "\(c.name): so is the header")
            checkEqual(Data(theirs.payload.dropLast(Proto.signatureLength)), Data(mine.payload.dropLast(Proto.signatureLength)),
                       "\(c.name): all but the signature is what this Mac makes")
            for size in [20, 182] {
                let frames = try Fragmenter.frames(for: bytes, seq: vSeq, maxFrame: size).map { Hex.encode($0) }.joined(separator: " ")
                checkEqual(frames, v["\(c.name).frames.\(size)"] ?? "", "\(c.name): its frames on a link of \(size) bytes")
            }
        }
        if let path = ProcessInfo.processInfo.environment["MESHCHAT_VECTORS_OUT"], !path.isEmpty {
            let text = "# MeshChat – packets a Mac signed with CryptoKit, for the Windows app to check\npublic-key = \(Hex.encode(s.publicKey))\n" + out
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            print("    (this Mac's packets: \(path))")
        }
    }
}
