import Foundation

public struct AIController: Sendable {
    public struct Move: Sendable {
        public let target: Double
        public let swing: Swing?
    }

    private struct Plan: Sendable {
        let paddleX: Double
        let swingAt: UInt64
        var hasSwung = false
    }

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
            return Move(target: position(of: current, in: game.config), swing: nil)
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
                    swing = makeSwing(in: game)
                    self.plan?.hasSwung = true
                }
            }
        } else {
            approachingSince = nil
            plan = nil
            if case .serving(side, let since) = game.phase, game.step - since >= steps(profile.serveDelay, in: game.config) {
                swing = makeSwing(in: game)
            }
        }
        let next = moved(current, toward: goal, in: game.config)
        return Move(target: position(of: next, in: game.config), swing: swing)
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
        return Plan(
            paddleX: path.position(after: seconds).x + gaussian() * profile.aimError,
            swingAt: game.step + UInt64((swingSeconds * Double(config.stepsPerSecond)).rounded())
        )
    }

    private mutating func makeSwing(in game: GameState) -> Swing {
        let strength = Double.random(in: profile.strength, using: &random)
        let aim: Double
        if Double.random(in: 0..<1, using: &random) < profile.aimsAwayShare {
            aim = game.paddlePosition(of: side.opponent) < 0.5 ? 1 : -1
        } else {
            aim = Double.random(in: -1...1, using: &random)
        }
        return Swing(side: side, step: game.step, strength: strength, aim: aim)
    }

    private func moved(_ x: Double, toward goal: Double, in config: GameConfig) -> Double {
        let maximumMove = profile.paddleSpeedInTableWidths * config.tableWidth / Double(config.stepsPerSecond)
        return x + min(max(goal - x, -maximumMove), maximumMove)
    }

    private func position(of x: Double, in config: GameConfig) -> Double {
        let half = config.paddleWidth / 2
        return (x - half) / (config.tableWidth - 2 * half)
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
