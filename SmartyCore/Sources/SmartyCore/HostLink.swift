import Foundation
import simd
import Synchronization

public final class HostLink: Sendable {
    public static let pingInterval: Microseconds = 1_000_000
    public static let roundTripHistory = 600
    private static let pointerRateWindow: Microseconds = 1_000_000
    private static let recentRoundTrips = 5
    private static let racketBacklog = 64

    public struct ReceivedSwing: Equatable, Sendable {
        public let macPeakTime: Microseconds?
        public let strength: Double
    }

    public struct ReceivedRacket: Equatable, Sendable {
        public let macTime: Microseconds?
        public let orientation: simd_quatd
        public let angularVelocity: SIMD3<Double>
        public let linearVelocity: SIMD3<Double>
        public let reach: SIMD3<Double>
    }

    public struct PaddleInput: Equatable, Sendable {
        public let position: Double?
        public let lastPointerAt: Microseconds?
        public let lastRacketAt: Microseconds?
        public let swings: [ReceivedSwing]
        public let rackets: [ReceivedRacket]
        public let isCalibrated: Bool
        public let handedness: Handedness
        public let isReady: Bool
        public let pauseRequests: [Bool]
        public let tossRequested: Bool
        public let recalibrated: Bool
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
        public let isCalibrated: Bool
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
        var handedness: Handedness?
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
        var untakenRackets: [ReceivedRacket] = []
        var lastRacketAt: Microseconds?
        var isReady = false
        var untakenPauseRequests: [Bool] = []
        var untakenToss = false
        var untakenCalibration = false

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
                        isCalibrated: paddle.handedness != nil,
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
                    lastRacketAt: paddle.lastRacketAt,
                    swings: paddle.untakenSwings,
                    rackets: paddle.untakenRackets,
                    isCalibrated: paddle.handedness != nil,
                    handedness: paddle.handedness ?? .right,
                    isReady: paddle.isReady,
                    pauseRequests: paddle.untakenPauseRequests,
                    tossRequested: paddle.untakenToss,
                    recalibrated: paddle.untakenCalibration,
                    roundTrip: paddle.recentRoundTrip
                )
                state.paddles[peer]?.untakenSwings.removeAll()
                state.paddles[peer]?.untakenRackets.removeAll()
                state.paddles[peer]?.untakenPauseRequests.removeAll()
                state.paddles[peer]?.untakenToss = false
                state.paddles[peer]?.untakenCalibration = false
            }
            return Input(paddles: paddles, vacant: Set(state.vacancies.keys), viewerName: state.viewer?.name)
        }
    }

    public func sendIncoming(contactAt macTime: Microseconds, to side: Side) {
        let peerTime = state.withLock { state in
            state.paddles.values.first { $0.side == side }?.clockSync.peerAheadOfMac.map { Int64(macTime) + $0 }
        }
        guard let peerTime, peerTime >= 0 else { return }
        send(.incoming(contactAt: Microseconds(peerTime)), to: side)
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
        case .racket(let racket):
            paddle.pointerArrivals.removeAll { $0 + Self.pointerRateWindow <= receivedAt }
            paddle.pointerArrivals.append(receivedAt)
            paddle.lastPointerAt = receivedAt
            paddle.lastRacketAt = receivedAt
            let q = racket.orientation
            paddle.untakenRackets.append(ReceivedRacket(
                macTime: paddle.clockSync.macTime(forPeerTime: racket.sampledAt),
                orientation: simd_quatd(ix: Double(q.x), iy: Double(q.y), iz: Double(q.z), r: Double(q.w)),
                angularVelocity: SIMD3<Double>(racket.angularVelocity),
                linearVelocity: SIMD3<Double>(racket.linearVelocity),
                reach: SIMD3<Double>(racket.reach)
            ))
            if paddle.untakenRackets.count > Self.racketBacklog {
                paddle.untakenRackets.removeFirst()
            }
        case .swing(let swing):
            let received = ReceivedSwing(
                macPeakTime: paddle.clockSync.macTime(forPeerTime: swing.peakAt),
                strength: Double(swing.strength)
            )
            paddle.swingCount += 1
            paddle.lastSwing = received
            paddle.untakenSwings.append(received)
        case .calibrated(let handedness):
            paddle.handedness = handedness
            paddle.untakenCalibration = true
        case .ready(let isReady):
            paddle.isReady = isReady
        case .pause(let pause):
            paddle.untakenPauseRequests.append(pause)
        case .toss:
            paddle.untakenToss = true
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
        // A relaunched phone says hello before its old connection is noticed gone; it takes that connection's place.
        if let old = state.paddles.first(where: { $0.value.name == phoneName })?.key, var paddle = state.paddles.removeValue(forKey: old) {
            paddle.clockSync = ClockSync()
            paddle.roundTrips = []
            paddle.unansweredPingAt = nil
            state.paddles[peer] = paddle
            state.waiting.removeAll { $0.peer == peer }
            state.outbox.send(.helloAck(name: name), to: peer, at: clock.now, over: transport)
            return
        }
        // A relaunched phone comes back under a new peer ID, so its held side is found by name. In a one-phone
        // game the held side can only be this player's; with two phones a stranger waits for the Mac to confirm.
        let held = state.vacancies.first { $0.value.peer == peer || $0.value.paddle.name == phoneName } ?? state.vacancies.first
        let isTheOnlyPhone = state.playableSides.count == 1 && state.freeSide == nil
        if isTheOnlyPhone || held?.value.peer == peer || held?.value.paddle.name == phoneName,
           let side = held?.key,
           let vacancy = state.vacancies.removeValue(forKey: side) {
            state.waiting.removeAll { $0.peer == peer }
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
            paddle.untakenToss = false
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
