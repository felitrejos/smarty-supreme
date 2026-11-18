public struct AIProfile: Sendable {
    public var reactionDelay: Double
    public var aimError: Double
    public var paddleSpeedInTableWidths: Double
    public var timingError: Double
    public var strength: ClosedRange<Double>
    public var aimsAwayShare: Double
    public var serveDelay = 0.8

    public init(
        reactionDelay: Double,
        aimError: Double,
        paddleSpeedInTableWidths: Double,
        timingError: Double,
        strength: ClosedRange<Double>,
        aimsAwayShare: Double
    ) {
        self.reactionDelay = reactionDelay
        self.aimError = aimError
        self.paddleSpeedInTableWidths = paddleSpeedInTableWidths
        self.timingError = timingError
        self.strength = strength
        self.aimsAwayShare = aimsAwayShare
    }
}

public enum Difficulty: String, CaseIterable, Sendable {
    case easy
    case medium
    case hard

    public var profile: AIProfile {
        switch self {
        case .easy:
            AIProfile(reactionDelay: 0.2, aimError: 0.045, paddleSpeedInTableWidths: 2.0, timingError: 0.045, strength: 0.1...0.4, aimsAwayShare: 0)
        case .medium:
            AIProfile(reactionDelay: 0.18, aimError: 0.035, paddleSpeedInTableWidths: 2.0, timingError: 0.045, strength: 0.2...0.7, aimsAwayShare: 0.3)
        case .hard:
            AIProfile(reactionDelay: 0.15, aimError: 0.035, paddleSpeedInTableWidths: 2.2, timingError: 0.042, strength: 0.3...0.8, aimsAwayShare: 0.7)
        }
    }
}
