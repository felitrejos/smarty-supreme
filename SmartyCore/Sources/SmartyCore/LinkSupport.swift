import Foundation
import Synchronization

public struct SystemClock: MonotonicClock {
    public init() {}

    public var now: Microseconds {
        Microseconds((ProcessInfo.processInfo.systemUptime * 1_000_000).rounded())
    }
}

public final class EventRelay: Sendable {
    private struct Target: Sendable {
        let handle: TransportEventHandler
    }

    private let target = Mutex<Target?>(nil)

    public init() {}

    public func connect(_ handler: @escaping TransportEventHandler) {
        target.withLock { $0 = Target(handle: handler) }
    }

    public func forward(_ event: TransportEvent) {
        target.withLock { $0 }?.handle(event)
    }
}

struct Outbox: Sendable {
    private var nextSequence: [Channel: UInt32] = [:]

    mutating func send(_ message: Message, to peer: PeerID, at time: Microseconds, over transport: any Transport) {
        let channel = message.channel
        let sequence = nextSequence[channel, default: 0]
        nextSequence[channel] = sequence &+ 1
        let data = MessageCodec.encode(Packet(sequence: sequence, sentAt: time, message: message))
        do throws(TransportError) {
            try transport.send(data, to: peer, on: channel)
        } catch {
            switch error {
            case .notConnected: return
            }
        }
    }
}
