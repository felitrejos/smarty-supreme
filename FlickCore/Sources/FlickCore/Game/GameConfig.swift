public struct GameConfig: Equatable, Sendable {
    public var stepsPerSecond = 240
    public var tableLength = 1.0
    public var tableWidth = 0.557
    public var ballRadius = 0.012
    public var startSpeed = 0.6
    public var maximumSpeed = 1.8
    public var paddleWidth = 0.12
    public var paddleFaceDistance = 0.05
    public var paddleSpeedInTableWidths = 3.0
    public var hitWindow = 0.18
    public var minimumZoneDepth = 0.04
    public var speedGain = 1.03
    public var strengthBoost = 0.4
    public var maximumReturnAngleDegrees = 50.0
    public var contactShare = 0.7
    public var serveSpreadDegrees = 15.0
    public var lagCompensation = 0.06
    public var swingCooldown = 0.3
    public var autoServeAfter = 5.0
    public var autoServeStrength = 0.3
    public var pauseBetweenPoints = 1.5
    public var winningScore = 11
    public var servesPerTurn = 2
    public var firstServer = Side.playerA

    public init() {}

    public func zoneDepth(forSpeed speed: Double) -> Double {
        max(speed * hitWindow, minimumZoneDepth)
    }

    public func canReach(ballX: Double, paddleX: Double) -> Bool {
        abs(ballX - paddleX) <= paddleWidth / 2 + ballRadius
    }

    public func paddleFaceY(of side: Side) -> Double {
        side == .playerA ? paddleFaceDistance : tableLength - paddleFaceDistance
    }

    func paddleX(forPosition position: Double) -> Double {
        let half = paddleWidth / 2
        return half + min(max(position, 0), 1) * (tableWidth - 2 * half)
    }

    func steps(_ seconds: Double) -> UInt64 {
        UInt64((seconds * Double(stepsPerSecond)).rounded(.down))
    }

    var stepDuration: Double {
        1 / Double(stepsPerSecond)
    }
}

extension Side {
    public var opponent: Side {
        self == .playerA ? .playerB : .playerA
    }

    var forward: Double {
        self == .playerA ? 1 : -1
    }
}
