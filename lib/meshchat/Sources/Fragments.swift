// MeshChat – fragments: a mesh packet (up to 2048 bytes) cut into DATA frames that fit one write or notification
// of a link (20–512 bytes), and put back together on the other side – in any order, each part once, with limits on
// how many packets may be half done, how large they get and how long they wait.

import Foundation

enum Fragmenter {
    static func frames(for packet: Data, seq: UInt16, maxFrame: Int) throws -> [Data] {
        let frame = min(maxFrame, Proto.maxFrame)
        guard frame >= Proto.minFrame else { throw WireError.invalid("a link with frames of \(maxFrame) bytes") }
        guard !packet.isEmpty, packet.count <= Proto.maxPacket else { throw WireError.tooLarge("packet of \(packet.count) bytes") }
        let chunk = frame - LinkFrame.dataHeader
        let count = (packet.count + chunk - 1) / chunk
        guard count <= Proto.maxFragments else { throw WireError.tooLarge("\(count) fragments") }
        let bytes = [UInt8](packet)
        return (0..<count).map { i in
            let part = Data(bytes[(i * chunk)..<min(bytes.count, (i + 1) * chunk)])
            return LinkFrame.data(seq: seq, index: UInt8(i), count: UInt8(count), payload: part).encode()
        }
    }
}

// One per link: the frames of a link arrive in order, but nothing here relies on it
final class Reassembler {
    enum Result: Equatable {
        case incomplete
        case complete(Data)
        case duplicate              // a part it has already
        case rejected(String)       // over a limit
    }

    private struct Pending {
        var count: UInt8
        var parts: [UInt8: Data]
        var bytes: Int
        let started: TimeInterval
    }

    let maxPending: Int
    let timeout: TimeInterval
    let maxPacket: Int
    private var pending: [UInt16: Pending] = [:]
    private var completed: [UInt16] = []       // the last packets put together: a late copy of a part is a duplicate
    private(set) var dropped = 0    // packets given up: too old, or pushed out by newer ones

    init(maxPending: Int = 8, timeout: TimeInterval = 15, maxPacket: Int = Proto.maxPacket) {
        self.maxPending = maxPending
        self.timeout = timeout
        self.maxPacket = maxPacket
    }

    var pendingCount: Int { pending.count }

    func add(seq: UInt16, index: UInt8, count: UInt8, payload: Data, now: TimeInterval) -> Result {
        expire(now: now)
        guard count >= 1, index < count else { return .rejected("fragment \(index) of \(count)") }
        guard payload.count <= maxPacket else { return .rejected("too large") }
        if pending[seq] == nil && completed.contains(seq) { return .duplicate }
        if count == 1 {
            pending[seq] = nil
            done(seq)
            return .complete(payload)
        }
        if var p = pending[seq], p.count == count {
            if p.parts[index] != nil { return .duplicate }
            guard p.bytes + payload.count <= maxPacket else {
                pending[seq] = nil
                dropped += 1
                return .rejected("too large")
            }
            p.parts[index] = payload
            p.bytes += payload.count
            if p.parts.count == Int(count) {
                pending[seq] = nil
                done(seq)
                var whole = Data(capacity: p.bytes)
                for i in 0..<count { whole.append(p.parts[i]!) }
                return .complete(whole)
            }
            pending[seq] = p
            return .incomplete
        }
        // a new packet – or the same sequence number with another count: the old one never finished
        if pending[seq] != nil {
            pending[seq] = nil
            dropped += 1
        }
        if pending.count >= maxPending, let oldest = pending.min(by: { $0.value.started < $1.value.started }) {
            pending[oldest.key] = nil
            dropped += 1
        }
        pending[seq] = Pending(count: count, parts: [index: payload], bytes: payload.count, started: now)
        return .incomplete
    }

    private func done(_ seq: UInt16) {
        completed.append(seq)
        if completed.count > 32 { completed.removeFirst() }
    }

    func expire(now: TimeInterval) {
        for (seq, p) in pending where now - p.started > timeout {
            pending[seq] = nil
            dropped += 1
        }
    }
}
