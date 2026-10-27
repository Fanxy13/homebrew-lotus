// MeshChat tests – the cryptography: published test vectors (so this Mac's CryptoKit is checked against the
// standards), the room keys, and packets that are opened only with the right key, unchanged and properly signed.

import Foundation

func cryptoTests() {
    test("SHA-256, HKDF-SHA256 (RFC 5869) and ChaCha20-Poly1305 (RFC 8439) give the published results") {
        checkEqual(Hex.encode(CryptoBackend.sha256(Data("abc".utf8))),
                   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 of abc")
        let okm = CryptoBackend.hkdf(hex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), salt: hex("000102030405060708090a0b0c"),
                                     info: hex("f0f1f2f3f4f5f6f7f8f9"), count: 42)
        checkEqual(Hex.encode(okm), "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865", "RFC 5869 test case 1")
        let key = Data((0x80...0x9F).map { UInt8($0) })
        let nonce = hex("070000004041424344454647")
        let aad = hex("50515253c0c1c2c3c4c5c6c7")
        let text = Data("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".utf8)
        let sealed = try CryptoBackend.seal(text, key: key, nonce: nonce, aad: aad)
        checkEqual(Hex.encode(sealed.ciphertext), Hex.encode(hex("""
            d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b
            1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc
            3ff4def08e4b7a9de576d26586cec64b6116
            """)), "RFC 8439 2.8.2 ciphertext")
        checkEqual(Hex.encode(sealed.tag), "1ae10b594f09e26a7e902ecbd0600691", "RFC 8439 2.8.2 tag")
        checkEqual(try CryptoBackend.open(sealed.ciphertext, tag: sealed.tag, key: key, nonce: nonce, aad: aad), text, "opened again")
        var badTag = sealed.tag
        badTag[0] ^= 1
        checkThrows("a changed tag") { try CryptoBackend.open(sealed.ciphertext, tag: badTag, key: key, nonce: nonce, aad: aad) }
        var badText = sealed.ciphertext
        badText[10] ^= 0x80
        checkThrows("a changed ciphertext") { try CryptoBackend.open(badText, tag: sealed.tag, key: key, nonce: nonce, aad: aad) }
        checkThrows("changed associated data") { try CryptoBackend.open(sealed.ciphertext, tag: sealed.tag, key: key, nonce: nonce, aad: aad + Data([0])) }
    }

    test("Ed25519 (RFC 8032): the published keys and signatures, and signatures of this Mac") {
        let seed = hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
        let pub = try CryptoBackend.signingPublicKey(seed: seed)
        checkEqual(Hex.encode(pub), "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "test 1 public key")
        let sig1 = hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        check(CryptoBackend.verify(sig1, message: Data(), publicKey: pub), "test 1 signature verifies")
        let pub2 = hex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
        let sig2 = hex("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")
        check(CryptoBackend.verify(sig2, message: Data([0x72]), publicKey: pub2), "test 2 signature verifies")
        check(!CryptoBackend.verify(sig2, message: Data([0x73]), publicKey: pub2), "not for another message")
        check(!CryptoBackend.verify(sig1, message: Data(), publicKey: pub2), "not with another key")
        // CryptoKit's signatures may be randomized, so they are checked by verifying them, not by their bytes
        let mine = try CryptoBackend.sign(Data("MeshChat".utf8), seed: seed)
        check(CryptoBackend.verify(mine, message: Data("MeshChat".utf8), publicKey: pub), "a signature of this Mac verifies")
        check(!CryptoBackend.verify(mine.prefix(63), message: Data("MeshChat".utf8), publicKey: pub), "a signature cut short does not")
        check(!CryptoBackend.verify(mine, message: Data("MeshChat".utf8), publicKey: Data(count: 31)), "nor with a key of the wrong size")
    }

    test("room keys: the same code gives the same keys, each part its own") {
        let secret = try RoomSecret(bytes: Data(repeating: 0x42, count: 16))
        let a = RoomKeys(secret: secret), b = RoomKeys(secret: secret)
        checkEqual(a.encryption, b.encryption, "same key")
        checkEqual(a.tag, b.tag, "same tag")
        checkEqual(a.id, b.id, "same ID")
        checkEqual(a.encryption.count, 32, "a 256-bit key")
        checkEqual(a.tag.count, 8, "an 8-byte tag")
        checkEqual(a.id.count, 8, "an 8-character ID")
        check(a.tag != a.encryption.prefix(8), "the tag is not part of the key")
        let other = RoomKeys(secret: RoomSecret.generate())
        check(other.encryption != a.encryption && other.tag != a.tag, "another room, other keys")
        // the derivation is pinned: a later version must give the same keys for the same code
        checkEqual(Hex.encode(CryptoBackend.hkdf(Data(repeating: 0x42, count: 16), salt: Data("MeshChat v1".utf8), info: Data("room tag".utf8), count: 8)),
                   Hex.encode(a.tag), "the tag is HKDF(code, \"MeshChat v1\", \"room tag\")")
    }

    test("packets: sealed and opened with the room key, refused when anything is wrong") {
        let secret = RoomSecret.generate()
        let keys = RoomKeys(secret: secret)
        let alice = try Signer(identity: CryptoBackend.randomBytes(32), room: keys)
        let room = RoomCrypto(keys: keys, signer: alice)
        let inner = InnerMessage(kind: .chat, senderKey: alice.publicKey, session: Data(repeating: 1, count: 8), nickname: "Alice", text: "Meet at the bridge")
        let p = try room.seal(inner, ttl: 5, messageID: 42, timestamp: 1_700_000_000_000)
        checkEqual(try room.open(p), inner, "opened by the room")
        check(!p.encode().contains(Data("Meet at the bridge".utf8)) && !p.encode().contains(Data("Alice".utf8)), "neither the text nor the name are readable on the wire")
        let bob = try Signer(identity: CryptoBackend.randomBytes(32), room: keys)
        checkEqual(try RoomCrypto(keys: keys, signer: bob).open(p), inner, "opened by another member of the room")
        var relayed = p
        relayed.ttl = 2
        relayed.hops = 3
        checkEqual(try room.open(relayed), inner, "relays may change ttl and hops")

        let outsider = RoomCrypto(keys: RoomKeys(secret: RoomSecret.generate()), signer: bob)
        do { _ = try outsider.open(p); check(false, "another room cannot open it") } catch RoomCrypto.OpenError.otherRoom { check(true, "another room cannot open it") }
        var wrongTag = p
        wrongTag.roomTag = outsider.keys.tag
        do { _ = try outsider.open(wrongTag); check(false, "a key that is not the room's fails") } catch RoomCrypto.OpenError.authentication { check(true, "a key that is not the room's fails") }

        func refused(_ what: String, _ change: (inout MeshPacket) -> Void) {
            var q = p
            change(&q)
            do {
                _ = try room.open(q)
                check(false, what)
            } catch RoomCrypto.OpenError.authentication {
                check(true, what)
            } catch {
                check(false, "\(what): \(error)")
            }
        }
        refused("a changed bit in the ciphertext") { $0.sealed[3] ^= 1 }
        refused("a changed tag") { $0.sealed[$0.sealed.count - 1] ^= 1 }
        refused("a changed message ID (a copy passed off as new)") { $0.messageID += 1 }
        refused("a changed time (an old message made new)") { $0.timestamp += 60_000 }
        refused("a changed nonce") { $0.nonce[0] ^= 1 }
        refused("a changed flag") { $0.flags = 1 }
    }

    test("signatures: a member cannot write in someone else's name") {
        let keys = RoomKeys(secret: RoomSecret.generate())
        let alice = try Signer(identity: CryptoBackend.randomBytes(32), room: keys)
        let mallory = try Signer(identity: CryptoBackend.randomBytes(32), room: keys)
        // Mallory has the room key, puts Alice's public key in, but can only sign with her own
        let forged = InnerMessage(kind: .chat, senderKey: alice.publicKey, session: Data(count: 8), nickname: "Alice", text: "Send me your password")
        let p = try RoomCrypto(keys: keys, signer: mallory).seal(forged, ttl: 5, messageID: 7, timestamp: 1)
        do {
            _ = try RoomCrypto(keys: keys, signer: alice).open(p)
            check(false, "a message signed with another key than the one it names is refused")
        } catch RoomCrypto.OpenError.signature {
            check(true, "a message signed with another key than the one it names is refused")
        }
        checkEqual(alice.fingerprint.count, 4, "fingerprints have four characters")
        check(alice.fingerprint != mallory.fingerprint, "two people, two fingerprints")
        let identity = CryptoBackend.randomBytes(32)
        let inRoom1 = try Signer(identity: identity, room: keys)
        let inRoom1Again = try Signer(identity: identity, room: keys)
        let inRoom2 = try Signer(identity: identity, room: RoomKeys(secret: RoomSecret.generate()))
        checkEqual(inRoom1.publicKey, inRoom1Again.publicKey, "the same Mac has the same key in a room")
        check(inRoom1.publicKey != inRoom2.publicKey, "and another one in another room – rooms cannot link people")
    }
}
