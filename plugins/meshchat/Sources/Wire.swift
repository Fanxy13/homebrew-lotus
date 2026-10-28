// MeshChat – the protocol on the wire, version 2. Numbers are big-endian; str8/str16 is UTF-8 after its length.
//
// Link frames – one GATT write or notification each, between two Macs that are connected:
//   [1 link version = 1][1 kind] then
//   HELLO 1  [1 lowest][1 highest mesh version][8 session][2 largest packet][1 flags][str8 software]
//   DATA  2  [2 sequence][1 index][1 count][a part of one mesh packet]
//   PING 3 · PONG 4   nothing more
//   BYE   5  [1 reason]
// A newer version may add fields at the end of a HELLO; they are skipped.
//
// Mesh packets – put together from DATA frames, checked, and passed on whole by every Mac on the way:
//   [1 version = 2][1 type = 1, a message to everyone][1 flags][1 ttl][1 hops][8 message ID][8 time, ms]
//   then the message and its signature
//   ttl: relays it may still take · hops: relays it took. Only these two change on the way, so the signature
//   covers the header with both set to 0.
//
// The message – in the clear: the chat is public, everyone nearby reads it:
//   [1 kind][1 flags][32 sender's public key][8 sender's session][str8 nickname] then
//   chat 1      [str16 text]
//   presence 2  [1 links][1 n][n × (4 token, 1 signal)]   flags bit 0: "who is here?" – answer with yours
//               the Macs it has a link to – the first 4 bytes of their session – and how strong it hears them
//               (dBm, signed; 127: not measured). A first MeshChat 2 sent only [1 links]; both are read.
//   bye 3       nothing more
//   [64 Ed25519 signature over "MeshChat v2", the header (ttl and hops 0) and everything before it]
//
// Version 1 had rooms with codes and encrypted everything for its room; version 2 has one chat for everyone
// nearby. The two do not mix: their HELLOs have no version in common, and each says the other needs an update.

import Foundation

enum Proto {
    static let version: UInt8 = 2               // mesh packets
    static let linkVersion: UInt8 = 1           // link frames
    static let software = "meshchat/2.0.0"
    static let maxFrame = 512                   // the most a GATT attribute value holds
    static let minFrame = 20                    // the least BLE gives (ATT MTU 23 minus 3)
    static let maxPacket = 2048
    static let maxFragments = 255
    static let hopLimit: UInt8 = 16             // ttl + hops is never more – every message is sent with all of it
    static let sessionLength = 8
    static let keyLength = 32
    static let signatureLength = 64
    static let headerLength = 21
    static let maxNicknameCharacters = 24
    static let maxNicknameBytes = 64
    static let maxTextBytes = 1000
    static let maxSoftwareBytes = 32
    static let maxNeighbours = 16

    // A version byte that is not ours: a plausible other version (1–15) is named as such, anything else is noise
    static func versionError(_ v: UInt8, ours: UInt8) -> WireError {
        (1...15).contains(v) && v != ours ? .unsupportedVersion(Int(v)) : .invalid("version byte \(v)")
    }
}

// ── Link frames ───────────────────────────────────────────────

enum LinkKind: UInt8 {
    case hello = 1, data = 2, ping = 3, pong = 4, bye = 5
}

enum ByeReason: UInt8 {
    case leaving = 1        // the chat was closed
    case incompatible = 2   // no protocol version in common
    case redundant = 3      // a second link to the same Mac
    case full = 4           // too many links already
}

struct Hello: Equatable {
    var minVersion: UInt8 = Proto.version
    var maxVersion: UInt8 = Proto.version
    var session: Data
    var maxPacket: UInt16 = UInt16(Proto.maxPacket)
    var flags: UInt8 = 0
    var software: String = Proto.software
}

enum LinkFrame: Equatable {
    case hello(Hello)
    case data(seq: UInt16, index: UInt8, count: UInt8, payload: Data)
    case ping
    case pong
    case bye(UInt8)

    static let dataHeader = 6

    func encode() -> Data {
        var w = ByteWriter()
        w.u8(Proto.linkVersion)
        switch self {
        case .hello(let h):
            w.u8(LinkKind.hello.rawValue)
            w.u8(h.minVersion)
            w.u8(h.maxVersion)
            w.bytes(h.session)
            w.u16(h.maxPacket)
            w.u8(h.flags)
            try? w.str8(Sanitize.cut(h.software, characters: Proto.maxSoftwareBytes, bytes: Proto.maxSoftwareBytes))
        case let .data(seq, index, count, payload):
            w.u8(LinkKind.data.rawValue)
            w.u16(seq)
            w.u8(index)
            w.u8(count)
            w.bytes(payload)
        case .ping:
            w.u8(LinkKind.ping.rawValue)
        case .pong:
            w.u8(LinkKind.pong.rawValue)
        case .bye(let reason):
            w.u8(LinkKind.bye.rawValue)
            w.u8(reason)
        }
        return w.data
    }

