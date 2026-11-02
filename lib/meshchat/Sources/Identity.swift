// MeshChat – who you are in the chat: a signing key made from this Mac's identity (32 random bytes in the data
// folder). Everything you write is signed with it, and the others see four letters of it after your name
// (Ada·k3f9). It stays the same as long as the identity file does: the others can tell it is you again – and so
// can anyone else listening nearby.

import Foundation

struct Signer {
    let seed: Data
    let publicKey: Data
    let fingerprint: String

    init(seed: Data) throws {
        self.seed = seed
        publicKey = try CryptoBackend.signingPublicKey(seed: seed)
        fingerprint = Signer.fingerprint(of: publicKey)
    }

    // The Ed25519 key of this Mac: HKDF-SHA256 of its identity – the file itself is never the key
    init(identity: Data) throws {
        try self.init(seed: CryptoBackend.hkdf(identity, salt: Data("MeshChat v2".utf8), info: Data("signing key".utf8), count: 32))
    }

    func sign(_ message: Data) throws -> Data { try CryptoBackend.sign(message, seed: seed) }

    // Four characters of the key's SHA-256 – enough to tell two people with the same name apart
    static func fingerprint(of publicKey: Data) -> String {
        String(Base32.encode(CryptoBackend.sha256(publicKey)).prefix(4)).lowercased()
    }
}
