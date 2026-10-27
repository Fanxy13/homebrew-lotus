// MeshChat – a simulated radio, for the tests and `lotus meshchat demo` only – never for a real chat (that is
// BLETransport.swift). Macs in memory: who hears whom (range), advertising and scanning, links with a frame size,
// and frames delivered in order on each link. It behaves like Bluetooth where the mesh relies on it:
//   - a scan reports each Mac it hears once, until scanning is switched on again
//   - a connection to a Mac out of range waits (the mesh gives up after its timeout), and completes when it comes
//   - only the central can end a link; when the peripheral closes one, it just stops listening, and the central
//     notices when the link goes silent
//   - out of range, a link breaks on both sides
//   - the signal strength follows the distance between two Macs (3 m unless a test says otherwise)
// A test can also lose or double frames, and switch "Bluetooth" off.

import Foundation

final class SimNetwork {
    private struct SimLink {
        let central: SimRadio
        let centralID: Int
        let peripheral: SimRadio
        let peripheralID: Int
        var centralOpen = true
        var peripheralOpen = true
    }

    var lossRate = 0.0                  // frames lost on the way (0…1)
    var duplicateRate = 0.0             // frames that arrive twice
    private(set) var manualNow: TimeInterval
    private let live: DispatchQueue?    // the demo: events on this queue, time from the clock
    private var rng: UInt64
    private var radios: [String: SimRadio] = [:]
    private var range: Set<String> = []
    private var distances: [String: Double] = [:]
    private var links: [Int: SimLink] = [:]
    private var nextLink = 1
    private var pending: [() -> Void] = []
    var tickers: [() -> Void] = []      // called once a simulated second (the meshes' tick)

    init(start: TimeInterval = 1_700_000_000, seed: UInt64 = 0x9E3779B97F4A7C15, live: DispatchQueue? = nil) {
        manualNow = start
        rng = seed
        self.live = live
    }

    var now: TimeInterval { live == nil ? manualNow : Date().timeIntervalSince1970 }

    func radio(_ name: String, maxFrame: Int = 182) -> SimRadio {
        let r = SimRadio(name: name, network: self, maxFrame: maxFrame)
        radios[name] = r
        return r
    }

    // ── Range ─────────────────────────────────────────────────

    private func key(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }

    func hears(_ a: String, _ b: String) -> Bool { range.contains(key(a, b)) }

    func setRange(_ a: String, _ b: String, _ inRange: Bool) {
        if inRange {
            range.insert(key(a, b))
        } else {
            range.remove(key(a, b))
            for (id, l) in links where (l.central.name == a && l.peripheral.name == b) || (l.central.name == b && l.peripheral.name == a) {
                breakLink(id, reason: "out of range")
            }
        }
    }

    // How far apart two Macs are – what their signal strength comes from
    func setDistance(_ a: String, _ b: String, _ metres: Double) { distances[key(a, b)] = metres }

    func signal(_ a: String, _ b: String) -> Int { Distance.rssi(metres: distances[key(a, b)] ?? 3) }

    // Everyone hears everyone of these
    func allInRange(_ names: [String]) {
        for a in names { for b in names where a < b { setRange(a, b, true) } }
    }

    // ── Time and events ───────────────────────────────────────

    func schedule(_ event: @escaping () -> Void) {
        if let q = live { q.async(execute: event) } else { pending.append(event) }
    }

    // Runs what is queued until nothing is left → how many events ran
    @discardableResult
    func pump(limit: Int = 2_000_000) -> Int {
        var n = 0
        while !pending.isEmpty && n < limit {
            let e = pending.removeFirst()
            e()
            n += 1
        }
        return n
    }

    // Time passes in steps of a second: scans hear, waiting connections complete, the meshes tick
    func advance(_ seconds: TimeInterval) {
        var left = seconds
        while left > 0 {
            let step = min(1, left)
            manualNow += step
            left -= step
            secondPassed()
            pump()
        }
    }

