// MeshChat – how far someone is. Bluetooth says how strong a Mac's signal arrives (RSSI, in dBm): the weaker, the
// further. From it comes a rough distance, by the log-distance model: about −59 dBm at one metre, fading with the
// 2.5th power of the distance indoors (2 in the open). Walls, bodies, which way a laptop faces and its Bluetooth
// chip easily make a Mac seem twice or half as far – an estimate, and said as one.
// Beyond the neighbours: each Mac's "I am here" lists the Macs it has a link to and how strong it hears them. Put
// together, they are a map of the mesh, and the way to someone – the fewest relays, then the shortest – has a
// distance for each leg.

import Foundation

enum Distance {
    static let atOneMetre = -59.0               // dBm a Mac's Bluetooth LE arrives with from one metre, roughly
    static let fading = 2.5                     // how fast the signal fades with distance indoors
    static let unknown: Int = 127               // "no signal measured" – as CoreBluetooth says it

    static func metres(_ rssi: Int) -> Double {
        min(100, max(0.3, pow(10, (atOneMetre - Double(rssi)) / (10 * fading))))
    }

    // The signal a Mac so far away arrives with – for the simulated radio
    static func rssi(metres: Double) -> Int {
        Int((atOneMetre - 10 * fading * log10(max(0.1, metres))).rounded())
    }

    // "< 1 m", "≈ 3 m", "≈ 15 m", "> 50 m" – no more precision than the estimate has
    static func label(_ m: Double) -> String {
        if m < 1 { return "< 1 m" }
        if m < 10 { return "≈ \(Int(m.rounded())) m" }
        if m <= 50 { return "≈ \(Int((m / 5).rounded()) * 5) m" }
        return "> 50 m"
    }

    // The same, short: for the line of who is here
    static func short(_ m: Double) -> String {
        if m < 1 { return "<1m" }
        if m < 10 { return "\(Int(m.rounded()))m" }
        if m <= 50 { return "\(Int((m / 5).rounded()) * 5)m" }
        return ">50m"
    }

    static func closeness(_ m: Double) -> String {
        switch m {
        case ..<1.5: return "right next to you"
        case ..<4: return "close"
        case ..<10: return "in the same room or near it"
        default: return "further away – or behind a wall"
        }
    }

    // The way from one Mac to another through links known to exist: the fewest relays first, then the shortest
    // estimated distance (a leg without a measured signal counts as 10 m). → the Macs on the way, each with the
    // signal of the leg that reaches it; nil when no way is known.
    static func route(from start: UInt32, to goal: UInt32, links: [UInt32: [UInt32: Int]]) -> [(mac: UInt32, rssi: Int?)]? {
        guard start != goal else { return [] }
        func cost(_ rssi: Int) -> Double { rssi == unknown ? 10 : metres(rssi) }
        var best: [UInt32: (hops: Int, metres: Double)] = [start: (0, 0)]
        var previous: [UInt32: UInt32] = [:]
        var open: Set<UInt32> = [start]
        var done: Set<UInt32> = []
        while let here = open.min(by: { a, b in
            let x = best[a]!, y = best[b]!
            return x.hops != y.hops ? x.hops < y.hops : x.metres < y.metres
        }) {
            open.remove(here)
            done.insert(here)
            if here == goal { break }
            let base = best[here]!
            for (next, rssi) in links[here] ?? [:] where !done.contains(next) {
                let candidate = (hops: base.hops + 1, metres: base.metres + cost(rssi))
                if let known = best[next], (known.hops, known.metres) <= (candidate.hops, candidate.metres) { continue }
                best[next] = candidate
                previous[next] = here
                open.insert(next)
            }
        }
        guard best[goal] != nil else { return nil }
        var way: [(mac: UInt32, rssi: Int?)] = []
        var at = goal
        while at != start, let from = previous[at] {
            let r = links[from]?[at] ?? unknown
            way.insert((at, r == unknown ? nil : r), at: 0)
            at = from
        }
        return way
    }
}
