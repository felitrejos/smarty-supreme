import Foundation

public struct GameState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case serving(Side, since: UInt64)
        case rally
        case pointScored(until: UInt64)
        case paused
        case gameOver(winner: Side)
    }

    public struct Ball: Equatable, Sendable {
        public var position: SIMD2<Double>
        public var velocity: SIMD2<Double>

        public var speed: Double {
            (velocity * velocity).sum().squareRoot()
        }
    }

    private struct Paddle: Equatable, Sendable {
        var x: Double
        var target: Double
        var swingsBlockedUntil: UInt64 = 0
    }

    private struct Moment: Equatable, Sendable {
        let step: UInt64
        let ball: Ball
        let paddleXA: Double
        let paddleXB: Double

        func paddleX(of side: Side) -> Double {
            side == .playerA ? paddleXA : paddleXB
        }
    }

    private struct PendingPoint: Equatable, Sendable {
        let loser: Side
        let crossedAt: UInt64
    }

    public let config: GameConfig
    public private(set) var step: UInt64 = 0
    public private(set) var phase: Phase
    public private(set) var ball: Ball
    public private(set) var score = Score(a: 0, b: 0)
    public private(set) var rally = 0
    public private(set) var shotStart: SIMD2<Double>
    private var paddleA: Paddle
    private var paddleB: Paddle
    private var phaseBeforePause: Phase?
    private var pendingPoint: PendingPoint?
    private var history: [Moment] = []
    private var random: SplitMix64

    public init(seed: UInt64, config: GameConfig = GameConfig()) {
        self.config = config
        random = SplitMix64(seed: seed)
        let middle = config.tableWidth / 2
        paddleA = Paddle(x: middle, target: middle)
        paddleB = Paddle(x: middle, target: middle)
        phase = .serving(config.firstServer, since: 0)
        ball = Ball(position: .zero, velocity: .zero)
        shotStart = .zero
        holdBallForServe(by: config.firstServer)
    }

    public func paddleX(of side: Side) -> Double {
        paddle(side).x
    }

    public func paddlePosition(of side: Side) -> Double {
        let half = config.paddleWidth / 2
        return (paddle(side).x - half) / (config.tableWidth - 2 * half)
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
        for swing in input.swings {
            handle(swing, events: &events)
        }
        switch phase {
        case .serving(let server, let since):
            holdBallForServe(by: server)
            if step - since >= config.steps(config.autoServeAfter) {
                serve(by: server, strength: config.autoServeStrength, aim: 0, events: &events)
            }
        case .rally:
            ball = advance(ball, events: &events)
            detectGoalLine()
            awardPendingPoint(events: &events)
        case .pointScored(let until):
            if step >= until {
                startServing()
            }
        case .paused, .gameOver:
            break
        }
        record()
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

    private mutating func handle(_ swing: Swing, events: inout [GameEvent]) {
        guard step >= paddle(swing.side).swingsBlockedUntil else { return }
        switch phase {
        case .serving(let server, _):
            guard swing.side == server else { return }
            serve(by: server, strength: swing.strength, aim: swing.aim, events: &events)
        case .rally:
            guard let moment = moment(forSwingAt: swing.step) else { return }
            if isReturnable(moment, by: swing.side) {
                hit(moment, swing: swing, events: &events)
            } else {
                block(swing.side)
                events.append(.whiff(swing.side))
            }
        case .pointScored, .paused, .gameOver:
            return
        }
    }

    private func moment(forSwingAt swingStep: UInt64) -> Moment? {
        history.last { $0.step <= swingStep } ?? history.first
    }

    private func isReturnable(_ moment: Moment, by side: Side) -> Bool {
        let approaching = moment.ball.velocity.y * side.forward < 0
        let face = config.paddleFaceY(of: side)
        let depth = config.zoneDepth(forSpeed: moment.ball.speed)
        let distanceInFront = (moment.ball.position.y - face) * side.forward
        let inZone = distanceInFront >= 0 && distanceInFront <= depth
        return approaching && inZone && config.canReach(ballX: moment.ball.position.x, paddleX: moment.paddleX(of: side))
    }

    private mutating func hit(_ moment: Moment, swing: Swing, events: inout [GameEvent]) {
        let side = swing.side
        let reach = config.paddleWidth / 2 + config.ballRadius
        let contact = min(max((moment.ball.position.x - moment.paddleX(of: side)) / reach, -1), 1)
        let maximumAngle = config.maximumReturnAngleDegrees * .pi / 180
        let angle = config.contactShare * contact * maximumAngle + (1 - config.contactShare) * swing.aim * maximumAngle
        let speed = min(moment.ball.speed * config.speedGain + swing.strength * config.strengthBoost, config.maximumSpeed)

        var returned = Ball(position: moment.ball.position, velocity: SIMD2(sin(angle), cos(angle) * side.forward) * speed)
        var ignored: [GameEvent] = []
        for _ in moment.step..<(step - 1) {
            returned = advance(returned, events: &ignored)
        }
        ball = returned
        shotStart = moment.ball.position
        if pendingPoint?.loser == side {
            pendingPoint = nil
        }
        history.removeAll(keepingCapacity: true)
        rally += 1
        block(side)
        events.append(.hit(side, strength: swing.strength, rally: rally))
    }

    private mutating func serve(by server: Side, strength: Double, aim: Double, events: inout [GameEvent]) {
        let spread = config.serveSpreadDegrees * .pi / 180
        let aimRange = (1 - config.contactShare) * config.maximumReturnAngleDegrees * .pi / 180
        let angle = Double.random(in: -spread...spread, using: &random) + aim * aimRange
        let speed = min(config.startSpeed + strength * config.strengthBoost, config.maximumSpeed)
        ball.velocity = SIMD2(sin(angle), cos(angle) * server.forward) * speed
        shotStart = ball.position
        rally = 0
        phase = .rally
        block(server)
        events.append(.served(server))
    }

    private func advance(_ ball: Ball, events: inout [GameEvent]) -> Ball {
        var position = ball.position + ball.velocity * config.stepDuration
        var velocity = ball.velocity
        let low = config.ballRadius
        let high = config.tableWidth - config.ballRadius
        while position.x < low || position.x > high {
            position.x = position.x < low ? 2 * low - position.x : 2 * high - position.x
            velocity.x = -velocity.x
            events.append(.wallBounce)
        }
        return Ball(position: position, velocity: velocity)
    }

    private mutating func detectGoalLine() {
        guard pendingPoint == nil else { return }
        if ball.position.y < 0 {
            pendingPoint = PendingPoint(loser: .playerA, crossedAt: step)
        } else if ball.position.y > config.tableLength {
            pendingPoint = PendingPoint(loser: .playerB, crossedAt: step)
        }
    }

    private mutating func awardPendingPoint(events: inout [GameEvent]) {
        guard let pending = pendingPoint, step - pending.crossedAt >= config.steps(config.lagCompensation) else { return }
        pendingPoint = nil
        history.removeAll(keepingCapacity: true)
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
        let y = config.paddleFaceY(of: server) + server.forward * (config.ballRadius + 0.01)
        ball = Ball(position: SIMD2(paddle(server).x, y), velocity: .zero)
        shotStart = ball.position
    }

    private mutating func block(_ side: Side) {
        var paddle = paddle(side)
        paddle.swingsBlockedUntil = step + config.steps(config.swingCooldown)
        setPaddle(side, paddle)
    }

    private mutating func record() {
        history.append(Moment(step: step, ball: ball, paddleXA: paddleA.x, paddleXB: paddleB.x))
        if history.count > Int(config.steps(config.lagCompensation)) + 1 {
            history.removeFirst()
        }
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
