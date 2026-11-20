import SmartyCore
import Foundation
import simd
import Testing

struct BallPhysicsTests {
    private let config = GameConfig()

    @Test func aDroppedBallBouncesBackToAboutTheRestitutionSquaredHeight() {
        var ball = Ball(position: SIMD3(0.7, 0.7, 0.3))
        var bounced = false
        var apex = 0.0
        for _ in 0..<2_000 {
            if BallPhysics.advance(&ball, seconds: 1.0 / 1_000, config: config) == .table(.playerA) {
                bounced = true
            }
            if bounced {
                apex = max(apex, ball.position.z)
            }
        }
        let expected = (0.3 - config.ballRadius) * config.tableRestitution * config.tableRestitution + config.ballRadius
        #expect(bounced)
        #expect(abs(apex - expected) < 0.02)
    }

    @Test func topspinPullsTheBallDownAndBackspinHoldsItUp() {
        func landing(spin: Double) -> Double {
            var ball = Ball(position: SIMD3(0.7, 0, 0.3), velocity: SIMD3(0, 6, 1), spin: SIMD3(spin, 0, 0))
            while ball.position.z > config.ballRadius {
                BallPhysicsTests.fly(&ball, config: config)
            }
            return ball.position.y
        }
        #expect(landing(spin: -300) < landing(spin: 0))
        #expect(landing(spin: 300) > landing(spin: 0))
    }

    @Test func aSlidingBounceTurnsSpeedIntoForwardSpin() {
        var ball = Ball(position: SIMD3(0.7, 1.8, 0.03), velocity: SIMD3(0, 5, -2))
        var contact: BallContact?
        for _ in 0..<50 where contact == nil {
            contact = BallPhysics.advance(&ball, seconds: 1.0 / 1_000, config: config)
        }
        #expect(contact == .table(.playerB))
        #expect(ball.velocity.y < 5)
        #expect(ball.velocity.z > 0)
        #expect(ball.spin.x < 0)
    }

    @Test func aBallBelowTheTapeIsStoppedByTheNet() {
        var ball = Ball(position: SIMD3(0.7, 1.3, 0.08), velocity: SIMD3(0, 6, 0))
        var contact: BallContact?
        for _ in 0..<100 where contact == nil {
            contact = BallPhysics.advance(&ball, seconds: 1.0 / 1_000, config: config)
        }
        #expect(contact == .net)
        #expect(ball.velocity.y < 0)
    }

    private static func fly(_ ball: inout Ball, config: GameConfig) {
        var free = config
        free.tableWidth = 0.001
        _ = BallPhysics.advance(&ball, seconds: 1.0 / 1_000, config: free)
    }
}

struct RallyRuleTests {
    @Test func aServeBouncesOnTheServersHalfThenOnTheReceiversHalf() {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        let events = game.run(until: { state, _ in state.predictedContact(for: .playerB)?.stepsAway == 1 })

        #expect(events.filter { if case .bounce = $0 { true } else { false } } == [.bounce(.playerA), .bounce(.playerB)])
    }

    @Test(arguments: [0.0, 0.5, 1.0])
    func everyServeStrengthLandsLegally(strength: Double) {
        for seed in 0..<20 as Range<UInt64> {
            var game = GameState(seed: seed)
            _ = serveAndToss(&game, strength: strength, aim: Double(seed % 3) - 1)
            #expect(game.predictedContact(for: .playerB) != nil, "Seed \(seed) strength \(strength)")
        }
    }

    @Test func anUnreturnedBallIsAPointToTheHitter() {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        let events = game.run(until: scoredAPoint)

        #expect(events.contains(.pointScored(winner: .playerA, score: Score(a: 1, b: 0))))
    }

    @Test func afterThePointTheBallKeepsFallingInsteadOfFreezing() {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        _ = game.run(until: scoredAPoint)
        let scoredAt = game.ball.position
        _ = game.run(steps: 20)

        #expect(simd_distance(game.ball.position, scoredAt) > 0.01)
    }

