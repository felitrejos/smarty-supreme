public struct BallPath: Sendable {
    private let start: SIMD2<Double>
    private let velocity: SIMD2<Double>
    private let lowestX: Double
    private let highestX: Double

    public init(ball: GameState.Ball, config: GameConfig) {
        self.init(position: ball.position, velocity: ball.velocity, config: config)
    }

    public init(position: SIMD2<Double>, velocity: SIMD2<Double>, config: GameConfig) {
        start = position
        self.velocity = velocity
        lowestX = config.ballRadius
        highestX = config.tableWidth - config.ballRadius
    }

    public func secondsUntil(y: Double) -> Double? {
        let seconds = (y - start.y) / velocity.y
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    public func position(after seconds: Double) -> SIMD2<Double> {
        let travelled = start + velocity * seconds
        return SIMD2(folded(travelled.x), travelled.y)
    }

    private func folded(_ x: Double) -> Double {
        let span = highestX - lowestX
        let offset = (x - lowestX).truncatingRemainder(dividingBy: 2 * span)
        let wrapped = offset < 0 ? offset + 2 * span : offset
        return lowestX + (wrapped <= span ? wrapped : 2 * span - wrapped)
    }
}
