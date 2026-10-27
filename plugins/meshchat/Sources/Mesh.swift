// MeshChat – the mesh: links to Macs nearby, the handshake, flooding with duplicate detection and a hop limit, the
// room's encryption, who is in the room and what they say. Runs on one queue; the radio calls it there.
//
// Routing is managed flooding – there is no central server and no routing table:
//   1. A message goes to every neighbour (a Mac with a link to this one).
//   2. A Mac that gets a packet looks at its ID: seen in the last 30 minutes → dropped (a loop, a second path).
//   3. Otherwise it opens it with the room key and checks the signature and the age (≤ 15 minutes). A packet that
//      fails is dropped and never passed on – nobody relays what they could not check.
//   4. It shows the message and passes the packet to all its other neighbours with ttl - 1 and hops + 1.
//      ttl 0 is not passed on; ttl + hops is at most 7, so no message travels more than 7 relays.
//   5. A neighbour that connects gets the room's last 32 packets (ones younger than 15 minutes): a Mac that was out
//      of range for a moment catches up, and the duplicate check keeps everyone else from seeing them twice.
// Links: every Mac advertises and scans. When two see each other, the one with the smaller token (4 random bytes
// in its advertised name) connects; the other waits 8 seconds before it tries itself. Should both connect at once,
// the link whose central has the smaller session is kept and the other one closed – both Macs decide alike.

import Foundation

struct MeshConfig {
    var hops = Proto.defaultHops                // how many relays a new message may take (1–7)
    var maxLinks = 8                            // Bluetooth links at most (each costs the radio time)
    var relayForeign = false                    // also pass on packets of other rooms, unread (relay mode)
    var presenceInterval: TimeInterval = 30     // "I am here" to the room
    var awayAfter: TimeInterval = 80            // not heard for so long: away
    var forgetAfter: TimeInterval = 600         // … and gone from the list
    var pingInterval: TimeInterval = 15         // a quiet link is asked whether it is still there
    var linkTimeout: TimeInterval = 45          // a link silent for so long is closed
    var helloTimeout: TimeInterval = 10
    var connectTimeout: TimeInterval = 15
    var maxBackoff: TimeInterval = 60           // between attempts to reach a Mac that does not answer
    var maxAge: TimeInterval = 15 * 60          // older messages are refused …
    var maxSkew: TimeInterval = 10 * 60         // … and ones from that far in the future (clocks that differ)
    var catchUp = 32                            // recent room packets a new neighbour gets
    var initiatorGrace: TimeInterval = 8        // the Mac with the larger token waits so long for the other one
    var sightingExpiry: TimeInterval = 120      // a Mac not heard advertising for so long is forgotten
    var scanOnLinked: TimeInterval = 10         // scanning once linked: 10 s of every 30 s
    var scanOffLinked: TimeInterval = 20
    var scanOnAlone: TimeInterval = 25          // with no link: nearly always, restarted every 27 s
    var scanOffAlone: TimeInterval = 2
}

struct ChatMessage: Equatable {
    let id: UInt64
    let nickname: String
    let fingerprint: String
    let text: String
    let sent: TimeInterval          // the sender's clock
    let received: TimeInterval      // this Mac's
    let hops: Int                   // relays it took – 0: from a neighbour (or this Mac)
    let mine: Bool
}

struct Participant: Equatable {
    let key: Data
    let fingerprint: String
    var nickname: String
    var session: Data
    var lastSeen: TimeInterval
    var hops: Int                   // relays the last packet took
    var links: Int                  // how many Macs it said it is connected to
    var direct = false              // a link to this Mac right now
    var left = false                // said goodbye
    var away = false                // not heard for a while
}

struct MeshStats: Equatable {
    var framesIn = 0, framesOut = 0
    var delivered = 0               // messages shown (or presence taken in)
    var relayed = 0                 // packets passed on
    var duplicates = 0
    var malformed = 0
    var authFailed = 0              // failed the room key or the signature
    var expired = 0                 // too old, or from the future
    var foreign = 0                 // other rooms' packets, not passed on
    var rateLimited = 0
    var incompatible = 0
    var connectFailures = 0
    var caughtUp = 0                // packets sent to a neighbour that connected
}