    @Test func aSwingWithNoBallComingIsAWhiffAndBlocksSwingsForThreeHundredMilliseconds() {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        _ = game.step(StepInput(swings: [Swing(side: .playerB, step: game.step, strength: 0.5, aim: 0)]))
        let whiff = game.run(steps: 30)
        _ = game.run(steps: 30)
        let blocked = game.step(StepInput(swings: [Swing(side: .playerB, step: game.step, strength: 0.5, aim: 0)]))
        let later = game.run(steps: 30)

        #expect(whiff.contains(.whiff(.playerB)))
        #expect(blocked.isEmpty)
        #expect(!later.contains(.whiff(.playerB)))
    }
}

struct PlannedShotTests {
    @Test func aWellTimedReturnLandsDeepOnTheOtherHalf() {
        let landing = returnLanding(timing: 0)

        #expect(landing.half == .playerA)
        #expect(landing.y < 0.6)
    }

    @Test func anEarlySwingGoesLongAndALateOneDropsShort() {
        let good = returnLanding(timing: 0)
        let early = returnLanding(timing: -1)
        let late = returnLanding(timing: 1)

        #expect(early.y < good.y)
        #expect(late.y > good.y)
    }

    @Test func returnsDoNotSpeedUpOverALongRally() {
        var game = GameState(seed: 2)
        let a = Returner(side: .playerA)
        let b = Returner(side: .playerB)
        var speeds: [Double] = []
        _ = serveAndToss(&game)
        while speeds.count < 20 {
            var input = a.input(for: game)
            let other = b.input(for: game)
            input.targetB = other.targetB
            input.swings += other.swings
            let events = game.step(input)
            if events.contains(where: { if case .hit = $0 { true } else { false } }) {
                speeds.append(game.ball.speed)
            }
            if case .pointScored = game.phase { break }
        }

        #expect(speeds.count == 20)
        #expect(speeds.max()! < speeds.first! * 1.25)
    }

    @Test func lagCompensationLetsASwingThatArrivesLateStillHit() {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
        _ = game.run(steps: Int(contactStep - game.step) + 6, input: tracking(.playerB))

        let events = game.step(StepInput(swings: [Swing(side: .playerB, step: contactStep, strength: 0.5, aim: 0)]))

        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(game.ball.velocity.y < 0)
    }

    private func returnLanding(timing: Double) -> (half: Side, y: Double) {
        var game = GameState(seed: 4)
        _ = serveAndToss(&game)
        let returner = Returner(side: .playerB, timing: timing)
        _ = game.run(until: { _, events in events.contains { if case .hit = $0 { true } else { false } } }, input: returner.input(for:))
        var y = game.ball.position.y
        _ = game.run(until: { state, events in
            y = state.ball.position.y
            return events.contains { if case .bounce = $0 { true } else { false } } || events.contains { if case .pointScored = $0 { true } else { false } }
        })
        return (y < game.config.tableLength / 2 ? .playerA : .playerB, y)
    }
}

struct RacketShotTests {
    private static let drive = SIMD3<Double>(0, 0, 15)

    @Test func aStillPhoneNeverReturnsTheBall() {
        let events = rallyAgainstPhone(spin: .zero)

        #expect(!events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(events.contains(.pointScored(winner: .playerA, score: Score(a: 1, b: 0))))
    }

    @Test func aForehandSwungThroughTheBallSendsItBack() {
        let events = rallyAgainstPhone(spin: Self.drive)

        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(events.contains { if case .stroke(.playerB, _) = $0 { true } else { false } })
    }

