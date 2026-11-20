import Foundation
import simd

public struct RacketPose: Equatable, Sendable {
    public let orientation: simd_quatd
    public let angularVelocity: SIMD3<Double>
    public let linearVelocity: SIMD3<Double>
    public let reach: SIMD3<Double>

    public func bladeVelocity(_ handedness: Handedness) -> SIMD3<Double> {
        ArmModel.bladeVelocity(angularVelocity, linearVelocity: linearVelocity, orientation: orientation, stance: ArmModel.stance(of: orientation), handedness: handedness)
    }
}

public struct RacketTracker: Sendable {
    private static let backIsForehand = simd_quatd(angle: .pi, axis: SIMD3(0, 1, 0))
    private static let gravity = 9.81
    private static let speedMemory = 0.3
    private static let reachMemory = 0.3
    private static let longestReach = 0.35
    private static let stillAcceleration = 0.5
    private static let stillRotation = 1.0
    private static let stillFor: Microseconds = 60_000
    private static let longestGap = 0.1

    private let heading: simd_quatd
    private var velocity = SIMD3<Double>.zero
    private var reach = SIMD3<Double>.zero
    private var lastSampleAt: Microseconds?
    private var stillSince: Microseconds?

    public init(calibratedAt attitude: simd_quatd) {
        let forehand = attitude.act(SIMD3(0, 0, -1))
        let facing = atan2(forehand.y, forehand.x)
        heading = simd_quatd(angle: .pi / 2 - facing, axis: SIMD3(0, 0, 1))
    }

    public mutating func update(_ sample: MotionSample) -> RacketPose {
        let orientation = heading * sample.attitude
        let spin = orientation.act(sample.rotationRate)
        let acceleration = orientation.act(sample.userAcceleration) * Self.gravity
        let seconds = lastSampleAt.map { sample.time > $0 ? Double(sample.time - $0) / 1_000_000 : 0 } ?? 0
        lastSampleAt = sample.time
        if simd_length(acceleration) < Self.stillAcceleration, simd_length(spin) < Self.stillRotation {
            stillSince = stillSince ?? sample.time
        } else {
            stillSince = nil
        }
        if let stillSince, sample.time - stillSince >= Self.stillFor {
            velocity = .zero
        } else if seconds > 0, seconds < Self.longestGap {
            velocity = velocity * exp(-seconds / Self.speedMemory) + acceleration * seconds
        }
        if seconds > 0, seconds < Self.longestGap {
            reach = reach * exp(-seconds / Self.reachMemory) + velocity * seconds
            if simd_length(reach) > Self.longestReach {
                reach *= Self.longestReach / simd_length(reach)
            }
        }
        return RacketPose(orientation: orientation * Self.backIsForehand, angularVelocity: spin, linearVelocity: velocity, reach: reach)
    }
}
