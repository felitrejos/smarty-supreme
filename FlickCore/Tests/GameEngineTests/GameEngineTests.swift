import FlickCore
import Foundation
import Testing

struct GameEngineTests {
    @Test func sideWallsReflectTheBallWithTheAnglePreserved() throws {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.run(steps: 120) { _ in StepInput(targetA: 1) }
        _ = game.step(StepInput(swings: [serve(.playerA, in: game, aim: 1)]))

        var before = game.ball.velocity
        var bounced = false
        for _ in 0..<500 where !bounced {
            before = game.ball.velocity
            bounced = game.step(StepInput()).contains(.wallBounce)
        }

        #expect(bounced)
        #expect(game.ball.velocity.x == -before.x)
        #expect(game.ball.velocity.y == before.y)
        #expect(game.ball.position.x <= game.config.tableWidth - game.config.ballRadius)
    }

    @Test func ballCrossingAGoalLineScoresForTheOtherSide() {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        let events = game.run(until: scoredAPoint)

        #expect(events.contains(.pointScored(winner: .playerA, score: Score(a: 1, b: 0))))
        #expect(game.score == Score(a: 1, b: 0))
    }

    @Test func swingWithTheBallInTheZoneAndWithinReachReturnsIt() {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        _ = game.run(until: { state, _ in state.ball.position.y >= state.zoneMiddle(of: .playerB) }, input: tracking(.playerB))

        let events = game.step(StepInput(swings: [Swing(side: .playerB, step: game.step, strength: 0.5, aim: 0)]))

        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(game.ball.velocity.y < 0)
    }

    @Test func swingOutsideTheZoneIsAWhiffAndBlocksSwingsForThreeHundredMilliseconds() {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        let zoneStart = game.config.paddleFaceY(of: .playerB) - game.config.zoneDepth(forSpeed: game.config.startSpeed)
        _ = game.run(until: { state, _ in state.ball.position.y >= zoneStart - 0.012 }, input: tracking(.playerB))

        let whiff = game.step(StepInput(swings: [Swing(side: .playerB, step: game.step, strength: 0.5, aim: 0)]))
        _ = game.run(steps: 24, input: tracking(.playerB))
        let blocked = game.step(StepInput(swings: [Swing(side: .playerB, step: game.step, strength: 0.5, aim: 0)]))
        let rest = game.run(until: scoredAPoint, input: tracking(.playerB))

        #expect(whiff == [.whiff(.playerB)])
        #expect(blocked.isEmpty)
        #expect(rest.contains(.pointScored(winner: .playerA, score: Score(a: 1, b: 0))))
    }

    @Test func aReturnFollowsTheSpeedAndAngleRules() throws {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        _ = game.run(until: { state, _ in state.ball.position.y >= state.zoneMiddle(of: .playerB) }, input: tracking(.playerB))
        let incoming = game.ball.speed

        _ = game.step(StepInput(swings: [Swing(side: .playerB, step: game.step, strength: 0.5, aim: 0.5)]))

        let speed = incoming * 1.03 + 0.5 * 0.4
        let angle = 0.3 * 0.5 * 50 * Double.pi / 180
        #expect(abs(game.ball.velocity.x - sin(angle) * speed) < 1e-12)
        #expect(abs(game.ball.velocity.y + cos(angle) * speed) < 1e-12)
    }

    @Test(arguments: [(0.95, true), (0.5, false)])
    func aReturnOffTheOuterPartOfThePaddleIsAnEdgeHit(share: Double, isEdge: Bool) {
        var game = GameState(seed: 1, config: straightServes())
        let config = game.config
        let reach = config.paddleWidth / 2 + config.ballRadius
        let target = config.position(ofPaddleX: config.tableWidth / 2 + share * reach)
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        _ = game.run(until: { state, _ in state.ball.position.y >= state.zoneMiddle(of: .playerB) }, input: { _ in StepInput(targetB: target) })

        let events = game.step(StepInput(targetB: target, swings: [Swing(side: .playerB, step: game.step, strength: 0.5, aim: 0)]))

        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(events.contains(.edgeHit(.playerB)) == isEdge)
    }

