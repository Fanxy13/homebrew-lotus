// MeshChat – the real radio: Bluetooth Low Energy with Apple's CoreBluetooth. Every Mac is both
//   peripheral  it advertises the MeshChat service – its UUID, and "mc" + 8 hex digits (a random token that
//               changes with every start) as its name, nothing else – and offers two characteristics:
//               RX, which the others write frames to (write without response), and TX, which it notifies frames on
//   central     it scans for the service, connects, subscribes to TX and writes to RX
// One link is one connection, in either direction. Frames wait in a queue per link while it is busy: writes
// without response and notifications both have flow control. A peripheral cannot end a connection – when this Mac
// closes a link someone else made, it ignores it from then on, and the other Mac notices the silence.
// macOS asks once whether the app that started MeshChat (the terminal) may use Bluetooth; until then the state is
// "starting", and "not allowed" after a no.

#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

enum MeshService {
    static let service = CBUUID(string: "31FF69C7-51D3-4241-AD2F-A4ADB116CD77")
    static let rx = CBUUID(string: "6292E318-9208-4000-8CD4-3A6EF318B275")     // frames to this Mac
    static let tx = CBUUID(string: "A4F81D3A-0BAA-4433-9D11-98BD9B97B79C")     // frames from this Mac

    // "mc1a2b3c4d" → the token; anything else → nil
    static func token(fromName name: String) -> UInt32? {
        guard name.count == 10, name.hasPrefix("mc"), let d = Hex.decode(String(name.dropFirst(2))), d.count == 4 else { return nil }
        return d.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    static func name(token: UInt32) -> String {
        "mc" + Hex.encode(Data([UInt8(token >> 24), UInt8(token >> 16 & 0xFF), UInt8(token >> 8 & 0xFF), UInt8(token & 0xFF)]))
    }
}

func radioState(_ s: CBManagerState) -> RadioState {
    switch s {
    case .poweredOn: return .on
    case .poweredOff: return .off
    case .unauthorized: return .unauthorized
    case .unsupported: return .unsupported
    case .resetting: return .resetting
    case .unknown: return .starting
    @unknown default: return .starting
    }
}

final class BLETransport: NSObject, LinkTransport {
    private final class OutLink {
        let id: Int
        let peripheral: CBPeripheral
        var rx: CBCharacteristic?
        var tx: CBCharacteristic?
        var open = false
        var queue: [Data] = []
        init(id: Int, peripheral: CBPeripheral) {
            self.id = id
            self.peripheral = peripheral
        }
    }

    private final class InLink {
        let id: Int
        let central: CBCentral
        var queue: [Data] = []
        init(id: Int, central: CBCentral) {
            self.id = id
            self.central = central
        }
    }

    private enum Ref {
        case out(UUID)
        case inbound(UUID)
    }

    static let maxQueue = 4096                  // frames waiting on one link before it counts as stuck

    weak var delegate: LinkTransportDelegate?
    var onLog: ((String) -> Void)?
    private(set) var state = RadioState.starting
    private let queue: DispatchQueue
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var token: UInt32 = 0
    private var wantScan = false
    private var wantAdvertise = false
    private var serviceReady = false
    private var txCharacteristic: CBMutableCharacteristic?
    private var known: [String: CBPeripheral] = [:]         // Macs seen advertising – CoreBluetooth drops what nobody holds
    private var outbound: [UUID: OutLink] = [:]             // by peripheral
    private var inbound: [UUID: InLink] = [:]               // by central
    private var ignored: Set<UUID> = []                     // centrals of links this Mac closed
    private var refs: [Int: Ref] = [:]
    private var nextID = 1

    // The delegate is called on this queue, and the transport must only be called there
    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
    }

    var peripheralState: RadioState { peripheralManager.map { radioState($0.state) } ?? .starting }

    private func log(_ s: String) { onLog?(s) }

    private func newID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    // ── LinkTransport ─────────────────────────────────────────

