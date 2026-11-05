// MeshChat – what someone says, made into a signed packet for everyone nearby, and packets checked again: the
// message read, the sender's signature verified. The chat is public: every Mac nearby with MeshChat reads it, and so
// can anyone with a Bluetooth scanner. The signature is what keeps it honest: no one can write in someone else's name,
// or change what they wrote, on the way. A packet that fails is never shown and never passed on.
// A private message (/tell) is the one thing that is encrypted: its text is sealed for the recipient (Sealing, below).

import Foundation

enum Signing {
    static let context = Data("MeshChat v2".utf8)

    enum OpenError: Error, Equatable {
        case malformed(WireError)   // not a message of this protocol
        case signature              // not signed by the key it names, or changed on the way
    }

    static func make(_ inner: InnerMessage, signer: Signer, ttl: UInt8, messageID: UInt64, timestamp: UInt64) throws -> MeshPacket {
        var packet = MeshPacket(ttl: ttl, hops: 0, messageID: messageID, timestamp: timestamp, payload: Data())
        let body = try inner.body()
        packet.payload = body + (try signer.sign(context + packet.signedHeader + body))
        guard packet.encode().count <= Proto.maxPacket else { throw WireError.tooLarge("message") }
        return packet
    }

    static func open(_ packet: MeshPacket) throws -> InnerMessage {
        let decoded: (InnerMessage, body: Data, signature: Data)
        do {
            decoded = try InnerMessage.decode(packet.payload)
        } catch let e as WireError {
            throw OpenError.malformed(e)
        }
        guard CryptoBackend.verify(decoded.signature, message: context + packet.signedHeader + decoded.body, publicKey: decoded.0.senderKey) else {
            throw OpenError.signature
        }
        return decoded.0
    }
}

// A private message (/tell): only the recipient can read it, every Mac on the way passes it on.
//   secret = X25519(a one-time key, the recipient's box key)        – the one-time key is used for this message only
//   key    = HKDF-SHA256(secret, salt "MeshChat v2", info "tell" + the one-time public key + the box key), 32 bytes
//   sealed = ChaCha20-Poly1305(key, a random 12-byte nonce, the text, associated data: the sender's and the recipient's
//            public keys) – so it cannot be passed off as someone else's, or as one to someone else
// The recipient makes the same secret from its box seed and the one-time public key. The packet around it is signed as
// every packet is: who wrote it, and to whom, is in the clear – what it says is not.
enum Sealing {
    struct Sealed {
        let oneTimeKey: Data            // its public key, in the message
        let nonce: Data
        let sealed: Data                // the ciphertext and its tag
    }

    private static func key(_ secret: Data, oneTime: Data, box: Data) -> Data {
        CryptoBackend.hkdf(secret, salt: Signing.context, info: Data("tell".utf8) + oneTime + box, count: 32)
    }

    // oneTime and nonce are random – the tests give fixed ones for the test vectors
    static func seal(_ text: String, from sender: Data, to recipient: Data, box: Data, oneTime: Data? = nil, nonce: Data? = nil) throws -> Sealed {
        let secret = oneTime ?? CryptoBackend.randomBytes(32)
        let pub = try CryptoBackend.boxPublicKey(secret)
        let n = nonce ?? CryptoBackend.randomBytes(Proto.nonceLength)
        let shared = try CryptoBackend.sharedSecret(secret, box)
        let sealed = try CryptoBackend.seal(Data(text.utf8), key: key(shared, oneTime: pub, box: box), nonce: n, aad: sender + recipient)
        return Sealed(oneTimeKey: pub, nonce: n, sealed: sealed)
    }

    // The text of a private message to this Mac (made safe for the terminal) – nil when it does not open: changed on the
    // way, or sealed for another key
    static func open(_ m: InnerMessage, signer: Signer) -> String? {
        guard m.kind == .tell, m.recipient == signer.publicKey,
              let shared = try? CryptoBackend.sharedSecret(signer.boxSeed, m.oneTimeKey),
              let plain = try? CryptoBackend.open(m.sealed, key: key(shared, oneTime: m.oneTimeKey, box: signer.boxKey), nonce: m.nonce,
                                                  aad: m.senderKey + m.recipient),
              let text = String(data: plain, encoding: .utf8) else { return nil }
        let clean = Sanitize.text(text)
        return clean.isEmpty ? nil : clean
    }
}