    @Test func aReturnNeverExceedsTheMaximumSpeed() throws {
        var config = straightServes()
        config.startSpeed = 1.7
        var game = GameState(seed: 1, config: config)
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        _ = game.run(until: { state, _ in state.ball.position.y >= state.zoneMiddle(of: .playerB) }, input: tracking(.playerB))
        _ = game.step(StepInput(swings: [Swing(side: .playerB, step: game.step, strength: 1, aim: 0)]))
        #expect(abs(game.ball.speed - config.maximumSpeed) < 1e-12)
    }

    @Test func swingsWorkAgainOnceTheWhiffCooldownIsOver() {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        let zoneStart = game.config.paddleFaceY(of: .playerB) - game.config.zoneDepth(forSpeed: game.config.startSpeed)
        _ = game.run(until: { state, _ in state.ball.position.y >= zoneStart - 0.126 }, input: tracking(.playerB))
        let whiff = game.step(StepInput(swings: [Swing(side: .playerB, step: game.step, strength: 0.5, aim: 0)]))
        _ = game.run(steps: 71, input: tracking(.playerB))
        let hit = game.step(StepInput(swings: [Swing(side: .playerB, step: game.step, strength: 0.5, aim: 0)]))

        #expect(whiff == [.whiff(.playerB)])
        #expect(hit.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
    }

    @Test func pausingMidRallyFreezesTheBallAndASwingFromJustBeforeStillCounts() {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        _ = game.run(until: { state, _ in state.ball.position.y >= state.zoneMiddle(of: .playerB) }, input: tracking(.playerB))
        let swingStep = game.step
        let position = game.ball.position

        _ = game.step(StepInput(command: .pause))
        _ = game.run(steps: 2_400, input: tracking(.playerB))
        let events = game.step(StepInput(swings: [Swing(side: .playerB, step: swingStep, strength: 0.5, aim: 0)], command: .resume))

        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(abs(game.ball.position.y - position.y) < 0.01)
    }

    @Test func thePauseBetweenPointsAndTheServeTimerStandStillWhilePaused() {
        var game = GameState(seed: 1)
        _ = game.run(steps: 1_000)
        _ = game.step(StepInput(command: .pause))
        _ = game.run(steps: 5_000)
        _ = game.step(StepInput(command: .resume))
        let before = game.run(steps: 198)
        let at = game.step(StepInput())

        #expect(!before.contains(.served(.playerA)))
        #expect(at.contains(.served(.playerA)))
    }

    @Test func contactExactlyAtTheReachLimitCountsAsAHit() {
        var config = GameConfig()
        config.paddleWidth = 0.125
        config.ballRadius = 0.007_812_5
        #expect(config.canReach(ballX: 0.320_312_5, paddleX: 0.25))
        #expect(config.canReach(ballX: 0.179_687_5, paddleX: 0.25))
        #expect(!config.canReach(ballX: 0.320_312_5 + 0x1p-20, paddleX: 0.25))
    }

    @Test(arguments: [(10, 3, true), (16, 5, false)])
    func lagCompensationLooksBackAtMostSixtyMilliseconds(stepsAfterFace: Int, claimedStepsBeforeFace: Int, hits: Bool) {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        let face = game.config.paddleFaceY(of: .playerB)
        _ = game.run(until: { state, _ in state.ball.position.y >= face }, input: tracking(.playerB))
        let faceStep = game.step
        _ = game.run(steps: stepsAfterFace - 1, input: tracking(.playerB))

        let claimed = faceStep - UInt64(claimedStepsBeforeFace)
        let events = game.step(StepInput(swings: [Swing(side: .playerB, step: claimed, strength: 0.5, aim: 0)]))

        #expect(events.contains { if case .hit = $0 { true } else { false } } == hits)
        #expect(events.contains(.whiff(.playerB)) == !hits)
    }

