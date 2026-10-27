// MeshChat – what someone says, sealed into a packet for the room, and packets opened again: decrypted with the
// room key, the fields checked, the sender's signature verified. A packet that fails any of it is never shown and
// never passed on.

import Foundation

struct RoomCrypto {
    static let signatureContext = Data("MeshChat v1 sig".utf8)

    enum OpenError: Error, Equatable {
        case otherRoom              // the packet is for another room (or one we do not have)
        case authentication         // wrong key, or changed on the way
        case malformed(WireError)   // decrypted, but not a message of this protocol
        case signature              // not signed by the key it names
    }

    let keys: RoomKeys
    let signer: Signer

    func seal(_ inner: InnerMessage, ttl: UInt8, messageID: UInt64, timestamp: UInt64) throws -> MeshPacket {
        var packet = MeshPacket(ttl: ttl, hops: 0, messageID: messageID, roomTag: keys.tag, timestamp: timestamp,
                                nonce: CryptoBackend.randomBytes(Proto.nonceLength), sealed: Data())
        let body = try inner.body()
        let aad = packet.aad
        let signature = try signer.sign(RoomCrypto.signatureContext + aad + body)
        let sealed = try CryptoBackend.seal(body + signature, key: keys.encryption, nonce: packet.nonce, aad: aad)
        packet.sealed = sealed.ciphertext + sealed.tag
        guard packet.encode().count <= Proto.maxPacket else { throw WireError.tooLarge("message") }
        return packet
    }

    func open(_ packet: MeshPacket) throws -> InnerMessage {
        guard packet.roomTag == keys.tag else { throw OpenError.otherRoom }
        let ciphertext = Data(packet.sealed.prefix(packet.sealed.count - Proto.tagLength))
        let tag = Data(packet.sealed.suffix(Proto.tagLength))
        let aad = packet.aad
        let plaintext: Data
        do {
            plaintext = try CryptoBackend.open(ciphertext, tag: tag, key: keys.encryption, nonce: packet.nonce, aad: aad)
        } catch {
            throw OpenError.authentication
        }
        let decoded: (InnerMessage, body: Data, signature: Data)
        do {
            decoded = try InnerMessage.decode(plaintext)
        } catch let e as WireError {
            throw OpenError.malformed(e)
        }
        guard CryptoBackend.verify(decoded.signature, message: RoomCrypto.signatureContext + aad + decoded.body, publicKey: decoded.0.senderKey) else {
            throw OpenError.signature
        }
        return decoded.0
    }
}