    @Test(arguments: [-0.09, -0.06, -0.03, 0, 0.03, 0.06, 0.09, 0.11])
    func anyHitInTheWindowCrossesTheNetHoweverItIsTimed(offset: Double) {
        for turn in [4.0, 12, 25] {
            var game = GameState(seed: 1)
            _ = serveAndToss(&game)
            let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
            _ = game.run(steps: Int(contactStep - game.step) + 40, input: phoneTracking(.playerB))
            let swingStep = UInt64(Double(contactStep) + (game.config.perceivedLag + offset) * Double(game.config.stepsPerSecond))
            var events = game.step(StepInput(rackets: [RacketSample(side: .playerB, step: swingStep, orientation: ArmModel.restOrientation, angularVelocity: SIMD3(0, 0, turn))]))
            events += game.run(steps: 480)
            let afterHit = events.drop { if case .hit(.playerB, _, _) = $0 { false } else { true } }

            #expect(afterHit.first { if case .bounce = $0 { true } else { false } } == .bounce(.playerA), "offset \(offset) turn \(turn)")
        }
    }

    @Test func aimingAtTheSidelineAndSwingingLateTakesTheBallOutWide() {
        let atTheLine = simd_quatd(angle: -.pi / 6, axis: SIMD3(0, 0, 1)) * ArmModel.restOrientation

        #expect(firstBounceAfterHit(holding: atTheLine, offset: 0) == .bounce(.playerA))
        #expect(firstBounceAfterHit(holding: atTheLine, offset: 0.11) != .bounce(.playerA))
        #expect(firstBounceAfterHit(holding: ArmModel.restOrientation, offset: 0.11) == .bounce(.playerA))
    }

    @Test func theBallOnlyWaitsForAHitWhileThePlayerIsSwinging() {
        for swinging in [false, true] {
            var game = GameState(seed: 1)
            _ = serveAndToss(&game)
            let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
            var awaited = false
            for _ in 0..<Int(contactStep - game.step) + 20 {
                let turn = swinging && game.step + 10 >= contactStep ? 12.0 : 0
                var input = phoneTracking(.playerB)(game)
                input.rackets = [RacketSample(side: .playerB, step: game.step, orientation: ArmModel.restOrientation, angularVelocity: SIMD3(0, 0, turn))]
                _ = game.step(input)
                awaited = awaited || game.isAwaitingPhoneHit
            }

            #expect(awaited == swinging)
        }
    }

    @Test func aHardSwingTimedRightLeavesFasterThanTheSameSwingMistimed() {
        #expect(returnSpeed(offset: 0) > returnSpeed(offset: 0.09) + 1)
    }

