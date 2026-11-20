import Foundation
import simd

public struct GameState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case serving(Side, since: UInt64)
        case rally
        case pointScored(until: UInt64)
        case paused
        case gameOver(winner: Side)
    }

    public struct SwingReport: Equatable, Sendable {
        public enum Outcome: String, Sendable {
            case clean
            case edge
            case whiff
            case noSwing
        }

        public let number: Int
        public let side: Side
        public let outcome: Outcome
        public let peakSpeed: Double
        public let timing: Double
        public let ballHeight: Double
        public let nearestPeakSpeed: Double
        public let nearestPeakOffset: Double
        public let fastestBlade: Double
        public let fastestBladeForward: Double
        public let paddleX: Double
        public let ballX: Double
        public var landing: SIMD2<Double>?
        public var clearsNet = false
        public var commitDelay = 0.0
        public var committedPower = 0.0
    }

    public struct Contact: Equatable, Sendable {
        public let stepsAway: UInt64
        public let position: SIMD3<Double>
    }

    private struct Paddle: Equatable, Sendable {
        var x: Double
        var target: Double
        var swingsBlockedUntil: UInt64 = 0
        var pendingSwing: Swing?
        var samples: [RacketSample] = []
        var timings: [Stance: [Double]] = [:]
        var direction = SwingDirection()
    }

    private struct Chance: Equatable, Sendable {
        let side: Side
        let step: UInt64
        let ball: Ball
        let paddleX: Double
    }

    // A phone stroke as known so far: committed when the swing first shows, refined as its peak arrives.
    private struct Stroked: Equatable, Sendable {
        let peak: RacketSample
        let ball: Ball
        let speed: Double
        let power: Double
        let raw: Double
        let timing: Double
        let stance: Stance
        let isClean: Bool
        let isRising: Bool
    }

    private struct Refining: Equatable, Sendable {
        let chance: Chance
        var stroked: Stroked
        let committedAt: UInt64
        let committedPower: Double
        let until: UInt64
    }

    private struct DirectionCheck: Equatable, Sendable {
        let side: Side
        let around: UInt64
    }

    private struct Toss: Equatable, Sendable {
        let startedAt: UInt64
        let queued: SIMD2<Double>?
        let start: Ball
        let strikeStep: UInt64
        let strikePoint: SIMD3<Double>
    }

    private struct PendingPoint: Equatable, Sendable {
        let loser: Side
        let awardAt: UInt64
    }

    private static let sampleMemory = 1.1
    private static let directionSpan = 0.5
    private static let predictionLimit = 3.0
    private static let ballInHand = 0.7
    private static let handSpeed = 1.2
    private static let longestToss = 2.0
    private static let servePull = 0.6
    private static let servePaceLoss = 0.35
    private static let aimPerFace = 2.0
    private static let sideOn = 0.3
    private static let learnableError = 0.95
    private static let biasAfter = 3
    private static let biasMemory = 8
    private static let largestBias = 0.05

    public let config: GameConfig
    public private(set) var step: UInt64 = 0
    public private(set) var phase: Phase
    public private(set) var score = Score(a: 0, b: 0)
    public private(set) var rally = 0
    public private(set) var flightNumber: UInt64 = 0
    public private(set) var lastSwing: SwingReport?
    private var flight: Flight
    private var paddleA: Paddle
    private var paddleB: Paddle
    private var chance: Chance?
    private var phaseBeforePause: Phase?
    private var pendingPoint: PendingPoint?
    private var toss: Toss?
    private var refining: Refining?
    private var directionChecks: [DirectionCheck] = []
    private var random: SplitMix64

    public init(seed: UInt64, config: GameConfig = GameConfig()) {
        self.config = config
        random = SplitMix64(seed: seed)
        let middle = config.tableWidth / 2
        paddleA = Paddle(x: middle, target: middle)
        paddleB = Paddle(x: middle, target: middle)
        phase = .serving(config.firstServer, since: 0)
        flight = Flight(ball: Ball(position: .zero), hitter: config.firstServer, isServe: true)
        holdBallForServe(by: config.firstServer, snap: true)
    }

    public var ball: Ball {
        flight.ball
    }

    public func paddleX(of side: Side) -> Double {
        paddle(side).x
    }

    public func paddlePosition(of side: Side) -> Double {
        config.position(ofPaddleX: paddle(side).x)
    }

    public func racket(of side: Side) -> RacketSample? {
        paddle(side).samples.last
    }

    public func isComing(to side: Side) -> Bool {
        guard case .rally = phase else { return false }
        return flight.receiver == side && !flight.isDecided
    }

    public func predictedContact(for side: Side) -> Contact? {
        guard isComing(to: side) else { return nil }
        var future = flight
        for stepsAway in 1...max(config.steps(Self.predictionLimit), 1) {
            for event in future.advance(config: config) {
                switch event {
                case .chance(side): return Contact(stepsAway: stepsAway, position: future.ball.position)
                case .fault: return nil
                default: break
                }
            }
        }
        return nil
    }

    public mutating func step(_ input: StepInput) -> [GameEvent] {
        var events: [GameEvent] = []
        apply(input.command, events: &events)
        switch phase {
        case .paused, .gameOver:
            return events
        default:
            break
        }
        step += 1
        movePaddles(input)
        remember(input.rackets)
        judgeDirections()
        for swing in input.swings {
            handle(swing, events: &events)
        }
        switch phase {
        case .serving(let server, let since):
            if let toss {
                followToss(toss, by: server, events: &events)
            } else {
                holdBallForServe(by: server)
                if input.tosses.contains(server), step >= paddle(server).swingsBlockedUntil {
                    startToss(by: server, queued: nil, events: &events)
                } else if paddle(server).samples.isEmpty, step - since >= config.steps(config.autoServeAfter) {
                    startToss(by: server, queued: SIMD2(config.autoServeStrength, 0), events: &events)
                }
            }
        case .rally:
            fly(events: &events)
            resolveChance(events: &events)
            expireSwings(events: &events)
            awardPendingPoint(events: &events)
        case .pointScored(let until):
            for event in flight.advance(config: config) {
                switch event {
                case .bounce(let half): events.append(.bounce(half))
                case .net: events.append(.net)
                case .fault, .chance: break
                }
            }
            if step >= until {
                startServing()
            }
        case .paused, .gameOver:
            break
        }
        return events
    }

    private mutating func apply(_ command: GameCommand?, events: inout [GameEvent]) {
        switch command {
        case .pause:
            guard phaseBeforePause == nil else { return }
            if case .gameOver = phase { return }
            phaseBeforePause = phase
            phase = .paused
            events.append(.paused)
        case .resume:
            guard let previous = phaseBeforePause else { return }
            phaseBeforePause = nil
            phase = previous
            events.append(.resumed)
        case .forfeit(let side):
            if case .gameOver = phase { return }
            phaseBeforePause = nil
            pendingPoint = nil
            refining = nil
            phase = .gameOver(winner: side.opponent)
            events.append(.gameOver(winner: side.opponent))
        case nil:
            return
        }
    }

    private mutating func movePaddles(_ input: StepInput) {
        let maximumMove = config.paddleSpeedInTableWidths * config.tableWidth * config.stepDuration
        for side in Side.allCases {
            var paddle = paddle(side)
            if let target = side == .playerA ? input.targetA : input.targetB {
                paddle.target = config.paddleX(forPosition: target)
            }
            paddle.x += min(max(paddle.target - paddle.x, -maximumMove), maximumMove)
            setPaddle(side, paddle)
        }
    }

    private mutating func remember(_ samples: [RacketSample]) {
        let memory = UInt64(config.steps(Self.sampleMemory))
        for sample in samples {
            var paddle = paddle(sample.side)
            paddle.samples.insert(sample, at: paddle.samples.lastIndex { $0.step <= sample.step }.map { $0 + 1 } ?? 0)
            paddle.samples.removeAll { $0.step + memory < step }
            setPaddle(sample.side, paddle)
        }
    }

    private mutating func handle(_ swing: Swing, events: inout [GameEvent]) {
        let side = swing.side
        guard step >= paddle(side).swingsBlockedUntil else { return }
        switch phase {
        case .serving(let server, _):
            guard side == server, toss == nil else { return }
            startToss(by: server, queued: SIMD2(swing.strength, swing.aim), events: &events)
        case .rally:
            if let chance, chance.side == side, isInWindow(swing.step, of: chance) {
                hit(chance, with: swing, events: &events)
            } else {
                var paddle = paddle(side)
                paddle.pendingSwing = swing
                setPaddle(side, paddle)
            }
        case .pointScored, .paused, .gameOver:
            return
        }
    }

    private mutating func fly(events: inout [GameEvent]) {
        let happened = flight.advance(config: config)
        defer {
            // A refined return stops changing once it touches anything.
            if !happened.isEmpty, let refining {
                settle(refining, events: &events)
            }
        }
        for event in happened {
            switch event {
            case .bounce(let half): events.append(.bounce(half))
            case .net: events.append(.net)
            case .fault(let loser): pendingPoint = PendingPoint(loser: loser, awardAt: step + config.steps(config.lagCompensation))
            case .chance(let side): chance = Chance(side: side, step: step, ball: flight.ball, paddleX: paddle(side).x)
            }
        }
    }

    private enum RacketSwing {
        case waiting
        case none
        case rising(RacketSample)
        case peak(RacketSample)
    }

    private mutating func resolveChance(events: inout [GameEvent]) {
        if let refining {
            refine(refining, events: &events)
        }
        guard let chance else { return }
        let side = chance.side
        if let swing = paddle(side).pendingSwing, isInWindow(swing.step, of: chance) {
            hit(chance, with: swing, events: &events)
            return
        }
        switch racketSwing(for: chance) {
        case .peak(let sample):
            strike(chance, with: sample, isRising: false, events: &events)
            return
        case .rising(let sample):
            strike(chance, with: sample, isRising: true, events: &events)
            return
        case .waiting:
            return
        case .none:
            break
        }
        if step > chance.step + lastSwingDecision {
            let window = swingWindow(around: chance.step, bias: timingBias(of: side, stance: stance(at: chance)))
            let inWindow = paddle(side).samples.filter { window.contains($0.step) }
            if !inWindow.isEmpty {
                directionChecks.append(DirectionCheck(side: side, around: chance.step))
                report(chance, .noSwing, peakSpeed: inWindow.map { forwardSpeed(of: $0) }.max() ?? 0, timing: 0)
            }
            self.chance = nil
        }
    }

    private func racketSwing(for chance: Chance) -> RacketSwing {
        swingPeak(of: chance.side, around: chance.step, bias: timingBias(of: chance.side, stance: stance(at: chance)), speed: swingSpeed(for: chance))
    }

    // The grip as the ball arrives decides which learned timing habit applies, for the window and the judgement alike.
    private func stance(at chance: Chance) -> Stance {
        let samples = paddle(chance.side).samples
        return (samples.last { $0.step <= chance.step } ?? samples.last)?.stance ?? .forehand
    }

    private func swingPeak(of side: Side, around contact: UInt64, bias: Double = 0, speed: (RacketSample) -> Double) -> RacketSwing {
        let samples = paddle(side).samples
        guard let latest = samples.last else { return .none }
        let window = swingWindow(around: contact, bias: bias)
        let isOver = latest.step >= window.upperBound || step >= window.upperBound + config.steps(config.lagCompensation)
        let candidates = samples.filter { window.contains($0.step) && speed($0) >= config.swingThreshold && isRise(to: $0, in: samples, after: window.lowerBound, speed: speed) }
        guard let peak = candidates.max(by: { speed($0) < speed($1) }) else {
            return isOver ? .none : .waiting
        }
        if hasFallen(after: peak, in: samples, speed: speed) || isOver {
            return .peak(peak)
        }
        return isNearTop(peak, in: samples, speed: speed) ? .rising(peak) : .waiting
    }

    // A swing meets the ball near its fastest moment, so a hit commits once the swing stops speeding up sharply
    // (or has started to slow), not at its first fast sample: the ball turns as the bat comes through.
    // A stroke climbs to its peak from well below it, so a bat already moving steadily, or the slowing tail of a
    // backswing, is not one.
    private func isRise(to peak: RacketSample, in samples: [RacketSample], after windowStart: UInt64, speed: (RacketSample) -> Double) -> Bool {
        let top = speed(peak)
        let earliest = windowStart - min(windowStart, config.steps(config.swingRiseLookback))
        let before = samples.filter { $0.step >= earliest && $0.step < peak.step }
        guard let start = before.lastIndex(where: { speed($0) < top * config.swingRiseFrom }) else { return false }
        return before[(start + 1)...].allSatisfy { speed($0) <= top }
    }

    private func isNearTop(_ peak: RacketSample, in samples: [RacketSample], speed: (RacketSample) -> Double) -> Bool {
        guard let before = samples.last(where: { $0.step < peak.step }) else { return false }
        let top = speed(peak)
        let seconds = Double(peak.step - before.step) / Double(config.stepsPerSecond)
        return samples.contains { $0.step > peak.step } || (top - speed(before)) / top / seconds < config.nearTopGrowth
    }

    // The higher the ball, the more a downward swing counts alongside a forward one.
    private func swingSpeed(for chance: Chance) -> (RacketSample) -> Double {
        let overhead = overhead(of: chance)
        let direction = paddle(chance.side).direction
        return { (sample: RacketSample) in
            direction.forward(sample.bladeVelocity) * (1 - overhead) + simd_length(sample.bladeVelocity) * overhead
        }
    }

    private func overhead(of chance: Chance) -> Double {
        let t = min(max((chance.ball.position.z - config.overheadFrom) / (config.overheadFull - config.overheadFrom), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private mutating func startToss(by server: Side, queued: SIMD2<Double>?, events: inout [GameEvent]) {
        flight.ball.velocity = SIMD3(0, 0, (2 * config.gravity * config.tossHeight).squareRoot())
        var ball = flight.ball
        var steps: UInt64 = 0
        while !(ball.velocity.z < 0 && ball.position.z <= config.serveHeight), steps < config.steps(Self.longestToss) {
            BallPhysics.fly(&ball, seconds: config.physicsStep, config: config)
            steps += 1
        }
        toss = Toss(startedAt: step, queued: queued, start: flight.ball, strikeStep: step + steps, strikePoint: ball.position)
        events.append(.tossed(server))
    }

    // The toss falls through the strike point like a rally ball reaching the bat: a swing there serves, a miss lets it drop back into the hand.
    private mutating func followToss(_ toss: Toss, by server: Side, events: inout [GameEvent]) {
        BallPhysics.fly(&flight.ball, seconds: config.physicsStep, config: config)
        if let queued = toss.queued {
            if step >= toss.strikeStep {
                serve(by: server, strength: queued.x, aim: queued.y, events: &events)
            }
            return
        }
        if case .peak(let peak) = swingPeak(of: server, around: toss.strikeStep, speed: serveSpeed(of:)) {
            strikeServe(toss, with: peak, by: server, events: &events)
        } else if step > toss.strikeStep + lastSwingDecision, flight.ball.velocity.z < 0, flight.ball.position.z <= config.tossFrom {
            self.toss = nil
        }
    }

    private mutating func strikeServe(_ toss: Toss, with peak: RacketSample, by server: Side, events: inout [GameEvent]) {
        var paddle = paddle(server)
        paddle.direction.served(peak.bladeVelocity)
        setPaddle(server, paddle)
        let timing = (Double(peak.step) - Double(toss.strikeStep + config.steps(config.perceivedLag))) / Double(config.stepsPerSecond)
        let struck = min(toss.strikeStep, step)
        var ball = toss.start
        for _ in toss.startedAt..<struck {
            BallPhysics.fly(&ball, seconds: config.physicsStep, config: config)
        }
        let error = timingError(timing)
        let strength = min(serveSpeed(of: peak) / config.fullSwingSpeed, 1) * (1 - Self.servePaceLoss * abs(error))
        let aim = min(max(faceAim(of: peak, by: server) + pull(of: peak, by: server) * error * Self.servePull, -1), 1)
        serve(by: server, from: ball.position, strength: strength, aim: aim, spin: serveSpin(of: peak, by: server), catchUp: step - struck, events: &events)
        events.append(.stroke(server, timing: timing))
    }

    // Aim fades out as the face turns side-on, so it can't flip from one side to the other between samples.
    private func faceAim(of peak: RacketSample, by server: Side) -> Double {
        let face = peak.orientation.act(SIMD3(0, 0, 1))
        let across = face.y < 0 ? -face.x : face.x
        let facing = min(abs(face.y) / Self.sideOn, 1)
        return min(max(across * Self.aimPerFace, -1), 1) * facing * server.forward
    }

    public func predictedServeStrike(for side: Side) -> Contact? {
        guard case .serving(side, _) = phase, let toss, toss.queued == nil, toss.strikeStep >= step else { return nil }
        return Contact(stepsAway: toss.strikeStep - step, position: toss.strikePoint)
    }

    // Brushing the ball spins it about (brush × face normal): across the body for sidespin, up or down for top or back.
    private func serveSpin(of peak: RacketSample, by server: Side) -> SIMD3<Double> {
        let across = (peak.stance == .forehand ? -1 : 1) * peak.handedness.mirror
        let lift = lift(of: peak)
        let spin = 2 * .pi * SIMD3(-(config.serveSpin + lift * config.serveLiftSpin), 0, across * config.serveSideSpin)
        return SIMD3(spin.x * server.forward, spin.y, spin.z)
    }

    private func hasFallen(after peak: RacketSample, in samples: [RacketSample], speed: (RacketSample) -> Double) -> Bool {
        let after = samples.filter { $0.step > peak.step }.suffix(2)
        return after.count == 2 && after.allSatisfy { speed($0) < config.peakFalloff * speed(peak) }
    }

    private func swingWindow(around contact: UInt64, bias: Double = 0) -> ClosedRange<UInt64> {
        let centre = UInt64(max(Int64(contact) + Int64(config.steps(config.perceivedLag)) + Int64((bias * Double(config.stepsPerSecond)).rounded()), 0))
        return (centre - min(centre, config.steps(config.earlySwing)))...(centre + config.steps(config.lateSwing))
    }

    // Any swing above the threshold in the window is a hit, so it is committed the moment it shows and the return
    // leaves the bat on time; the peak arriving later only refines pace, depth and aim, never undoes the hit.
    private mutating func strike(_ chance: Chance, with peak: RacketSample, isRising: Bool, events: inout [GameEvent]) {
        guard (config.lowestContact...config.highestContact).contains(chance.ball.position.z) else {
            let measured = measure(chance, at: peak, isRising: isRising)
            report(chance, measured.isClean ? .clean : .edge, peakSpeed: measured.speed, timing: measured.timing)
            self.chance = nil
            whiff(chance.side, events: &events)
            return
        }
        let stroked = stroke(chance, at: peak, isRising: isRising)
        land(stroked.ball, from: chance, strength: stroked.power, contact: 0, events: &events)
        let refining = Refining(
            chance: chance,
            stroked: stroked,
            committedAt: step,
            committedPower: stroked.power,
            until: step + config.steps(config.swingRefinement)
        )
        if isRising {
            self.refining = refining
        } else {
            settle(refining, events: &events)
        }
    }

    private mutating func refine(_ current: Refining, events: inout [GameEvent]) {
        switch racketSwing(for: current.chance) {
        case .peak(let peak):
            reshape(current, at: peak, isRising: false)
        case .rising(let peak):
            reshape(current, at: peak, isRising: true)
            guard step >= current.until else { return }
        case .waiting:
            // The swing is still speeding up past the committed sample: keep refining.
            guard step >= current.until else { return }
        case .none:
            break
        }
        if let refining {
            settle(refining, events: &events)
        }
    }

    private mutating func reshape(_ current: Refining, at peak: RacketSample, isRising: Bool) {
        guard peak != current.stroked.peak || isRising != current.stroked.isRising else { return }
        let stroked = stroke(current.chance, at: peak, isRising: isRising)
        guard stroked != current.stroked else { return }
        let side = current.chance.side
        flight = Flight(ball: stroked.ball, hitter: side, isServe: false)
        flightNumber += 1
        if pendingPoint?.loser == side {
            pendingPoint = nil
        }
        replayFlight(from: current.chance.step)
        refining?.stroked = stroked
    }

    private mutating func settle(_ refining: Refining, events: inout [GameEvent]) {
        let stroked = refining.stroked
        let side = refining.chance.side
        self.refining = nil
        directionChecks.append(DirectionCheck(side: side, around: refining.chance.step))
        if !stroked.isRising, abs(timingError(stroked.timing)) < Self.learnableError {
            remember(timing: stroked.raw, of: side, stance: stroked.stance)
        }
        report(refining.chance, stroked.isClean ? .clean : .edge, peakSpeed: stroked.speed, timing: stroked.timing)
        let flight = Shot.freeFlight(of: stroked.ball, config: config)
        lastSwing?.landing = flight.landing
        lastSwing?.clearsNet = flight.clearsNet
        lastSwing?.commitDelay = Double(refining.committedAt - refining.chance.step) / Double(config.stepsPerSecond)
        lastSwing?.committedPower = refining.committedPower
        if !stroked.isClean {
            events.append(.edgeHit(side))
        }
        events.append(.stroke(side, timing: stroked.timing))
    }

    private struct Measured {
        let raw: Double
        let timing: Double
        let speed: Double
        let power: Double
        let stance: Stance
        let isClean: Bool
    }

    // While the swing is still rising its peak can only come later, so the provisional timing is never early.
    private func measure(_ chance: Chance, at peak: RacketSample, isRising: Bool) -> Measured {
        let raw = (Double(peak.step) - Double(chance.step + config.steps(config.perceivedLag))) / Double(config.stepsPerSecond)
        let stance = stance(at: chance)
        let measured = raw - timingBias(of: chance.side, stance: stance)
        let timing = isRising ? max(measured, 0) : measured
        let speed = swingSpeed(for: chance)(peak)
        return Measured(raw: raw, timing: timing, speed: speed, power: min(speed / config.fullSwingSpeed, 1), stance: stance, isClean: abs(timing) <= config.cleanTiming)
    }

    private func stroke(_ chance: Chance, at peak: RacketSample, isRising: Bool) -> Stroked {
        let side = chance.side
        let measured = measure(chance, at: peak, isRising: isRising)
        let ball = Shot.stroke(chance.ball, by: side, Shot.Stroke(
            power: measured.power,
            aim: faceAim(of: peak, by: side),
            lift: lift(of: peak),
            error: timingError(measured.timing),
            pull: pull(of: peak, by: side),
            overhead: overhead(of: chance)
        ), config: config)
        return Stroked(
            peak: peak,
            ball: ball,
            speed: measured.speed,
            power: measured.power,
            raw: measured.raw,
            timing: measured.timing,
            stance: measured.stance,
            isClean: measured.isClean,
            isRising: isRising
        )
    }

    private var lastSwingDecision: UInt64 {
        max(config.steps(config.swingWindow), config.steps(config.perceivedLag + config.lateSwing + Self.largestBias)) + config.steps(config.lagCompensation)
    }

    private func timingError(_ timing: Double) -> Double {
        min(max(timing / (timing < 0 ? config.earlySwing : config.lateSwing), -1), 1)
    }

    // Early meets a bat already swung through, late one still coming round: each drifts the ball its own way across.
    private func pull(of peak: RacketSample, by side: Side) -> Double {
        (peak.stance == .forehand ? 1 : -1) * peak.handedness.mirror * side.forward
    }

    private func lift(of peak: RacketSample) -> Double {
        min(max(peak.bladeVelocity.z / config.liftSpeed, -1), 1)
    }

    public func swingDirection(of side: Side) -> SwingDirection {
        paddle(side).direction
    }

    // A fresh calibration says which way the table is again, so anything learned about the direction starts over.
    public mutating func resetSwingDirection(of side: Side) {
        var paddle = paddle(side)
        paddle.direction = SwingDirection()
        setPaddle(side, paddle)
    }

    // Each ball is judged once its whole swing is in view, half a second either side of it.
    private mutating func judgeDirections() {
        let span = config.steps(Self.directionSpan)
        let due = directionChecks.filter { step >= $0.around + span }
        directionChecks.removeAll { step >= $0.around + span }
        for check in due {
            var paddle = paddle(check.side)
            let around = paddle.samples.filter { $0.step + span >= check.around && $0.step <= check.around + span }
            paddle.direction.judge(
                forward: around.map { paddle.direction.forward($0.bladeVelocity) }.max() ?? 0,
                backward: around.map { paddle.direction.backward($0.bladeVelocity) }.max() ?? 0
            )
            setPaddle(check.side, paddle)
        }
    }

    // A player's swings land consistently early or late on one side; judge timing against their own habit.
    public func timingBias(of side: Side, stance: Stance) -> Double {
        let recent = paddle(side).timings[stance] ?? []
        guard recent.count >= Self.biasAfter else { return 0 }
        return min(max(recent.sorted()[recent.count / 2], -Self.largestBias), Self.largestBias)
    }

    private mutating func remember(timing: Double, of side: Side, stance: Stance) {
        var paddle = paddle(side)
        paddle.timings[stance, default: []].append(timing)
        if paddle.timings[stance, default: []].count > Self.biasMemory {
            paddle.timings[stance]?.removeFirst()
        }
        setPaddle(side, paddle)
    }

    private mutating func report(_ chance: Chance, _ outcome: SwingReport.Outcome, peakSpeed: Double, timing: Double) {
        let wide = config.steps(0.5)
        let around = paddle(chance.side).samples.filter { $0.step + wide >= chance.step && $0.step <= chance.step + wide }
        let forwardPeak = around.max { forwardSpeed(of: $0) < forwardSpeed(of: $1) }
        let fastest = around.max { simd_length($0.bladeVelocity) < simd_length($1.bladeVelocity) }
        lastSwing = SwingReport(
            number: (lastSwing?.number ?? 0) + 1,
            side: chance.side,
            outcome: outcome,
            peakSpeed: peakSpeed,
            timing: timing,
            ballHeight: chance.ball.position.z,
            nearestPeakSpeed: forwardPeak.map { forwardSpeed(of: $0) } ?? 0,
            nearestPeakOffset: forwardPeak.map { (Double($0.step) - Double(chance.step)) / Double(config.stepsPerSecond) } ?? 0,
            fastestBlade: fastest.map { simd_length($0.bladeVelocity) } ?? 0,
            fastestBladeForward: fastest.map { forwardSpeed(of: $0) } ?? 0,
            paddleX: chance.paddleX,
            ballX: chance.ball.position.x
        )
    }

    private func forwardSpeed(of sample: RacketSample) -> Double {
        paddle(sample.side).direction.forward(sample.bladeVelocity)
    }

    // A serve is struck from a still toss with no backswing to mistake, so either direction serves.
    private func serveSpeed(of sample: RacketSample) -> Double {
        abs(sample.bladeVelocity.y)
    }

    private mutating func hit(_ chance: Chance, with swing: Swing, events: inout [GameEvent]) {
        var paddle = paddle(swing.side)
        paddle.pendingSwing = nil
        setPaddle(swing.side, paddle)
        guard isReachable(chance) else {
            whiff(swing.side, events: &events)
            return
        }
        let timing = (Double(swing.step) - Double(chance.step)) / Double(max(config.steps(config.swingWindow), 1))
        let plan = Shot.Plan(strength: swing.strength, aim: swing.aim, contact: contactPoint(of: chance), timing: min(max(timing, -1), 1))
        let returned = Shot.planned(chance.ball, by: swing.side, plan: plan, wander: Double.random(in: -1...1, using: &random), config: config)
        land(returned, from: chance, strength: swing.strength, contact: plan.contact, events: &events)
    }

    private mutating func land(_ returned: Ball, from chance: Chance, strength: Double, contact: Double, events: inout [GameEvent]) {
        let side = chance.side
        flight = Flight(ball: returned, hitter: side, isServe: false)
        flightNumber += 1
        self.chance = nil
        if pendingPoint?.loser == side {
            pendingPoint = nil
        }
        rally += 1
        block(side)
        events.append(.hit(side, strength: strength, rally: rally))
        if abs(contact) >= config.edgeContact {
            events.append(.edgeHit(side))
        }
        replayFlight(from: chance.step)
    }

    // A hit decided or refined after the contact step replays the return from there to now.
    private mutating func replayFlight(from start: UInt64) {
        for _ in start..<step {
            for event in flight.advance(config: config) {
                if case .fault(let loser) = event {
                    pendingPoint = PendingPoint(loser: loser, awardAt: step + config.steps(config.lagCompensation))
                }
            }
        }
    }

    private mutating func expireSwings(events: inout [GameEvent]) {
        let window = config.steps(config.swingWindow)
        for side in Side.allCases {
            guard let swing = paddle(side).pendingSwing, swing.step + window < step, chance?.side != side else { continue }
            var paddle = paddle(side)
            paddle.pendingSwing = nil
            setPaddle(side, paddle)
            whiff(side, events: &events)
        }
    }

    private mutating func whiff(_ side: Side, events: inout [GameEvent]) {
        block(side)
        events.append(.whiff(side))
    }

    private mutating func serve(
        by server: Side,
        from position: SIMD3<Double>? = nil,
        strength: Double,
        aim: Double,
        spin: SIMD3<Double>? = nil,
        catchUp: UInt64 = 0,
        events: inout [GameEvent]
    ) {
        let plan = Shot.Plan(strength: strength, aim: aim, contact: 0, timing: 0)
        flightNumber += 1
        flight = Flight(ball: Shot.serve(from: position ?? flight.ball.position, by: server, plan: plan, spin: spin, config: config), hitter: server, isServe: true)
        toss = nil
        rally = 0
        chance = nil
        phase = .rally
        block(server)
        events.append(.served(server))
        replayFlight(from: step - catchUp)
    }

    private mutating func awardPendingPoint(events: inout [GameEvent]) {
        guard let pending = pendingPoint, step >= pending.awardAt, chance?.side != pending.loser, refining?.chance.side != pending.loser else { return }
        pendingPoint = nil
        chance = nil
        rally = 0
        let winner = pending.loser.opponent
        score.award(winner)
        events.append(.pointScored(winner: winner, score: score))
        if let champion = score.winner(target: config.winningScore) {
            phase = .gameOver(winner: champion)
            events.append(.gameOver(winner: champion))
        } else {
            phase = .pointScored(until: step + config.steps(config.pauseBetweenPoints))
        }
    }

    private mutating func startServing() {
        let server = score.server(firstServer: config.firstServer, target: config.winningScore, servesPerTurn: config.servesPerTurn)
        phase = .serving(server, since: step)
        toss = nil
        holdBallForServe(by: server, snap: true)
    }

    // A phone server holds the ball on the side of the stroke they're shaping up for.
    private mutating func holdBallForServe(by server: Side, snap: Bool = false) {
        let edge = config.ballRadius * 4
        let hand = paddle(server).samples.last.map { ArmModel.restingHand($0.stance, $0.handedness).x * server.forward * Self.ballInHand } ?? 0
        let wanted = min(max(paddle(server).x + hand, edge), config.tableWidth - edge)
        let held = flight.ball.position.x
        let most = Self.handSpeed * config.stepDuration
        let x = snap ? wanted : held + min(max(wanted - held, -most), most)
        let y = server == .playerA ? -config.ballRadius * 3 : config.tableLength + config.ballRadius * 3
        flight = Flight(ball: Ball(position: SIMD3(x, y, config.tossFrom)), hitter: server, isServe: true)
    }

    private func isInWindow(_ swingStep: UInt64, of chance: Chance) -> Bool {
        distance(swingStep, chance.step) <= config.steps(config.swingWindow)
    }

    private func isReachable(_ chance: Chance) -> Bool {
        config.canReach(ballX: chance.ball.position.x, paddleX: chance.paddleX)
            && (config.lowestContact...config.highestContact).contains(chance.ball.position.z)
    }

    private func contactPoint(of chance: Chance) -> Double {
        min(max((chance.ball.position.x - chance.paddleX) / config.reach, -1), 1)
    }

    private func distance(_ a: UInt64, _ b: UInt64) -> UInt64 {
        a > b ? a - b : b - a
    }

    private mutating func block(_ side: Side) {
        var paddle = paddle(side)
        paddle.swingsBlockedUntil = step + config.steps(config.swingCooldown)
        setPaddle(side, paddle)
    }

    private func paddle(_ side: Side) -> Paddle {
        side == .playerA ? paddleA : paddleB
    }

    private mutating func setPaddle(_ side: Side, _ paddle: Paddle) {
        if side == .playerA {
            paddleA = paddle
        } else {
            paddleB = paddle
        }
    }
}
