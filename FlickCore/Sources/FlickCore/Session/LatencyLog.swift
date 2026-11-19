public struct LatencyLog: Sendable {
    private let capacity: Int
    private var values: [Microseconds] = []
    private var next = 0

    public init(capacity: Int) {
        self.capacity = capacity
    }

    public mutating func add(_ value: Microseconds) {
        if values.count < capacity {
            values.append(value)
        } else {
            values[next] = value
        }
        next = (next + 1) % capacity
    }

    public func percentile(_ fraction: Double) -> Microseconds? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[max(rank, 1) - 1]
    }
}
