// MeshChat tests – fragments and duplicates: packets cut for small and large links and put back together in any
// order, with limits that hold against a hostile neighbour; message IDs remembered for a while.

import Foundation

private func parts(_ frames: [Data]) -> [(UInt16, UInt8, UInt8, Data)] {
    frames.compactMap {
        if case let .data(seq, index, count, payload)? = try? LinkFrame.decode($0) { return (seq, index, count, payload) }
        return nil
    }
}

func fragmentTests() {
    test("fragments: cut to fit every link size, and put back together") {
        let packet = CryptoBackend.randomBytes(Proto.maxPacket)
        for size in [20, 23, 64, 182, 185, 512, 600] {
            let frames = try Fragmenter.frames(for: packet, seq: 9, maxFrame: size)
            check(frames.allSatisfy { $0.count <= min(size, Proto.maxFrame) }, "every frame fits \(size) bytes")
            let r = Reassembler()
            var result = Reassembler.Result.incomplete
            for (seq, index, count, payload) in parts(frames) {
                result = r.add(seq: seq, index: index, count: count, payload: payload, now: 0)
            }
            checkEqual(result, .complete(packet), "\(frames.count) frames of up to \(size) bytes back to 2048")
        }
        let small = Data("hi".utf8)
        checkEqual(try Fragmenter.frames(for: small, seq: 1, maxFrame: 182).count, 1, "a small packet is one frame")
        checkThrows("a link with frames under 20 bytes") { try Fragmenter.frames(for: small, seq: 1, maxFrame: 12) }
        checkThrows("a packet over 2048 bytes") { try Fragmenter.frames(for: Data(count: 2049), seq: 1, maxFrame: 512) }
        checkThrows("an empty packet") { try Fragmenter.frames(for: Data(), seq: 1, maxFrame: 512) }
    }

    test("fragments: out of order, twice, and two packets mixed") {
        let a = CryptoBackend.randomBytes(900), b = CryptoBackend.randomBytes(700)
        let fa = parts(try Fragmenter.frames(for: a, seq: 1, maxFrame: 100))
        let fb = parts(try Fragmenter.frames(for: b, seq: 2, maxFrame: 100))
        let r = Reassembler()
        var done: [Data] = []
        var duplicates = 0
        // b backwards, mixed with a forwards, and every part of a twice
        var mixed: [(UInt16, UInt8, UInt8, Data)] = []
        for i in 0..<max(fa.count, fb.count) {
            if i < fa.count { mixed.append(fa[i]); mixed.append(fa[i]) }
            if i < fb.count { mixed.append(fb[fb.count - 1 - i]) }
        }
        for (seq, index, count, payload) in mixed {
            switch r.add(seq: seq, index: index, count: count, payload: payload, now: 0) {
            case .complete(let d): done.append(d)
            case .duplicate: duplicates += 1
            default: break
            }
        }
        checkEqual(done.count, 2, "both packets whole")
        check(done.contains(a) && done.contains(b), "and right")
        checkEqual(duplicates, fa.count, "parts that came twice are recognized – also after the packet was complete")
        checkEqual(r.pendingCount, 0, "nothing left half done")
    }

    test("fragments: limits against a hostile or broken neighbour") {
        let r = Reassembler(maxPending: 4, timeout: 15, maxPacket: Proto.maxPacket)
        // a part that never gets its other parts is dropped after 15 seconds
        checkEqual(r.add(seq: 1, index: 0, count: 3, payload: Data(count: 10), now: 0), .incomplete, "first of three")
        _ = r.add(seq: 1, index: 1, count: 3, payload: Data(count: 10), now: 1)
        r.expire(now: 20)
        checkEqual(r.pendingCount, 0, "a packet missing a part is given up after its time")
        checkEqual(r.add(seq: 1, index: 2, count: 3, payload: Data(count: 10), now: 21), .incomplete, "its last part alone does not complete anything")
        // many half packets: only the newest four are kept
        for s in 10..<30 { _ = r.add(seq: UInt16(s), index: 0, count: 2, payload: Data(count: 10), now: 22) }
        check(r.pendingCount <= 4, "at most 4 packets half done")
        // a packet that grows over 2048 bytes is refused
        let big = Reassembler()
        var result = Reassembler.Result.incomplete
        for i in 0..<5 { result = big.add(seq: 7, index: UInt8(i), count: 6, payload: Data(count: 500), now: 0) }
        checkEqual(result, .rejected("too large"), "parts adding up to more than 2048 bytes")
        checkEqual(big.add(seq: 8, index: 0, count: 1, payload: Data(count: 3000), now: 0), .rejected("too large"), "a single part over 2048 bytes")
        // the same sequence number with another count: the old one is dropped, the new one starts
        let again = Reassembler()
        _ = again.add(seq: 5, index: 0, count: 3, payload: Data([1]), now: 0)
        _ = again.add(seq: 5, index: 0, count: 2, payload: Data([2]), now: 0)
        checkEqual(again.add(seq: 5, index: 1, count: 2, payload: Data([3]), now: 0), .complete(Data([2, 3])), "a reused sequence number")
        checkEqual(again.add(seq: 6, index: 3, count: 2, payload: Data([3]), now: 0), .rejected("fragment 3 of 2"), "an index outside the count")
    }
}

func dedupTests() {
    test("duplicates: remembered for 30 minutes, 4096 at most") {
        var d = DedupCache(capacity: 4, window: 1800)
        check(d.insert(1, now: 0), "new")
        check(!d.insert(1, now: 10), "the second time it is a duplicate")
        check(d.contains(1, now: 1799), "still known after 29 minutes")
        check(!d.contains(1, now: 1801), "forgotten after 30")
        for i in 10..<20 { d.insert(UInt64(i), now: 2000) }
        checkEqual(d.count, 4, "the oldest go first when it is full")
        check(d.contains(19, now: 2000) && !d.contains(10, now: 2000), "the newest stay")
        var big = DedupCache()
        for i in 0..<10_000 { big.insert(UInt64(i), now: Double(i) / 10) }
        check(big.count <= 4096, "never more than 4096 IDs")
    }
}