struct MeshSnapshot {
    var radio: RadioState = .starting
    var links = 0                   // ready links
    var connecting = 0
    var participants: [Participant] = []        // the others, by name
    var scanning = false
    var advertising = false
    var stats = MeshStats()
    var roomName = ""
}

struct Notice: Equatable {
    enum Level { case info, warning, error }
    let level: Level
    let text: String
}

enum MeshEvent {
    case message(ChatMessage)       // someone wrote (or this Mac did)
    case sent(id: UInt64, links: Int)               // a message of ours left on so many links
    case notice(Notice)
    case roomName(String)           // learned from the others
    case snapshot(MeshSnapshot)
    case log(String)                // for the diagnostics log: never secrets or what people wrote
}

struct TokenBucket {
    let capacity: Double
    let rate: Double
    private var tokens: Double
    private var last: TimeInterval?

    init(capacity: Double, rate: Double) {
        self.capacity = capacity
        self.rate = rate
        tokens = capacity
    }

    mutating func take(_ now: TimeInterval) -> Bool {
        if let l = last { tokens = min(capacity, tokens + max(0, now - l) * rate) }
        last = now
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}

final class MeshNode: LinkTransportDelegate {
    private final class Link {
        enum State { case hello, ready, redundant, closed }
        let id: Int
        let outbound: Bool
        let endpoint: String
        var state = State.hello
        var session: Data?          // set by the handshake
        var software = ""
        var closeReason: String?
        var pruned = false          // a second link to the same Mac, closed on purpose
        let helloDeadline: TimeInterval
        var lastHeard: TimeInterval
        var lastSent: TimeInterval
        var seq: UInt16 = 0
        let reassembler = Reassembler()
        var frames = TokenBucket(capacity: 300, rate: 150)    // frames a second it may send us
        var packets = TokenBucket(capacity: 40, rate: 15)     // whole packets a second

        init(_ info: LinkInfo, now: TimeInterval, helloTimeout: TimeInterval) {
            id = info.id
            outbound = info.outbound
            endpoint = info.endpoint
            helloDeadline = now + helloTimeout
            lastHeard = now
            lastSent = now
        }

        func nextSeq() -> UInt16 {
            seq = seq &+ 1
            return seq
        }
    }

    private struct Candidate {
        let endpoint: String
        var token: UInt32?
        var rssi: Int
        let firstSeen: TimeInterval
        var lastSeen: TimeInterval
        var connectingSince: TimeInterval?
        var failures = 0
        var nextAttempt: TimeInterval = 0
    }

    private struct Recent {
        let packet: MeshPacket
        let mine: Bool
    }

    private struct ActiveRoom {
        let keys: RoomKeys
        let crypto: RoomCrypto
        var name: String
    }

    let transport: LinkTransport
    var config: MeshConfig
    let session: Data
    let token: UInt32
    private(set) var nickname: String
    private let clock: () -> TimeInterval
    private let emit: (MeshEvent) -> Void

    private var room: ActiveRoom?
    private var links: [Int: Link] = [:]
    private var candidates: [String: Candidate] = [:]
    private var endpointSessions: [String: Data] = [:]
    private var dedup = DedupCache()
    private var recent: [Recent] = []
    private var people: [Data: Participant] = [:]
    private var undelivered: Set<UInt64> = []
    private var presenceDue = TimeInterval.infinity
    private var lastPresence = -TimeInterval.infinity
    private var noticed: [String: TimeInterval] = [:]
    private var foreignBucket = TokenBucket(capacity: 20, rate: 5)
    private var scanEpoch: TimeInterval = 0
    private var scanning = false
    private var advertising = false
    private var running = false
    private var dirty = true
    private(set) var stats = MeshStats()

    init(transport: LinkTransport, config: MeshConfig = MeshConfig(), nickname: String,
         clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
         events: @escaping (MeshEvent) -> Void) {
        self.transport = transport
        self.config = config
        self.nickname = Sanitize.nickname(nickname).isEmpty ? "anon" : Sanitize.nickname(nickname)
        self.clock = clock
        emit = events
        session = CryptoBackend.randomBytes(Proto.sessionLength)
        token = session.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        transport.delegate = self
    }

