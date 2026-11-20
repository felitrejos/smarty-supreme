public struct StepTimeline: Sendable {
    private let stepsPerSecond: Int
    private var markedStep: UInt64
    private var markedAt: Microseconds

    public init(step: UInt64, at time: Microseconds, stepsPerSecond: Int) {
        self.stepsPerSecond = stepsPerSecond
        markedStep = step
        markedAt = time
    }

    public mutating func mark(step: UInt64, at time: Microseconds) {
        markedStep = step
        markedAt = time
    }

    public func step(at time: Microseconds) -> UInt64 {
        guard time < markedAt else {
            return markedStep + UInt64((Double(time - markedAt) * Double(stepsPerSecond) / 1_000_000).rounded())
        }
        let stepsBack = UInt64((Double(markedAt - time) * Double(stepsPerSecond) / 1_000_000).rounded())
        return markedStep - min(stepsBack, markedStep)
    }
}
