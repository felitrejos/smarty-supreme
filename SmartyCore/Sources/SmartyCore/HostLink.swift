import Foundation
import Synchronization

public final class HostLink: Sendable {
    public static let pingInterval: Microseconds = 1_000_000
    public static let roundTripHistory = 600
    private static let pointerRateWindow: Microseconds = 1_000_000
    private static let recentRoundTrips = 5

    public struct ReceivedSwing: Equatable, Sendable {
        public let macPeakTime: Microseconds?
        public let strength: Double
    }

    public struct PaddleInput: Equatable, Sendable {
        public let position: Double?
        public let lastPointerAt: Microseconds?
        public let swings: [ReceivedSwing]
        public let isCalibrated: Bool
        public let isReady: Bool
        public let pauseRequests: [Bool]
        public let roundTrip: Microseconds?
    }

    public struct Input: Equatable, Sendable {
        public let paddles: [Side: PaddleInput]
        public let vacant: Set<Side>
        public let viewerName: String?
    }

    public struct ConnectedPaddle: Equatable, Sendable {
        public let peer: PeerID
        public let name: String
        public let side: Side
        public let sensitivity: Sensitivity?
        public let position: Double?
        public let pointerRate: Int
        public let roundTrips: [Microseconds]
        public let swingCount: Int
        public let lastSwing: ReceivedSwing?
        public let isReady: Bool
    }

    public struct WaitingPhone: Equatable, Sendable {
        public let peer: PeerID
        public let name: String
    }

    private struct Paddle: Sendable {
        let name: String
        var side: Side
        var sensitivity: Sensitivity?
        var position: Double?
        var lastPointerSequence: UInt32?
        var lastPointerAt: Microseconds?
        var pointerArrivals: [Microseconds] = []
        var clockSync = ClockSync()
        var roundTrips: [Microseconds] = []
        var lastPingAt: Microseconds?
        var unansweredPingAt: Microseconds?
        var swingCount = 0
        var lastSwing: ReceivedSwing?
        var untakenSwings: [ReceivedSwing] = []
        var isReady = false
        var untakenPauseRequests: [Bool] = []

        init(name: String, side: Side) {
            self.name = name
            self.side = side
        }

        var recentRoundTrip: Microseconds? {
            let recent = roundTrips.suffix(HostLink.recentRoundTrips).sorted()
            return recent.isEmpty ? nil : recent[recent.count / 2]
        }
    }

    private struct Vacancy: Sendable {
        let peer: PeerID
        let paddle: Paddle
    }

    private struct Viewer: Sendable {
        let peer: PeerID
        let name: String
    }

    private struct State: Sendable {
        var paddles: [PeerID: Paddle] = [:]
        var vacancies: [Side: Vacancy] = [:]
        var waiting: [WaitingPhone] = []
        var viewer: Viewer?
        var isHoldingSlots = false
        var playableSides = Set(Side.allCases)
        var outbox = Outbox()

        var freeSide: Side? {
            Side.allCases.first { side in
                playableSides.contains(side) && vacancies[side] == nil && !paddles.values.contains { $0.side == side }
            }
        }

