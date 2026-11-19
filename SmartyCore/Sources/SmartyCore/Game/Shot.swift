import simd

enum Shot {
    private static let solverStep = 1.0 / 480
    private static let longestFlight = 3.0
    private static let lowestAngle = -25.0 * .pi / 180
    private static let highestAngle = 50.0 * .pi / 180
    private static let solverRounds = 24
    private static let slowestServe = 1.5
    private static let fastestServe = 9.0
    private static let safeDepth = 0.2...0.92
    private static let safeEdge = 0.06

    struct Plan {
        let strength: Double
        let aim: Double
        let contact: Double
        let timing: Double
    }

    static func planned(_ incoming: Ball, by side: Side, plan: Plan, wander: Double, config: GameConfig) -> Ball {
        let error = max(0, (abs(plan.timing) - config.sweetSpot) / (1 - config.sweetSpot))
        let half = config.tableLength / 2
        var depth = half + side.forward * (config.targetDepth + config.targetDepthPerStrength * plan.strength) * half
        depth += side.forward * (plan.timing < 0 ? config.earlyLong : -config.lateShort) * error
        let across = config.tableWidth / 2 + lateral(plan, config: config) * config.lateralSpan * config.tableWidth / 2 + config.wideError * error * wander
        let speed = min(config.slowestShot + plan.strength * (config.fastestShot - config.slowestShot) + config.incomingCarry * incoming.speed, config.fastestBall)
        let spin = 2 * .pi * (config.slowestSpin + plan.strength * (config.fastestSpin - config.slowestSpin))
        return aimed(from: incoming.position, toward: SIMD2(across, depth), speed: speed, topspin: spin, config: config)
    }

    static func serve(from position: SIMD3<Double>, by side: Side, plan: Plan, config: GameConfig) -> Ball {
        let half = config.tableLength / 2
        let target = SIMD2(
            config.tableWidth / 2 + lateral(plan, config: config) * config.lateralSpan * config.tableWidth / 2,
            half + side.forward * (config.serveDepth + config.targetDepthPerStrength * plan.strength) * half
        )
        let heading = direction(from: position, to: target)
        let angle = config.serveAngleDegrees * .pi / 180
        let spin = simd_cross(SIMD3(0, 0, 1), SIMD3(heading.x, heading.y, 0)) * 2 * .pi * config.serveSpin
        let wanted = simd_distance(SIMD2(position.x, position.y), target)
        func ball(_ speed: Double) -> Ball {
            Ball(position: position, velocity: SIMD3(heading.x * cos(angle), heading.y * cos(angle), sin(angle)) * speed, spin: spin)
        }
        var low = slowestServe
        var high = fastestServe
        for _ in 0..<solverRounds {
            let speed = (low + high) / 2
            if secondBounceDistance(of: ball(speed), from: position, config: config) < wanted {
                low = speed
            } else {
                high = speed
            }
        }
        return ball((low + high) / 2)
    }

    static func racket(_ incoming: Ball, by side: Side, sample: RacketSample, config: GameConfig) -> Ball? {
        let turn = side == .playerA ? simd_quatd(ix: 0, iy: 0, iz: 0, r: 1) : simd_quatd(angle: .pi, axis: SIMD3(0, 0, 1))
        let racketVelocity = turn.act(sample.velocity)
        let forehand = (turn * sample.orientation).act(SIMD3(0, 0, 1))
        let relative = incoming.velocity - racketVelocity
        let normal = simd_dot(forehand, relative) < 0 ? forehand : -forehand
        let normalSpeed = simd_dot(relative, normal)
        guard normalSpeed < 0 else { return nil }
        let restitution = min(max(config.racketNormalRestitution - config.racketRestitutionPerSpeed * abs(normalSpeed), 0.5), 0.9)
        let tangential = relative - normalSpeed * normal
        let slip = tangential + simd_cross(incoming.spin, -config.ballRadius * normal)
        let change = -(1 + config.racketTangentialRestitution) / 2.5 * slip
        let spin = incoming.spin - 1.5 / config.ballRadius * simd_cross(normal, change)
        var velocity = racketVelocity - restitution * normalSpeed * normal + tangential + change
        velocity = assisted(velocity, spin: spin, from: incoming.position, by: side, config: config)
        if simd_length(velocity) > config.fastestBall {
            velocity *= config.fastestBall / simd_length(velocity)
        }
        return Ball(position: incoming.position, velocity: velocity, spin: spin)
    }

