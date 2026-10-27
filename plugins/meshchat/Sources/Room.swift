// MeshChat – rooms: the secret behind a room code, the code itself, the keys derived from it, and the signing key
// each person has in a room.
//
// A room is 16 random bytes (128 bits). Its code carries them with a 2-byte check and a version:
//   MC1-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXX     (base32: 18 bytes → 29 characters, in groups of five)
// From the secret, with HKDF-SHA256 (salt "MeshChat v1"):
//   "room key"  32 bytes  ChaCha20-Poly1305 key for everything said in the room
//   "room tag"   8 bytes  in the clear on every packet: which room it is for (it reveals nothing of the secret)
//   "room id"    5 bytes  the room's short name on screen and the name of its folder, e.g. k7q2m9ab
// Whoever has the code can read the room and write in it – it is the room.

import Foundation

struct RoomSecret: Equatable {
    static let length = 16
    let bytes: Data

    init(bytes: Data) throws {
        guard bytes.count == RoomSecret.length else { throw InviteError.wrongLength }
        self.bytes = bytes
    }

    static func generate() -> RoomSecret {
        return try! RoomSecret(bytes: CryptoBackend.randomBytes(RoomSecret.length))     // the length is right
    }
}

enum InviteError: Error, Equatable, CustomStringConvertible {
    case empty
    case newerVersion(String)        // MC2-… from a newer MeshChat
    case badCharacter(Character)
    case wrongLength
    case checksum                    // a typo: the check bytes do not match

    var description: String {
        switch self {
        case .empty: return "There is no room code."
        case .newerVersion(let p): return "This room code (\(p)) is from a newer MeshChat – update it: lotus plugin update meshchat"
        case .badCharacter(let c): return "A room code has no \"\(c)\" – it uses the digits and the letters A–Z without I, L, O and U."
        case .wrongLength: return "That is not a whole room code – it has 29 letters and digits after MC1."
        case .checksum: return "That room code has a typo – check it letter by letter."
        }
    }
}

enum InviteCode {
    static let prefix = "MC1"
    static let characters = 29          // (16 + 2) bytes in base32

    static func make(_ secret: RoomSecret) -> String {
        let body = Base32.encode(secret.bytes + check(secret.bytes))
        var groups: [String] = []
        var rest = Substring(body)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(5)))
            rest = rest.dropFirst(5)
        }
        return ([prefix] + groups).joined(separator: "-")
    }

    // Accepts what people do with codes: lower case, spaces or no dashes, O for 0 and I or L for 1, the
    // prefix left out. Says exactly what is wrong.
    static func parse(_ text: String) throws -> RoomSecret {
        var s = text.uppercased().filter { !($0.isWhitespace || $0 == "-" || $0 == "_" || $0 == ".") }
        guard !s.isEmpty else { throw InviteError.empty }
        // MC and a version digit in front (MCI and MCL are MC1 typed like the rest) – unless the code is complete
        // without them, as its own first letters
        if s.count != characters, s.hasPrefix("MC"), s.count >= 3, var v = s.dropFirst(2).first {
            if v == "I" || v == "L" { v = "1" }
            if v.isNumber {
                guard v == "1" else { throw InviteError.newerVersion("MC\(v)") }
                s = String(s.dropFirst(3))
            }
        }
        if let bad = s.first(where: { Base32.value(of: $0) == nil }) { throw InviteError.badCharacter(bad) }
        guard s.count == characters, let raw = Base32.decode(s, count: RoomSecret.length + 2) else { throw InviteError.wrongLength }
        let secret = raw.prefix(RoomSecret.length)
        guard check(Data(secret)) == raw.suffix(2) else { throw InviteError.checksum }
        return try RoomSecret(bytes: Data(secret))
    }

    private static func check(_ secret: Data) -> Data {
        Data(CryptoBackend.sha256(Data("MeshChat invite v1".utf8) + secret).prefix(2))
    }
}

struct RoomKeys {
    let encryption: Data     // 32 bytes
    let tag: Data            // 8 bytes, on the wire
    let id: String           // 8 characters, on screen

    init(secret: RoomSecret) {
        let salt = Data("MeshChat v1".utf8)
        encryption = CryptoBackend.hkdf(secret.bytes, salt: salt, info: Data("room key".utf8), count: 32)
        tag = CryptoBackend.hkdf(secret.bytes, salt: salt, info: Data("room tag".utf8), count: 8)
        id = Base32.encode(CryptoBackend.hkdf(secret.bytes, salt: salt, info: Data("room id".utf8), count: 5)).lowercased()
    }
}

// The key someone signs their messages with in one room. It comes from their Mac's own secret (identity) and the
// room, so it stays the same in a room – the others see the same fingerprint every time – but differs from room to
// room: two rooms cannot tell that they have the same person in them.
struct Signer {
    let seed: Data
    let publicKey: Data
    let fingerprint: String

    init(seed: Data) throws {
        self.seed = seed
        publicKey = try CryptoBackend.signingPublicKey(seed: seed)
        fingerprint = Signer.fingerprint(of: publicKey)
    }

    init(identity: Data, room: RoomKeys) throws {
        try self.init(seed: CryptoBackend.hkdf(identity, salt: room.tag, info: Data("MeshChat v1 signing key".utf8), count: 32))
    }

    func sign(_ message: Data) throws -> Data { try CryptoBackend.sign(message, seed: seed) }

    // Four characters of the key's SHA-256 – enough to tell two people with the same name apart
    static func fingerprint(of publicKey: Data) -> String {
        String(Base32.encode(CryptoBackend.sha256(publicKey)).prefix(4)).lowercased()
    }
}
