// MeshChat – bytes on the wire: a writer, a strict reader that never reads past the end, hex and base32.

import Foundation

// What can be wrong with bytes that came from another Mac. Never crashes, never reads past the end.
enum WireError: Error, Equatable, CustomStringConvertible {
    case truncated                      // fewer bytes than the field needs
    case tooLarge(String)               // a field or a packet over its limit
    case invalid(String)                // a value that is not allowed
    case unsupportedVersion(Int)        // a newer (or unknown) protocol

    var description: String {
        switch self {
        case .truncated: return "cut short"
        case .tooLarge(let what): return "too large: \(what)"
        case .invalid(let what): return "invalid: \(what)"
        case .unsupportedVersion(let v): return "protocol version \(v) is not supported"
        }
    }
}

// Big-endian fields, one after the other
struct ByteWriter {
    private(set) var data = Data()

    mutating func u8(_ v: UInt8) { data.append(v) }

    mutating func u16(_ v: UInt16) {
        data.append(UInt8(v >> 8))
        data.append(UInt8(v & 0xFF))
    }

    mutating func u64(_ v: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8((v >> UInt64(shift)) & 0xFF)) }
    }

    mutating func bytes(_ d: Data) { data.append(d) }

    // A string with its length in one byte (at most 255 bytes of UTF-8)
    mutating func str8(_ s: String) throws {
        let b = Data(s.utf8)
        guard b.count <= 255 else { throw WireError.tooLarge("text field") }
        u8(UInt8(b.count))
        bytes(b)
    }

    // A string with its length in two bytes
    mutating func str16(_ s: String) throws {
        let b = Data(s.utf8)
        guard b.count <= 65535 else { throw WireError.tooLarge("text field") }
        u16(UInt16(b.count))
        bytes(b)
    }
}

// Reads what ByteWriter wrote. Every read checks the length first; text must be valid UTF-8.
struct ByteReader {
    private let buf: [UInt8]
    private(set) var offset = 0

    init(_ data: Data) { buf = [UInt8](data) }

    var remaining: Int { buf.count - offset }
    var isAtEnd: Bool { offset == buf.count }

    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw WireError.truncated }
        defer { offset += 1 }
        return buf[offset]
    }

    mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw WireError.truncated }
        defer { offset += 2 }
        return UInt16(buf[offset]) << 8 | UInt16(buf[offset + 1])
    }

    mutating func u64() throws -> UInt64 {
        guard remaining >= 8 else { throw WireError.truncated }
        var v: UInt64 = 0
        for i in 0..<8 { v = v << 8 | UInt64(buf[offset + i]) }
        offset += 8
        return v
    }

    mutating func bytes(_ n: Int) throws -> Data {
        guard n >= 0, remaining >= n else { throw WireError.truncated }
        defer { offset += n }
        return Data(buf[offset..<offset + n])
    }

    mutating func rest() -> Data {
        defer { offset = buf.count }
        return Data(buf[offset...])
    }

    mutating func str8(max: Int) throws -> String {
        let n = Int(try u8())
        guard n <= max else { throw WireError.tooLarge("text field") }
        return try utf8(try bytes(n))
    }

    mutating func str16(max: Int) throws -> String {
        let n = Int(try u16())
        guard n <= max else { throw WireError.tooLarge("text field") }
        return try utf8(try bytes(n))
    }

    private func utf8(_ d: Data) throws -> String {
        guard let s = String(bytes: d, encoding: .utf8) else { throw WireError.invalid("text is not UTF-8") }
        return s
    }
}

enum Hex {
    private static let digits = Array("0123456789abcdef")

    static func encode(_ d: Data) -> String {
        var s = ""
        s.reserveCapacity(d.count * 2)
        for b in d {
            s.append(digits[Int(b >> 4)])
            s.append(digits[Int(b & 0x0F)])
        }
        return s
    }

    static func decode(_ s: String) -> Data? {
        let chars = Array(s.lowercased())
        guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = chars[i].hexDigitValue, let lo = chars[i + 1].hexDigitValue else { return nil }
            out.append(UInt8(hi << 4 | lo))
            i += 2
        }
        return out
    }

    static func u64(_ v: UInt64) -> String {
        let s = String(v, radix: 16)
        return String(repeating: "0", count: max(0, 16 - s.count)) + s
    }
}

// Crockford's base32: no I, L, O or U, so the four letters of a fingerprint are not mistaken for others
enum Base32 {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func encode(_ d: Data) -> String {
        var out = ""
        var acc: UInt32 = 0
        var bits = 0
        for b in d {
            acc = acc << 8 | UInt32(b)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(alphabet[Int((acc >> UInt32(bits)) & 0x1F)])
            }
            acc &= (1 << UInt32(bits)) - 1
        }
        if bits > 0 { out.append(alphabet[Int((acc << UInt32(5 - bits)) & 0x1F)]) }
        return out
    }
}
