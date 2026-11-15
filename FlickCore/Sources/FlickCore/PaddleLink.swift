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
        var sensitivity: Sensitivity?
        var outbox = Outbox()
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

    public var status: Status {
        state.withLock { $0.status }
    }

    public var pairedAt: Microseconds? {
        state.withLock { $0.pairedAt }
    }

    public func handle(_ event: TransportEvent) {
        let receivedAt = clock.now
        state.withLock { state in
            switch event {
            case .connected(let host):
                state.host = host
                state.status = .handshaking
                send(.hello(name: name), in: &state)
            case .disconnected(let peer):
                guard peer == state.host else { return }
                state.host = nil
                if state.status != .refused(.versionMismatch) {
                    state.status = .searching
                }
            case .received(let data, let sender):
                guard sender == state.host else { return }
                receive(data, at: receivedAt, in: &state)
            }
        }
    }

    public func sendPointer(_ position: Double) {
        sendWhilePaired(.pointer(position: Float(position)))
    }

    public func sendSwing(_ swing: SwingEvent) {
        sendWhilePaired(.swing(SwingMessage(
            peakAt: swing.peakTime,
            strength: Float(swing.strength),
            direction: SIMD3<Float>(swing.direction)
        )))
    }

    public func announceCalibration(_ sensitivity: Sensitivity) {
        state.withLock { state in
            state.sensitivity = sensitivity
            guard case .paired = state.status else { return }
            send(.calibrated(sensitivity), in: &state)
        }
    }

    public func leave(_ reason: ByeReason) {
        state.withLock { state in
            guard state.host != nil else { return }
            send(.bye(reason), in: &state)
        }
    }

    private func receive(_ data: Data, at receivedAt: Microseconds, in state: inout State) {
        let packet: Packet
        do throws(MessageDecodingError) {
            packet = try MessageCodec.decode(data)
        } catch .otherVersion {
            state.status = .refused(.versionMismatch)
            return
        } catch {
            return
        }
        switch packet.message {
        case .helloAck(let hostName):
            state.status = .paired(hostName: hostName)
            state.pairedAt = state.pairedAt ?? receivedAt
            if let sensitivity = state.sensitivity {
                send(.calibrated(sensitivity), in: &state)
            }
        case .bye(let reason):
            state.status = .refused(reason)
        case .ping:
            send(.pong(pingSentAt: packet.sentAt, receivedAt: receivedAt), in: &state)
        default:
            return
        }
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