    var roomID: String? { room?.keys.id }
    var roomName: String { room?.name ?? "" }
    var fingerprint: String? { room?.crypto.signer.fingerprint }
    var readyLinks: Int { links.values.filter { $0.state == .ready }.count }

    // ── Starting, rooms, speaking ─────────────────────────────

    func start() {
        guard !running else { return }
        running = true
        scanEpoch = clock()
        transport.start(token: token)
        flush()
    }

    // Goodbye to the room and every neighbour; the radio goes off with stop()
    func goodbye() {
        if room != nil { _ = try? flood(kind: .bye) }
        for link in links.values where link.state == .ready { sendFrame(.bye(ByeReason.leaving.rawValue), on: link) }
    }

    // IDs of messages this Mac has already (its history): copies that come again are not shown twice
    func markSeen(_ ids: [UInt64]) {
        let t = clock()
        for id in ids { dedup.insert(id, now: t) }
    }

    func stop() {
        guard running else { return }
        running = false
        transport.stop()
        links.removeAll()
        candidates.removeAll()
        scanning = false
        advertising = false
        dirty = true
        flush()
    }

    // Into a room: its keys, and this Mac's signing key there (from its identity)
    func enter(secret: RoomSecret, name: String, identity: Data) throws {
        if room != nil { _ = try? flood(kind: .bye) }     // the links stay: they carry any room
        let keys = RoomKeys(secret: secret)
        room = ActiveRoom(keys: keys, crypto: RoomCrypto(keys: keys, signer: try Signer(identity: identity, room: keys)),
                          name: Sanitize.roomName(name))
        people.removeAll()
        recent.removeAll()
        undelivered.removeAll()
        lastPresence = -.infinity
        presenceDue = clock() + 0.5         // "who is here?" right away
        dirty = true
        flush()
    }

    func leaveRoom() {
        if room != nil { _ = try? flood(kind: .bye) }
        room = nil
        people.removeAll()
        recent.removeAll()
        presenceDue = .infinity
        dirty = true
        flush()
    }

    func rename(_ name: String) {
        let clean = Sanitize.nickname(name)
        guard !clean.isEmpty else { return }
        nickname = clean
        if room != nil { sendPresence(request: false) }
        flush()
    }

    enum SendError: Error, CustomStringConvertible {
        case noRoom, empty, tooLong
        var description: String {
            switch self {
            case .noRoom: return "You are in no room."
            case .empty: return "There is nothing to send."
            case .tooLong: return "A message can be up to \(Proto.maxTextBytes) bytes long – that is about \(Proto.maxTextBytes) letters, fewer with emoji or accents."
            }
        }
    }

    @discardableResult
    func send(_ text: String) throws -> ChatMessage {
        guard let room = room else { throw SendError.noRoom }
        let clean = Sanitize.line(text, characters: Int.max, bytes: Int.max)
        guard !clean.isEmpty else { throw SendError.empty }
        guard clean.utf8.count <= Proto.maxTextBytes else { throw SendError.tooLong }
        let (packet, links) = try flood(kind: .chat, text: clean)
        let msg = ChatMessage(id: packet.messageID, nickname: nickname, fingerprint: room.crypto.signer.fingerprint, text: clean,
                              sent: Double(packet.timestamp) / 1000, received: clock(), hops: 0, mine: true)
        stats.delivered += 1
        emit(.message(msg))
        emit(.sent(id: packet.messageID, links: links))
        flush()
        return msg
    }

    // ── The radio ─────────────────────────────────────────────

    func radio(stateChanged state: RadioState) {
        log("Bluetooth: \(state.label)")
        if state == .on {
            scanEpoch = clock()
            scanning = false
            advertising = false
        } else {
            for k in candidates.keys { candidates[k]?.connectingSince = nil }
            scanning = false
            advertising = false
        }
        manageRadio(clock())
        dirty = true
        flush()
    }