    func start(token: UInt32) {
        self.token = token
        guard centralManager == nil else { return }
        // creating the managers is what makes macOS ask for the permission
        centralManager = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        peripheralManager = CBPeripheralManager(delegate: self, queue: queue, options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
    }

    func stop() {
        wantScan = false
        wantAdvertise = false
        if let c = centralManager, c.state == .poweredOn {
            if c.isScanning { c.stopScan() }
            for link in outbound.values { c.cancelPeripheralConnection(link.peripheral) }
        }
        if let p = peripheralManager, p.state == .poweredOn {
            if p.isAdvertising { p.stopAdvertising() }
            p.removeAllServices()
        }
        centralManager?.delegate = nil
        peripheralManager?.delegate = nil
        outbound.removeAll()
        inbound.removeAll()
        refs.removeAll()
        known.removeAll()
        state = .off
    }

    func setScanning(_ on: Bool) {
        wantScan = on
        applyScanning()
    }

    func setAdvertising(_ on: Bool) {
        wantAdvertise = on
        applyAdvertising()
    }

    func connect(_ endpoint: String) {
        guard let c = centralManager, c.state == .poweredOn, let p = known[endpoint] else {
            queue.async { [weak self] in self?.delegate?.radio(connectFailed: endpoint, reason: "that Mac is no longer seen") }
            return
        }
        p.delegate = self
        c.connect(p, options: nil)
    }

    func cancelConnect(_ endpoint: String) {
        guard let c = centralManager, let p = known[endpoint], outbound[p.identifier]?.open != true else { return }
        if let link = outbound.removeValue(forKey: p.identifier) { refs[link.id] = nil }
        c.cancelPeripheralConnection(p)
    }

    func send(_ frame: Data, on id: Int) {
        switch refs[id] {
        case .out(let u)?:
            guard let link = outbound[u], link.open else { return }
            guard link.queue.count < BLETransport.maxQueue else { return close(id, reason: "the link is not keeping up") }
            link.queue.append(frame)
            flush(link)
        case .inbound(let u)?:
            guard let link = inbound[u] else { return }
            guard link.queue.count < BLETransport.maxQueue else { return close(id, reason: "the link is not keeping up") }
            link.queue.append(frame)
            flush(link)
        case nil:
            return
        }
    }

    func close(_ id: Int) { close(id, reason: "closed by this Mac") }

    private func close(_ id: Int, reason: String) {
        switch refs[id] {
        case .out(let u)?:
            // didDisconnectPeripheral tells the mesh
            if let link = outbound[u] { centralManager?.cancelPeripheralConnection(link.peripheral) }
        case .inbound(let u)?:
            // a peripheral cannot hang up: forget the link and ignore what still comes on it
            inbound[u] = nil
            refs[id] = nil
            ignored.insert(u)
            queue.async { [weak self] in self?.delegate?.radio(closed: id, reason: reason) }
        case nil:
            return
        }
    }

    func maxFrame(for id: Int) -> Int {
        switch refs[id] {
        case .out(let u)?: return outbound[u].map { maxWrite($0.peripheral) } ?? Proto.minFrame
        case .inbound(let u)?: return inbound[u].map { clamp($0.central.maximumUpdateValueLength) } ?? Proto.minFrame
        case nil: return Proto.minFrame
        }
    }

    private func clamp(_ n: Int) -> Int { max(Proto.minFrame, min(Proto.maxFrame, n)) }
    private func maxWrite(_ p: CBPeripheral) -> Int { clamp(p.maximumWriteValueLength(for: .withoutResponse)) }

    // ── State ─────────────────────────────────────────────────
    // The central decides: without it this Mac can neither find nor reach anyone. The peripheral role follows
    // when it can.

    private func updateState() {
        let new = radioState(centralManager?.state ?? .unknown)
        guard new != state else { return }
        state = new
        log("Bluetooth central: \(new.label), peripheral: \(peripheralState.label)")
        if new != .on { dropAll(reason: "Bluetooth is \(new.label)") }
        delegate?.radio(stateChanged: new)
    }

    private func dropAll(reason: String) {
        let ids = outbound.values.filter { $0.open }.map { $0.id } + inbound.values.map { $0.id }
        outbound.removeAll()
        inbound.removeAll()
        refs.removeAll()
        for id in ids { delegate?.radio(closed: id, reason: reason) }
    }

    private func applyScanning() {
        guard let c = centralManager, c.state == .poweredOn else { return }
        if wantScan {
            // a fresh scan, so that Macs seen before are reported again
            if c.isScanning { c.stopScan() }
            c.scanForPeripherals(withServices: [MeshService.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        } else if c.isScanning {
            c.stopScan()
        }
    }

    private func applyAdvertising() {
        guard let p = peripheralManager, p.state == .poweredOn, serviceReady else { return }
        if wantAdvertise && !p.isAdvertising {
            p.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [MeshService.service],
                                CBAdvertisementDataLocalNameKey: MeshService.name(token: token)])
        } else if !wantAdvertise && p.isAdvertising {
            p.stopAdvertising()
        }
    }

    private func publishService() {
        guard let p = peripheralManager else { return }
        serviceReady = false
        p.removeAllServices()
        let rx = CBMutableCharacteristic(type: MeshService.rx, properties: [.writeWithoutResponse], value: nil, permissions: [.writeable])
        let tx = CBMutableCharacteristic(type: MeshService.tx, properties: [.notify], value: nil, permissions: [.readable])
        let service = CBMutableService(type: MeshService.service, primary: true)
        service.characteristics = [rx, tx]
        txCharacteristic = tx
        p.add(service)
    }

    // ── Sending ───────────────────────────────────────────────

    private func flush(_ link: OutLink) {
        guard let rx = link.rx else { return }
        while let frame = link.queue.first, link.peripheral.canSendWriteWithoutResponse {
            link.peripheral.writeValue(frame, for: rx, type: .withoutResponse)
            link.queue.removeFirst()
        }
    }

    private func flush(_ link: InLink) {
        guard let p = peripheralManager, let tx = txCharacteristic else { return }
        while let frame = link.queue.first {
            // false: the queue for notifications is full – peripheralManagerIsReady(toUpdateSubscribers:) follows
            guard p.updateValue(frame, for: tx, onSubscribedCentrals: [link.central]) else { return }
            link.queue.removeFirst()
        }
    }

    private func failSetup(_ p: CBPeripheral, _ reason: String) {
        log("link setup with \(p.identifier.uuidString.prefix(8)) failed: \(reason)")
        if let link = outbound[p.identifier], !link.open {
            outbound[p.identifier] = nil
            refs[link.id] = nil
            delegate?.radio(connectFailed: p.identifier.uuidString, reason: reason)
        }
        centralManager?.cancelPeripheralConnection(p)
    }
}

// ── The central: finding and connecting ───────────────────────

extension BLETransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateState()
        applyScanning()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let endpoint = peripheral.identifier.uuidString
        if known[endpoint] == nil && known.count >= 64 {
            for (k, p) in known where outbound[p.identifier] == nil { known[k] = nil }
        }
        known[endpoint] = peripheral
        let token = (advertisementData[CBAdvertisementDataLocalNameKey] as? String).flatMap { MeshService.token(fromName: $0) }
        let rssi = RSSI.intValue
        delegate?.radio(sighted: Sighting(endpoint: endpoint, token: token, rssi: rssi == 127 ? -100 : rssi))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let link = OutLink(id: newID(), peripheral: peripheral)
        outbound[peripheral.identifier] = link
        refs[link.id] = .out(peripheral.identifier)
        peripheral.delegate = self
        peripheral.discoverServices([MeshService.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegate?.radio(connectFailed: peripheral.identifier.uuidString, reason: error?.localizedDescription ?? "the connection failed")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let link = outbound.removeValue(forKey: peripheral.identifier) else { return }
        refs[link.id] = nil
        let reason = error?.localizedDescription ?? "disconnected"
        if link.open {
            delegate?.radio(closed: link.id, reason: reason)
        } else {
            delegate?.radio(connectFailed: peripheral.identifier.uuidString, reason: reason)
        }
    }
}

// ── The central: the other Mac's service ──────────────────────

extension BLETransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == MeshService.service }) else {
            return failSetup(peripheral, error?.localizedDescription ?? "it has no MeshChat service")
        }
        peripheral.discoverCharacteristics([MeshService.rx, MeshService.tx], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let link = outbound[peripheral.identifier], let chars = service.characteristics,
              let rx = chars.first(where: { $0.uuid == MeshService.rx }), let tx = chars.first(where: { $0.uuid == MeshService.tx }) else {
            return failSetup(peripheral, error?.localizedDescription ?? "its MeshChat service is incomplete")
        }
        link.rx = rx
        link.tx = tx
        peripheral.setNotifyValue(true, for: tx)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == MeshService.tx, let link = outbound[peripheral.identifier], !link.open else { return }
        guard error == nil, characteristic.isNotifying else {
            return failSetup(peripheral, error?.localizedDescription ?? "it did not let this Mac subscribe")
        }
        link.open = true
        log("link \(link.id): connected to \(peripheral.identifier.uuidString.prefix(8)), frames of up to \(maxWrite(peripheral)) bytes")
        delegate?.radio(opened: LinkInfo(id: link.id, outbound: true, endpoint: peripheral.identifier.uuidString, maxFrame: maxWrite(peripheral)))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == MeshService.tx, let link = outbound[peripheral.identifier], link.open,
              let value = characteristic.value else { return }
        delegate?.radio(received: value, on: link.id)
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if let link = outbound[peripheral.identifier] { flush(link) }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // the other Mac took its service away: it quit, or its Bluetooth restarted
        guard invalidatedServices.contains(where: { $0.uuid == MeshService.service }), let link = outbound[peripheral.identifier] else { return }
        if link.open { close(link.id, reason: "the other Mac closed MeshChat") } else { failSetup(peripheral, "its service went away") }
    }
}

