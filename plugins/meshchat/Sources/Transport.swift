// MeshChat – what the mesh needs from a radio: find Macs with MeshChat nearby, connect, and move frames over the
// links. The real one is Bluetooth LE (BLETransport.swift); the tests and `lotus meshchat demo` use a simulated one
// (SimTransport.swift). The mesh (Mesh.swift) works the same on both and never learns which one it has.
// A radio calls its delegate on the mesh's queue, and is only called there.

import Foundation

enum RadioState: Equatable {
    case starting           // not known yet – macOS may be asking whether the terminal may use Bluetooth
    case on
    case off                // Bluetooth is turned off
    case unauthorized       // the permission was denied
    case unsupported        // no Bluetooth LE on this Mac
    case resetting

    var label: String {
        switch self {
        case .starting: return "starting"
        case .on: return "on"
        case .off: return "off"
        case .unauthorized: return "not allowed"
        case .unsupported: return "not available"
        case .resetting: return "restarting"
        }
    }
}

struct LinkInfo {
    let id: Int
    let outbound: Bool      // true: we connected to them (central) · false: they connected to us (peripheral)
    let endpoint: String    // the other Mac as the radio knows it (a Bluetooth identifier – it changes now and then)
    let maxFrame: Int       // the most one frame may have on this link
}

// A Mac with MeshChat that the radio heard advertising
struct Sighting {
    let endpoint: String
    let token: UInt32?      // from its advertised name: the first 4 bytes of its session (nil when not heard)
    let rssi: Int
}

protocol LinkTransportDelegate: AnyObject {
    func radio(stateChanged state: RadioState)
    func radio(sighted: Sighting)
    func radio(opened link: LinkInfo)
    func radio(closed link: Int, reason: String)
    func radio(received frame: Data, on link: Int)
    func radio(connectFailed endpoint: String, reason: String)
    func radio(signal rssi: Int, on link: Int)  // how strong the other Mac of a link arrives (after measureSignal)
}

extension LinkTransportDelegate {
    func radio(signal rssi: Int, on link: Int) {}
}

protocol LinkTransport: AnyObject {
    var delegate: LinkTransportDelegate? { get set }
    var state: RadioState { get }
    func start(token: UInt32)               // advertise with this token in the name, once the radio is on
    func stop()                             // everything off: no advertising, no scanning, every link closed
    func setScanning(_ on: Bool)            // on again: a fresh scan, so Macs already seen are reported again
    func setAdvertising(_ on: Bool)
    func connect(_ endpoint: String)
    func cancelConnect(_ endpoint: String)
    func send(_ frame: Data, on link: Int)  // in order; the radio waits while the link is busy
    func close(_ link: Int)                 // the radio answers with radio(closed:)
    func maxFrame(for link: Int) -> Int
    func measureSignal(on link: Int)        // answered with radio(signal:on:) – where the radio can measure it
}

extension LinkTransport {
    func measureSignal(on link: Int) {}
}
