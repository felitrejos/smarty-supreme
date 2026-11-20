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
    private static let landingTolerance = 0.05
    private static let slowestStroke = 3.0
    private static let strokeSpeedStep = 1.0
    private static let strokeRefinement = 8
    private static let strokeDepth = 0.45...0.9
    private static let strokeShortening = 0.25
    private static let strokePaceLoss = 0.35
    private static let strokePull = 0.9
    private static let strokeWidest = 2.2
    private static let strokeSpin = 15.0
    private static let strokeLiftSpin = 30.0
    private static let nailedPace = 3.0
    private static let nailedSpin = 12.0
    private static let flattestStroke = 3.0 * .pi / 180
    private static let steepestStroke = -25.0 * .pi / 180
    private static let mishitLoft = 12.0 * .pi / 180

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

    static func serve(from position: SIMD3<Double>, by side: Side, plan: Plan, spin chosen: SIMD3<Double>? = nil, config: GameConfig) -> Ball {
        let half = config.tableLength / 2
        let target = SIMD2(
            config.tableWidth / 2 + lateral(plan, config: config) * config.lateralSpan * config.tableWidth / 2,
            half + side.forward * (config.serveDepth + config.targetDepthPerStrength * plan.strength) * half
        )
        let heading = direction(from: position, to: target)
        let angle = config.serveAngleDegrees * .pi / 180
        let spin = chosen ?? simd_cross(SIMD3(0, 0, 1), SIMD3(heading.x, heading.y, 0)) * 2 * .pi * config.serveSpin
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

    // A phone stroke: what the phone measures well (swing speed, face angle, brush up or down, timing) sets
    // where the ball goes, how fast and with what spin; the flight is then solved to get there.
    struct Stroke {
        let power: Double
        let aim: Double
        let lift: Double
        let error: Double
        let pull: Double
        let overhead: Double
    }

    static func stroke(_ incoming: Ball, by side: Side, _ stroke: Stroke, config: GameConfig) -> Ball {
        let half = config.tableLength / 2
        let miss = abs(stroke.error)
        let lateral = min(max(stroke.aim + stroke.pull * stroke.error * strokePull, -strokeWidest), strokeWidest)
        let depth = min(max(strokeDepth.lowerBound + (strokeDepth.upperBound - strokeDepth.lowerBound) * stroke.power - strokeShortening * miss, safeDepth.lowerBound), safeDepth.upperBound)
        let target = SIMD2(config.tableWidth / 2 + lateral * config.lateralSpan * config.tableWidth / 2, half + side.forward * depth * half)
        // A hard swing timed right gets extra pace and topspin to dip it in: the reward for nailing it.
        let nailed = stroke.power * (1 - miss) * (1 - miss)
        let pace = slowestStroke + (config.fastestShot - slowestStroke) * stroke.power * (1 - strokePaceLoss * miss) + nailedPace * nailed
        let topspin = 2 * .pi * (strokeSpin + strokeLiftSpin * stroke.lift + nailedSpin * nailed)
        let flattest = flattestStroke + (steepestStroke - flattestStroke) * stroke.overhead + mishitLoft * miss
        func shot(_ speed: Double) -> Ball {
            aimed(from: incoming.position, toward: target, speed: speed, topspin: topspin, config: config)
        }
        func lands(_ speed: Double, rising: Bool = false) -> Bool {
            let ball = shot(speed)
            guard !rising || asin(ball.velocity.z / ball.speed) >= flattest else { return false }
            let flight = freeFlight(of: ball, config: config)
            return flight.clearsNet && simd_distance(flight.landing, target) < landingTolerance
        }
        func fits(_ speed: Double) -> Bool {
            lands(speed, rising: true)
        }
        if fits(pace) {
            return shot(pace)
        }
        // The pace the swing asked for can't make it: take the workable speed closest to it, slower or faster.
        let speeds = Array(stride(from: slowestStroke, through: config.fastestBall, by: strokeSpeedStep))
        let workable = speeds.filter(fits)
        guard var inside = workable.min(by: { abs($0 - pace) < abs($1 - pace) }) else {
            return shot(speeds.filter { lands($0) }.min { abs($0 - pace) < abs($1 - pace) } ?? pace)
        }
        var outside = pace
        for _ in 0..<strokeRefinement {
            let middle = (inside + outside) / 2
            if fits(middle) {
                inside = middle
            } else {
                outside = middle
            }
        }
        return shot(inside)
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

    static func freeFlight(of start: Ball, config: GameConfig) -> (landing: SIMD2<Double>, clearsNet: Bool) {
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