    // One second of the radio's own work – the demo calls it from its timer
    func secondPassed() {
        for r in radios.values where r.running && r.powered {
            if r.scanning {
                for other in radios.values where other !== r && other.running && other.powered && other.advertising
                    && hears(r.name, other.name) && !r.reported.contains(other.name) {
                    r.reported.insert(other.name)
                    let token = other.token, rssi = signal(r.name, other.name)
                    schedule { r.delegate?.radio(sighted: Sighting(endpoint: other.name, token: token, rssi: rssi)) }
                }
            }
            for target in r.waiting { tryConnect(r, target) }
        }
        for t in tickers { t() }
    }

    // ── Links ─────────────────────────────────────────────────

    fileprivate func tryConnect(_ from: SimRadio, _ to: String) {
        guard let target = radios[to], from.waiting.contains(to), target.running, target.powered, from.running, from.powered,
              hears(from.name, to), target.advertising else { return }
        from.waiting.remove(to)
        let id = nextLink
        nextLink += 1
        let cid = from.newLocal(link: id), pid = target.newLocal(link: id)
        links[id] = SimLink(central: from, centralID: cid, peripheral: target, peripheralID: pid)
        let frame = min(from.maxFrameSize, target.maxFrameSize)
        schedule {
            from.delegate?.radio(opened: LinkInfo(id: cid, outbound: true, endpoint: to, maxFrame: frame))
            target.delegate?.radio(opened: LinkInfo(id: pid, outbound: false, endpoint: from.name, maxFrame: frame))
        }
    }

    fileprivate func measure(link id: Int, local: Int, by radio: SimRadio) {
        guard let l = links[id] else { return }
        let other = l.central === radio ? l.peripheral : l.central
        guard l.central === radio else { return }           // as on a Mac: only the central can read it
        let rssi = signal(radio.name, other.name)
        schedule { radio.delegate?.radio(signal: rssi, on: local) }
    }

    fileprivate func maxFrame(_ id: Int) -> Int {
        guard let l = links[id] else { return Proto.minFrame }
        return min(l.central.maxFrameSize, l.peripheral.maxFrameSize)
    }

    fileprivate func send(_ frame: Data, link id: Int, from radio: SimRadio) {
        guard let l = links[id] else { return }
        let toCentral = radio === l.peripheral
        guard toCentral ? l.peripheralOpen : l.centralOpen else { return }
        let to = toCentral ? l.central : l.peripheral, local = toCentral ? l.centralID : l.peripheralID
        radio.framesSent += 1
        if lossRate > 0 && random() < lossRate { return }
        let copies = duplicateRate > 0 && random() < duplicateRate ? 2 : 1
        for _ in 0..<copies {
            schedule { [weak self] in
                // still there, and still listening on that side?
                guard let l = self?.links[id], toCentral ? l.centralOpen : l.peripheralOpen else { return }
                to.delegate?.radio(received: frame, on: local)
            }
        }
    }

    fileprivate func close(link id: Int, by radio: SimRadio) {
        guard var l = links[id] else { return }
        if radio === l.central {
            breakLink(id, reason: "disconnected")
        } else if l.peripheralOpen {
            // a peripheral cannot end a connection: it stops listening, the central finds out by itself
            l.peripheralOpen = false
            links[id] = l
            let pid = l.peripheralID, p = l.peripheral
            p.forget(pid)
            schedule { p.delegate?.radio(closed: pid, reason: "closed by this Mac") }
        }
    }

    private func breakLink(_ id: Int, reason: String) {
        guard let l = links.removeValue(forKey: id) else { return }
        l.central.forget(l.centralID)
        l.peripheral.forget(l.peripheralID)
        if l.centralOpen { schedule { l.central.delegate?.radio(closed: l.centralID, reason: reason) } }
        if l.peripheralOpen { schedule { l.peripheral.delegate?.radio(closed: l.peripheralID, reason: reason) } }
    }