    static func decode(_ d: Data) throws -> LinkFrame {
        guard d.count <= Proto.maxFrame else { throw WireError.tooLarge("frame of \(d.count) bytes") }
        var r = ByteReader(d)
        let version = try r.u8()
        guard version == Proto.linkVersion else { throw Proto.versionError(version, ours: Proto.linkVersion) }
        guard let kind = LinkKind(rawValue: try r.u8()) else { throw WireError.invalid("frame kind") }
        switch kind {
        case .hello:
            let lo = try r.u8(), hi = try r.u8()
            guard lo >= 1, lo <= hi else { throw WireError.invalid("version range") }
            let session = try r.bytes(Proto.sessionLength)
            let maxPacket = try r.u16()
            let flags = try r.u8()
            let software = Sanitize.line(try r.str8(max: Proto.maxSoftwareBytes), characters: Proto.maxSoftwareBytes, bytes: Proto.maxSoftwareBytes)
            return .hello(Hello(minVersion: lo, maxVersion: hi, session: session, maxPacket: maxPacket, flags: flags, software: software))
        case .data:
            let seq = try r.u16(), index = try r.u8(), count = try r.u8()
            guard count >= 1, index < count else { throw WireError.invalid("fragment \(index) of \(count)") }
            let payload = r.rest()
            guard !payload.isEmpty else { throw WireError.truncated }
            return .data(seq: seq, index: index, count: count, payload: payload)
        case .ping:
            return .ping
        case .pong:
            return .pong
        case .bye:
            return .bye(r.isAtEnd ? 0 : try r.u8())
        }
    }
}

// ── Mesh packets ──────────────────────────────────────────────

struct MeshPacket: Equatable {
    static let typePublic: UInt8 = 1

    var version: UInt8 = Proto.version
    var type: UInt8 = MeshPacket.typePublic
    var flags: UInt8 = 0
    var ttl: UInt8
    var hops: UInt8
    var messageID: UInt64
    var timestamp: UInt64            // milliseconds since 1970, the sender's clock
    var payload: Data                // the message and its signature

    func encode() -> Data {
        var w = ByteWriter()
        header(&w, ttl: ttl, hops: hops)
        w.bytes(payload)
        return w.data
    }

    // What the signature covers of the header: all of it, with what relays change set to 0
    var signedHeader: Data {
        var w = ByteWriter()
        header(&w, ttl: 0, hops: 0)
        return w.data
    }

    // The same packet one relay further
    func relayed() -> MeshPacket? {
        guard ttl > 0 else { return nil }
        var p = self
        p.ttl -= 1
        p.hops += 1
        return p
    }

    private func header(_ w: inout ByteWriter, ttl: UInt8, hops: UInt8) {
        w.u8(version)
        w.u8(type)
        w.u8(flags)
        w.u8(ttl)
        w.u8(hops)
        w.u64(messageID)
        w.u64(timestamp)
    }

    static func decode(_ d: Data) throws -> MeshPacket {
        guard d.count <= Proto.maxPacket else { throw WireError.tooLarge("packet of \(d.count) bytes") }
        var r = ByteReader(d)
        let version = try r.u8()
        guard version == Proto.version else { throw Proto.versionError(version, ours: Proto.version) }
        let type = try r.u8()
        guard type == typePublic else { throw WireError.invalid("packet type \(type)") }
        let flags = try r.u8(), ttl = try r.u8(), hops = try r.u8()
        guard Int(ttl) + Int(hops) <= Int(Proto.hopLimit) else { throw WireError.invalid("ttl \(ttl) and hops \(hops)") }
        let id = try r.u64()
        let time = try r.u64()
        let payload = r.rest()
        guard payload.count > Proto.signatureLength else { throw WireError.truncated }
        return MeshPacket(version: version, type: type, flags: flags, ttl: ttl, hops: hops, messageID: id, timestamp: time, payload: payload)
    }
}

// ── The message in a packet ───────────────────────────────────

enum InnerKind: UInt8 {
    case chat = 1, presence = 2, bye = 3
}

// A Mac someone has a link to, and how strong they hear it
struct Neighbour: Equatable {
    let token: UInt32                       // the first 4 bytes of its session
    let rssi: Int                           // dBm; Distance.unknown when not measured
}

struct InnerMessage: Equatable {
    static let requestFlag: UInt8 = 1       // presence: please answer with yours

    var kind: InnerKind
    var flags: UInt8 = 0
    var senderKey: Data
    var session: Data
    var nickname: String
    var text = ""                           // chat
    var links: UInt8 = 0                    // presence: how many Macs it is connected to
    var neighbours: [Neighbour] = []        // presence: which, and how strong it hears them