    func radio(sighted s: Sighting) {
        let t = clock()
        if var c = candidates[s.endpoint] {
            c.lastSeen = t
            c.rssi = s.rssi
            if s.token != nil { c.token = s.token }
            candidates[s.endpoint] = c
        } else {
            candidates[s.endpoint] = Candidate(endpoint: s.endpoint, token: s.token, rssi: s.rssi, firstSeen: t, lastSeen: t)
            log("sighted a Mac with MeshChat (\(short(s.endpoint)), signal \(s.rssi) dBm)")
        }
        connectCandidates(t)
        flush()
    }

    func radio(opened info: LinkInfo) {
        let t = clock()
        let link = Link(info, now: t, helloTimeout: config.helloTimeout)
        links[info.id] = link
        if info.outbound, candidates[info.endpoint] != nil {
            candidates[info.endpoint]?.connectingSince = nil
            candidates[info.endpoint]?.failures = 0
        }
        log("link \(info.id) open – \(info.outbound ? "this Mac connected" : "the other Mac connected"), frames of up to \(info.maxFrame) bytes")
        if links.values.filter({ $0.state != .closed }).count > config.maxLinks {
            sendFrame(.bye(ByeReason.full.rawValue), on: link)
            closeLink(link, reason: "too many links")
        } else {
            sendFrame(.hello(Hello(session: session, flags: config.relayForeign ? Hello.relayFlag : 0)), on: link)
        }
        dirty = true
        flush()
    }

    func radio(closed id: Int, reason: String) {
        guard let link = links.removeValue(forKey: id) else { return }
        let t = clock()
        let wasReady = link.session != nil && !link.pruned
        let reason = link.closeReason ?? reason
        log("link \(id) closed: \(reason)")
        if link.outbound, var c = candidates[link.endpoint] {
            c.connectingSince = nil
            // a Mac that was there a moment ago: try again soon, it may only have moved a little
            c.nextAttempt = t + (wasReady ? 2 : backoff(c.failures))
            candidates[link.endpoint] = c
        }
        if wasReady, let s = link.session, !links.values.contains(where: { $0.state == .ready && $0.session == s }) {
            if let p = people.values.first(where: { $0.session == s }), !p.left {
                notice("The Bluetooth link to \(p.nickname) ended (\(reason)) – the mesh may still reach \(p.nickname) through others.")
            }
        }
        dirty = true
        flush()
    }

    func radio(received frame: Data, on id: Int) {
        guard let link = links[id], link.state != .closed else { return }
        let t = clock()
        link.lastHeard = t
        stats.framesIn += 1
        guard link.frames.take(t) else {
            stats.rateLimited += 1
            return
        }
        let decoded: LinkFrame
        do {
            decoded = try LinkFrame.decode(frame)
        } catch WireError.unsupportedVersion(let v) {
            stats.incompatible += 1
            noticeOnce("link-version-\(v)", "A Mac nearby speaks a newer MeshChat (link protocol \(v)) – update this one: lotus plugin update meshchat", .warning)
            return
        } catch {
            stats.malformed += 1
            return
        }
        switch decoded {
        case .hello(let h):
            hello(h, on: link)
        case let .data(seq, index, count, payload):
            guard link.state == .ready else {
                stats.malformed += 1         // data before the handshake, or on a link that is going
                break
            }
            switch link.reassembler.add(seq: seq, index: index, count: count, payload: payload, now: t) {
            case .complete(let packet): received(packet, from: link)
            case .incomplete: break
            case .duplicate: stats.duplicates += 1
            case .rejected: stats.malformed += 1
            }
        case .ping:
            sendFrame(.pong, on: link)
        case .pong:
            break
        case .bye(let reason):
            log("link \(id): the other Mac ended it (reason \(reason))")
            closeLink(link, reason: reason == ByeReason.leaving.rawValue ? "it left" : "it ended the link")
        }
        flush()
    }

    func radio(connectFailed endpoint: String, reason: String) {
        failed(endpoint, reason: reason)
        flush()
    }

    private func failed(_ endpoint: String, reason: String) {
        guard var c = candidates[endpoint] else { return }
        c.connectingSince = nil
        c.failures += 1
        c.nextAttempt = clock() + backoff(c.failures)
        candidates[endpoint] = c
        stats.connectFailures += 1
        log("could not connect to \(short(endpoint)): \(reason) (attempt \(c.failures))")
        dirty = true
    }

