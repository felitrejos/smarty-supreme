import FlickCore
import Foundation
import Synchronization

public struct LinkConditions: Sendable {
    public let latency: Microseconds
    public let jitter: Microseconds
    public let unreliableLossRate: Double

    public init(latency: Microseconds = 0, jitter: Microseconds = 0, unreliableLossRate: Double = 0) {
        precondition(jitter <= latency, "Jitter above latency would deliver packets before they were sent")
        precondition((0...1).contains(unreliableLossRate), "Loss rate must be between 0 and 1")
        self.latency = latency
        self.jitter = jitter
        self.unreliableLossRate = unreliableLossRate
    }
}

public final class LoopbackNetwork: Sendable {
    private struct Route: Hashable {
        let sender: PeerID
        let recipient: PeerID
    }

    private struct Link: Hashable {
        let first: PeerID
        let second: PeerID

        init(_ one: PeerID, _ other: PeerID) {
            (first, second) = one.name < other.name ? (one, other) : (other, one)
        }

        func joins(_ route: Route) -> Bool {
            self == Link(route.sender, route.recipient)
        }
    }

    private struct Delivery: Sendable {
        let at: Microseconds
        let event: TransportEvent
        let route: Route?
        let handler: TransportEventHandler
    }

    private struct State: Sendable {
        var random: SplitMix64
        var handlers: [PeerID: TransportEventHandler] = [:]
        var links: Set<Link> = []
        var pending: [Delivery] = []
        var lastReliableArrival: [Route: Microseconds] = [:]

        mutating func schedule(_ delivery: Delivery) {
            let index = pending.firstIndex { $0.at > delivery.at } ?? pending.endIndex
            pending.insert(delivery, at: index)
        }

        mutating func notify(_ peer: PeerID, of event: TransportEvent, at instant: Microseconds) {
            schedule(Delivery(at: instant, event: event, route: nil, handler: handlers[peer]!))
        }
    }

    private let clock: ManualClock
    private let conditions: LinkConditions
    private let state: Mutex<State>

    public init(clock: ManualClock, conditions: LinkConditions = LinkConditions(), seed: UInt64) {
        self.clock = clock
        self.conditions = conditions
        state = Mutex(State(random: SplitMix64(seed: seed)))
    }

    public func join(as peer: PeerID, onEvent handler: @escaping TransportEventHandler) -> LoopbackTransport {
        state.withLock { state in
            precondition(state.handlers[peer] == nil, "\(peer.name) already joined")
            state.handlers[peer] = handler
        }
        return LoopbackTransport(peer: peer, network: self)
    }

    public func connect(_ one: PeerID, _ other: PeerID) {
        let now = clock.now
        state.withLock { state in
            precondition(one != other, "A peer cannot connect to itself")
            precondition(state.handlers[one] != nil && state.handlers[other] != nil, "Both peers must join first")
            precondition(state.links.insert(Link(one, other)).inserted, "\(one.name) and \(other.name) are already connected")
            state.notify(one, of: .connected(other), at: now)
            state.notify(other, of: .connected(one), at: now)
        }
    }

    public func disconnect(_ one: PeerID, _ other: PeerID) {
        let now = clock.now
        let link = Link(one, other)
        state.withLock { state in
            precondition(state.links.remove(link) != nil, "\(one.name) and \(other.name) are not connected")
            state.pending.removeAll { delivery in delivery.route.map(link.joins) ?? false }
            state.notify(one, of: .disconnected(other), at: now)
            state.notify(other, of: .disconnected(one), at: now)
        }
    }

    public func advance(by duration: Microseconds) {
        let end = clock.now + duration
        while let delivery = takeDelivery(dueBy: end) {
            clock.advance(to: max(delivery.at, clock.now))
            delivery.handler(delivery.event)
        }
        clock.advance(to: max(end, clock.now))
    }

    func send(_ payload: Data, from sender: PeerID, to recipient: PeerID, on channel: Channel) throws(TransportError) {
        let now = clock.now
        let route = Route(sender: sender, recipient: recipient)
        try state.withLock { (state: inout State) throws(TransportError) in
            guard state.links.contains(Link(sender, recipient)) else {
                throw .notConnected(recipient)
            }
            if channel == .unreliable && Double.random(in: 0..<1, using: &state.random) < conditions.unreliableLossRate {
                return
            }
            let spread = UInt64.random(in: 0...(2 * conditions.jitter), using: &state.random)
            var arrival = now + conditions.latency - conditions.jitter + spread
            if channel == .reliable {
                arrival = max(arrival, state.lastReliableArrival[route] ?? 0)
                state.lastReliableArrival[route] = arrival
            }
            let event = TransportEvent.received(payload, from: sender)
            state.schedule(Delivery(at: arrival, event: event, route: route, handler: state.handlers[recipient]!))
        }
    }

    private func takeDelivery(dueBy end: Microseconds) -> Delivery? {
        state.withLock { state in
            guard let next = state.pending.first, next.at <= end else { return nil }
            return state.pending.removeFirst()
        }
    }
}

public final class LoopbackTransport: Transport {
    private let peer: PeerID
    private let network: LoopbackNetwork

    init(peer: PeerID, network: LoopbackNetwork) {
        self.peer = peer
        self.network = network
    }

    public func send(_ payload: Data, to recipient: PeerID, on channel: Channel) throws(TransportError) {
        try network.send(payload, from: peer, to: recipient, on: channel)
    }
}
