import simd

public struct MotionSample: Equatable, Sendable {
    public let time: Microseconds
    public let userAcceleration: SIMD3<Double>
    public let rotationRate: SIMD3<Double>
    public let attitude: simd_quatd
    public let gravity: SIMD3<Double>

    public init(
        time: Microseconds,
        userAcceleration: SIMD3<Double>,
        rotationRate: SIMD3<Double>,
        attitude: simd_quatd,
        gravity: SIMD3<Double>
    ) {
        self.time = time
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.attitude = attitude
        self.gravity = gravity
    }
}
