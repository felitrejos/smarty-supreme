import Foundation

public struct PeerID: Hashable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }
}

public enum Channel: Sendable {
    case reliable
    case unreliable
}

public enum TransportEvent: Equatable, Sendable {
    case connected(PeerID)
    case disconnected(PeerID)
    case received(Data, from: PeerID)
}

public typealias TransportEventHandler = @Sendable (TransportEvent) -> Void

public enum TransportError: Error, Equatable {
    case notConnected(PeerID)
}

public protocol Transport: Sendable {
    func send(_ payload: Data, to peer: PeerID, on channel: Channel) throws(TransportError)
}
