import simd

public enum Stance: Equatable, Sendable {
    case forehand
    case backhand
}

public enum Handedness: UInt8, CaseIterable, Sendable {
    case right
    case left

    var mirror: Double {
        self == .right ? 1 : -1
    }
}

public enum ArmModel {
    public static let grip = 0.13
    private static let forehandHand = SIMD3<Double>(0.32, 0.25, -0.25)
    private static let backhandHand = SIMD3<Double>(-0.2, 0.3, -0.25)
    private static let forehandForearm = SIMD3<Double>(0.25, 0.08, 0)
    private static let backhandForearm = SIMD3<Double>(-0.25, 0.08, 0)
    private static let switchMargin = 0.2
    private static let backhandMargin = 0.1
    private static let forehandRest = simd_quatd(simd_double3x3(columns: (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0))))
    private static let backhandRest = simd_quatd(angle: .pi, axis: SIMD3(0, 0, 1)) * forehandRest

    public static var restOrientation: simd_quatd {
        forehandRest
    }

    public static func stance(of orientation: simd_quatd, previous: Stance? = nil) -> Stance {
        let facing = orientation.act(SIMD3(0, 0, 1)).y
        if facing > switchMargin { return .forehand }
        if facing < -switchMargin { return .backhand }
        return previous ?? (facing >= 0 ? .forehand : .backhand)
    }

    public static func restingHand(_ stance: Stance, _ handedness: Handedness = .right) -> SIMD3<Double> {
        mirrored(stance == .forehand ? forehandHand : backhandHand, handedness)
    }

    public static func bladeVelocity(
        _ angularVelocity: SIMD3<Double>,
        linearVelocity: SIMD3<Double>,
        orientation: simd_quatd,
        stance: Stance,
        handedness: Handedness = .right
    ) -> SIMD3<Double> {
        let forearm = (orientation * rest(stance).inverse).act(self.forearm(stance, handedness))
        return simd_cross(angularVelocity, forearm + orientation.act(SIMD3(0, grip, 0))) + linearVelocity
    }

    public static func stance(forBallAt across: Double, handedness: Handedness) -> Stance {
        across * handedness.mirror >= -backhandMargin ? .forehand : .backhand
    }

    private static func forearm(_ stance: Stance, _ handedness: Handedness) -> SIMD3<Double> {
        mirrored(stance == .forehand ? forehandForearm : backhandForearm, handedness)
    }

    private static func mirrored(_ vector: SIMD3<Double>, _ handedness: Handedness) -> SIMD3<Double> {
        SIMD3(vector.x * handedness.mirror, vector.y, vector.z)
    }

    private static func rest(_ stance: Stance) -> simd_quatd {
        stance == .forehand ? forehandRest : backhandRest
    }
}