    // Once a second: timeouts, pings, scanning, connecting, "I am here", who is away
    func tick() {
        guard running else { return }
        let t = clock()
        for link in Array(links.values) {
            if link.state == .hello && t > link.helloDeadline {
                closeLink(link, reason: "no handshake")
            } else if link.state != .closed && t - link.lastHeard > config.linkTimeout {
                closeLink(link, reason: "no answer for \(Int(config.linkTimeout)) seconds")
            } else if link.state == .ready && t - link.lastSent >= config.pingInterval {
                sendFrame(.ping, on: link)
            }
            link.reassembler.expire(now: t)
        }
        connectCandidates(t)
        manageRadio(t)
        if room != nil && t >= presenceDue { sendPresence(request: lastPresence == -.infinity) }
        age(t)
        dirty = true
        flush()
    }

    // ── Links ─────────────────────────────────────────────────

    private func hello(_ h: Hello, on link: Link) {
        guard link.state == .hello else { return }
        guard h.minVersion <= Proto.version && h.maxVersion >= Proto.version else {
            stats.incompatible += 1
            if h.minVersion > Proto.version {
                noticeOnce("newer-\(h.minVersion)", "A Mac nearby runs a newer MeshChat (protocol \(h.minVersion)) – update this one to chat with it: lotus plugin update meshchat", .warning)
            } else {
                noticeOnce("older-\(h.maxVersion)", "A Mac nearby runs an older MeshChat (protocol \(h.maxVersion)) – it needs an update to chat with this one.", .warning)
            }
            sendFrame(.bye(ByeReason.incompatible.rawValue), on: link)
            closeLink(link, reason: "no protocol version in common")
            return
        }
        guard h.session != session else {
            closeLink(link, reason: "this Mac itself")
            return
        }
        link.session = h.session
        link.software = h.software
        link.state = .ready
        endpointSessions[link.endpoint] = h.session
        log("link \(link.id) ready (\(h.software))")
        guard keepOne(of: link) else { return }
        catchUp(link)
        if room != nil { presenceDue = min(presenceDue, clock() + 1) }
        dirty = true
    }

    // Two links to the same Mac: keep the one whose central has the smaller session, close the others. Both Macs
    // decide alike. false when `link` itself is one that goes.
    private func keepOne(of link: Link) -> Bool {
        let same = links.values.filter { $0.state == .ready && $0.session == link.session }
        guard same.count > 1 else { return true }
        func preferred(_ l: Link) -> Bool {
            guard let remote = l.session else { return false }
            return l.outbound ? session.lexicographicallyPrecedes(remote) : remote.lexicographicallyPrecedes(session)
        }
        let keep = same.min { a, b in preferred(a) != preferred(b) ? preferred(a) : a.id < b.id }!
        for other in same where other !== keep {
            log("link \(other.id) is a second link to the same Mac – closed")
            sendFrame(.bye(ByeReason.redundant.rawValue), on: other)
            other.state = .redundant
            other.pruned = true
            if other.outbound { closeLink(other, reason: "a second link to the same Mac") }
        }
        return keep === link
    }

    private func closeLink(_ link: Link, reason: String) {
        guard link.state != .closed else { return }
        link.closeReason = link.closeReason ?? reason
        link.state = .closed
        dirty = true
        transport.close(link.id)
    }

    private func sendFrame(_ frame: LinkFrame, on link: Link) {
        guard link.state != .closed else { return }
        transport.send(frame.encode(), on: link.id)
        link.lastSent = clock()
        stats.framesOut += 1
    }

    private func sendPacket(_ packet: MeshPacket, on link: Link) {
        guard link.state == .ready else { return }
        do {
            for f in try Fragmenter.frames(for: packet.encode(), seq: link.nextSeq(), maxFrame: transport.maxFrame(for: link.id)) {
                transport.send(f, on: link.id)
                stats.framesOut += 1
            }
            link.lastSent = clock()
        } catch {
            log("could not send on link \(link.id): \(error)")
        }
    }

    private func isLinked(session s: Data) -> Bool {
        links.values.contains { $0.state == .ready && $0.session == s }
    }