    private func returnSpeed(offset: Double) -> Double {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
        _ = game.run(steps: Int(contactStep - game.step) + 40, input: phoneTracking(.playerB))
        let swingStep = UInt64(Double(contactStep) + (game.config.perceivedLag + offset) * Double(game.config.stepsPerSecond))
        _ = game.step(StepInput(rackets: [RacketSample(side: .playerB, step: swingStep, orientation: ArmModel.restOrientation, angularVelocity: SIMD3(0, 0, 25))]))
        _ = game.run(until: { _, events in events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } } })
        return game.ball.speed
    }

    private func firstBounceAfterHit(holding orientation: simd_quatd, offset: Double) -> GameEvent? {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
        _ = game.run(steps: Int(contactStep - game.step) + 40, input: phoneTracking(.playerB))
        let swingStep = UInt64(Double(contactStep) + (game.config.perceivedLag + offset) * Double(game.config.stepsPerSecond))
        var events = game.step(StepInput(rackets: [RacketSample(side: .playerB, step: swingStep, orientation: orientation, angularVelocity: SIMD3(0, 0, 12))]))
        events += game.run(steps: 480)
        return events.drop { if case .hit(.playerB, _, _) = $0 { false } else { true } }.first { if case .bounce = $0 { true } else { false } }
    }

    @Test(arguments: [4.0, 8, 15, 25])
    func aCleanHitLandsOnTheOtherHalfHoweverHardItIsSwung(turn: Double) {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
        _ = game.run(steps: Int(contactStep - game.step) + 20, input: phoneTracking(.playerB))
        let swingStep = contactStep + UInt64(game.config.perceivedLag * Double(game.config.stepsPerSecond))
        var events = game.step(StepInput(rackets: [RacketSample(side: .playerB, step: swingStep, orientation: ArmModel.restOrientation, angularVelocity: SIMD3(0, 0, turn))]))
        events += game.run(steps: 480)
        let afterHit = events.drop { if case .hit(.playerB, _, _) = $0 { false } else { true } }

        #expect(game.lastSwing?.outcome == .clean)
        #expect(afterHit.first { if case .bounce = $0 { true } else { false } } == .bounce(.playerA))
    }

    @Test func aSwingReadAsGoingAwayFromTheTableStillSendsTheBallBack() {
        let events = rallyAgainstPhone(spin: -Self.drive)

        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(events.contains { if case .stroke(.playerB, _) = $0 { true } else { false } })
    }

    @Test func aBackhandHeldPhoneReturnsABallSetUpOnTheBackhand() {
        let backhand = simd_quatd(angle: .pi, axis: SIMD3(0, 0, 1)) * ArmModel.restOrientation
        let events = rallyAgainstPhone(spin: -Self.drive, holding: backhand, standing: phoneTracking(.playerB, stance: .backhand))

        #expect(events.contains { if case .stroke(.playerB, _) = $0 { true } else { false } })
        #expect(events.contains { if case .bounce(.playerA) = $0 { true } else { false } })
    }

    @Test func aFasterSwingHitsTheBallHarder() {
        #expect(returnSpeed(spin: SIMD3(0, 0, 22)) > returnSpeed(spin: SIMD3(0, 0, 9)) + 1)
    }

    @Test func aSwingWellOffTheBallsTimingCatchesTheEdgeButStillReturnsIt() {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
        let lag = Int(game.config.perceivedLag * Double(game.config.stepsPerSecond))
        _ = game.run(steps: Int(contactStep - game.step) + lag - 21, input: phoneTracking(.playerB))
        var events: [GameEvent] = []
        for speed in [0.0, 15, 0, 0] {
            events += game.step(StepInput(rackets: [RacketSample(side: .playerB, step: game.step, orientation: ArmModel.restOrientation, angularVelocity: SIMD3(0, 0, speed))]))
        }
        events += game.run(steps: 60)

        #expect(game.lastSwing?.outcome == .edge)
        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
    }

    @Test func aDownwardSwingSmashesAHighBallButDoesNothingToALowOne() {
        var high = GameConfig()
        high.overheadFrom = -1
        high.overheadFull = -0.9
        let chop = SIMD3<Double>(0, 15, 0)

        #expect(rallyAgainstPhone(spin: chop, config: high).contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(!rallyAgainstPhone(spin: chop).contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
    }

    @Test func aPhoneSampleThatArrivesLateStillCounts() {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
        _ = game.run(steps: Int(contactStep - game.step) + 20, input: phoneTracking(.playerB))
        let swingStep = contactStep + UInt64(game.config.perceivedLag * Double(game.config.stepsPerSecond))

        var events = game.step(StepInput(rackets: [RacketSample(side: .playerB, step: swingStep, orientation: ArmModel.restOrientation, angularVelocity: Self.drive)]))
        events += game.run(steps: 120)

        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(game.ball.velocity.y < 0)
    }

    @Test func forehandAndBackhandPhoneServesCurveOppositeWaysAndStillLand() {
        let forehand = phoneServe(holding: ArmModel.restOrientation)
        let backhand = phoneServe(holding: simd_quatd(angle: .pi, axis: SIMD3(0, 0, 1)) * ArmModel.restOrientation)

        #expect(forehand.spin.z * backhand.spin.z < 0)
        #expect(forehand.landed && backhand.landed)
    }

    @Test func aTossWithNoSwingDropsBackIntoTheHandToTryAgain() {
        var game = GameState(seed: 1)
        let tossed = game.step(StepInput(rackets: [RacketSample(side: .playerA, step: game.step, orientation: ArmModel.restOrientation, angularVelocity: .zero)], tosses: [.playerA]))
        var events: [GameEvent] = []
        for _ in 0..<480 {
            events += game.step(StepInput(rackets: [RacketSample(side: .playerA, step: game.step, orientation: ArmModel.restOrientation, angularVelocity: .zero)]))
        }
        let again = game.step(StepInput(tosses: [.playerA]))

        #expect(tossed.contains(.tossed(.playerA)))
        #expect(!events.contains(.served(.playerA)))
        #expect(again.contains(.tossed(.playerA)))
    }

    @Test func choppingDownOnAServeGivesBackspin() {
        let chop = phoneServe(holding: ArmModel.restOrientation, drop: 3)
        let lift = phoneServe(holding: ArmModel.restOrientation, drop: -3)

        #expect(chop.spin.x > 0)
        #expect(lift.spin.x < 0)
        #expect(chop.landed && lift.landed)
    }

    private func phoneServe(holding orientation: simd_quatd, drop: Double = 0) -> (spin: SIMD3<Double>, landed: Bool) {
        var game = GameState(seed: 1)
        var events = game.step(StepInput(rackets: [RacketSample(side: .playerA, step: game.step, orientation: orientation, angularVelocity: .zero)], tosses: [.playerA]))
        let strike = game.predictedServeStrike(for: .playerA)!.stepsAway + UInt64(game.config.perceivedLag * Double(game.config.stepsPerSecond))
        events += game.run(steps: Int(strike) - 2)
        for speed in [0.0, 8, 16, 8, 2, 0] {
            events += game.step(StepInput(rackets: [RacketSample(
                side: .playerA,
                step: game.step,
                orientation: orientation,
                angularVelocity: SIMD3(0, 0, speed),
                linearVelocity: SIMD3(0, 0, -drop * speed / 16)
            )]))
        }
        let spin = game.ball.spin
        events += game.run(steps: 480)
        #expect(events.contains { if case .stroke(.playerA, let timing) = $0 { abs(timing) <= game.config.cleanTiming } else { false } })
        let landed = events.contains(.bounce(.playerB)) && !events.contains { if case .pointScored(winner: .playerB, _) = $0 { true } else { false } }
        return (spin, landed)
    }

    private func rallyAgainstPhone(spin: SIMD3<Double>, holding orientation: simd_quatd = ArmModel.restOrientation, standing: @escaping (GameState) -> StepInput = phoneTracking(.playerB), config: GameConfig = GameConfig()) -> [GameEvent] {
        var game = GameState(seed: 1, config: config)
        _ = serveAndToss(&game)
        return game.run(until: scoredAPoint) { state in
            var input = standing(state)
            input.rackets = [RacketSample(side: .playerB, step: state.step, orientation: orientation, angularVelocity: spin)]
            return input
        }
    }

    private func returnSpeed(spin: SIMD3<Double>) -> Double {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        _ = game.run(until: { _, events in events.contains { if case .hit = $0 { true } else { false } } }) { state in
            var input = phoneTracking(.playerB)(state)
            input.rackets = [RacketSample(side: .playerB, step: state.step, orientation: ArmModel.restOrientation, angularVelocity: spin)]
            return input
        }
        return game.ball.speed
    }
}

