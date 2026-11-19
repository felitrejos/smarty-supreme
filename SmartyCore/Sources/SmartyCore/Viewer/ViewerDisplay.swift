import simd

public struct ViewerConfig: Sendable {
    public var correctionSpeed = 0.5
    public var snapDistance = 0.1

    public init() {}
}

public struct ViewerDisplay: Sendable {
    public struct Frame: Equatable, Sendable {
        public let ball: SIMD2<Double>
        public let velocity: SIMD2<Double>
        public let shotStart: SIMD2<Double>
        public let paddleA: Double
        public let paddleB: Double
        public let phase: GamePhase
        public let scoreA: Int
        public let scoreB: Int
        public let serving: Side
        public let rally: Int
    }

    private let config: GameConfig
    private let viewerConfig: ViewerConfig
    private var source: ViewerLink.ReceivedSnapshot?
    private var offset = SIMD2<Double>.zero
    private var lastFrameAt: Microseconds?

    public init(config: GameConfig, viewerConfig: ViewerConfig = ViewerConfig()) {
        self.config = config
        self.viewerConfig = viewerConfig
    }

    public mutating func frame(from latest: ViewerLink.ReceivedSnapshot, at now: Microseconds) -> Frame {
        let truth = position(of: latest, at: now)
        if let source, source.snapshot.step != latest.snapshot.step {
            offset += position(of: source, at: now) - truth
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
            ball: truth + offset,
            velocity: SIMD2<Double>(snapshot.velocity),
            shotStart: SIMD2<Double>(snapshot.shotStart),
            paddleA: Double(snapshot.paddleA),
            paddleB: Double(snapshot.paddleB),
            phase: snapshot.phase,
            scoreA: Int(snapshot.scoreA),
            scoreB: Int(snapshot.scoreB),
            serving: snapshot.serving,
            rally: Int(snapshot.rally)
        )
    }

    private func position(of received: ViewerLink.ReceivedSnapshot, at now: Microseconds) -> SIMD2<Double> {
        let snapshot = received.snapshot
        let ball = SIMD2<Double>(snapshot.ball)
        guard snapshot.phase == .rally, now > received.receivedAt else { return ball }
        let path = BallPath(position: ball, velocity: SIMD2<Double>(snapshot.velocity), config: config)
        return path.position(after: Double(now - received.receivedAt) / 1_000_000)
    }
}