    private func shouldConnect(_ c: Candidate, _ t: TimeInterval) -> Bool {
        if links.values.contains(where: { $0.endpoint == c.endpoint && $0.outbound }) { return false }
        if let s = endpointSessions[c.endpoint], isLinked(session: s) { return false }
        if let theirs = c.token {
            let linkedTokens = links.values.compactMap { l -> UInt32? in
                guard l.state != .closed, let s = l.session else { return nil }
                return s.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            }
            if linkedTokens.contains(theirs) { return false }
            if theirs == token { return t - c.firstSeen > 30 }            // the same 4 bytes as ours: very rare
            if theirs < token && t - c.firstSeen < config.initiatorGrace { return false }    // theirs connects
        }
        return true
    }

    private func connectCandidates(_ t: TimeInterval) {
        guard running, transport.state == .on else { return }
        for (endpoint, c) in candidates {
            if let since = c.connectingSince, t - since > config.connectTimeout {
                transport.cancelConnect(endpoint)
                failed(endpoint, reason: "no answer within \(Int(config.connectTimeout)) seconds")
            } else if c.connectingSince == nil && t - c.lastSeen > config.sightingExpiry
                        && !links.values.contains(where: { $0.endpoint == endpoint }) {
                candidates[endpoint] = nil
            }
        }
        var busy = links.values.filter { $0.state != .closed }.count + candidates.values.filter { $0.connectingSince != nil }.count
        for c in candidates.values.sorted(by: { $0.rssi > $1.rssi }) {
            guard busy < config.maxLinks else { break }
            guard c.connectingSince == nil, t >= c.nextAttempt, shouldConnect(c, t) else { continue }
            candidates[c.endpoint]?.connectingSince = t
            busy += 1
            log("connecting to \(short(c.endpoint))")
            transport.connect(c.endpoint)
        }
    }

    private func backoff(_ failures: Int) -> TimeInterval {
        min(config.maxBackoff, 2 * pow(2, Double(max(0, failures - 1))))
    }

    // Advertising while there is room for another link; scanning in bursts – nearly always while alone, a third of
    // the time once linked, never when full
    private func manageRadio(_ t: TimeInterval) {
        guard running, transport.state == .on else { return }
        let open = links.values.filter { $0.state != .closed }.count
        let full = open >= config.maxLinks
        if advertising != !full {
            advertising = !full
            transport.setAdvertising(advertising)
        }
        let alone = readyLinks == 0
        let on = alone ? config.scanOnAlone : config.scanOnLinked
        let cycle = on + (alone ? config.scanOffAlone : config.scanOffLinked)
        let want = !full && (t - scanEpoch).truncatingRemainder(dividingBy: cycle) < on
        if want != scanning {
            scanning = want
            transport.setScanning(want)
        }
    }

    // ── Packets ───────────────────────────────────────────────

    private func received(_ bytes: Data, from link: Link) {
        let t = clock()
        guard link.packets.take(t) else {
            stats.rateLimited += 1
            return
        }
        let packet: MeshPacket
        do {
            packet = try MeshPacket.decode(bytes)
        } catch WireError.unsupportedVersion(let v) {
            stats.incompatible += 1
            noticeOnce("packet-version-\(v)", "A Mac nearby sends messages of a newer MeshChat (protocol \(v)) – update this one: lotus plugin update meshchat", .warning)
            return
        } catch {
            stats.malformed += 1
            return
        }
        guard !dedup.contains(packet.messageID, now: t) else {
            stats.duplicates += 1
            return
        }
        guard let room = room, packet.roomTag == room.keys.tag else {
            relayForeign(packet, from: link, now: t)
            return
        }
        let inner: InnerMessage
        do {
            inner = try room.crypto.open(packet)
        } catch {
            // not remembered as seen: a forged copy must not keep the real message out
            stats.authFailed += 1
            noticeOnce("auth", "Ignored a damaged or forged packet for this room – it was not shown and not passed on.", .warning, every: 120)
            return
        }
        dedup.insert(packet.messageID, now: t)
        let sent = Double(packet.timestamp) / 1000
        if t - sent > config.maxAge || sent - t > config.maxSkew {
            stats.expired += 1
            let minutes = Int((sent - t) / 60)
            noticeOnce("clock-\(Hex.encode(inner.senderKey))",
                       "Ignored a message from \(inner.nickname) dated \(abs(minutes)) minutes \(minutes > 0 ? "ahead" : "ago") – if it was just sent, the clocks of the two Macs differ: check the date and time in System Settings.",
                       .warning, every: 300)
            return
        }
        remember(packet, mine: false)
        deliver(inner, packet: packet, now: t)
        if let next = packet.relayed() {
            let n = forward(next, except: link)
            if n > 0 { stats.relayed += 1 }
        }
    }

