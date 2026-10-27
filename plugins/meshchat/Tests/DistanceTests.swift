// MeshChat tests – how far someone is: the signal strength turned into metres, the way through the mesh with the
// fewest relays and then the shortest legs, and the whole of it on the simulated radio, where the distances are
// known.

import Foundation

func distanceTests() {
    test("how far: signal strength to metres, and said no more exactly than it is known") {
        checkEqual(Int(Distance.metres(-59).rounded()), 1, "−59 dBm: about a metre")
        checkEqual(Int(Distance.metres(-84).rounded()), 10, "−84 dBm: about ten")
        check(Distance.metres(-70) < Distance.metres(-75), "a weaker signal is further away")
        checkEqual(Distance.metres(-10), 0.3, "never closer than 30 cm")
        checkEqual(Distance.metres(-120), 100, "never further than 100 m")
        for m in [0.5, 1.0, 2.0, 5.0, 12.0, 40.0] {
            check(abs(Distance.metres(Distance.rssi(metres: m)) - m) / m < 0.1, "\(m) m there and back")
        }
        checkEqual(Distance.label(0.6), "< 1 m", "under a metre")
        checkEqual(Distance.label(3.4), "≈ 3 m", "metres")
        checkEqual(Distance.label(17), "≈ 15 m", "fives beyond ten")
        checkEqual(Distance.label(80), "> 50 m", "far")
        checkEqual(Distance.short(3.4), "3m", "short, for the line of who is here")
        checkEqual(Distance.closeness(1), "right next to you", "words for it")
    }

    test("the way through the mesh: the fewest relays, then the shortest") {
        let u = Distance.unknown
        // me 1 – 2 – 4 and me 1 – 3 – 4: two ways of two relays; the one through 3 is shorter
        var links: [UInt32: [UInt32: Int]] = [:]
        func link(_ a: UInt32, _ b: UInt32, _ rssi: Int) {
            links[a, default: [:]][b] = rssi
            links[b, default: [:]][a] = rssi
        }
        link(1, 2, Distance.rssi(metres: 2))
        link(2, 4, Distance.rssi(metres: 20))
        link(1, 3, Distance.rssi(metres: 3))
        link(3, 4, Distance.rssi(metres: 4))
        let way = Distance.route(from: 1, to: 4, links: links)
        checkEqual(way?.map { $0.mac }, [3, 4], "through 3: 7 m rather than 22 m")
        checkEqual(way?.first?.rssi, Distance.rssi(metres: 3), "with each leg's signal")
        link(1, 5, Distance.rssi(metres: 30))
        link(5, 4, Distance.rssi(metres: 30))
        link(1, 4, Distance.rssi(metres: 40))
        checkEqual(Distance.route(from: 1, to: 4, links: links)?.map { $0.mac }, [4], "a direct link first, however long")
        link(6, 7, u)
        check(Distance.route(from: 1, to: 7, links: links) == nil, "no way known: nil")
        link(4, 8, u)
        let toEight = Distance.route(from: 1, to: 8, links: links)
        checkEqual(toEight?.map { $0.mac }, [4, 8], "a leg without a signal still makes a way")
        check(toEight?.last?.rssi == nil, "and says it was not measured")
        checkEqual(Distance.route(from: 1, to: 1, links: links)?.count, 0, "to oneself: no way at all")
    }

    test("how far on the simulated radio: a neighbour by its signal, someone further along the way") {
        let m = TestMesh()
        for n in ["A", "B", "C"] { m.add(n) }
        m.net.setRange("A", "B", true)
        m.net.setRange("B", "C", true)
        m.net.setDistance("A", "B", 2)
        m.net.setDistance("B", "C", 8)
        m.run(75)
        let b = m.person("B", seenBy: "A")
        check(b?.direct == true, "B is A's neighbour")
        check(b?.signal != nil, "A measured B's signal")
        if let rssi = b?.signal { check(abs(Distance.metres(rssi) - 2) < 0.6, "B is about 2 m from A (\(Distance.label(Distance.metres(rssi))))") }
        let c = m.person("C", seenBy: "A")
        checkEqual(c?.via, "B", "C's messages come through B")
        check(c?.signal == nil, "A cannot hear C itself")
        let way = c.flatMap { m.node("A").route(to: $0.key) }
        checkEqual(way?.map { $0.name }, ["B", "C"], "the way to C: through B")
        if let legs = way, legs.count == 2, let r1 = legs[0].rssi, let r2 = legs[1].rssi {
            check(abs(Distance.metres(r1) - 2) < 0.6 && abs(Distance.metres(r2) - 8) < 2, "legs of about 2 m and 8 m")
            let text = ChatApp.describe(c!, route: legs)
            check(text.contains("1 relay away through B") && text.contains("10 m"), "said as: 1 relay away through B, about 10 m (\(text))")
        } else {
            check(false, "both legs measured: \(String(describing: way))")
        }
        check(ChatApp.describe(b!, route: m.node("A").route(to: b!.key)).contains("≈ 2 m from you"), "and B: about 2 m from you")
    }
}
