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

    @Test(arguments: [-0.09, -0.06, -0.03, 0, 0.03, 0.06, 0.09, 0.11])
    func anyHitInTheWindowCrossesTheNetHoweverItIsTimed(offset: Double) {
        for turn in [4.0, 12, 25] {
            let swing = phoneSwing { t in Self.bump(turn, at: offset, t) }

            #expect(Self.firstBounceAfterTheHit(in: swing.events) == .bounce(.playerA), "offset \(offset) turn \(turn)")
        }
    }

    @Test func aimingAtTheSidelineAndSwingingLateTakesTheBallOutWide() {
        let atTheLine = simd_quatd(angle: -.pi / 6, axis: SIMD3(0, 0, 1)) * ArmModel.restOrientation

        #expect(firstBounceAfterHit(holding: atTheLine, offset: 0) == .bounce(.playerA))
        #expect(firstBounceAfterHit(holding: atTheLine, offset: 0.11) != .bounce(.playerA))
        #expect(firstBounceAfterHit(holding: ArmModel.restOrientation, offset: 0.11) == .bounce(.playerA))
    }

    @Test func aHitCommitsAsTheSwingNearsItsPeakBeforeThePeakIsConfirmed() {
        let swung = liveSwing(peakingLate: 0)
        let still = liveSwing(peakingLate: 0, turn: 0)
        let hit = Int(swung.hitStep ?? 0)

        #expect((swung.peakStep - 3...swung.peakStep).contains(hit))
        #expect(still.hitStep == nil)
    }

    @Test func aRefinedHitSendsOneHitThenOneStrokeWithTheFinalTiming() {
        let swing = liveSwing(peakingLate: 0.03)
        let hits = swing.events.indices.filter { if case .hit(.playerB, _, _) = swing.events[$0] { true } else { false } }
        let strokes = swing.events.indices.filter { if case .stroke(.playerB, _) = swing.events[$0] { true } else { false } }

        #expect(hits.count == 1)
        #expect(strokes.count == 1)
        #expect(hits.first! < strokes.first!)
        #expect(abs(swing.game.lastSwing!.timing - 0.03) < 0.01)
    }

    @Test func aSwingSeenLiveEndsInTheSameReturnAsTheSameSwingSeenLate() {
        let live = liveSwing(peakingLate: 0.02)
        let late = liveSwing(peakingLate: 0.02, deliveredLate: true)

        #expect(simd_distance(live.game.ball.position, late.game.ball.position) < 1e-9)
        #expect(live.game.lastSwing?.timing == late.game.lastSwing?.timing)
    }

    @Test func aSwingThatLevelsOffThenSurgesIsHitAtItsRealPeakLiveOrLate() {
        let surging = { (t: Double) -> Double in
            let rates: [Double] = [0, 6, 6.5, 10, 14, 16, 10, 4, 0]
            let index = Int(((t + 0.07) / 0.01).rounded())
            return rates.indices.contains(index) ? rates[index] : 0
        }
        let live = phoneSwing(surging)
        let late = phoneSwing(surging, deliveredLate: true)

        #expect(live.game.lastSwing.map { $0.peakSpeed > 3.5 } == true)
        #expect(simd_distance(live.game.ball.position, late.game.ball.position) < 1e-9)
    }

    @Test func aBatDriftingBeforeTheStrokeIsNotTheHit() {
        let drifting = { (t: Double) in max(3.5, Self.bump(16, at: 0, t)) }
        let swing = phoneSwing(drifting)

        #expect(swing.game.lastSwing.map { $0.peakSpeed > 3.5 && abs($0.timing) < 0.02 } == true)
        #expect(!phoneSwing { _ in 3.5 }.events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
    }

    @Test func aBackswingBeforeTheStrokeIsNotTheHit() {
        let swing = phoneSwing { t in Self.bump(-5, at: -0.11, t) + Self.bump(16, at: 0, t) }

        #expect(swing.game.lastSwing.map { $0.peakSpeed > 3.5 && abs($0.timing) < 0.02 } == true)
    }

    private static func bump(_ height: Double, at centre: Double, _ t: Double, halfWidth: Double = 0.05) -> Double {
        abs(t - centre) < halfWidth ? height * 0.5 * (1 + cos(.pi * (t - centre) / halfWidth)) : 0
    }

    private func phoneSwing(_ turn: @escaping (Double) -> Double, deliveredLate: Bool = false) -> (game: GameState, events: [GameEvent], launchSpeed: Double?) {
        phoneSwing({ t in SIMD3(0, 0, turn(t)) }, deliveredLate: deliveredLate)
    }

    // A swing sampled every 10 ms like the phone, rotating at `turn(t)` at t seconds from the ideal moment; the samples
    // arrive as they're taken, or all together after the swing. Runs until the point is over.
    private func phoneSwing(
        _ turn: @escaping (Double) -> SIMD3<Double>,
        holding orientation: simd_quatd = ArmModel.restOrientation,
        standing: @escaping (GameState) -> StepInput = phoneTracking(.playerB),
        config: GameConfig = GameConfig(),
        deliveredLate: Bool = false,
        through last: Double = 0.13
    ) -> (game: GameState, events: [GameEvent], launchSpeed: Double?) {
        var game = GameState(seed: 1, config: config)
        _ = serveAndToss(&game)
        let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
        let perSecond = Double(game.config.stepsPerSecond)
        let ideal = Double(contactStep) + game.config.perceivedLag * perSecond
        let samples = stride(from: -0.3, through: last, by: 0.01).map { t in
            RacketSample(side: .playerB, step: UInt64((ideal + t * perSecond).rounded()), orientation: orientation, angularVelocity: turn(t))
        }
        let deliverAt = UInt64((ideal + 0.13 * perSecond).rounded())
        var events: [GameEvent] = []
        var launchSpeed: Double?
        var next = 0
        while game.step < contactStep + 1_200, !scoredAPoint(game, events) {
            var input = standing(game)
            if deliveredLate {
                input.rackets = game.step == deliverAt ? samples : []
            } else {
                while next < samples.count, samples[next].step <= game.step {
                    input.rackets.append(samples[next])
                    next += 1
                }
            }
            let happened = game.step(input)
            if launchSpeed == nil, happened.contains(where: { if case .stroke(.playerB, _) = $0 { true } else { false } }) {
                launchSpeed = game.ball.speed
            }
            events += happened
        }
        return (game, events, launchSpeed)
    }

    // A swing easing up to `turn` rad/s and back over 50 ms either side, peaking `peakingLate` after the ideal moment;
    // its samples arrive as it happens, or all at once well after the ball has passed.
    private func liveSwing(peakingLate offset: Double, turn: Double = 16, deliveredLate: Bool = false) -> (game: GameState, events: [GameEvent], peakStep: Int, hitStep: UInt64?) {
        var game = GameState(seed: 1)
        _ = serveAndToss(&game)
        let contactStep = game.step + game.predictedContact(for: .playerB)!.stepsAway
        let perSecond = Double(game.config.stepsPerSecond)
        let peakStep = Int(Double(contactStep) + (game.config.perceivedLag + offset) * perSecond)
        func sample(at step: UInt64) -> RacketSample {
            let away = Double(abs(Int(step) - peakStep))
            let speed = away < 12 ? turn * 0.5 * (1 + cos(.pi * away / 12)) : 0
            return RacketSample(side: .playerB, step: step, orientation: ArmModel.restOrientation, angularVelocity: SIMD3(0, 0, speed))
        }
        var events: [GameEvent] = []
        var hitStep: UInt64?
        let deliverAt = UInt64(peakStep + 30)
        while game.step < contactStep + 200 {
            var input = phoneTracking(.playerB)(game)
            if !deliveredLate {
                input.rackets = [sample(at: game.step)]
            } else if game.step == deliverAt {
                input.rackets = (UInt64(peakStep - 14)...UInt64(peakStep + 14)).map(sample(at:))
            }
            let happened = game.step(input)
            if hitStep == nil, happened.contains(where: { if case .hit(.playerB, _, _) = $0 { true } else { false } }) {
                hitStep = game.step
            }
            events += happened
        }
        return (game, events, peakStep, hitStep)
    }

    @Test func aHardSwingTimedRightLeavesFasterThanTheSameSwingMistimed() {
        #expect(returnSpeed(offset: 0) > returnSpeed(offset: 0.09) + 1)
    }

    private func returnSpeed(offset: Double) -> Double {
        phoneSwing { t in Self.bump(25, at: offset, t) }.launchSpeed ?? 0
    }

    private func firstBounceAfterHit(holding orientation: simd_quatd, offset: Double) -> GameEvent? {
        Self.firstBounceAfterTheHit(in: phoneSwing({ t in SIMD3(0, 0, Self.bump(12, at: offset, t)) }, holding: orientation).events)
    }

    private static func firstBounceAfterTheHit(in events: [GameEvent]) -> GameEvent? {
        events.drop { if case .hit(.playerB, _, _) = $0 { false } else { true } }.first { if case .bounce = $0 { true } else { false } }
    }

    @Test(arguments: [4.0, 8, 15, 25])
    func aCleanHitLandsOnTheOtherHalfHoweverHardItIsSwung(turn: Double) {
        let swing = phoneSwing { t in Self.bump(turn, at: 0, t) }

        #expect(swing.game.lastSwing?.outcome == .clean)
        #expect(Self.firstBounceAfterTheHit(in: swing.events) == .bounce(.playerA))
    }

    @Test func aSwingAwayFromTheTableIsNotAStroke() {
        #expect(!rallyAgainstPhone(spin: -Self.drive).contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
    }

    @Test func aBackswingInsideTheWindowIsNotTheHitTheStrokeAfterItIs() {
        let swing = phoneSwing { t in Self.bump(-9, at: -0.05, t, halfWidth: 0.03) + Self.bump(16, at: 0, t, halfWidth: 0.04) }

        #expect(swing.game.lastSwing.map { $0.peakSpeed > 3.5 && abs($0.timing) < 0.02 } == true)
    }

    @Test func aLateStrokeAfterABackswingInTheWindowDoesNotCountAsSwingingTheOtherWay() {
        let swing = phoneSwing({ t in SIMD3(0, 0, Self.bump(-12, at: -0.05, t, halfWidth: 0.04) + Self.bump(16, at: 0.2, t)) }, through: 0.3)

        #expect(swing.game.swingDirection(of: .playerB).wrongWayInARow == 0)
    }

    @Test func aHardSwingOnlyTheOtherWayCountsOnce() {
        let swing = phoneSwing { t in Self.bump(-16, at: 0, t) }

        #expect(swing.game.swingDirection(of: .playerB).wrongWayInARow == 1)
    }

    @Test func recalibratingForgetsWhatWasLearnedAboutTheDirection() {
        var game = phoneSwing { t in Self.bump(-16, at: 0, t) }.game
        game.resetSwingDirection(of: .playerB)

        #expect(game.swingDirection(of: .playerB) == SwingDirection())
    }

    @Test func aSlowEarlySwingStillHits() {
        let swing = phoneSwing { t in Self.bump(16, at: -0.09, t, halfWidth: 0.25) }

        #expect(swing.events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
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

    @Test func aSwingWhoseSamplesAllArriveLateStillCounts() {
        let swing = phoneSwing({ t in Self.bump(15, at: 0, t) }, deliveredLate: true)

        #expect(swing.events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(Self.firstBounceAfterTheHit(in: swing.events) == .bounce(.playerA))
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

    @Test func aServeSwungTheOtherWayTeachesThatWayAsForward() {
        let usual = phoneServe(holding: ArmModel.restOrientation)
        let reversed = phoneServe(holding: ArmModel.restOrientation, turning: -1)

        #expect(usual.forward == 1)
        #expect(reversed.forward == -1)
        #expect(usual.landed && reversed.landed)
    }

    private func phoneServe(holding orientation: simd_quatd, drop: Double = 0, turning: Double = 1) -> (spin: SIMD3<Double>, landed: Bool, forward: Double) {
        var game = GameState(seed: 1)
        var events = game.step(StepInput(rackets: [RacketSample(side: .playerA, step: game.step, orientation: orientation, angularVelocity: .zero)], tosses: [.playerA]))
        let strike = game.predictedServeStrike(for: .playerA)!.stepsAway + UInt64(game.config.perceivedLag * Double(game.config.stepsPerSecond))
        events += game.run(steps: Int(strike) - 2)
        for speed in [0.0, 8, 16, 8, 2, 0] {
            events += game.step(StepInput(rackets: [RacketSample(
                side: .playerA,
                step: game.step,
                orientation: orientation,
                angularVelocity: SIMD3(0, 0, turning * speed),
                linearVelocity: SIMD3(0, 0, -drop * speed / 16)
            )]))
        }
        let spin = game.ball.spin
        let forward = game.swingDirection(of: .playerA).sign
        events += game.run(steps: 480)
        #expect(events.contains { if case .stroke(.playerA, let timing) = $0 { abs(timing) <= game.config.cleanTiming } else { false } })
        let landed = events.contains(.bounce(.playerB)) && !events.contains { if case .pointScored(winner: .playerB, _) = $0 { true } else { false } }
        return (spin, landed, forward)
    }

    // An on-time swing whose rotation rate rises to `spin` and falls back.
    private func rallyAgainstPhone(spin: SIMD3<Double>, holding orientation: simd_quatd = ArmModel.restOrientation, standing: @escaping (GameState) -> StepInput = phoneTracking(.playerB), config: GameConfig = GameConfig()) -> [GameEvent] {
        phoneSwing({ t in spin * Self.bump(1, at: 0, t) }, holding: orientation, standing: standing, config: config).events
    }

    private func returnSpeed(spin: SIMD3<Double>) -> Double {
        phoneSwing { t in spin * Self.bump(1, at: 0, t) }.launchSpeed ?? 0
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

struct SwingDirectionTests {
    @Test func ballsSwungClearlyTheOtherWayTurnTheDirectionRound() {
        var direction = SwingDirection()
        for _ in 1...SwingDirection.wrongWayToTurn {
            direction.judge(forward: 0.3, backward: 4)
        }

        #expect(direction.sign == -1)
    }

    @Test func aLatePlayersBackswingNeverCountsAgainstThemWhenTheStrokeFollows() {
        var direction = SwingDirection()
        for _ in 1...5 {
            direction.judge(forward: 4, backward: 2.6)
        }

        #expect(direction.sign == 1)
        #expect(direction.wrongWayInARow == 0)
    }

    @Test func aWrongTurnTurnsBackAfterTheSameEvidence() {
        var direction = SwingDirection()
        for _ in 1...SwingDirection.wrongWayToTurn {
            direction.judge(forward: 0.3, backward: 4)
        }
        for _ in 1...SwingDirection.wrongWayToTurn {
            direction.judge(forward: 0.3, backward: 4)
        }

        #expect(direction.sign == 1)
    }

    @Test func aServeSwingSetsWhichWayIsForward() {
        var direction = SwingDirection()
        direction.served(SIMD3(0, -3, 0))

        #expect(direction.forward(SIMD3(0, -3, 0)) == 3)
        #expect(direction.forward(SIMD3(0, 3, 0)) == 0)
    }

    @Test func aGentleSwingTheOtherWayDoesNotCount() {
        var direction = SwingDirection()
        direction.judge(forward: 0, backward: 2)

        #expect(direction.wrongWayInARow == 0)
    }
}
