import Foundation
import simd

public struct RacketPose: Equatable, Sendable {
    public let orientation: simd_quatd
    public let velocity: SIMD3<Double>
}

public struct RacketTracker: Sendable {
    public static let bladeReach = 0.25
    private static let gravity = 9.81
    private static let linearMemory = 0.15
    private static let backIsForehand = simd_quatd(angle: .pi, axis: SIMD3(0, 1, 0))

    private let heading: simd_quatd
    private var linear = SIMD3<Double>.zero
    private var lastSampleAt: Microseconds?

    public init(calibratedAt attitude: simd_quatd) {
        let forehand = attitude.act(SIMD3(0, 0, -1))
        let facing = atan2(forehand.y, forehand.x)
        heading = simd_quatd(angle: .pi / 2 - facing, axis: SIMD3(0, 0, 1))
    }

    public mutating func update(_ sample: MotionSample) -> RacketPose {
        let orientation = heading * sample.attitude
        let seconds = lastSampleAt.map { sample.time > $0 ? Double(sample.time - $0) / 1_000_000 : 0 } ?? 0
        lastSampleAt = sample.time
        if seconds > 0, seconds < 0.1 {
            linear = linear * exp(-seconds / Self.linearMemory) + orientation.act(sample.userAcceleration) * Self.gravity * seconds
        }
        let spin = orientation.act(sample.rotationRate)
        let blade = orientation.act(SIMD3(0, Self.bladeReach, 0))
        return RacketPose(orientation: orientation * Self.backIsForehand, velocity: simd_cross(spin, blade) + linear)
    }
}
