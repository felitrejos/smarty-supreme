import Foundation

public struct AIController: Sendable {
    public struct Move: Sendable {
        public let target: Double
        public let swing: Swing?
    }

    private struct Plan: Sendable {
        let paddleX: Double
        let swingAt: UInt64?
        let aim: Double
        var hasSwung = false
    }

    private static let steeringContact = 0.3

    private let side: Side
    private let profile: AIProfile
    private var random: SplitMix64
    private var comingSince: UInt64?
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
        if game.isComing(to: side) {
            let since = comingSince ?? game.step
            comingSince = since
            if plan == nil, game.step - since >= steps(profile.reactionDelay, in: game.config) {
                plan = makePlan(for: game, from: current)
            }
            if let plan {
                goal = plan.paddleX
                if !plan.hasSwung, let swingAt = plan.swingAt, game.step >= swingAt {
                    swing = makeSwing(in: game, aim: plan.aim)
                    self.plan?.hasSwung = true
                }
            }
        } else {
            comingSince = nil
            plan = nil
            if case .serving(side, let since) = game.phase, game.step - since >= steps(profile.serveDelay, in: game.config) {
                swing = makeSwing(in: game, aim: steerAway(in: game).aim)
            }
        }
        let next = moved(current, toward: goal, in: game.config)
        return Move(target: game.config.position(ofPaddleX: next), swing: swing)
    }

    private mutating func makePlan(for game: GameState, from current: Double) -> Plan {
        let config = game.config
        guard let contact = game.predictedContact(for: side) else {
            return Plan(paddleX: current, swingAt: nil, aim: 0)
        }
        let contactStep = Double(game.step + contact.stepsAway)
        let swingAt = UInt64(max(contactStep + gaussian() * profile.timingError * Double(config.stepsPerSecond), Double(game.step)).rounded())
        let steering = Double.random(in: 0..<1, using: &random) < profile.aimsAwayShare
            ? steerAway(in: game)
            : (contact: 0, aim: Double.random(in: -1...1, using: &random))
        return Plan(
            paddleX: contact.position.x - steering.contact * config.reach + gaussian() * profile.aimError,
            swingAt: swingAt,
            aim: steering.aim
        )
    }

    private func steerAway(in game: GameState) -> (contact: Double, aim: Double) {
        let config = game.config
        let target = (game.paddlePosition(of: side.opponent) < 0.5 ? Lane.right : Lane.left).centre(in: config)
        let wanted = min(max((target - config.tableWidth / 2) / (config.lateralSpan * config.tableWidth / 2), -1), 1)
        let aimShare = 1 - config.contactShare
        let aim = wanted >= 0 ? min(wanted / aimShare, 1) : max(wanted / aimShare, -1)
        guard config.contactShare > 0 else { return (0, aim) }
        let contact = min(max((wanted - aimShare * aim) / config.contactShare, -Self.steeringContact), Self.steeringContact)
        return (contact, aim)
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
