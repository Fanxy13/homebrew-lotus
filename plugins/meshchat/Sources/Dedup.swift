// MeshChat – duplicate detection: the IDs of the messages seen in the last half hour, at most 4096 of them. A
// message that arrives twice – over two paths, or again when a Mac reconnects – is shown and passed on once.
// Messages older than 15 minutes are refused anyway, so a copy can never come back after its ID was forgotten.

import Foundation

struct DedupCache {
    let capacity: Int
    let window: TimeInterval
    private var seen: [UInt64: TimeInterval] = [:]
    private var order: [(id: UInt64, time: TimeInterval)] = []      // oldest first
    private var head = 0

    init(capacity: Int = 4096, window: TimeInterval = 30 * 60) {
        self.capacity = capacity
        self.window = window
    }

    var count: Int { seen.count }

    mutating func contains(_ id: UInt64, now: TimeInterval) -> Bool {
        purge(now)
        return seen[id] != nil
    }

    // true when it is new
    @discardableResult
    mutating func insert(_ id: UInt64, now: TimeInterval) -> Bool {
        purge(now)
        guard seen[id] == nil else { return false }
        seen[id] = now
        order.append((id, now))
        while seen.count > capacity { dropOldest() }
        return true
    }

    private mutating func purge(_ now: TimeInterval) {
        while head < order.count, now - order[head].time > window { dropOldest() }
        if head > 1024 && head * 2 > order.count {
            order.removeFirst(head)
            head = 0
        }
    }

    private mutating func dropOldest() {
        guard head < order.count else { return }
        let e = order[head]
        if seen[e.id] == e.time { seen[e.id] = nil }
        head += 1
    }
}
