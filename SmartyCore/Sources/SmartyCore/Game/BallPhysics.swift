import simd

public struct Ball: Equatable, Sendable {
    public var position: SIMD3<Double>
    public var velocity: SIMD3<Double>
    public var spin: SIMD3<Double>

    public init(position: SIMD3<Double>, velocity: SIMD3<Double> = .zero, spin: SIMD3<Double> = .zero) {
        self.position = position
        self.velocity = velocity
        self.spin = spin
    }

    public var speed: Double {
        simd_length(velocity)
    }
}

public enum BallContact: Equatable, Sendable {
    case table(Side)
    case net
    case floor
}

public enum BallPhysics {
    private static let rollingShare = 0.4

    public static func advance(_ ball: inout Ball, seconds: Double, config: GameConfig) -> BallContact? {
        let before = ball
        fly(&ball, seconds: seconds, config: config)
        if let net = netContact(from: before, to: &ball, config: config) {
            return net
        }
        return surfaceContact(from: before, to: &ball, config: config)
    }

    static func fly(_ ball: inout Ball, seconds: Double, config: GameConfig) {
        let acceleration = SIMD3<Double>(0, 0, -config.gravity)
            - config.drag * ball.speed * ball.velocity
            + config.magnus * simd_cross(ball.spin, ball.velocity)
        ball.velocity += acceleration * seconds
        ball.position += ball.velocity * seconds
    }

    private static func netContact(from before: Ball, to ball: inout Ball, config: GameConfig) -> BallContact? {
        let middle = config.tableLength / 2
        let wasBefore = before.position.y < middle
        guard wasBefore != (ball.position.y < middle) else { return nil }
        let x = ball.position.x
        guard x > -config.netOverhang, x < config.tableWidth + config.netOverhang, ball.position.z - config.ballRadius < config.netHeight else { return nil }
        if ball.position.z < config.netHeight - config.ballRadius {
            ball.position.y = middle + (wasBefore ? -config.ballRadius : config.ballRadius)
            ball.velocity = SIMD3(ball.velocity.x * config.netDamping, -ball.velocity.y * config.netRestitution, ball.velocity.z * config.netDamping)
        } else {
            ball.velocity.y *= config.netCordDamping
            ball.velocity.z = abs(ball.velocity.z) * config.netDamping
        }
        ball.spin *= config.netDamping
        return .net
    }

    private static func surfaceContact(from before: Ball, to ball: inout Ball, config: GameConfig) -> BallContact? {
        let overTable = (0...config.tableWidth).contains(ball.position.x) && (0...config.tableLength).contains(ball.position.y)
        if overTable, before.position.z >= config.ballRadius, ball.position.z < config.ballRadius, ball.velocity.z < 0 {
            ball.position.z = 2 * config.ballRadius - ball.position.z
            bounce(&ball, restitution: config.tableRestitution, friction: config.tableFriction, radius: config.ballRadius)
            return .table(ball.position.y < config.tableLength / 2 ? .playerA : .playerB)
        }
        let floor = config.ballRadius - config.tableHeight
        if ball.position.z < floor, ball.velocity.z < 0 {
            ball.position.z = 2 * floor - ball.position.z
            bounce(&ball, restitution: config.floorRestitution, friction: config.tableFriction, radius: config.ballRadius)
            return .floor
        }
        return nil
    }

    private static func bounce(_ ball: inout Ball, restitution: Double, friction: Double, radius: Double) {
        let normalSpeed = -ball.velocity.z
        ball.velocity.z = normalSpeed * restitution
        let slip = SIMD2(ball.velocity.x - radius * ball.spin.y, ball.velocity.y + radius * ball.spin.x)
        let slipSpeed = simd_length(slip)
        guard slipSpeed > 0 else { return }
        let sliding = friction * (1 + restitution) * normalSpeed
        let change = sliding < rollingShare * slipSpeed ? -slip / slipSpeed * sliding : -slip * rollingShare
        ball.velocity.x += change.x
        ball.velocity.y += change.y
        ball.spin.x += 1.5 / radius * change.y
        ball.spin.y -= 1.5 / radius * change.x
    }
}