    fileprivate func linksOf(_ radio: SimRadio) -> [Int] {
        links.filter { $0.value.central === radio || $0.value.peripheral === radio }.map { $0.key }
    }

    fileprivate func dropAll(_ radio: SimRadio, reason: String) {
        for id in linksOf(radio) { breakLink(id, reason: reason) }
    }

    var linkCount: Int { links.values.filter { $0.centralOpen && $0.peripheralOpen }.count }

    // Which radios have an open link to each other, as "a-b" sorted pairs
    var linkPairs: Set<String> {
        Set(links.values.filter { $0.centralOpen && $0.peripheralOpen }.map { key($0.central.name, $0.peripheral.name) })
    }

    private func random() -> Double {
        // SplitMix64: the same run every time for a given seed
        rng = rng &+ 0x9E3779B97F4A7C15
        var z = rng
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}

final class SimRadio: LinkTransport {
    let name: String
    unowned let network: SimNetwork
    weak var delegate: LinkTransportDelegate?
    private(set) var state = RadioState.starting
    let maxFrameSize: Int
    fileprivate(set) var running = false
    fileprivate(set) var scanning = false
    fileprivate(set) var advertising = false
    fileprivate(set) var token: UInt32 = 0
    fileprivate var reported: Set<String> = []
    fileprivate var waiting: Set<String> = []
    fileprivate(set) var framesSent = 0
    private var locals: [Int: Int] = [:]          // this radio's link id → the network's
    private var nextLocal = 1

    fileprivate(set) var powered = true

    init(name: String, network: SimNetwork, maxFrame: Int) {
        self.name = name
        self.network = network
        maxFrameSize = maxFrame
    }

    fileprivate func newLocal(link: Int) -> Int {
        let id = nextLocal
        nextLocal += 1
        locals[id] = link
        return id
    }

    fileprivate func forget(_ local: Int) { locals[local] = nil }

    var openLinks: Int { locals.count }

    // "Bluetooth" switched off or on in a test: links break, the mesh is told
    func setPower(_ on: Bool) {
        guard on != powered else { return }
        powered = on
        if !on {
            scanning = false
            advertising = false
            waiting.removeAll()
            network.dropAll(self, reason: "Bluetooth is off")
        }
        guard running else { return }
        state = on ? .on : .off
        let s = state
        network.schedule { [weak self] in self?.delegate?.radio(stateChanged: s) }
    }

    func start(token: UInt32) {
        self.token = token
        running = true
        state = powered ? .on : .off
        let s = state
        network.schedule { [weak self] in self?.delegate?.radio(stateChanged: s) }
    }

    func stop() {
        running = false
        scanning = false
        advertising = false
        waiting.removeAll()
        network.dropAll(self, reason: "stopped")
        locals.removeAll()
        state = .off
    }

    func setScanning(_ on: Bool) {
        guard powered else { return }
        scanning = on
        if on { reported.removeAll() }
    }

    func setAdvertising(_ on: Bool) {
        guard powered else { return }
        advertising = on
    }

    func connect(_ endpoint: String) {
        waiting.insert(endpoint)
        network.schedule { [weak self] in
            guard let self = self else { return }
            self.network.tryConnect(self, endpoint)
        }
    }

    func cancelConnect(_ endpoint: String) { waiting.remove(endpoint) }

    func send(_ frame: Data, on link: Int) {
        guard let id = locals[link] else { return }
        network.send(frame, link: id, from: self)
    }

    func close(_ link: Int) {
        guard let id = locals[link] else { return }
        network.close(link: id, by: self)
    }

    func maxFrame(for link: Int) -> Int {
        guard let id = locals[link] else { return Proto.minFrame }
        return network.maxFrame(id)
    }

    func measureSignal(on link: Int) {
        guard let id = locals[link] else { return }
        network.measure(link: id, local: link, by: self)
    }
}