    @Test func aLateSwingCanSaveABallThatHasJustCrossedTheGoalLine() {
        var config = straightServes()
        config.startSpeed = config.maximumSpeed
        var game = GameState(seed: 1, config: config)
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        let face = config.paddleFaceY(of: .playerB)
        _ = game.run(until: { state, _ in state.ball.position.y >= face }, input: tracking(.playerB))
        let faceStep = game.step
        _ = game.run(until: { state, _ in state.ball.position.y > config.tableLength }, input: tracking(.playerB))
        _ = game.run(steps: 2, input: tracking(.playerB))

        let events = game.step(StepInput(swings: [Swing(side: .playerB, step: faceStep - 2, strength: 0.5, aim: 0)]))
        let later = game.run(steps: 100)

        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(!later.contains { if case .pointScored = $0 { true } else { false } })
        #expect(game.score == Score(a: 0, b: 0))
    }

    @Test(arguments: [0.3, 0.6, 1.2, 1.8])
    func theBallSpendsAtLeastOneHundredEightyMillisecondsInTheHitZone(speed: Double) {
        var config = straightServes()
        config.startSpeed = speed
        config.strengthBoost = 0
        var game = GameState(seed: 1, config: config)
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        let face = config.paddleFaceY(of: .playerB)
        let depth = config.zoneDepth(forSpeed: speed)
        var stepsInZone = 0
        while game.ball.position.y < face {
            _ = game.step(StepInput())
            if game.ball.position.y >= face - depth, game.ball.position.y <= face {
                stepsInZone += 1
            }
        }
        #expect(Double(stepsInZone) >= 0.18 * Double(config.stepsPerSecond) - 1)
    }

    @Test func atMaximumSpeedTheBallNeverLeavesTheTableSidesOrSkipsTheHitZone() {
        var config = GameConfig()
        config.startSpeed = config.maximumSpeed
        config.serveSpreadDegrees = 40
        let low = config.ballRadius
        let high = config.tableWidth - config.ballRadius
        let face = config.paddleFaceY(of: .playerB)
        let zoneStart = face - config.zoneDepth(forSpeed: config.maximumSpeed)
        var random = SplitMix64(seed: 99)

        for seed in 0..<10_000 as Range<UInt64> {
            var game = GameState(seed: seed, config: config)
            let aim = Double.random(in: -1...1, using: &random)
            _ = game.step(StepInput(swings: [serve(.playerA, in: game, aim: aim)]))
            var stepsInZone = 0
            var insideWalls = true
            while game.ball.position.y < face {
                _ = game.step(StepInput())
                insideWalls = insideWalls && game.ball.position.x >= low - 1e-12 && game.ball.position.x <= high + 1e-12
                if game.ball.position.y >= zoneStart, game.ball.position.y <= face {
                    stepsInZone += 1
                }
            }
            guard insideWalls, stepsInZone > 0 else {
                Issue.record("Seed \(seed): inside walls \(insideWalls), steps in zone \(stepsInZone)")
                return
            }
        }
    }

    @Test func paddleNeverMovesFasterThanThreeTableWidthsPerSecond() {
        var game = GameState(seed: 1)
        var positions = [game.paddleX(of: .playerA)]
        for _ in 0..<200 {
            _ = game.step(StepInput(targetA: positions.count < 100 ? 1 : 0))
            positions.append(game.paddleX(of: .playerA))
        }
        let limit = 3 * game.config.tableWidth / Double(game.config.stepsPerSecond) + 1e-12
        #expect(zip(positions, positions.dropFirst()).allSatisfy { abs($1 - $0) <= limit })
        #expect(positions.max()! > game.config.tableWidth * 0.8)
    }

    @Test func paddlePositionIsTheTargetScaleItWasMovedWith() {
        var game = GameState(seed: 1)
        _ = game.run(steps: 200) { _ in StepInput(targetA: 0.25, targetB: 1) }
        #expect(abs(game.paddlePosition(of: .playerA) - 0.25) < 1e-12)
        #expect(abs(game.paddlePosition(of: .playerB) - 1) < 1e-12)
    }

    @Test func theServerServesAutomaticallyAfterFiveSeconds() {
        var game = GameState(seed: 1)
        let before = game.run(steps: 1_199)
        let at = game.step(StepInput())
        #expect(!before.contains(.served(.playerA)))
        #expect(at.contains(.served(.playerA)))
    }