// ── The peripheral: being found, and links others make ────────

extension BLETransport: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        log("Bluetooth peripheral: \(radioState(peripheral.state).label)")
        if peripheral.state == .poweredOn {
            publishService()
        } else {
            serviceReady = false
            let ids = inbound.values.map { $0.id }
            inbound.removeAll()
            for id in ids {
                refs[id] = nil
                delegate?.radio(closed: id, reason: "Bluetooth is \(radioState(peripheral.state).label)")
            }
        }
        updateState()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            log("could not offer the MeshChat service: \(error.localizedDescription)")
            return
        }
        serviceReady = true
        applyAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error { log("could not advertise: \(error.localizedDescription)") }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == MeshService.tx else { return }
        ignored.remove(central.identifier)
        if let old = inbound.removeValue(forKey: central.identifier) {
            refs[old.id] = nil
            delegate?.radio(closed: old.id, reason: "it connected again")
        }
        let link = InLink(id: newID(), central: central)
        inbound[central.identifier] = link
        refs[link.id] = .inbound(central.identifier)
        log("link \(link.id): \(central.identifier.uuidString.prefix(8)) connected, frames of up to \(clamp(central.maximumUpdateValueLength)) bytes")
        delegate?.radio(opened: LinkInfo(id: link.id, outbound: false, endpoint: central.identifier.uuidString,
                                         maxFrame: clamp(central.maximumUpdateValueLength)))
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic.uuid == MeshService.tx else { return }
        ignored.remove(central.identifier)
        guard let link = inbound.removeValue(forKey: central.identifier) else { return }
        refs[link.id] = nil
        delegate?.radio(closed: link.id, reason: "the other Mac disconnected")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // RX allows only writes without response: there is nothing to answer
        for r in requests where r.characteristic.uuid == MeshService.rx {
            guard let value = r.value, !ignored.contains(r.central.identifier), let link = inbound[r.central.identifier] else { continue }
            delegate?.radio(received: value, on: link.id)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        for link in inbound.values { flush(link) }
    }
}