struct ArmModelTests {
    @Test func aForehandReachesToTheRightAndABackhandAcrossTheBody() {
        #expect(ArmModel.restingHand(.forehand).x > 0.25)
        #expect(ArmModel.restingHand(.backhand).x < -0.1)
    }

    @Test func aLeftHandersHandRestsOnTheLeftAndTheBallSideChoosesTheStroke() {
        #expect(ArmModel.restingHand(.forehand, .left).x < -0.25)
        #expect(ArmModel.stance(forBallAt: -0.3, handedness: .left) == .forehand)
        #expect(ArmModel.stance(forBallAt: 0.3, handedness: .left) == .backhand)
        #expect(ArmModel.stance(forBallAt: 0.3, handedness: .right) == .forehand)
    }

    @Test func aBackhandTurnIsAsQuickAsAForehandTurn() {
        let backhandRest = simd_quatd(angle: .pi, axis: SIMD3(0, 0, 1)) * ArmModel.restOrientation
        let forehand = ArmModel.bladeVelocity(SIMD3(0, 0, 10), linearVelocity: .zero, orientation: ArmModel.restOrientation, stance: .forehand)
        let backhand = ArmModel.bladeVelocity(SIMD3(0, 0, -10), linearVelocity: .zero, orientation: backhandRest, stance: .backhand)

        #expect(abs(forehand.y - backhand.y) < 1e-9)
        #expect(backhand.y > 2)
    }
}