        func peer(on side: Side) -> PeerID? {
            paddles.first { $0.value.side == side }?.key
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
                        swingCount: paddle.swingCount,
                        lastSwing: paddle.lastSwing,
                        isReady: paddle.isReady
                    )
                }
                .sorted { $0.side.rawValue < $1.side.rawValue }
        }
    }

    public var waiting: [WaitingPhone] {
        state.withLock { $0.waiting }
    }

    public var waitingNames: [String] {
        waiting.map(\.name)
    }

    public var viewerName: String? {
        state.withLock { $0.viewer?.name }
    }

    public func takeInput() -> Input {
        state.withLock { state in
            var paddles: [Side: PaddleInput] = [:]
            for (peer, paddle) in state.paddles {
                paddles[paddle.side] = PaddleInput(
                    position: paddle.position,
                    lastPointerAt: paddle.lastPointerAt,
                    swings: paddle.untakenSwings,
                    isCalibrated: paddle.sensitivity != nil,
                    isReady: paddle.isReady,
                    pauseRequests: paddle.untakenPauseRequests,
                    roundTrip: paddle.recentRoundTrip
                )
                state.paddles[peer]?.untakenSwings.removeAll()
                state.paddles[peer]?.untakenPauseRequests.removeAll()
            }
            return Input(paddles: paddles, vacant: Set(state.vacancies.keys), viewerName: state.viewer?.name)
        }
    }

    public func send(_ message: Message, to side: Side) {
        let now = clock.now
        state.withLock { state in
            guard let peer = state.peer(on: side) else { return }
            state.outbox.send(message, to: peer, at: now, over: transport)
        }
    }

    public func sendToViewer(_ snapshot: TableSnapshot) {
        let now = clock.now
        state.withLock { state in
            guard let viewer = state.viewer else { return }
            state.outbox.send(.snapshot(snapshot), to: viewer.peer, at: now, over: transport)
        }
    }

    public func setPlayableSides(_ sides: Set<Side>) {
        let now = clock.now
        state.withLock { state in
            state.playableSides = sides
            for (peer, paddle) in state.paddles where !sides.contains(paddle.side) {
                state.paddles[peer] = nil
                state.waiting.append(WaitingPhone(peer: peer, name: paddle.name))
                state.outbox.send(.bye(.gameFull), to: peer, at: now, over: transport)
            }
            while state.freeSide != nil, !state.waiting.isEmpty {
                admitWaitingPhone(in: &state)
            }
        }
    }

    public func holdSlots(_ hold: Bool) {
        state.withLock { state in
            state.isHoldingSlots = hold
            guard !hold else { return }
            state.vacancies.removeAll()
            while state.freeSide != nil, !state.waiting.isEmpty {
                admitWaitingPhone(in: &state)
            }
        }
    }

    public func fillVacancy(_ side: Side, with peer: PeerID) {
        state.withLock { state in
            guard state.vacancies[side] != nil, let index = state.waiting.firstIndex(where: { $0.peer == peer }) else { return }
            let phone = state.waiting.remove(at: index)
            state.vacancies[side] = nil
            admit(phone.peer, named: phone.name, as: side, in: &state)
        }
    }

    public func swapSides() {
        state.withLock { state in
            for (peer, paddle) in state.paddles {
                state.paddles[peer]?.side = paddle.side.opponent
            }
        }
    }

    public func resetReadiness() {
        state.withLock { state in
            for peer in state.paddles.keys {
                state.paddles[peer]?.isReady = false
            }
        }
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
        case .viewerHello(let viewerName):
            greetViewer(sender, named: viewerName, in: &state)
            return
        case .bye:
            forget(sender, in: &state)
            return
        case .ping where state.viewer?.peer == sender:
            state.outbox.send(.pong(pingSentAt: packet.sentAt, receivedAt: receivedAt), to: sender, at: clock.now, over: transport)
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
                paddle.lastPointerAt = receivedAt
            }
        case .swing(let swing):
            let received = ReceivedSwing(
                macPeakTime: paddle.clockSync.macTime(forPeerTime: swing.peakAt),
                strength: Double(swing.strength)
            )
            paddle.swingCount += 1
            paddle.lastSwing = received
            paddle.untakenSwings.append(received)
        case .calibrated(let sensitivity):
            paddle.sensitivity = sensitivity
        case .ready(let isReady):
            paddle.isReady = isReady
        case .pause(let pause):
            paddle.untakenPauseRequests.append(pause)
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
        if let side = state.vacancies.first(where: { $0.value.peer == peer })?.key, let vacancy = state.vacancies.removeValue(forKey: side) {
            state.paddles[peer] = vacancy.paddle
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

    private func greetViewer(_ peer: PeerID, named viewerName: String, in state: inout State) {
        guard state.viewer == nil || state.viewer?.peer == peer else {
            state.outbox.send(.bye(.gameFull), to: peer, at: clock.now, over: transport)
            return
        }
        state.viewer = Viewer(peer: peer, name: viewerName)
        state.outbox.send(.helloAck(name: name), to: peer, at: clock.now, over: transport)
    }

    private func forget(_ peer: PeerID, in state: inout State) {
        state.waiting.removeAll { $0.peer == peer }
        if state.viewer?.peer == peer {
            state.viewer = nil
            return
        }
        guard var paddle = state.paddles.removeValue(forKey: peer) else { return }
        if state.isHoldingSlots {
            paddle.untakenSwings.removeAll()
            paddle.untakenPauseRequests.removeAll()
            paddle.position = nil
            paddle.lastPointerAt = nil
            state.vacancies[paddle.side] = Vacancy(peer: peer, paddle: paddle)
        } else {
            admitWaitingPhone(in: &state)
        }
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
