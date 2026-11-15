public struct SwingConfig: Sendable {
    public var onThreshold = 2.5
    public var offThreshold = 1.0
    public var minimumRiseTime: Microseconds = 20_000
    public var reportFraction = 0.9
    public var maximumDuration: Microseconds = 250_000
    public var minimumRotationRate = 3.0
    public var cooldown: Microseconds = 300_000
    public var ceiling = 8.0
    public var minimumUprightness = 0.5
    public var freeFallThreshold = 0.3
    public var freeFallDuration: Microseconds = 100_000
    public var fullStrengthAcceleration = 6.0

    public init() {}

    public func strength(forPeakAcceleration peak: Double) -> Double {
        let fraction = (peak - onThreshold) / (fullStrengthAcceleration - onThreshold)
        return min(max(fraction, 0), 1)
    }
}
