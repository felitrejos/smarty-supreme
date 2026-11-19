import SmartyCore
import simd
import Testing

struct PredictionTests {
    @Test func thePredictedContactIsWhereTheEngineOffersTheChance() throws {
        var game = GameState(seed: 1)
        _ = game.step(StepInput(swings: [Swing(side: .playerA, step: game.step, strength: 0.4, aim: 1)]))
        let contact = try #require(game.predictedContact(for: .playerB))

        for _ in 1..<contact.stepsAway {
            _ = game.step(StepInput())
        }
        #expect(game.predictedContact(for: .playerB)?.stepsAway == 1)
        _ = game.step(StepInput())

        #expect(simd_distance(game.ball.position, contact.position) < 1e-9)
    }

    @Test func aBallGoingAwayHasNoContactForTheHitter() {
        var game = GameState(seed: 1)
        _ = game.step(StepInput(swings: [Swing(side: .playerA, step: game.step, strength: 0, aim: 0)]))

        #expect(game.predictedContact(for: .playerA) == nil)
    }
}

struct AIControllerTests {
    @Test(arguments: Difficulty.allCases)
    func paddleNeverMovesFasterThanTheSpeedCap(difficulty: Difficulty) {
        var duel = Duel(seed: 3, playerA: .scriptedAverage, playerB: difficulty.profile)
        let config = duel.game.config
        let limit = difficulty.profile.paddleSpeedInTableWidths * config.tableWidth / Double(config.stepsPerSecond)
        var fastest = 0.0
        while !duel.isOver {
            let before = duel.game.paddleX(of: .playerB)
            _ = duel.step()
            fastest = max(fastest, abs(duel.game.paddleX(of: .playerB) - before))
        }

        #expect(fastest > limit * 0.99)
        #expect(fastest <= limit * (1 + 1e-9))
    }

    @Test(arguments: Difficulty.allCases)
    func aiOnlyGoesForTheBallOnceItsReactionDelayHasPassed(difficulty: Difficulty) {
        var duel = Duel(seed: 4, playerA: .scriptedAverage, playerB: difficulty.profile)
        let reactionSteps = UInt64((difficulty.profile.reactionDelay * Double(duel.game.config.stepsPerSecond)).rounded(.up))
        let middle = duel.game.config.tableWidth / 2
        var approachingSince: UInt64?
        var swings = 0
        var reactions = 0
        while !duel.isOver {
            if duel.game.isComing(to: .playerB) {
                approachingSince = approachingSince ?? duel.game.step
            } else {
                approachingSince = nil
            }
            let before = abs(duel.game.paddleX(of: .playerB) - middle)
            let turn = duel.step()
            let after = abs(duel.game.paddleX(of: .playerB) - middle)
            guard let since = approachingSince else { continue }
            let elapsed = turn.stepBefore - since
            if elapsed < reactionSteps {
                #expect(after <= before + 1e-12)
            } else if elapsed == reactionSteps, after > before {
                reactions += 1
            }
            for swing in turn.swingsB {
                swings += 1
                #expect(swing.step - since >= reactionSteps)
            }
        }

        #expect(reactions > 10)
        #expect(swings > 10)
    }

    @Test func returnsAimedAwayLandOnTheSideThePlayerIsNotOn() {
        func awayShare(aimsAwayShare: Double) -> Double {
            var profile = Difficulty.medium.profile
            profile.aimsAwayShare = aimsAwayShare
            var away = 0
            var returns = 0
            for seed in 0..<12 {
                var duel = Duel(seed: UInt64(seed) &+ 100, playerA: .scriptedAverage, playerB: profile)
                while !duel.isOver {
                    let turn = duel.step()
                    let game = duel.game
                    guard turn.events.contains(where: { if case .hit(.playerB, _, _) = $0 { true } else { false } }),
                          let contact = game.predictedContact(for: .playerA) else { continue }
                    let farLane: Lane = game.paddlePosition(of: .playerA) < 0.5 ? .right : .left
                    returns += 1
                    away += Lane(x: contact.position.x, config: game.config) == farLane ? 1 : 0
                }
            }
            return Double(away) / Double(returns)
        }

        #expect(awayShare(aimsAwayShare: 1) > awayShare(aimsAwayShare: 0) + 0.1)
    }

    @Test func theSameSeedsPlayTheSameMatch() {
        var first = Duel(seed: 5, playerA: .scriptedAverage, playerB: Difficulty.medium.profile)
        var second = Duel(seed: 5, playerA: .scriptedAverage, playerB: Difficulty.medium.profile)
        var otherSeed = Duel(seed: 5, aiSeed: 6, playerA: .scriptedAverage, playerB: Difficulty.medium.profile)

        let firstEvents = first.playToTheEnd()
        let secondEvents = second.playToTheEnd()
        let otherEvents = otherSeed.playToTheEnd()

        #expect(firstEvents == secondEvents)
        #expect(first.game == second.game)
        #expect(otherEvents != firstEvents)
    }

