public struct GameConfig: Equatable, Sendable {
    public var stepsPerSecond = 240
    public var timeScale = 0.7

    public var tableLength = 2.74
    public var tableWidth = 1.525
    public var tableHeight = 0.76
    public var netHeight = 0.1525
    public var netOverhang = 0.1525
    public var ballRadius = 0.02

    public var gravity = 9.81
    public var drag = 0.14
    public var magnus = 0.0015
    public var tableRestitution = 0.92
    public var tableFriction = 0.25
    public var floorRestitution = 0.6
    public var netRestitution = 0.1
    public var netDamping = 0.4
    public var netCordDamping = 0.6

    public var contactDistance = 0.3
    public var lowestContact = -0.3
    public var highestContact = 0.9
    public var reachDownHeight = 0.08
    public var paddleTravelMargin = 0.3
    public var paddleSpeedInTableWidths = 1.2
    public var reach = 0.3
    public var swingWindow = 0.1
    public var swingThreshold = 0.8
    public var serveThreshold = 1.5
    public var fullSwingSpeed = 8.0
    public var racketNormalRestitution = 0.878
    public var racketRestitutionPerSpeed = 0.02
    public var racketTangentialRestitution = 0.8
    public var aimAssist = 0.35
    public var sweetSpot = 0.25
    public var lagCompensation = 0.06
    public var swingCooldown = 0.3

    public var slowestShot = 4.5
    public var fastestShot = 12.0
    public var fastestBall = 20.0
    public var incomingCarry = 0.08
    public var slowestSpin = 20.0
    public var fastestSpin = 60.0
    public var targetDepth = 0.7
    public var targetDepthPerStrength = 0.15
    public var earlyLong = 0.75
    public var lateShort = 0.9
    public var wideError = 0.55
    public var contactShare = 0.4
    public var edgeContact = 0.85
    public var lateralSpan = 0.62
    public var netClearance = 0.04

    public var serveHeight = 0.25
    public var serveAngleDegrees = -14.0
    public var serveDepth = 0.75
    public var serveSpin = 15.0

    public var autoServeAfter = 5.0
    public var autoServeStrength = 0.3
    public var pauseBetweenPoints = 1.5
    public var winningScore = 11
    public var servesPerTurn = 2
    public var firstServer = Side.playerA

    public init() {}

    public func contactY(of side: Side) -> Double {
        side == .playerA ? -contactDistance : tableLength + contactDistance
    }

    public func canReach(ballX: Double, paddleX: Double) -> Bool {
        abs(ballX - paddleX) <= reach
    }

    public func paddleX(forPosition position: Double) -> Double {
        -paddleTravelMargin + min(max(position, 0), 1) * (tableWidth + 2 * paddleTravelMargin)
    }

    public func position(ofPaddleX x: Double) -> Double {
        (x + paddleTravelMargin) / (tableWidth + 2 * paddleTravelMargin)
    }

    public func half(atY y: Double) -> Side {
        y < tableLength / 2 ? .playerA : .playerB
    }

    func steps(_ seconds: Double) -> UInt64 {
        UInt64((seconds * Double(stepsPerSecond)).rounded(.down))
    }

    var stepDuration: Double {
        1 / Double(stepsPerSecond)
    }

    var physicsStep: Double {
        stepDuration * timeScale
    }
}

extension Side {
    public var playerName: String {
        self == .playerA ? "Player A" : "Player B"
    }

    public var opponent: Side {
        self == .playerA ? .playerB : .playerA
    }

    var forward: Double {
        self == .playerA ? 1 : -1
    }
}
