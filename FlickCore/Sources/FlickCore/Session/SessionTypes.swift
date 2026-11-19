public enum MatchMode: Equatable, Sendable {
    case computer(Difficulty)
    case twoPlayers

    var phoneSides: [Side] {
        self == .twoPlayers ? Side.allCases : [.playerA]
    }
}

public enum Interruption: Equatable, Sendable {
    case byHost
    case onHold
    case byPlayer(Side)
    case pointerLost(Side)
    case serveTimeouts(Side)
    case phoneLost(Side, until: Microseconds)
    case viewerLost(continued: Set<Side>)

    func canBeResumed(by side: Side) -> Bool {
        switch self {
        case .byPlayer(let owner), .pointerLost(let owner), .serveTimeouts(let owner):
            owner == side
        case .viewerLost(let continued):
            !continued.contains(side)
        case .byHost, .onHold, .phoneLost:
            false
        }
    }
}

public enum MatchStage: Equatable, Sendable {
    case lobby
    case countdown(until: Microseconds)
    case playing
    case interrupted(Interruption)
    case over
}

public enum Readiness: Equatable, Sendable {
    case noPhone
    case needsCalibration
    case notReady
    case measuring
    case tooSlow(roundTrip: Microseconds)
    case ready(roundTrip: Microseconds)
}

public struct LocalInput: Sendable {
    public var targets: [Side: Double] = [:]
    public var swings: [Swing] = []

    public init() {}
}

public struct SessionConfig: Sendable {
    public var countdown: Microseconds = 3_000_000
    public var reconnectWindow: Microseconds = 30_000_000
    public var pointerStaleAfter: Microseconds = 250_000
    public var pointerLostAfter: Microseconds = 2_000_000
    public var serveTimeoutsBeforeAsking = 3
    public var roundTripWarning: Microseconds = 40_000
    public var roundTripLimit: Microseconds = 100_000
    public var longestFrame: Microseconds = 100_000
    public var latencyHistory = 600

    public init() {}
}

extension GamePhase {
    public init(_ phase: GameState.Phase) {
        switch phase {
        case .serving: self = .serving
        case .rally: self = .rally
        case .pointScored: self = .pointScored
        case .paused: self = .paused
        case .gameOver: self = .gameOver
        }
    }
}
