// MeshChat tests – the cryptography: published test vectors (so this Mac's CryptoKit is checked against the
// standards), this Mac's signing key, and packets that are refused when anything in them was changed.

import Foundation

func cryptoTests() {
    test("SHA-256 and HKDF-SHA256 (RFC 5869) give the published results") {
        checkEqual(Hex.encode(CryptoBackend.sha256(Data("abc".utf8))),
                   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 of abc")
        let okm = CryptoBackend.hkdf(hex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), salt: hex("000102030405060708090a0b0c"),
                                     info: hex("f0f1f2f3f4f5f6f7f8f9"), count: 42)
        checkEqual(Hex.encode(okm), "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865", "RFC 5869 test case 1")
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

    test("this Mac's key: the same identity gives the same key, another identity another") {
        let identity = Data(repeating: 0x42, count: 32)
        let a = try Signer(identity: identity), b = try Signer(identity: identity)
        checkEqual(a.publicKey, b.publicKey, "the same identity, the same key")
        checkEqual(a.fingerprint, b.fingerprint, "and the same fingerprint – the others recognize you")
        let c = try Signer(identity: CryptoBackend.randomBytes(32))
        check(c.publicKey != a.publicKey && c.fingerprint != a.fingerprint, "another identity, another key")
        check(a.seed != identity, "the identity file itself is not the key")
        // the derivation is pinned: a later version must give the same key for the same identity
        checkEqual(a.seed, CryptoBackend.hkdf(identity, salt: Data("MeshChat v2".utf8), info: Data("signing key".utf8), count: 32),
                   "the key is HKDF(identity, \"MeshChat v2\", \"signing key\")")
        checkEqual(a.fingerprint.count, 4, "fingerprints have four characters")
        check(a.fingerprint.allSatisfy { Base32.alphabet.contains(Character($0.uppercased())) }, "of base32")
    }

    test("packets: signed, readable by everyone, refused when anything was changed") {
        let alice = try Signer(identity: CryptoBackend.randomBytes(32))
        let inner = InnerMessage(kind: .chat, senderKey: alice.publicKey, session: Data(repeating: 1, count: 8), nickname: "Alice", text: "Meet at the bridge")
        let p = try Signing.make(inner, signer: alice, ttl: 16, messageID: 42, timestamp: 1_700_000_000_000)
        checkEqual(try Signing.open(p), inner, "opened – by anyone: the chat is public")
        let wire = p.encode()       // (Data.range(of:): Collection.contains(_:) needs macOS 13)
        check(wire.range(of: Data("Meet at the bridge".utf8)) != nil && wire.range(of: Data("Alice".utf8)) != nil,
              "the text and the name are on the wire as they are – nothing is encrypted, as the README says")
        var relayed = p
        relayed.ttl = 2
        relayed.hops = 3
        checkEqual(try Signing.open(relayed), inner, "relays may change ttl and hops")

        // where the name and the text are in the message: kind, flags, key, session, then str8 name and str16 text
        let nameAt = 1 + 1 + 32 + 8 + 1, textAt = nameAt + 5 + 2
        checkEqual(p.payload[textAt], UInt8(ascii: "M"), "the text starts where it should")
        let bob = try Signer(identity: CryptoBackend.randomBytes(32))
        func refused(_ what: String, _ change: (inout MeshPacket) -> Void) {
            var q = p
            change(&q)
            do {
                _ = try Signing.open(q)
                check(false, what)
            } catch Signing.OpenError.signature {
                check(true, what)
            } catch {
                check(false, "\(what): \(error)")
            }
        }
        refused("a changed letter in the text") { $0.payload[textAt] ^= 0x01 }
        refused("a changed name") { $0.payload[nameAt] ^= 0x01 }
        refused("someone else's key put in") { $0.payload.replaceSubrange(2..<34, with: bob.publicKey) }
        refused("a changed message ID (a copy passed off as new)") { $0.messageID += 1 }
        refused("a changed time (an old message made new)") { $0.timestamp += 60_000 }
        refused("a changed flag") { $0.flags = 1 }
        refused("a changed signature") { $0.payload[$0.payload.count - 1] ^= 1 }
        var cut = p
        cut.payload = Data(p.payload.prefix(30)) + Data(p.payload.suffix(64))
        do {
            _ = try Signing.open(cut)
            check(false, "a message cut short is refused as broken")
        } catch Signing.OpenError.malformed {
            check(true, "a message cut short is refused as broken")
        }
    }

    test("signatures: no one can write in someone else's name") {
        let alice = try Signer(identity: CryptoBackend.randomBytes(32))
        let mallory = try Signer(identity: CryptoBackend.randomBytes(32))
        // Mallory puts Alice's public key and name in, but can only sign with her own key
        let forged = InnerMessage(kind: .chat, senderKey: alice.publicKey, session: Data(count: 8), nickname: "Alice", text: "Send me your password")
        let p = try Signing.make(forged, signer: mallory, ttl: 16, messageID: 7, timestamp: 1)
        do {
            _ = try Signing.open(p)
            check(false, "a message signed with another key than the one it names is refused")
        } catch Signing.OpenError.signature {
            check(true, "a message signed with another key than the one it names is refused")
        }
        check(alice.fingerprint != mallory.fingerprint, "two people, two fingerprints")
    }
}
