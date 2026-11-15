public enum Sensitivity: CaseIterable, Sendable {
    case high
    case medium
    case low

    public var rangeDegrees: Double {
        switch self {
        case .high: 12
        case .medium: 20
        case .low: 30
        }
    }
}

public struct PointerConfig: Sendable {
    public var minimumCutoff = 1.0
    public var beta = 10.0
    public var derivativeCutoff = 5.0
    public var minimumUprightness = 0.5
    public var calibrationDuration: Microseconds = 500_000
    public var maximumCalibrationVariationDegrees = 3.0

    public init() {}
}

public enum PointerReading: Equatable, Sendable {
    case position(Double)
    case notUpright
}

public struct PointerMapper: Sendable {
    public let neutralRollDegrees: Double
    private let sensitivity: Sensitivity
    private let config: PointerConfig
    private var filter: OneEuroFilter
    private var lastPosition: Double?

    public init(neutralRollDegrees: Double, sensitivity: Sensitivity, config: PointerConfig = PointerConfig()) {
        self.neutralRollDegrees = neutralRollDegrees
        self.sensitivity = sensitivity
        self.config = config
        filter = OneEuroFilter(minimumCutoff: config.minimumCutoff, beta: config.beta, derivativeCutoff: config.derivativeCutoff)
    }

    public mutating func update(_ sample: MotionSample, holding: Bool) -> PointerReading {
        if holding, let lastPosition {
            return .position(lastPosition)
        }
        guard sample.uprightness >= config.minimumUprightness else { return .notUpright }
        let relativeRoll = sample.rollDegrees - neutralRollDegrees
        let raw = min(max(0.5 + relativeRoll / (2 * sensitivity.rangeDegrees), 0), 1)
        let position = filter.filter(raw, at: sample.time)
        lastPosition = position
        return .position(position)
    }
}

public enum CalibrationFailure: Equatable, Sendable {
    case handMoved
    case notUpright
}

public enum CalibrationResult: Equatable, Sendable {
    case calibrated(neutralRollDegrees: Double)
    case failed(CalibrationFailure)
}

public struct Calibrator: Sendable {
    private let config: PointerConfig
    private var samples: [MotionSample] = []

    public init(config: PointerConfig = PointerConfig()) {
        self.config = config
    }

    public mutating func add(_ sample: MotionSample) -> CalibrationResult? {
        samples.append(sample)
        guard sample.time - samples[0].time >= config.calibrationDuration else { return nil }
        guard samples.allSatisfy({ $0.uprightness >= config.minimumUprightness }) else { return .failed(.notUpright) }
        let rolls = samples.map(\.rollDegrees)
        guard rolls.max()! - rolls.min()! <= config.maximumCalibrationVariationDegrees else { return .failed(.handMoved) }
        return .calibrated(neutralRollDegrees: rolls.reduce(0, +) / Double(rolls.count))
    }
}
