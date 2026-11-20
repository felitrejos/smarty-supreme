import SmartyCore
import Testing

struct CalibratorTests {
    @Test func calibratesAfterHalfASecondHeldStillEvenIfTheTapJoltedThePhone() {
        var calibrator = Calibrator()
        var signal = MotionSignal()
        signal.tilt(rollDegrees: 25, for: 340_000)
        signal.tilt(rollDegrees: 4, for: 260_000)
        signal.tilt(rollDegrees: 6, for: 260_000)
        #expect(signal.samples.compactMap { calibrator.add($0) } == [.calibrated])
    }

    @Test func rejectsWhenRollVariesMoreThanThreeDegrees() {
        var calibrator = Calibrator()
        var signal = MotionSignal()
        signal.tilt(rollDegrees: 0, for: 600_000)
        signal.tilt(rollDegrees: 3.5, for: 260_000)
        #expect(signal.samples.compactMap { calibrator.add($0) } == [.failed(.handMoved)])
    }

    @Test func rejectsWhenThePhoneIsNotUpright() {
        var calibrator = Calibrator()
        var signal = MotionSignal()
        signal.gravity = MotionSignal.flat
        signal.hold(for: 860_000)
        #expect(signal.samples.compactMap { calibrator.add($0) } == [.failed(.notUpright)])
    }
}