    private static func assisted(_ velocity: SIMD3<Double>, spin: SIMD3<Double>, from position: SIMD3<Double>, by side: Side, config: GameConfig) -> SIMD3<Double> {
        guard config.aimAssist > 0, velocity.y * side.forward > 0 else { return velocity }
        let flight = freeFlight(of: Ball(position: position, velocity: velocity, spin: spin), config: config)
        let half = config.tableLength / 2
        let depth = (flight.landing.y - half) * side.forward / half
        let clamped = SIMD2(
            min(max(flight.landing.x, safeEdge), config.tableWidth - safeEdge),
            half + side.forward * min(max(depth, safeDepth.lowerBound), safeDepth.upperBound) * half
        )
        guard clamped != flight.landing || !flight.clearsNet else { return velocity }
        let speed = simd_length(velocity)
        let topspin = simd_length(spin) * (simd_dot(spin, simd_cross(SIMD3(0, 0, 1), velocity)) >= 0 ? 1 : -1)
        let ideal = aimed(from: position, toward: clamped, speed: speed, topspin: topspin, config: config).velocity
        return simd_normalize(simd_mix(simd_normalize(velocity), simd_normalize(ideal), SIMD3(repeating: config.aimAssist))) * speed
    }

    private static func lateral(_ plan: Plan, config: GameConfig) -> Double {
        min(max(config.contactShare * plan.contact + (1 - config.contactShare) * plan.aim, -1), 1)
    }

    private static func aimed(from position: SIMD3<Double>, toward target: SIMD2<Double>, speed: Double, topspin: Double, config: GameConfig) -> Ball {
        let heading = direction(from: position, to: target)
        let spin = simd_cross(SIMD3(0, 0, 1), SIMD3(heading.x, heading.y, 0)) * topspin
        let wanted = simd_distance(SIMD2(position.x, position.y), target)
        func ball(_ angle: Double) -> Ball {
            Ball(position: position, velocity: SIMD3(heading.x * cos(angle), heading.y * cos(angle), sin(angle)) * speed, spin: spin)
        }
        var low = lowestAngle
        var high = highestAngle
        for _ in 0..<solverRounds {
            let angle = (low + high) / 2
            if simd_distance(freeFlight(of: ball(angle), config: config).landing, SIMD2(position.x, position.y)) < wanted {
                low = angle
            } else {
                high = angle
            }
        }
        var angle = (low + high) / 2
        if !freeFlight(of: ball(angle), config: config).clearsNet {
            var blocked = angle
            var clear = highestAngle
            for _ in 0..<solverRounds {
                let middle = (blocked + clear) / 2
                if freeFlight(of: ball(middle), config: config).clearsNet {
                    clear = middle
                } else {
                    blocked = middle
                }
            }
            angle = clear
        }
        return ball(angle)
    }

    private static func direction(from position: SIMD3<Double>, to target: SIMD2<Double>) -> SIMD2<Double> {
        simd_normalize(target - SIMD2(position.x, position.y))
    }

    private static func freeFlight(of start: Ball, config: GameConfig) -> (landing: SIMD2<Double>, clearsNet: Bool) {
        var ball = start
        var clearsNet = true
        let middle = config.tableLength / 2
        var elapsed = 0.0
        while elapsed < longestFlight {
            let before = ball
            BallPhysics.fly(&ball, seconds: solverStep, config: config)
            elapsed += solverStep
            if (before.position.y < middle) != (ball.position.y < middle), ball.position.z - config.ballRadius < config.netHeight + config.netClearance {
                clearsNet = false
            }
            if ball.velocity.z < 0, ball.position.z <= config.ballRadius {
                break
            }
        }
        return (SIMD2(ball.position.x, ball.position.y), clearsNet)
    }

    private static func secondBounceDistance(of start: Ball, from position: SIMD3<Double>, config: GameConfig) -> Double {
        var ball = start
        var bounces = 0
        var elapsed = 0.0
        while elapsed < longestFlight {
            let contact = BallPhysics.advance(&ball, seconds: solverStep, config: config)
            elapsed += solverStep
            switch contact {
            case .table:
                bounces += 1
                if bounces == 2 {
                    return simd_distance(SIMD2(ball.position.x, ball.position.y), SIMD2(position.x, position.y))
                }
            case .floor:
                return bounces == 1 ? .infinity : 0
            case .net, nil:
                break
            }
        }
        return 0
    }
}