    // Everything but the signature
    func body() throws -> Data {
        guard senderKey.count == Proto.keyLength, session.count == Proto.sessionLength else { throw WireError.invalid("key or session") }
        var w = ByteWriter()
        w.u8(kind.rawValue)
        w.u8(flags)
        w.bytes(senderKey)
        w.bytes(session)
        guard nickname.utf8.count <= Proto.maxNicknameBytes else { throw WireError.tooLarge("nickname") }
        try w.str8(nickname)
        switch kind {
        case .chat:
            guard text.utf8.count <= Proto.maxTextBytes else { throw WireError.tooLarge("message") }
            try w.str16(text)
        case .presence:
            w.u8(links)
            let list = neighbours.prefix(Proto.maxNeighbours)
            w.u8(UInt8(list.count))
            for n in list {
                w.bytes(Data([UInt8(n.token >> 24 & 0xFF), UInt8(n.token >> 16 & 0xFF), UInt8(n.token >> 8 & 0xFF), UInt8(n.token & 0xFF)]))
                w.u8(UInt8(bitPattern: Int8(clamping: n.rssi)))
            }
        case .bye:
            break
        }
        return w.data
    }

    // → the message (its texts made safe for the terminal), the signed bytes and the signature
    static func decode(_ payload: Data) throws -> (InnerMessage, body: Data, signature: Data) {
        guard payload.count > Proto.signatureLength + 2 else { throw WireError.truncated }
        let body = Data(payload.prefix(payload.count - Proto.signatureLength))
        let signature = Data(payload.suffix(Proto.signatureLength))
        var r = ByteReader(body)
        guard let kind = InnerKind(rawValue: try r.u8()) else { throw WireError.invalid("message kind") }
        let flags = try r.u8()
        let key = try r.bytes(Proto.keyLength)
        let session = try r.bytes(Proto.sessionLength)
        let nickname = Sanitize.nickname(try r.str8(max: Proto.maxNicknameBytes))
        guard !nickname.isEmpty else { throw WireError.invalid("empty nickname") }
        var m = InnerMessage(kind: kind, flags: flags, senderKey: key, session: session, nickname: nickname)
        switch kind {
        case .chat:
            m.text = Sanitize.text(try r.str16(max: Proto.maxTextBytes))
            guard !m.text.isEmpty else { throw WireError.invalid("empty message") }
        case .presence:
            m.links = try r.u8()
            if !r.isAtEnd {
                let n = Int(try r.u8())
                guard n <= Proto.maxNeighbours else { throw WireError.invalid("\(n) neighbours") }
                for _ in 0..<n {
                    let token = try r.bytes(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                    m.neighbours.append(Neighbour(token: token, rssi: Int(Int8(bitPattern: try r.u8()))))
                }
            }
        case .bye:
            break
        }
        // a newer version may add fields here – they are signed, and skipped
        return (m, body, signature)
    }
}

// ── Texts from other Macs ─────────────────────────────────────
// Whatever arrives is shown in a terminal: control characters (ESC starts terminal commands), direction
// overrides and invisible characters are taken out, line breaks become spaces, and lengths are cut.

enum Sanitize {
    static func isUnsafe(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x00...0x1F, 0x7F...0x9F: return true                  // control characters, ESC among them
        case 0x200B, 0x200E, 0x200F: return true                    // zero width space, direction marks
        case 0x202A...0x202E, 0x2066...0x2069: return true          // direction overrides and isolates
        case 0x2060...0x2064, 0xFEFF: return true                   // invisible joiners and operators
        case 0xFFF9...0xFFFB: return true                           // annotations
        case 0xE0000...0xE007F: return true                         // tag characters (hidden text)
        default: return false
        }
    }

    // One line: spaces for line breaks and tabs, no unsafe characters, spaces collapsed and trimmed, then cut
    static func line(_ s: String, characters: Int, bytes: Int) -> String {
        var scalars = String.UnicodeScalarView()
        var space = false
        for u in s.unicodeScalars {
            if u.properties.isWhitespace {          // spaces of all kinds, tabs and line breaks
                space = true
                continue
            }
            if isUnsafe(u) { continue }
            if space && !scalars.isEmpty { scalars.append(" ") }
            space = false
            scalars.append(u)
        }
        return cut(String(scalars), characters: characters, bytes: bytes)
    }

    // At most so many characters and UTF-8 bytes, never in the middle of a character
    static func cut(_ s: String, characters: Int, bytes: Int) -> String {
        var out = ""
        var n = 0, b = 0
        for ch in s {
            let size = String(ch).utf8.count
            if n + 1 > characters || b + size > bytes { break }
            out.append(ch)
            n += 1
            b += size
        }
        return out
    }

    static func nickname(_ s: String) -> String { line(s, characters: Proto.maxNicknameCharacters, bytes: Proto.maxNicknameBytes) }
    static func text(_ s: String) -> String { line(s, characters: Int.max, bytes: Proto.maxTextBytes) }
}