func phoneTracking(_ side: Side, stance: Stance = .forehand) -> (GameState) -> StepInput {
    { game in
        let hand = ArmModel.restingHand(stance).x * side.forward
        let x = (game.predictedContact(for: side)?.position.x ?? game.config.tableWidth / 2) - hand
        let position = game.config.position(ofPaddleX: x)
        return side == .playerA ? StepInput(targetA: position) : StepInput(targetB: position)
    }
}

struct GameFlowTests {
    @Test func thePauseBetweenPointsAndTheServeTimerStandStillWhilePaused() {
        var game = GameState(seed: 1)
        _ = game.run(steps: 1_000)
        _ = game.step(StepInput(command: .pause))
        _ = game.run(steps: 5_000)
        _ = game.step(StepInput(command: .resume))
        let before = game.run(steps: 198)
        let at = game.step(StepInput())

        #expect(!before.contains(.tossed(.playerA)))
        #expect(at.contains(.tossed(.playerA)))
    }

    @Test func theServerTossesAutomaticallyAfterFiveSecondsAndServesAsTheBallFalls() {
        var game = GameState(seed: 1)
        let before = game.run(steps: 1_199)
        let at = game.step(StepInput())
        let toss = game.run(steps: 240)

        #expect(!before.contains(.tossed(.playerA)))
        #expect(at.contains(.tossed(.playerA)))
        #expect(toss.contains(.served(.playerA)))
    }

    @Test func swingsAreIgnoredWhilePausedWithoutStartingACooldown() {
        var game = GameState(seed: 1)
        let paused = game.step(StepInput(command: .pause))
        let swing = game.step(StepInput(swings: [serve(.playerA, in: game)]))
        _ = game.step(StepInput(command: .resume))
        let served = game.step(StepInput(swings: [serve(.playerA, in: game)]))

        #expect(paused == [.paused])
        #expect(swing.isEmpty)
        #expect(served.contains(.tossed(.playerA)))
    }

    @Test func swingsAreIgnoredBetweenPoints() {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        _ = game.run(until: scoredAPoint)

        let between = game.step(StepInput(swings: [serve(.playerA, in: game), serve(.playerB, in: game)]))
        _ = game.run(until: { state, _ in if case .serving = state.phase { true } else { false } })
        let served = game.step(StepInput(swings: [serve(.playerA, in: game)]))

        #expect(between.isEmpty)
        #expect(served.contains(.tossed(.playerA)))
    }

    @Test func aGameEndsElevenNilWhenOnlyOnePlayerEverReturns() {
        var game = GameState(seed: 1)
        let returner = Returner(side: .playerA)
        for _ in 0..<100_000 {
            if case .gameOver = game.phase { break }
            var input = returner.input(for: game)
            if case .serving(let server, _) = game.phase {
                input.swings = [serve(server, in: game)]
            }
            _ = game.step(input)
        }
        #expect(game.phase == .gameOver(winner: .playerA))
        #expect(game.score == Score(a: 11, b: 0))
    }

    @Test func paddleNeverMovesFasterThanItsSpeedCap() {
        var game = GameState(seed: 1)
        var positions = [game.paddleX(of: .playerA)]
        for _ in 0..<200 {
            _ = game.step(StepInput(targetA: positions.count < 100 ? 1 : 0))
            positions.append(game.paddleX(of: .playerA))
        }
        let limit = game.config.paddleSpeedInTableWidths * game.config.tableWidth / Double(game.config.stepsPerSecond) + 1e-12
        #expect(zip(positions, positions.dropFirst()).allSatisfy { abs($1 - $0) <= limit })
    }

