// MeshChat – what someone says, made into a signed packet for everyone nearby, and packets checked again: the
// message read, the sender's signature verified. Nothing is encrypted – the chat is public: every Mac nearby with
// MeshChat reads it, and so can anyone with a Bluetooth scanner. The signature is what keeps it honest: no one can
// write in someone else's name, or change what they wrote, on the way. A packet that fails is never shown and
// never passed on.

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