// ── For lotus meshchat doctor ─────────────────────────────────
// Starts both managers, waits for their state, and says what it found. Run in a process of its own: when the
// terminal app does not declare Bluetooth use, macOS ends the process that tries.

final class BluetoothProbe: NSObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate {
    private let queue = DispatchQueue(label: "meshchat.probe")
    private let done = DispatchSemaphore(value: 0)
    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var centralState = CBManagerState.unknown
    private var peripheralState = CBManagerState.unknown

    static func authorization() -> String {
        switch CBManager.authorization {
        case .allowedAlways: return "allowed"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not-determined"
        @unknown default: return "unknown"
        }
    }

    // → key=value lines: authorization, central, peripheral (on, off, not allowed, …)
    func run(timeout: TimeInterval) -> [String: String] {
        var out = ["authorization": BluetoothProbe.authorization()]
        queue.sync {
            central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            peripheral = CBPeripheralManager(delegate: self, queue: queue, options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            _ = done.wait(timeout: .now() + 0.2)
            let ready = queue.sync { centralState != .unknown && peripheralState != .unknown }
            if ready { break }
        }
        queue.sync {
            out["central"] = radioState(centralState).label
            out["peripheral"] = radioState(peripheralState).label
        }
        out["authorization-after"] = BluetoothProbe.authorization()
        return out
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        centralState = central.state
        done.signal()
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        peripheralState = peripheral.state
        done.signal()
    }
}
#endif
