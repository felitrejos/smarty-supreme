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
    }

    @Test func turningThePhoneTurnsTheBatAndSwingingItMovesTheBlade() {
        var tracker = RacketTracker(calibratedAt: Self.heldUpright)
        let opened = simd_quatd(angle: -0.3, axis: SIMD3(0, 1, 0)) * Self.heldUpright

        let pose = tracker.update(sample(attitude: opened, rotationRate: SIMD3(-8, 0, 0)))

        #expect(pose.orientation.act(SIMD3(0, 0, 1)).z > 0.2)
        #expect(pose.velocity.y > 1)
    }

    private func sample(attitude: simd_quatd, rotationRate: SIMD3<Double> = .zero) -> MotionSample {
        MotionSample(time: 1_000_000, userAcceleration: .zero, rotationRate: rotationRate, attitude: attitude, gravity: attitude.inverse.act(SIMD3(0, 0, -1)))
    }
}
