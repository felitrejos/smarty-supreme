// Which way along the table counts as a stroke, so a backswing never does. A held phone can reverse the reading, so a
// serve swing sets it outright and a couple of rally balls swung clearly the other way turn it round.
public struct SwingDirection: Equatable, Sendable {
    public static let wrongWayToTurn = 2
    public static let clearlyHard = 2.5
    public static let clearlyHarder = 1.5

    public private(set) var sign = 1.0
    public private(set) var wrongWayInARow = 0

    public init() {}

    public mutating func served(_ bladeVelocity: SIMD3<Double>) {
        sign = bladeVelocity.y < 0 ? -1 : 1
        wrongWayInARow = 0
    }

    public func forward(_ bladeVelocity: SIMD3<Double>) -> Double {
        max(bladeVelocity.y * sign, 0)
    }

    public func backward(_ bladeVelocity: SIMD3<Double>) -> Double {
        max(-bladeVelocity.y * sign, 0)
    }

    // The hardest swing each way around one ball: a late player's stroke outweighs their backswing, so only a
    // clearly harder swing the other way counts.
    public mutating func judge(forward: Double, backward: Double) {
        guard backward >= Self.clearlyHard, backward >= Self.clearlyHarder * forward else {
            wrongWayInARow = 0
            return
        }
        wrongWayInARow += 1
        if wrongWayInARow >= Self.wrongWayToTurn {
            sign = -sign
            wrongWayInARow = 0
        }
    }
}
