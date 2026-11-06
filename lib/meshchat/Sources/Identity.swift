// MeshChat – who you are in the chat: a signing key made from this Mac's identity (32 random bytes in the data
// folder). Everything you write is signed with it, and the others see four letters of it after your name
// (Ada·k3f9). It stays the same as long as the identity file does: the others can tell it is you again – and so
// can anyone else listening nearby. A second key made from it, the box key, opens private messages (/tell).

import Foundation

struct Signer {
    let seed: Data
    let publicKey: Data
    let fingerprint: String
    let boxSeed: Data           // X25519: private messages to this Mac are sealed for its public key …
    let boxKey: Data            // … which every presence of it carries

    // boxSeed nil: made from the seed (a Signer for a test, the demo or a relay)
    init(seed: Data, boxSeed: Data? = nil) throws {
        self.seed = seed
        publicKey = try CryptoBackend.signingPublicKey(seed: seed)
        fingerprint = Signer.fingerprint(of: publicKey)
        self.boxSeed = boxSeed ?? CryptoBackend.hkdf(seed, salt: Data("MeshChat v2".utf8), info: Data("box key".utf8), count: 32)
        boxKey = try CryptoBackend.boxPublicKey(self.boxSeed)
    }

    // The Ed25519 key and the box key of this Mac: HKDF-SHA256 of its identity – the file itself is never a key
    init(identity: Data) throws {
        let salt = Data("MeshChat v2".utf8)
        try self.init(seed: CryptoBackend.hkdf(identity, salt: salt, info: Data("signing key".utf8), count: 32),
                      boxSeed: CryptoBackend.hkdf(identity, salt: salt, info: Data("box key".utf8), count: 32))
    }

    func sign(_ message: Data) throws -> Data { try CryptoBackend.sign(message, seed: seed) }

    // Four characters of the key's SHA-256 – enough to tell two people with the same name apart
    static func fingerprint(of publicKey: Data) -> String {
        String(Base32.encode(CryptoBackend.sha256(publicKey)).prefix(4)).lowercased()
    }
}