    @Test func aiServesItselfAfterItsServeDelay() {
        let profile = Difficulty.medium.profile
        var duel = Duel(seed: 7, playerA: .scriptedAverage, playerB: profile)
        let serveDelay = UInt64((profile.serveDelay * Double(duel.game.config.stepsPerSecond)).rounded())
        var serves = 0
        while !duel.isOver {
            guard case .serving(.playerB, let since) = duel.game.phase else {
                _ = duel.step()
                continue
            }
            let turn = duel.step()
            if turn.events.contains(.served(.playerB)) {
                serves += 1
                #expect(duel.game.step - 1 - since == serveDelay)
            }
        }

        #expect(serves >= 5)
    }

    @Test func whilePausedTheAiHoldsStillAndStillReturnsTheBallOnceResumed() {
        var profile = Difficulty.hard.profile
        profile.aimError = 0
        profile.timingError = 0
        var duel = Duel(seed: 10, playerA: .scriptedAverage, playerB: profile)
        while !duel.game.isComing(to: .playerB) {
            _ = duel.step()
        }
        _ = duel.step(command: .pause)
        let pausedAt = duel.game.paddleX(of: .playerB)
        for _ in 0..<500 {
            let turn = duel.step()
            #expect(turn.swingsB.isEmpty)
        }
        #expect(duel.game.phase == .paused)
        #expect(duel.game.paddleX(of: .playerB) == pausedAt)

        var events = duel.step(command: .resume).events
        while !events.contains(where: { if case .pointScored = $0 { true } else { false } }) {
            events += duel.step().events
        }

        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
    }

    @Test func betweenBallsTheAiDriftsBackToTheMiddle() {
        let profile = Difficulty.easy.profile
        var duel = Duel(seed: 9, playerA: .scriptedAverage, playerB: profile)
        let config = duel.game.config
        let middle = config.tableWidth / 2
        let longestDrift = (config.tableWidth / 2 + config.paddleTravelMargin) / (profile.paddleSpeedInTableWidths * config.tableWidth)
        let settledAfter = Int((longestDrift * Double(config.stepsPerSecond)).rounded(.up)) + 1
        var stepsAway = 0
        var checked = 0
        while !duel.isOver {
            _ = duel.step()
            guard case .rally = duel.game.phase, !duel.game.isComing(to: .playerB) else {
                stepsAway = 0
                continue
            }
            stepsAway += 1
            if stepsAway > settledAfter {
                checked += 1
                #expect(abs(duel.game.paddleX(of: .playerB) - middle) < 1e-9)
            }
        }

        #expect(checked > 100)
    }
}

struct Duel {
    struct Turn {
        let stepBefore: UInt64
        let events: [GameEvent]
        let swingsB: [Swing]
    }

    struct Weakness {
        let lane: Lane
        let missShare: Double
    }

    private(set) var game: GameState
    private var playerA: AIController
    private var playerB: AIController
    private let weaknessA: Weakness?
    private var weaknessRandom: SplitMix64

    init(
        seed: UInt64,
        aiSeed: UInt64? = nil,
        config: GameConfig = GameConfig(),
        playerA: AIProfile,
        playerB: AIProfile,
        weaknessA: Weakness? = nil
    ) {
        game = GameState(seed: seed, config: config)
        self.weaknessA = weaknessA

        weaknessRandom = SplitMix64(seed: seed &+ 3)
        self.playerA = AIController(side: .playerA, profile: playerA, seed: seed &+ 1)
        self.playerB = AIController(side: .playerB, profile: playerB, seed: aiSeed ?? seed &+ 2)
    }

    var isOver: Bool {
        if case .gameOver = game.phase { return true }
        return false
    }

    var winner: Side? {
        if case .gameOver(let winner) = game.phase { return winner }
        return nil
    }

    mutating func step(command: GameCommand? = nil) -> Turn {
        let stepBefore = game.step
        let moveA = playerA.move(in: game)
        let moveB = playerB.move(in: game)
        let swingsB = moveB.swing.map { [$0] } ?? []
        var swingsA = moveA.swing.map { [$0] } ?? []
        if let weaknessA, !swingsA.isEmpty, case .rally = game.phase, Lane(x: game.ball.position.x, config: game.config) == weaknessA.lane,
           Double.random(in: 0..<1, using: &weaknessRandom) < weaknessA.missShare {
            swingsA = []
        }
        let input = StepInput(targetA: moveA.target, targetB: moveB.target, swings: swingsA + swingsB, command: command)
        return Turn(stepBefore: stepBefore, events: game.step(input), swingsB: swingsB)
    }

    mutating func playToTheEnd() -> [GameEvent] {
        var events: [GameEvent] = []
        while !isOver {
            events += step().events
        }
        return events
    }
}

extension AIProfile {
    static let scriptedAverage = AIProfile(
        reactionDelay: 0.18,
        aimError: 0.08,
        paddleSpeedInTableWidths: 1.1,
        timingError: 0.035,
        strength: 0.2...0.7,
        aimsAwayShare: 0
    )
}

