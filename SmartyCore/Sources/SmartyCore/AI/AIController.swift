import Foundation

public struct AIController: Sendable {
    public struct Move: Sendable {
        public let target: Double
        public let swing: Swing?
    }

    private struct Plan: Sendable {
        let paddleX: Double
        let swingAt: UInt64
        let aim: Double
        var hasSwung = false
    }

    private static let steeringContact = 0.6

    private let side: Side
    private let profile: AIProfile
    private var random: SplitMix64
    private var approachingSince: UInt64?
    private var plan: Plan?

    public init(side: Side, profile: AIProfile, seed: UInt64) {
        self.side = side
        self.profile = profile
        random = SplitMix64(seed: seed)
    }

    public mutating func move(in game: GameState) -> Move {
        let current = game.paddleX(of: side)
        switch game.phase {
        case .paused, .gameOver:
            return Move(target: game.config.position(ofPaddleX: current), swing: nil)
        case .serving, .rally, .pointScored:
            break
        }
        var goal = game.config.tableWidth / 2
        var swing: Swing?
        if isApproaching(in: game) {
            let since = approachingSince ?? game.step
            approachingSince = since
            if plan == nil, game.step - since >= steps(profile.reactionDelay, in: game.config) {
                plan = makePlan(for: game)
            }
            if let plan {
                goal = plan.paddleX
                if !plan.hasSwung, game.step >= plan.swingAt {
                    swing = makeSwing(in: game, aim: plan.aim)
                    self.plan?.hasSwung = true
                }
            }
        } else {
            approachingSince = nil
            plan = nil
            if case .serving(side, let since) = game.phase, game.step - since >= steps(profile.serveDelay, in: game.config) {
                swing = makeSwing(in: game, aim: aim(in: game))
            }
        }
        let next = moved(current, toward: goal, in: game.config)
        return Move(target: game.config.position(ofPaddleX: next), swing: swing)
    }

    private func isApproaching(in game: GameState) -> Bool {
        guard case .rally = game.phase else { return false }
        return game.ball.velocity.y * side.forward < 0
    }

    private mutating func makePlan(for game: GameState) -> Plan {
        let config = game.config
        let path = BallPath(ball: game.ball, config: config)
        let zoneMiddle = config.paddleFaceY(of: side) + side.forward * config.zoneDepth(forSpeed: game.ball.speed) / 2
        let seconds = path.secondsUntil(y: zoneMiddle) ?? 0
        let swingSeconds = max(seconds + gaussian() * profile.timingError, 0)
        let contactX = path.position(after: seconds).x
        let steering = Double.random(in: 0..<1, using: &random) < profile.aimsAwayShare ? steerAway(from: contactX, in: game) : nil
        let reach = config.paddleWidth / 2 + config.ballRadius
        return Plan(
            paddleX: contactX - (steering?.contact ?? 0) * reach + gaussian() * profile.aimError,
            swingAt: game.step + UInt64((swingSeconds * Double(config.stepsPerSecond)).rounded()),
            aim: steering?.aim ?? Double.random(in: -1...1, using: &random)
        )
    }

    private mutating func aim(in game: GameState) -> Double {
        Double.random(in: 0..<1, using: &random) < profile.aimsAwayShare
            ? steerAway(from: game.ball.position.x, in: game).aim
            : Double.random(in: -1...1, using: &random)
    }

    private func steerAway(from contactX: Double, in game: GameState) -> (contact: Double, aim: Double) {
        let config = game.config
        let target = (game.paddlePosition(of: side.opponent) < 0.5 ? Lane.right : Lane.left).centre(in: config)
        let distance = abs(config.paddleFaceY(of: side.opponent) - config.paddleFaceY(of: side))
        let low = config.ballRadius
        let high = config.tableWidth - config.ballRadius
        let maximumAngle = config.maximumReturnAngleDegrees * .pi / 180
        let angles = [target, 2 * low - target, 2 * high - target].map { atan(($0 - contactX) / distance) }
        let angle = angles.filter { abs($0) <= maximumAngle }.min { abs($0) < abs($1) } ?? 0
        let aimRange = (1 - config.contactShare) * maximumAngle
        let aimAngle = min(max(angle, -aimRange), aimRange)
        guard config.contactShare > 0 else { return (0, aimAngle / aimRange) }
        let contact = min(max((angle - aimAngle) / (config.contactShare * maximumAngle), -Self.steeringContact), Self.steeringContact)
        return (contact, aimAngle / aimRange)
    }

    private mutating func makeSwing(in game: GameState, aim: Double) -> Swing {
        Swing(side: side, step: game.step, strength: Double.random(in: profile.strength, using: &random), aim: aim)
    }

    private func moved(_ x: Double, toward goal: Double, in config: GameConfig) -> Double {
        let maximumMove = profile.paddleSpeedInTableWidths * config.tableWidth / Double(config.stepsPerSecond)
        return x + min(max(goal - x, -maximumMove), maximumMove)
    }

    private func steps(_ seconds: Double, in config: GameConfig) -> UInt64 {
        UInt64((seconds * Double(config.stepsPerSecond)).rounded(.up))
    }

    private mutating func gaussian() -> Double {
        let radius = Double.random(in: Double.leastNonzeroMagnitude...1, using: &random)
        let angle = Double.random(in: 0..<(2 * .pi), using: &random)
        return (-2 * log(radius)).squareRoot() * cos(angle)
    }
}
