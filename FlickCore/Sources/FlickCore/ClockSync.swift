public struct ClockExchange: Sendable {
    static let latestTime: Microseconds = 1 << 62

    public let macSentAt: Microseconds
    public let peerReceivedAt: Microseconds
    public let peerSentAt: Microseconds
    public let macReceivedAt: Microseconds

    public init?(macSentAt: Microseconds, peerReceivedAt: Microseconds, peerSentAt: Microseconds, macReceivedAt: Microseconds) {
        guard [macSentAt, peerReceivedAt, peerSentAt, macReceivedAt].allSatisfy({ $0 <= Self.latestTime }),
              macSentAt <= macReceivedAt,
              peerReceivedAt <= peerSentAt,
              peerSentAt - peerReceivedAt <= macReceivedAt - macSentAt else { return nil }
        self.macSentAt = macSentAt
        self.peerReceivedAt = peerReceivedAt
        self.peerSentAt = peerSentAt
        self.macReceivedAt = macReceivedAt
    }

    var roundTrip: Microseconds {
        (macReceivedAt - macSentAt) - (peerSentAt - peerReceivedAt)
    }

    var peerAheadOfMac: Int64 {
        let outbound = Int64(peerReceivedAt) - Int64(macSentAt)
        let inbound = Int64(peerSentAt) - Int64(macReceivedAt)
        return (outbound + inbound) / 2
    }
}

public struct ClockSync: Sendable {
    public static let maximumRoundTrip: Microseconds = 100_000
    private static let windowSize = 10

    private var recent: [ClockExchange] = []

    public init() {}

    @discardableResult
    public mutating func add(_ exchange: ClockExchange) -> Microseconds {
        let roundTrip = exchange.roundTrip
        guard roundTrip <= Self.maximumRoundTrip else { return roundTrip }
        recent.append(exchange)
        if recent.count > Self.windowSize {
            recent.removeFirst()
        }
        return roundTrip
    }

    public var peerAheadOfMac: Int64? {
        recent.min { $0.roundTrip < $1.roundTrip }?.peerAheadOfMac
    }

    public func macTime(forPeerTime peerTime: Microseconds) -> Microseconds? {
        guard let offset = peerAheadOfMac, peerTime <= ClockExchange.latestTime else { return nil }
        let macTime = Int64(peerTime) - offset
        return macTime >= 0 ? Microseconds(macTime) : nil
    }
}
