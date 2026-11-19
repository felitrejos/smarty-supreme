import Foundation

public struct OneEuroFilter: Sendable {
    private let minimumCutoff: Double
    private let beta: Double
    private let derivativeCutoff: Double

    private var previousValue: Double?
    private var previousDerivative = 0.0
    private var previousTime: Microseconds = 0

    public init(minimumCutoff: Double, beta: Double, derivativeCutoff: Double) {
        self.minimumCutoff = minimumCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    public mutating func filter(_ value: Double, at time: Microseconds) -> Double {
        defer { previousTime = time }
        guard let previous = previousValue else {
            previousValue = value
            return value
        }
        precondition(time > previousTime, "Samples must arrive in time order")
        let interval = Double(time - previousTime) / 1_000_000
        let derivative = (value - previous) / interval
        previousDerivative += Self.smoothing(cutoff: derivativeCutoff, interval: interval) * (derivative - previousDerivative)
        let cutoff = minimumCutoff + beta * abs(previousDerivative)
        let filtered = previous + Self.smoothing(cutoff: cutoff, interval: interval) * (value - previous)
        previousValue = filtered
        return filtered
    }

    private static func smoothing(cutoff: Double, interval: Double) -> Double {
        let timeConstant = 1 / (2 * .pi * cutoff)
        return 1 / (1 + timeConstant / interval)
    }
}
