struct Flight: Equatable, Sendable {
    enum Event: Equatable, Sendable {
        case bounce(Side)
        case net
        case fault(Side)
        case chance(Side)
    }

    var ball: Ball
    let hitter: Side
    let isServe: Bool
    private(set) var bounces: [Side] = []
    private(set) var chanceGiven = false
    private(set) var isDecided = false

    init(ball: Ball, hitter: Side, isServe: Bool) {
        self.ball = ball
        self.hitter = hitter
        self.isServe = isServe
    }

    var receiver: Side {
        hitter.opponent
    }

    var isReady: Bool {
        !isDecided && bounces == (isServe ? [hitter, receiver] : [receiver])
    }

    mutating func advance(config: GameConfig) -> [Event] {
        let before = ball
        var events: [Event] = []
        switch BallPhysics.advance(&ball, seconds: config.physicsStep, config: config) {
        case .table(let half):
            events.append(.bounce(half))
            judgeBounce(on: half, events: &events)
        case .net:
            events.append(.net)
        case .floor:
            decide(loser: isReady ? receiver : hitter, events: &events)
        case nil:
            break
        }
        if isReady, !chanceGiven, reachesReceiver(from: before, config: config) {
            chanceGiven = true
            events.append(.chance(receiver))
        }
        return events
    }

    private mutating func judgeBounce(on half: Side, events: inout [Event]) {
        guard !isDecided else { return }
        if isReady {
            decide(loser: receiver, events: &events)
            return
        }
        let expected = isServe && bounces.isEmpty ? hitter : receiver
        if half == expected {
            bounces.append(half)
        } else {
            decide(loser: hitter, events: &events)
        }
    }

    private mutating func decide(loser: Side, events: inout [Event]) {
        guard !isDecided else { return }
        isDecided = true
        events.append(.fault(loser))
    }

    private func reachesReceiver(from before: Ball, config: GameConfig) -> Bool {
        let plane = config.contactY(of: receiver)
        let toward = receiver.forward
        if (before.position.y - plane) * toward > 0, (ball.position.y - plane) * toward <= 0 {
            return true
        }
        let height = config.reachDownHeight + config.ballRadius
        return before.position.z >= height && ball.position.z < height && ball.velocity.z < 0
            && config.half(atY: ball.position.y) == receiver
    }
}
