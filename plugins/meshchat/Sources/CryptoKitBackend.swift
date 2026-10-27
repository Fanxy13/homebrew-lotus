// MeshChat – the only file that touches cryptography: Apple's CryptoKit, nothing self-made.
//   SHA-256, HKDF-SHA256 (RFC 5869), ChaCha20-Poly1305 (RFC 8439) and Ed25519 signatures (RFC 8032).
// Random bytes come from arc4random_buf, the system's cryptographic random number generator.
// Everything else in MeshChat calls these functions, so the tests check exactly what the chat uses.

import Foundation
import CryptoKit

enum CryptoBackend {
    static let name = "CryptoKit"

    struct OpenFailed: Error {}

    // CryptoKit hands out slices of its buffers (a tag whose first index is not 0); everything leaves this file as
    // plain Data that starts at 0, so d[0] is always the first byte
    private static func plain(_ d: Data) -> Data { Data([UInt8](d)) }

    static func randomBytes(_ count: Int) -> Data {
        var d = Data(count: count)
        d.withUnsafeMutableBytes { buf in
            if let base = buf.baseAddress { arc4random_buf(base, count) }
        }
        return d
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    static func hkdf(_ ikm: Data, salt: Data, info: Data, count: Int) -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: info, outputByteCount: count)
        return key.withUnsafeBytes { Data($0) }
    }

    // ChaCha20-Poly1305 with a 32-byte key and a 12-byte nonce → the ciphertext and the 16-byte tag
    static func seal(_ plaintext: Data, key: Data, nonce: Data, aad: Data) throws -> (ciphertext: Data, tag: Data) {
        let box = try ChaChaPoly.seal(plaintext, using: SymmetricKey(data: key), nonce: ChaChaPoly.Nonce(data: nonce), authenticating: aad)
        return (plain(box.ciphertext), plain(box.tag))
    }

    // Throws when the tag does not match: a wrong key, or a single changed bit anywhere
    static func open(_ ciphertext: Data, tag: Data, key: Data, nonce: Data, aad: Data) throws -> Data {
        do {
            let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
            return plain(try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: aad))
        } catch {
            throw OpenFailed()
        }
    }

    // Ed25519: a 32-byte private key (seed) → its 32-byte public key
    static func signingPublicKey(seed: Data) throws -> Data {
        plain(try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation)
    }

    static func sign(_ message: Data, seed: Data) throws -> Data {
        plain(try Curve25519.Signing.PrivateKey(rawRepresentation: seed).signature(for: message))
    }

    static func verify(_ signature: Data, message: Data, publicKey: Data) -> Bool {
        guard signature.count == 64, let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: message)
    }
}
