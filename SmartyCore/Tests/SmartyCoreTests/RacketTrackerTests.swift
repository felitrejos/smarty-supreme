import SmartyCore
import simd
import Testing

struct RacketTrackerTests {
    private static let heldUpright = simd_quatd(simd_double3x3(columns: (SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(-1, 0, 0))))

    @Test func theBackOfAPhoneHeldUprightFacesTheTableAfterCalibrating() {
        var tracker = RacketTracker(calibratedAt: Self.heldUpright)

        let pose = tracker.update(sample(attitude: Self.heldUpright))

        #expect(simd_distance(pose.orientation.act(SIMD3(0, 0, 1)), SIMD3(0, 1, 0)) < 1e-9)
        #expect(simd_distance(pose.orientation.act(SIMD3(0, 1, 0)), SIMD3(0, 0, 1)) < 1e-9)
        #expect(ArmModel.stance(of: pose.orientation) == .forehand)
    }

    @Test func aForehandTurnAboutTheVerticalSwingsTheBladeForward() {
        var tracker = RacketTracker(calibratedAt: Self.heldUpright)

        let pose = tracker.update(sample(attitude: Self.heldUpright, rotationRate: SIMD3(0, 10, 0)))

        #expect(pose.bladeVelocity(.right).y > 2)
    }

    @Test func aLeftHandersForehandTurnsTheOtherWayAndStillSwingsForward() {
        var tracker = RacketTracker(calibratedAt: Self.heldUpright)

        let pose = tracker.update(sample(attitude: Self.heldUpright, rotationRate: SIMD3(0, -10, 0)))

        #expect(pose.bladeVelocity(.left).y > 2)
        #expect(pose.bladeVelocity(.right).y < 0)
    }

    @Test func pushingThePhoneForwardDrivesTheHandAndTheBlade() {
        var tracker = RacketTracker(calibratedAt: Self.heldUpright)
        var pose = tracker.update(sample(attitude: Self.heldUpright))
        for step in 1...15 {
            pose = tracker.update(sample(attitude: Self.heldUpright, at: 1_000_000 + Microseconds(step) * 10_000, push: 2))
        }

        #expect(pose.linearVelocity.y > 1.5)
        #expect(pose.reach.y > 0.1)
        #expect(pose.bladeVelocity(.right).y > 1.5)
    }

    @Test func holdingStillStopsTheDriveFromDrifting() {
        var tracker = RacketTracker(calibratedAt: Self.heldUpright)
        var time: Microseconds = 1_000_000
        for _ in 1...15 {
            time += 10_000
            _ = tracker.update(sample(attitude: Self.heldUpright, at: time, push: 2))
        }
        var pose = tracker.update(sample(attitude: Self.heldUpright, at: time))
        for _ in 1...100 {
            time += 10_000
            pose = tracker.update(sample(attitude: Self.heldUpright, at: time))
        }

        #expect(simd_length(pose.linearVelocity) < 1e-9)
        #expect(simd_length(pose.reach) < 0.02)
    }

    @Test func turningTheBackFaceAwayFromTheTableIsABackhand() {
        var tracker = RacketTracker(calibratedAt: Self.heldUpright)
        let turned = simd_quatd(angle: .pi, axis: SIMD3(0, 0, 1)) * Self.heldUpright

        #expect(ArmModel.stance(of: tracker.update(sample(attitude: turned)).orientation) == .backhand)
    }

    private func sample(attitude: simd_quatd, at time: Microseconds = 1_000_000, rotationRate: SIMD3<Double> = .zero, push: Double = 0) -> MotionSample {
        let towardTheMac = attitude.inverse.act(SIMD3(1, 0, 0))
        return MotionSample(
            time: time,
            userAcceleration: towardTheMac * push,
            rotationRate: rotationRate,
            attitude: attitude,
            gravity: attitude.inverse.act(SIMD3(0, 0, -1))
        )
    }
}
