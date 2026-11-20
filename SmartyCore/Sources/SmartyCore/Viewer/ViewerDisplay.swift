import simd

public struct ViewerConfig: Sendable {
    public var correctionSpeed = 0.5
    public var snapDistance = 0.1

    public init() {}
}

public struct ViewerDisplay: Sendable {
    public struct Frame: Equatable, Sendable {
        public let ball: SIMD3<Double>
        public let velocity: SIMD3<Double>
        public let paddleA: Double
        public let paddleB: Double
        public let phase: GamePhase
        public let scoreA: Int
        public let scoreB: Int
        public let rally: Int
    }

    private let config: GameConfig
    private let viewerConfig: ViewerConfig
    private var source: ViewerLink.ReceivedSnapshot?
    private var offset = SIMD3<Double>.zero
    private var lastFrameAt: Microseconds?

    public init(config: GameConfig, viewerConfig: ViewerConfig = ViewerConfig()) {
        self.config = config
        self.viewerConfig = viewerConfig
    }

    public mutating func frame(from latest: ViewerLink.ReceivedSnapshot, at now: Microseconds) -> Frame {
        let truth = ball(of: latest, at: now)
        if let source, source.snapshot.step != latest.snapshot.step {
            offset += ball(of: source, at: now).position - truth.position
            if source.snapshot.phase != .rally || latest.snapshot.phase != .rally || simd_length(offset) > viewerConfig.snapDistance {
                offset = .zero
            }
        }
        source = latest
        let elapsed = Double(now - (lastFrameAt ?? now)) / 1_000_000
        lastFrameAt = now
        let length = simd_length(offset)
        let correction = viewerConfig.correctionSpeed * elapsed
        offset = length <= correction ? .zero : offset * ((length - correction) / length)
        let snapshot = latest.snapshot
        return Frame(
            ball: truth.position + offset,
            velocity: truth.velocity,
            paddleA: Double(snapshot.paddleA),
            paddleB: Double(snapshot.paddleB),
            phase: snapshot.phase,
            scoreA: Int(snapshot.scoreA),
            scoreB: Int(snapshot.scoreB),
            rally: Int(snapshot.rally)
        )
    }

    private func ball(of received: ViewerLink.ReceivedSnapshot, at now: Microseconds) -> Ball {
        let snapshot = received.snapshot
        var ball = Ball(position: SIMD3<Double>(snapshot.ball), velocity: SIMD3<Double>(snapshot.velocity), spin: SIMD3<Double>(snapshot.spin))
        guard snapshot.phase == .rally, now > received.receivedAt else { return ball }
        let elapsed = Double(now - received.receivedAt) / 1_000_000 * config.timeScale
        let steps = min(Int(elapsed / config.physicsStep), config.stepsPerSecond)
        for _ in 0..<steps {
            _ = BallPhysics.advance(&ball, seconds: config.physicsStep, config: config)
        }
        return ball
    }
}