    @Test func swingsAreIgnoredWhilePausedWithoutStartingACooldown() {
        var game = GameState(seed: 1)
        let paused = game.step(StepInput(command: .pause))
        let swing = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        _ = game.step(StepInput(command: .resume))
        let served = game.step(StepInput(swings: [serve(.playerA, in: game)]))

        #expect(paused == [.paused])
        #expect(swing.isEmpty)
        #expect(served.contains(.served(.playerA)))
    }

    @Test func pausingTwiceStillResumesWithOneResume() {
        var game = GameState(seed: 1)
        _ = game.step(StepInput(command: .pause))
        _ = game.step(StepInput(command: .pause))
        _ = game.step(StepInput(command: .resume))
        let served = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        #expect(served.contains(.served(.playerA)))
    }

    @Test func aBallMovingAwayCannotBeHitAgainEvenWithoutACooldown() {
        var config = straightServes()
        config.swingCooldown = 0
        var game = GameState(seed: 1, config: config)
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        let again = game.step(StepInput(swings: [Swing(side: .playerA, step: game.step, strength: 1, aim: 0)]))
        #expect(again == [.whiff(.playerA)])
        #expect(game.ball.velocity.y > 0)
    }

    @Test func swingsAreIgnoredBetweenPoints() {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        _ = game.run(until: scoredAPoint)

        let between = game.step(StepInput(swings: [serve(.playerA, in: game), serve(.playerB, in: game)]))
        _ = game.run(until: { state, _ in if case .serving = state.phase { true } else { false } })
        let served = game.step(StepInput(swings: [serve(.playerA, in: game)]))

        #expect(between.isEmpty)
        #expect(served.contains(.served(.playerA)))
    }

    @Test func aGameEndsAtElevenWhenTheOpponentNeverReturns() {
        var game = GameState(seed: 1, config: straightServes())
        var events: [GameEvent] = []
        for _ in 0..<40_000 {
            if case .gameOver = game.phase { break }
            events += game.step(returning(.playerA)(game))
        }
        #expect(game.phase == .gameOver(winner: .playerA))
        #expect(events.last == .gameOver(winner: .playerA))
        #expect(game.score == Score(a: 11, b: 0))
    }

    @Test func sameSeedAndInputsGiveTheSameGameAfterOneHundredThousandSteps() {
        let first = randomPlay(seed: 21)
        let second = randomPlay(seed: 21)
        #expect(first.game == second.game)
        #expect(first.events == second.events)
        #expect(first.game != randomPlay(seed: 22).game)
    }
}

struct ForfeitTests {
    @Test func aForfeitMidRallyEndsTheGameWithTheScoreSoFar() {
        var game = GameState(seed: 1, config: straightServes())
        _ = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        _ = game.run(until: scoredAPoint)
        _ = game.run(until: { state, _ in state.phase == .rally }, input: returning(.playerA))

        let events = game.step(StepInput(command: .forfeit(.playerA)))

        #expect(events == [.gameOver(winner: .playerB)])
        #expect(game.phase == .gameOver(winner: .playerB))
        #expect(game.score == Score(a: 1, b: 0))
    }

    @Test func aForfeitWhilePausedEndsTheGameAndResumeDoesNothing() {
        var game = GameState(seed: 1)
        _ = game.step(StepInput(command: .pause))

        let forfeit = game.step(StepInput(command: .forfeit(.playerB)))
        let resume = game.step(StepInput(command: .resume))

        #expect(forfeit == [.gameOver(winner: .playerA)])
        #expect(resume.isEmpty)
        #expect(game.phase == .gameOver(winner: .playerA))
    }

    @Test func aForfeitAfterTheGameIsOverChangesNothing() {
        var game = GameState(seed: 1)
        _ = game.step(StepInput(command: .forfeit(.playerB)))

        let again = game.step(StepInput(command: .forfeit(.playerA)))

        #expect(again.isEmpty)
        #expect(game.phase == .gameOver(winner: .playerA))
    }
}

