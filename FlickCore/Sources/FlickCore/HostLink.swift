import Foundation
import Synchronization

public final class HostLink: Sendable {
    public static let pingInterval: Microseconds = 1_000_000
    public static let roundTripHistory = 600
    private static let pointerRateWindow: Microseconds = 1_000_000

    public struct ReceivedSwing: Equatable, Sendable {
        public let macPeakTime: Microseconds?
        public let strength: Double
        public let direction: SIMD3<Double>
    }

    public struct ConnectedPaddle: Equatable, Sendable {
        public let peer: PeerID
        public let name: String
        public let side: Side
        public let sensitivity: Sensitivity?
        public let position: Double?
        public let pointerRate: Int
        public let roundTrips: [Microseconds]
        public let peerAheadOfMac: Int64?
        public let swingCount: Int
        public let lastSwing: ReceivedSwing?
    }

    private struct Paddle: Sendable {
        let name: String
        let side: Side
        var sensitivity: Sensitivity?
        var position: Double?
        var lastPointerSequence: UInt32?
        var pointerArrivals: [Microseconds] = []
        var clockSync = ClockSync()
        var roundTrips: [Microseconds] = []
        var lastPingAt: Microseconds?
        var unansweredPingAt: Microseconds?
        var swingCount = 0
        var lastSwing: ReceivedSwing?

        init(name: String, side: Side) {
            self.name = name
            self.side = side
        }
    }

    private struct WaitingPhone: Sendable {
        let peer: PeerID
        let name: String
    }

    private struct State: Sendable {
        var paddles: [PeerID: Paddle] = [:]
        var waiting: [WaitingPhone] = []
        var outbox = Outbox()

        var freeSide: Side? {
            Side.allCases.first { side in !paddles.values.contains { $0.side == side } }
        }
    }

    private let name: String
    private let transport: any Transport
    private let clock: any MonotonicClock
    private let state = Mutex(State())

    public init(name: String, transport: any Transport, clock: any MonotonicClock) {
        self.name = name
        self.transport = transport
        self.clock = clock
    }

    public var paddles: [ConnectedPaddle] {
        let now = clock.now
        return state.withLock { state in
            state.paddles
                .map { peer, paddle in
                    ConnectedPaddle(
                        peer: peer,
                        name: paddle.name,
                        side: paddle.side,
                        sensitivity: paddle.sensitivity,
                        position: paddle.position,
                        pointerRate: paddle.pointerArrivals.filter { $0 + Self.pointerRateWindow > now }.count,
                        roundTrips: paddle.roundTrips,
                        peerAheadOfMac: paddle.clockSync.peerAheadOfMac,
                        swingCount: paddle.swingCount,
                        lastSwing: paddle.lastSwing
                    )
                }
                .sorted { $0.side.rawValue < $1.side.rawValue }
        }
    }

    public var waitingNames: [String] {
        state.withLock { $0.waiting.map(\.name) }
    }

    public func handle(_ event: TransportEvent) {
        let receivedAt = clock.now
        state.withLock { state in
            switch event {
            case .connected:
                return
            case .disconnected(let peer):
                forget(peer, in: &state)
            case .received(let data, let sender):
                receive(data, from: sender, at: receivedAt, in: &state)
            }
        }
    }

    public func tick() {
        let now = clock.now
        state.withLock { state in
            for (peer, paddle) in state.paddles {
                if let lastPingAt = paddle.lastPingAt, now - lastPingAt < Self.pingInterval {
                    continue
                }
                state.paddles[peer]?.lastPingAt = now
                state.paddles[peer]?.unansweredPingAt = now
                state.outbox.send(.ping, to: peer, at: now, over: transport)
            }
        }
    }

    private func receive(_ data: Data, from sender: PeerID, at receivedAt: Microseconds, in state: inout State) {
        let packet: Packet
        do throws(MessageDecodingError) {
            packet = try MessageCodec.decode(data)
        } catch .otherVersion {
            state.outbox.send(.bye(.versionMismatch), to: sender, at: clock.now, over: transport)
            return
        } catch {
            return
        }
        switch packet.message {
        case .hello(let phoneName):
            greet(sender, named: phoneName, in: &state)
            return
        case .bye:
            forget(sender, in: &state)
            return
        default:
            break
        }
        guard var paddle = state.paddles[sender] else { return }
        switch packet.message {
        case .pong(let pingSentAt, let peerReceivedAt):
            guard pingSentAt == paddle.unansweredPingAt,
                  let exchange = ClockExchange(
                      macSentAt: pingSentAt,
                      peerReceivedAt: peerReceivedAt,
                      peerSentAt: packet.sentAt,
                      macReceivedAt: receivedAt
                  ) else { return }
            paddle.unansweredPingAt = nil
            paddle.roundTrips.append(paddle.clockSync.add(exchange))
            if paddle.roundTrips.count > Self.roundTripHistory {
                paddle.roundTrips.removeFirst()
            }
        case .pointer(let position):
            paddle.pointerArrivals.removeAll { $0 + Self.pointerRateWindow <= receivedAt }
            paddle.pointerArrivals.append(receivedAt)
            if paddle.lastPointerSequence.map({ SequenceNumber.isNewer(packet.sequence, than: $0) }) ?? true {
                paddle.lastPointerSequence = packet.sequence
                paddle.position = Double(position)
            }
        case .swing(let swing):
            paddle.swingCount += 1
            paddle.lastSwing = ReceivedSwing(
                macPeakTime: paddle.clockSync.macTime(forPeerTime: swing.peakAt),
                strength: Double(swing.strength),
                direction: SIMD3<Double>(swing.direction)
            )
        case .calibrated(let sensitivity):
            paddle.sensitivity = sensitivity
        default:
            return
        }
        state.paddles[sender] = paddle
    }

    private func greet(_ peer: PeerID, named phoneName: String, in state: inout State) {
        if state.paddles[peer] != nil {
            state.outbox.send(.helloAck(name: name), to: peer, at: clock.now, over: transport)
            return
        }
        guard let side = state.freeSide else {
            if !state.waiting.contains(where: { $0.peer == peer }) {
                state.waiting.append(WaitingPhone(peer: peer, name: phoneName))
            }
            state.outbox.send(.bye(.gameFull), to: peer, at: clock.now, over: transport)
            return
        }
        admit(peer, named: phoneName, as: side, in: &state)
    }

    private func forget(_ peer: PeerID, in state: inout State) {
        state.waiting.removeAll { $0.peer == peer }
        guard state.paddles.removeValue(forKey: peer) != nil else { return }
        admitWaitingPhone(in: &state)
    }

    private func admitWaitingPhone(in state: inout State) {
        guard let side = state.freeSide, !state.waiting.isEmpty else { return }
        let next = state.waiting.removeFirst()
        admit(next.peer, named: next.name, as: side, in: &state)
    }

    private func admit(_ peer: PeerID, named phoneName: String, as side: Side, in state: inout State) {
        state.paddles[peer] = Paddle(name: phoneName, side: side)
        state.outbox.send(.helloAck(name: name), to: peer, at: clock.now, over: transport)
    }
}
