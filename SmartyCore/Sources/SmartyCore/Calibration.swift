public struct CalibrationConfig: Sendable {
    public var minimumUprightness = 0.5
    public var duration: Microseconds = 500_000
    public var maximumVariationDegrees = 3.0

    public init() {}
}

public enum CalibrationFailure: Equatable, Sendable {
    case handMoved
    case notUpright
}

public enum CalibrationResult: Equatable, Sendable {
    case calibrated
    case failed(CalibrationFailure)
}

public struct Calibrator: Sendable {
    private let config: CalibrationConfig
    private var samples: [MotionSample] = []

    public init(config: CalibrationConfig = CalibrationConfig()) {
        self.config = config
    }

    public mutating func add(_ sample: MotionSample) -> CalibrationResult? {
        samples.append(sample)
        guard sample.time - samples[0].time >= config.duration else { return nil }
        guard samples.allSatisfy({ $0.uprightness >= config.minimumUprightness }) else { return .failed(.notUpright) }
        let rolls = samples.map(\.rollDegrees)
        guard rolls.max()! - rolls.min()! <= config.maximumVariationDegrees else { return .failed(.handMoved) }
        return .calibrated
    }
}
