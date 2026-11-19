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
    }

    private struct Chance: Equatable, Sendable {
        let side: Side
        let step: UInt64
        let ball: Ball
        let paddleX: Double
    }

    private struct PendingPoint: Equatable, Sendable {
        let loser: Side
        let awardAt: UInt64
    }

    private static let sampleMemory = 0.4
    private static let predictionLimit = 3.0

    public let config: GameConfig
    public private(set) var step: UInt64 = 0
    public private(set) var phase: Phase
    public private(set) var score = Score(a: 0, b: 0)
    public private(set) var rally = 0
    public private(set) var flightNumber: UInt64 = 0
    private var flight: Flight
    private var paddleA: Paddle
    private var paddleB: Paddle
    private var chance: Chance?
    private var phaseBeforePause: Phase?
    private var pendingPoint: PendingPoint?
    private var random: SplitMix64

    public init(seed: UInt64, config: GameConfig = GameConfig()) {
        self.config = config
        random = SplitMix64(seed: seed)
        let middle = config.tableWidth / 2
        paddleA = Paddle(x: middle, target: middle)
        paddleB = Paddle(x: middle, target: middle)
        phase = .serving(config.firstServer, since: 0)
        flight = Flight(ball: Ball(position: .zero), hitter: config.firstServer, isServe: true)
        holdBallForServe(by: config.firstServer)
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
        for swing in input.swings {
            handle(swing, events: &events)
        }
        switch phase {
        case .serving(let server, let since):
            holdBallForServe(by: server)
            if let sample = paddle(server).samples.last, sample.step + config.steps(config.lagCompensation) >= step, sample.speed >= config.serveThreshold, step >= paddle(server).swingsBlockedUntil {
                serve(by: server, strength: min(sample.speed / config.fullSwingSpeed, 1), aim: 0, events: &events)
            } else if step - since >= config.steps(config.autoServeAfter) {
                serve(by: server, strength: config.autoServeStrength, aim: 0, events: &events)
            }
        case .rally:
            fly(events: &events)
            resolveChance(events: &events)
            expireSwings(events: &events)
            awardPendingPoint(events: &events)
        case .pointScored(let until):
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
            paddle.samples.append(sample)
            paddle.samples.removeAll { $0.step + memory < step }
            setPaddle(sample.side, paddle)
        }
    }

    private mutating func handle(_ swing: Swing, events: inout [GameEvent]) {
        let side = swing.side
        guard step >= paddle(side).swingsBlockedUntil else { return }
        switch phase {
        case .serving(let server, _):
            guard side == server else { return }
            serve(by: server, strength: swing.strength, aim: swing.aim, events: &events)
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
        for event in flight.advance(config: config) {
            switch event {
            case .bounce(let half): events.append(.bounce(half))
            case .net: events.append(.net)
            case .fault(let loser): pendingPoint = PendingPoint(loser: loser, awardAt: step + config.steps(config.lagCompensation))
            case .chance(let side): chance = Chance(side: side, step: step, ball: flight.ball, paddleX: paddle(side).x)
            }
        }
    }

    private mutating func resolveChance(events: inout [GameEvent]) {
        guard let chance else { return }
        let side = chance.side
        if let swing = paddle(side).pendingSwing, isInWindow(swing.step, of: chance) {
            hit(chance, with: swing, events: &events)
            return
        }
        let waited = step - chance.step
        let samples = paddle(side).samples
        let hasSamplesPastContact = samples.contains { $0.step >= chance.step }
        if hasSamplesPastContact || waited >= config.steps(config.lagCompensation) {
            let window = config.steps(config.swingWindow)
            let swinging = samples.filter { $0.speed >= config.swingThreshold && $0.step + window >= chance.step && $0.step <= chance.step + window }
            if let sample = swinging.min(by: { distance($0.step, chance.step) < distance($1.step, chance.step) }),
               isReachable(chance),
               let returned = Shot.racket(chance.ball, by: side, sample: sample, config: config) {
                land(returned, from: chance, strength: min(sample.speed / config.fullSwingSpeed, 1), contact: contactPoint(of: chance), events: &events)
                return
            }
        }
        if waited > max(config.steps(config.swingWindow), config.steps(config.lagCompensation)) {
            self.chance = nil
        }
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
        for _ in chance.step..<step {
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

    private mutating func serve(by server: Side, strength: Double, aim: Double, events: inout [GameEvent]) {
        let plan = Shot.Plan(strength: strength, aim: aim, contact: 0, timing: 0)
        flightNumber += 1
        flight = Flight(ball: Shot.serve(from: flight.ball.position, by: server, plan: plan, config: config), hitter: server, isServe: true)
        rally = 0
        chance = nil
        phase = .rally
        block(server)
        events.append(.served(server))
    }

    private mutating func awardPendingPoint(events: inout [GameEvent]) {
        guard let pending = pendingPoint, step >= pending.awardAt, chance?.side != pending.loser else { return }
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
        holdBallForServe(by: server)
    }

    private mutating func holdBallForServe(by server: Side) {
        let edge = config.ballRadius * 4
        let x = min(max(paddle(server).x, edge), config.tableWidth - edge)
        let y = server == .playerA ? -config.ballRadius * 3 : config.tableLength + config.ballRadius * 3
        flight = Flight(ball: Ball(position: SIMD3(x, y, config.serveHeight)), hitter: server, isServe: true)
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