    // A packet of a room this Mac is not in: passed on unread in relay mode, never looked into
    private func relayForeign(_ packet: MeshPacket, from link: Link, now t: TimeInterval) {
        stats.foreign += 1
        guard config.relayForeign else { return }
        let sent = Double(packet.timestamp) / 1000
        guard t - sent <= config.maxAge, sent - t <= config.maxSkew, foreignBucket.take(t) else { return }
        dedup.insert(packet.messageID, now: t)
        if let next = packet.relayed(), forward(next, except: link) > 0 { stats.relayed += 1 }
    }

    @discardableResult
    private func forward(_ packet: MeshPacket, except: Link?) -> Int {
        var n = 0
        for l in links.values where l.state == .ready && l !== except {
            sendPacket(packet, on: l)
            n += 1
        }
        return n
    }

    // A new message of this Mac to the whole room → the packet and how many links it left on
    @discardableResult
    private func flood(kind: InnerKind, text: String = "", request: Bool = false) throws -> (MeshPacket, Int) {
        guard let room = room else { throw SendError.noRoom }
        let inner = InnerMessage(kind: kind, flags: request ? InnerMessage.requestFlag : 0, senderKey: room.crypto.signer.publicKey,
                                 session: session, nickname: nickname, text: text, roomName: room.name,
                                 links: UInt8(min(255, readyLinks)))
        var id: UInt64 = 0
        repeat { id = CryptoBackend.randomBytes(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) } } while id == 0
        let packet = try room.crypto.seal(inner, ttl: UInt8(max(1, min(Int(Proto.hopLimit), config.hops))), messageID: id,
                                          timestamp: UInt64(max(0, clock() * 1000)))
        dedup.insert(id, now: clock())
        remember(packet, mine: true)
        let n = forward(packet, except: nil)
        if n == 0 && kind == .chat { undelivered.insert(id) }
        return (packet, n)
    }

    private func sendPresence(request: Bool) {
        guard room != nil else { return }
        _ = try? flood(kind: .presence, request: request)
        lastPresence = clock()
        presenceDue = clock() + config.presenceInterval * Double.random(in: 0.8...1.2)
    }

    private func remember(_ packet: MeshPacket, mine: Bool) {
        recent.append(Recent(packet: packet, mine: mine))
        if recent.count > config.catchUp { recent.removeFirst(recent.count - config.catchUp) }
    }

    // What a new neighbour may have missed: the room's recent packets, as they would have been passed on
    private func catchUp(_ link: Link) {
        let t = clock()
        var n = 0
        for r in recent where t - Double(r.packet.timestamp) / 1000 < config.maxAge - 60 {
            guard let p = r.mine ? r.packet : r.packet.relayed() else { continue }
            sendPacket(p, on: link)
            n += 1
            if undelivered.remove(r.packet.messageID) != nil { emit(.sent(id: r.packet.messageID, links: 1)) }
        }
        if n > 0 {
            stats.caughtUp += n
            log("link \(link.id): sent the \(n) most recent packets of the room")
        }
    }

    // ── People ────────────────────────────────────────────────

