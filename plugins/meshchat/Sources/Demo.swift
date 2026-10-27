// MeshChat – `lotus meshchat demo`: the chat with two simulated people, to try it without a second Mac. Nothing
// goes over Bluetooth and nothing is saved; the screen says DEMO. Ada is your neighbour; Grace is out of your
// range and reaches you through Ada, so her messages arrive relayed (⇢1). The mesh, the signatures and the screen
// are the real ones – only the radio is simulated (SimTransport.swift).

import Foundation

final class DemoWorld {
    let net: SimNetwork
    private var bots: [DemoBot] = []
    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
        net = SimNetwork(live: queue)
    }

    func userRadio() -> SimRadio { net.radio("you") }

    // On the mesh's queue
    func start() {
        bots = [
            DemoBot(name: "Ada", world: self, queue: queue,
                    greeting: "Hi! I'm right next to you – a direct Bluetooth link (● in the list below).",
                    replies: ["Got it 👍",
                              "Grace is out of your range – what she writes reaches you through my Mac.",
                              "Try /where Grace – how far she is, and the way your messages take to her.",
                              "There are no rooms: every Mac with MeshChat nearby reads this, and passes it on.",
                              "Ctrl-C closes the chat; on real Macs your history stays on yours."],
                    replyEvery: 1),
            DemoBot(name: "Grace", world: self, queue: queue,
                    greeting: "Hello from further away! I can't reach you directly – Ada passes this on, hence the mark after it.",
                    replies: ["I read you through Ada 👋",
                              "If Ada left, we could not hear each other any more – a mesh needs someone in between.",
                              "Each Mac passes a message on once; the copies that come back are dropped."],
                    replyEvery: 2),
        ]
        net.setRange("you", "Ada", true)
        net.setRange("Ada", "Grace", true)
        net.setDistance("you", "Ada", 2)
        net.setDistance("Ada", "Grace", 8)
    }

    func tick() { net.secondPassed() }

    var botNames: [String] { ["Ada", "Grace"] }
}

final class DemoBot {
    private(set) var node: MeshNode!
    private let name: String
    private let greeting: String
    private let replies: [String]
    private let replyEvery: Int
    private let queue: DispatchQueue
    private weak var world: DemoWorld?
    private var greeted = false
    private var heard = 0
    private var next = 0

    init(name: String, world: DemoWorld, queue: DispatchQueue, greeting: String, replies: [String], replyEvery: Int) {
        self.name = name
        self.world = world
        self.queue = queue
        self.greeting = greeting
        self.replies = replies
        self.replyEvery = replyEvery
        let net = world.net
        // a key made from a random identity cannot fail – Signer only refuses a seed that is not 32 bytes
        let signer = try! Signer(identity: CryptoBackend.randomBytes(32))
        let node = MeshNode(transport: net.radio(name), nickname: name, signer: signer, clock: { net.now },
                            events: { [weak self] e in self?.handle(e) })
        self.node = node
        net.tickers.append { [weak node] in node?.tick() }
        node.start()
    }

    private func say(_ text: String, after seconds: Double) {
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in _ = try? self?.node.send(text) }
    }

    private func handle(_ e: MeshEvent) {
        switch e {
        case .snapshot(let s):
            // greet once the person trying the demo is known
            let others = s.participants.filter { !(world?.botNames.contains($0.nickname) ?? false) }
            if !greeted && !others.isEmpty {
                greeted = true
                say(greeting, after: name == "Ada" ? 1.0 : 2.5)
            }
        case .message(let m) where !m.mine && !(world?.botNames.contains(m.nickname) ?? true):
            heard += 1
            guard heard % replyEvery == 0 || m.text.lowercased().contains(name.lowercased()) else { return }
            say(replies[next % replies.count], after: Double.random(in: 1.2...2.4))
            next += 1
        default:
            break
        }
    }
}
