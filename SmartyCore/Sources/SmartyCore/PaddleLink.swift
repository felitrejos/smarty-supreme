import Foundation
import Synchronization

public final class PaddleLink: Sendable {
    public enum Status: Equatable, Sendable {
        case searching
        case handshaking
        case paired(hostName: String)
        case refused(ByeReason)
    }

    private struct State: Sendable {
        var host: PeerID?
        var status = Status.searching
        var pairedAt: Microseconds?
        var handedness: Handedness?
        var gameState: GameStateUpdate?
        var outbox = Outbox()
    }

    private let name: String
    private let transport: any Transport
    private let clock: any MonotonicClock
    private let onHaptic: @Sendable (HapticKind) -> Void
    private let onIncoming: @Sendable (Microseconds) -> Void
    private let state = Mutex(State())

    public init(
        name: String,
        transport: any Transport,
        clock: any MonotonicClock,
        onHaptic: @escaping @Sendable (HapticKind) -> Void,
        onIncoming: @escaping @Sendable (Microseconds) -> Void = { _ in }
    ) {
        self.name = name
        self.transport = transport
        self.clock = clock
        self.onHaptic = onHaptic
        self.onIncoming = onIncoming
    }

    public var status: Status {
        state.withLock { $0.status }
    }

    public var pairedAt: Microseconds? {
        state.withLock { $0.pairedAt }
    }

    public var gameState: GameStateUpdate? {
        state.withLock { $0.gameState }
    }

    public func handle(_ event: TransportEvent) {
        let receivedAt = clock.now
        let haptic = state.withLock { state -> HapticKind? in
            switch event {
            case .connected(let host):
                state.host = host
                state.status = .handshaking
                send(.hello(name: name), in: &state)
                return nil
            case .disconnected(let peer):
                guard peer == state.host else { return nil }
                state.host = nil
                state.gameState = nil
                if state.status != .refused(.versionMismatch) {
                    state.status = .searching
                }
                return nil
            case .received(let data, let sender):
                guard sender == state.host else { return nil }
                return receive(data, at: receivedAt, in: &state)
            }
        }
        if let haptic {
            onHaptic(haptic)
        }
    }

    public func sendPointer(_ position: Double) {
        sendWhilePaired(.pointer(position: Float(position)))
    }

    public func sendRacket(_ pose: RacketPose, at time: Microseconds) {
        let q = pose.orientation
        sendWhilePaired(.racket(RacketMessage(
            sampledAt: time,
            orientation: SIMD4<Float>(Float(q.imag.x), Float(q.imag.y), Float(q.imag.z), Float(q.real)),
            angularVelocity: SIMD3<Float>(pose.angularVelocity),
            linearVelocity: SIMD3<Float>(pose.linearVelocity),
            reach: SIMD3<Float>(pose.reach)
        )))
    }

    public func sendSwing(_ swing: SwingEvent) {
        sendWhilePaired(.swing(SwingMessage(
            peakAt: swing.peakTime,
            strength: Float(swing.strength),
            direction: SIMD3<Float>(swing.direction)
        )))
    }

    public func setReady(_ isReady: Bool) {
        sendWhilePaired(.ready(isReady))
    }

    public func requestToss() {
        sendWhilePaired(.toss)
    }

    public func requestPause(_ pause: Bool) {
        sendWhilePaired(.pause(pause))
    }

    public func announceCalibration(_ handedness: Handedness) {
        state.withLock { state in
            state.handedness = handedness
            guard case .paired = state.status else { return }
            send(.calibrated(handedness), in: &state)
        }
    }

    public func leave(_ reason: ByeReason) {
        state.withLock { state in
            guard state.host != nil else { return }
            send(.bye(reason), in: &state)
        }
    }

    private func receive(_ data: Data, at receivedAt: Microseconds, in state: inout State) -> HapticKind? {
        let packet: Packet
        do throws(MessageDecodingError) {
            packet = try MessageCodec.decode(data)
        } catch .otherVersion {
            state.status = .refused(.versionMismatch)
            return nil
        } catch {
            return nil
        }
        switch packet.message {
        case .helloAck(let hostName):
            state.status = .paired(hostName: hostName)
            state.pairedAt = state.pairedAt ?? receivedAt
            if let handedness = state.handedness {
                send(.calibrated(handedness), in: &state)
            }
        case .bye(let reason):
            state.status = .refused(reason)
        case .ping:
            send(.pong(pingSentAt: packet.sentAt, receivedAt: receivedAt), in: &state)
        case .haptic(let kind):
            return kind
        case .incoming(let contactAt):
            onIncoming(contactAt)
        case .gameState(let update):
            state.gameState = update
        default:
            break
        }
        return nil
    }

    private func sendWhilePaired(_ message: Message) {
        state.withLock { state in
            guard case .paired = state.status else { return }
            send(message, in: &state)
        }
    }

    private func send(_ message: Message, in state: inout State) {
        guard let host = state.host else { return }
        state.outbox.send(message, to: host, at: clock.now, over: transport)
    }
}