    private func deliver(_ inner: InnerMessage, packet: MeshPacket, now t: TimeInterval) {
        guard var room = room else { return }
        let sent = Double(packet.timestamp) / 1000
        let fingerprint = Signer.fingerprint(of: inner.senderKey)
        if inner.senderKey == room.crypto.signer.publicKey {
            // this Mac's own, from before it was restarted: a neighbour still had it
            if inner.kind == .chat {
                emit(.message(ChatMessage(id: packet.messageID, nickname: inner.nickname, fingerprint: fingerprint, text: inner.text,
                                          sent: sent, received: t, hops: Int(packet.hops), mine: true)))
            }
            return
        }
        let seen = t - sent < 60 ? t : min(t, sent)            // a late packet does not make someone "here"
        var p = people[inner.senderKey] ?? Participant(key: inner.senderKey, fingerprint: fingerprint, nickname: inner.nickname,
                                                       session: inner.session, lastSeen: -.infinity, hops: Int(packet.hops), links: 0)
        let isNew = people[inner.senderKey] == nil || p.left || p.away
        let fresh = seen >= p.lastSeen
        if fresh {
            if p.nickname != inner.nickname && people[inner.senderKey] != nil && inner.kind != .bye {
                notice("\(p.nickname) is now called \(inner.nickname).")
            }
            p.nickname = inner.nickname
            p.session = inner.session
            p.lastSeen = seen
            p.hops = Int(packet.hops)
            p.away = t - seen > config.awayAfter
            if inner.kind == .presence { p.links = Int(inner.links) }
            p.left = inner.kind == .bye
        }
        people[inner.senderKey] = p
        stats.delivered += 1
        switch inner.kind {
        case .chat:
            emit(.message(ChatMessage(id: packet.messageID, nickname: inner.nickname, fingerprint: fingerprint, text: inner.text,
                                      sent: sent, received: t, hops: Int(packet.hops), mine: false)))
        case .presence:
            if room.name.isEmpty && !inner.roomName.isEmpty {
                room.name = inner.roomName
                self.room = room
                emit(.roomName(inner.roomName))
            }
            if inner.flags & InnerMessage.requestFlag != 0 && clock() - lastPresence > 5 {
                presenceDue = min(presenceDue, t + Double.random(in: 0.3...2))
            }
        case .bye:
            if fresh { notice("\(inner.nickname) left the chat.") }
        }
        if isNew && fresh && !p.left && !p.away {
            let how = p.hops == 0 ? "a neighbour" : "\(p.hops) relay\(p.hops == 1 ? "" : "s") away"
            notice("\(inner.nickname) is here – \(how).")
        }
        dirty = true
    }

    private func age(_ t: TimeInterval) {
        for (key, var p) in people {
            if (p.left && t - p.lastSeen > 120) || t - p.lastSeen > config.forgetAfter {
                people[key] = nil
                continue
            }
            let away = !p.left && t - p.lastSeen > config.awayAfter
            if away && !p.away { notice("\(p.nickname) has not been heard for a while – out of range?") }
            p.away = away
            people[key] = p
        }
    }

    // ── Telling the app ───────────────────────────────────────

    func snapshot() -> MeshSnapshot {
        let direct = Set(links.values.filter { $0.state == .ready }.compactMap { $0.session })
        var list = Array(people.values)
        for i in list.indices { list[i].direct = direct.contains(list[i].session) && !list[i].left }
        list.sort { $0.nickname.lowercased() != $1.nickname.lowercased() ? $0.nickname.lowercased() < $1.nickname.lowercased() : $0.fingerprint < $1.fingerprint }
        return MeshSnapshot(radio: transport.state, links: readyLinks, connecting: candidates.values.filter { $0.connectingSince != nil }.count,
                            participants: list, scanning: scanning, advertising: advertising, stats: stats, roomName: room?.name ?? "")
    }

    private func flush() {
        guard dirty else { return }
        dirty = false
        emit(.snapshot(snapshot()))
    }

    private func notice(_ text: String, _ level: Notice.Level = .info) {
        emit(.notice(Notice(level: level, text: text)))
    }

    // The same notice at most once (or once every `every` seconds)
    private func noticeOnce(_ key: String, _ text: String, _ level: Notice.Level, every: TimeInterval = .infinity) {
        let t = clock()
        if let last = noticed[key], every == .infinity || t - last < every { return }
        noticed[key] = t
        notice(text, level)
    }

    private func log(_ text: String) { emit(.log(text)) }

    private func short(_ endpoint: String) -> String { String(endpoint.prefix(8)) }
}