    @Test func paddlePositionIsTheTargetScaleItWasMovedWith() {
        var game = GameState(seed: 1)
        _ = game.run(steps: 300) { _ in StepInput(targetA: 0.25, targetB: 1) }
        #expect(abs(game.paddlePosition(of: .playerA) - 0.25) < 1e-12)
        #expect(abs(game.paddlePosition(of: .playerB) - 1) < 1e-12)
    }

    @Test func sameSeedAndInputsGiveTheSameGame() {
        let first = randomPlay(seed: 21)
        let second = randomPlay(seed: 21)
        #expect(first.game == second.game)
        #expect(first.events == second.events)
        #expect(first.game != randomPlay(seed: 22).game)
    }
}

struct ForfeitTests {
    @Test func aForfeitMidRallyEndsTheGameWithTheScoreSoFar() {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        _ = game.run(until: scoredAPoint)
        _ = game.run(until: { state, _ in state.phase == .rally }) { state in
            if case .serving(let server, _) = state.phase { StepInput(swings: [serve(server, in: state)]) } else { StepInput() }
        }

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

final class Returner {
    private let side: Side
    private let timing: Double
    private var swingAt: (flight: UInt64, step: UInt64)?

    init(side: Side, timing: Double = 0) {
        self.side = side
        self.timing = timing
    }

    func input(for game: GameState) -> StepInput {
        var input = tracking(side)(game)
        if swingAt?.flight != game.flightNumber, let contact = game.predictedContact(for: side) {
            let window = game.config.swingWindow * Double(game.config.stepsPerSecond)
            let offset = Int((timing * window * 0.95).rounded())
            swingAt = (game.flightNumber, UInt64(Int(game.step + contact.stepsAway) + offset))
        }
        if let swingAt, swingAt.flight == game.flightNumber, game.step == swingAt.step {
            input.swings = [Swing(side: side, step: game.step, strength: 0.5, aim: 0)]
        }
        return input
    }
}

func serve(_ side: Side, in game: GameState, aim: Double = 0) -> Swing {
    Swing(side: side, step: game.step, strength: 0.3, aim: aim)
}

func serveAndToss(_ game: inout GameState, by side: Side = .playerA, strength: Double = 0.3, aim: Double = 0) -> [GameEvent] {
    var events = game.step(StepInput(swings: [Swing(side: side, step: game.step, strength: strength, aim: aim)]))
    for _ in 0..<2_400 where !events.contains(.served(side)) {
        events += game.step(StepInput())
    }
    return events
}

func scoredAPoint(_ state: GameState, _ events: [GameEvent]) -> Bool {
    events.contains { if case .pointScored = $0 { true } else { false } }
}

func tracking(_ side: Side) -> (GameState) -> StepInput {
    { game in
        let x = game.predictedContact(for: side)?.position.x ?? game.config.tableWidth / 2
        let position = game.config.position(ofPaddleX: x)
        return side == .playerA ? StepInput(targetA: position) : StepInput(targetB: position)
    }
}

func randomPlay(seed: UInt64) -> (game: GameState, events: [GameEvent]) {
    var random = SplitMix64(seed: seed)
    var game = GameState(seed: seed)
    var events: [GameEvent] = []
    for _ in 0..<50_000 {
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
    mutating func run(steps: Int, input: (GameState) -> StepInput = { _ in StepInput() }) -> [GameEvent] {
        var events: [GameEvent] = []
        for _ in 0..<steps {
            events += step(input(self))
        }
        return events
    }

    mutating func run(
        until done: (GameState, [GameEvent]) -> Bool,
        limit: Int = 20_000,
        input: (GameState) -> StepInput = { _ in StepInput() }
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
