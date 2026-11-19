import simd

struct PaddleMotion {
    private static let stiffness: Float = 16
    private static let sideSwitch: Float = 9
    private static let windUpRate: Float = 7
    private static let windUpLead: Float = 0.32
    private static let backhandMargin: Float = 0.04
    private static let strike: Float = 0.09
    private static let followThrough: Float = 0.2
    private static let recovery: Float = 0.42
    private static let reachRate: Float = 18
    private static let farthestReach: Float = 0.3

    private(set) var x: Float
    private var velocity: Float = 0
    private var backhand: Float = 0
    private var windUp: Float = 0
    private var stroke: (elapsed: Float, strength: Float, backhand: Float)?
    private var reach: Float = 0
    private(set) var reachWeight: Float = 0

    init(x: Float) {
        self.x = x
    }

    mutating func hit(strength: Float) {
        stroke = (0, strength, backhand)
        windUp = 0
    }

    mutating func update(target: Float, ballAcross: Float, contactAcross: Float?, secondsToContact: Float?, elapsed: Float) {
        let acceleration = Self.stiffness * Self.stiffness * (target - x) - 2 * Self.stiffness * velocity
        velocity += acceleration * elapsed
        x += velocity * elapsed

        if secondsToContact != nil, abs(ballAcross) > Self.backhandMargin {
            backhand += ((ballAcross < 0 ? 1 : 0) - backhand) * min(Self.sideSwitch * elapsed, 1)
        }
        let winding: Float = secondsToContact.map { $0 < Self.windUpLead ? 1 : 0 } ?? 0
        windUp += (winding - windUp) * min(Self.windUpRate * elapsed, 1)
        if let current = stroke {
            let next = current.elapsed + elapsed
            stroke = next < Self.recovery ? (next, current.strength, current.backhand) : nil
        }
        let holding = stroke.map { $0.elapsed < Self.followThrough } ?? false
        let reaching = holding || (secondsToContact.map { $0 < Self.windUpLead } ?? false)
        if !holding, reaching, let contactAcross {
            reach += (min(max(contactAcross, -Self.farthestReach), Self.farthestReach) - reach) * min(Self.reachRate * elapsed, 1)
        }
        reachWeight += ((reaching ? 1 : 0) - reachWeight) * min(Self.reachRate * elapsed, 1)
    }

    var lateralSpeed: Float {
        velocity
    }

    func pose() -> (offset: SIMD3<Float>, orientation: simd_quatf) {
        let face = backhand * 2 - 1
        var offset = SIMD3<Float>(0, 0, 0)
        var yaw = -0.25 * face
        var pitch: Float = 0.12
        let back = smooth(windUp)
        offset += [0.05 * -face, -0.05, 0.1] * back
        yaw += -0.45 * face * back
        pitch += 0.25 * back

        if let stroke {
            let power = 0.6 + 0.6 * stroke.strength
            let strokeFace = stroke.backhand * 2 - 1
            let t = stroke.elapsed
            let swing: Float
            let rise: Float
            if t < Self.strike {
                swing = smooth(t / Self.strike)
                rise = swing * 0.6
            } else if t < Self.followThrough {
                swing = 1 + 0.35 * smooth((t - Self.strike) / (Self.followThrough - Self.strike))
                rise = 0.6 + 0.4 * smooth((t - Self.strike) / (Self.followThrough - Self.strike))
            } else {
                let settle = 1 - smooth((t - Self.followThrough) / (Self.recovery - Self.followThrough))
                swing = 1.35 * settle
                rise = settle
            }
            offset += [0, 0.14 * rise, -0.2 * min(swing, 1)] * power
            yaw += 0.6 * strokeFace * swing * power
            pitch -= 0.5 * min(swing, 1) * power
        }
        offset.x += reach * reachWeight
        let orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
        return (offset, orientation)
    }

    private func smooth(_ t: Float) -> Float {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
