import SmartyCore
import simd

struct MotionSignal {
    static let interval: Microseconds = 10_000
    static let upright = SIMD3<Double>(0, -1, 0)
    static let flat = SIMD3<Double>(0, 0, -1)

    private(set) var samples: [MotionSample] = []
    var gravity = upright
    var attitude = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    private var time: Microseconds = 0

    var now: Microseconds {
        time
    }

    mutating func hold(for duration: Microseconds, acceleration: Double = 0, rotation: Double = 0) {
        for _ in 0..<(duration / Self.interval) {
            append(userAcceleration: SIMD3(0, 0, acceleration), rotation: rotation)
        }
    }

    mutating func halfSine(peak: Double, lasting duration: Microseconds, rotation: Double) {
        let start = time
        while time - start < duration {
            let phase = Double(time - start) / Double(duration)
            append(userAcceleration: SIMD3(0, 0, peak * sin(.pi * phase)), rotation: rotation)
        }
    }

    mutating func freeFall(for duration: Microseconds) {
        for _ in 0..<(duration / Self.interval) {
            append(userAcceleration: -gravity, rotation: 0)
        }
    }

    mutating func tilt(rollDegrees: Double, for duration: Microseconds, noise: (() -> Double)? = nil) {
        for _ in 0..<(duration / Self.interval) {
            let roll = (rollDegrees + (noise?() ?? 0)) * .pi / 180
            gravity = SIMD3(sin(roll), -cos(roll), 0)
            append(userAcceleration: .zero, rotation: 0)
        }
    }

    private mutating func append(userAcceleration: SIMD3<Double>, rotation: Double) {
        samples.append(MotionSample(
            time: time,
            userAcceleration: userAcceleration,
            rotationRate: SIMD3(rotation, 0, 0),
            attitude: attitude,
            gravity: gravity
        ))
        time += Self.interval
    }
}
