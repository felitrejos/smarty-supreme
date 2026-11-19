import Foundation
import Synchronization

public final class ViewerLink: Sendable {
    public enum Status: Equatable, Sendable {
        case searching
        case handshaking
        case paired(hostName: String)
        case refused(ByeReason)
    }

    public struct ReceivedSnapshot: Equatable, Sendable {
        public let snapshot: TableSnapshot
        public let sentAt: Microseconds
        public let receivedAt: Microseconds
    }

    private struct State: Sendable {
        var host: PeerID?
        var status = Status.searching
        var latest: ReceivedSnapshot?
        var latestSequence: UInt32?
        var clockSync = ClockSync()
        var lastPingAt: Microseconds?
        var unansweredPingAt: Microseconds?
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

    public var latest: ReceivedSnapshot? {
        state.withLock { $0.latest }
    }

    public func snapshotAge(at now: Microseconds) -> Microseconds? {
        state.withLock { state in
            guard let latest = state.latest, let hostAhead = state.clockSync.peerAheadOfMac else { return nil }
            return Microseconds(max(Int64(now) + hostAhead - Int64(latest.sentAt), 0))
        }
    }

    public func handle(_ event: TransportEvent) {
        let receivedAt = clock.now
        state.withLock { state in
            switch event {
            case .connected(let host):
                state.host = host
                state.status = .handshaking
                send(.viewerHello(name: name), in: &state)
            case .disconnected(let peer):
                guard peer == state.host else { return }
                state.host = nil
                state.latest = nil
                state.latestSequence = nil
                if state.status != .refused(.versionMismatch) {
                    state.status = .searching
                }
            case .received(let data, let sender):
                guard sender == state.host else { return }
                receive(data, at: receivedAt, in: &state)
            }
        }
    }

    public func tick() {
        let now = clock.now
        state.withLock { state in
            guard case .paired = state.status else { return }
            if let lastPingAt = state.lastPingAt, now - lastPingAt < HostLink.pingInterval { return }
            state.lastPingAt = now
            state.unansweredPingAt = now
            send(.ping, in: &state)
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
        case .bye(let reason):
            state.status = .refused(reason)
        case .pong(let pingSentAt, let hostReceivedAt):
            guard pingSentAt == state.unansweredPingAt,
                  let exchange = ClockExchange(
                      macSentAt: pingSentAt,
                      peerReceivedAt: hostReceivedAt,
                      peerSentAt: packet.sentAt,
                      macReceivedAt: receivedAt
                  ) else { return }
            state.unansweredPingAt = nil
            state.clockSync.add(exchange)
        case .snapshot(let snapshot):
            if let latestSequence = state.latestSequence, !SequenceNumber.isNewer(packet.sequence, than: latestSequence) { return }
            state.latestSequence = packet.sequence
            state.latest = ReceivedSnapshot(snapshot: snapshot, sentAt: packet.sentAt, receivedAt: receivedAt)
        default:
            return
        }
    }

    private func send(_ message: Message, in state: inout State) {
        guard let host = state.host else { return }
        state.outbox.send(message, to: host, at: clock.now, over: transport)
    }
}