struct ScoreTests {
    @Test(arguments: [
        (11, 9, Side.playerA as Side?), (11, 10, nil), (12, 10, .playerA), (10, 12, .playerB), (9, 11, .playerB), (10, 10, nil),
    ])
    func firstToElevenWinsByTwo(a: Int, b: Int, winner: Side?) {
        #expect(Score(a: a, b: b).winner(target: 11) == winner)
    }

    @Test(arguments: [
        (0, 0, Side.playerA), (1, 0, .playerA), (1, 1, .playerB), (3, 0, .playerB), (2, 2, .playerA),
        (10, 10, .playerA), (11, 10, .playerB), (11, 11, .playerA), (12, 11, .playerB), (9, 10, .playerB),
    ])
    func serveSwapsEveryTwoPointsAndEveryPointAtDeuce(a: Int, b: Int, server: Side) {
        #expect(Score(a: a, b: b).server(firstServer: .playerA, target: 11, servesPerTurn: 2) == server)
    }
}

func straightServes() -> GameConfig {
    var config = GameConfig()
    config.serveSpreadDegrees = 0
    return config
}

func serve(_ side: Side, in game: GameState, aim: Double = 0) -> Swing {
    Swing(side: side, step: game.step, strength: 0, aim: aim)
}

func scoredAPoint(_ state: GameState, _ events: [GameEvent]) -> Bool {
    events.contains { if case .pointScored = $0 { true } else { false } }
}

func returning(_ side: Side) -> (GameState) -> StepInput {
    { game in
        var input = tracking(side)(game)
        let approaching = (game.ball.velocity.y < 0) == (side == .playerA)
        let face = game.config.paddleFaceY(of: side)
        let inZone = abs(game.ball.position.y - face) < game.config.zoneDepth(forSpeed: game.config.startSpeed) / 2
        if case .serving(side, _) = game.phase {
            input.swings = [serve(side, in: game)]
        } else if case .rally = game.phase, approaching, inZone {
            input.swings = [Swing(side: side, step: game.step, strength: 0, aim: 0)]
        }
        return input
    }
}

func tracking(_ side: Side) -> (GameState) -> StepInput {
    { game in
        let config = game.config
        let half = config.paddleWidth / 2
        let position = (game.ball.position.x - half) / (config.tableWidth - 2 * half)
        return side == .playerA ? StepInput(targetA: position) : StepInput(targetB: position)
    }
}

func randomPlay(seed: UInt64) -> (game: GameState, events: [GameEvent]) {
    var random = SplitMix64(seed: seed)
    var game = GameState(seed: seed)
    var events: [GameEvent] = []
    for _ in 0..<100_000 {
        var input = StepInput(targetA: Double.random(in: 0...1, using: &random), targetB: Double.random(in: 0...1, using: &random))
        if Int.random(in: 0..<40, using: &random) == 0 {
            let side: Side = Bool.random(using: &random) ? .playerA : .playerB
            let lag = UInt64.random(in: 0...30, using: &random)
            input.swings = [Swing(side: side, step: game.step - min(lag, game.step), strength: Double.random(in: 0...1, using: &random), aim: Double.random(in: -1...1, using: &random))]
        }
        events += game.step(input)
    }
    return (game, events)
}

extension GameState {
    func zoneMiddle(of side: Side) -> Double {
        let face = config.paddleFaceY(of: side)
        let depth = config.zoneDepth(forSpeed: (ball.velocity.x * ball.velocity.x + ball.velocity.y * ball.velocity.y).squareRoot())
        return side == .playerB ? face - depth / 2 : face + depth / 2
    }

    mutating func run(steps: Int, input: (GameState) -> StepInput = { _ in StepInput() }) -> [GameEvent] {
        var events: [GameEvent] = []
        for _ in 0..<steps {
            events += step(input(self))
        }
        return events
    }

    mutating func run(
        until done: (GameState, [GameEvent]) -> Bool,
        input: (GameState) -> StepInput = { _ in StepInput() },
        limit: Int = 20_000
    ) -> [GameEvent] {
        var events: [GameEvent] = []
        for _ in 0..<limit {
            events += step(input(self))
            if done(self, events) { return events }
        }
        Issue.record("Condition not reached within \(limit) steps")
        return events
    }
}
