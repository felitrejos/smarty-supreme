import SmartyCore
import Synchronization

final class PaddleSensing: Sendable {
    enum CalibrationStatus: Equatable {
        case needed
        case inProgress
        case calibrated
        case failed(CalibrationFailure)
    }

    struct Outcome {
        var pose: RacketPose?
        var didCalibrate = false
        var contact: Contact?
    }

    struct Contact {
        let strength: Double
        let isClean: Bool
    }

    struct Snapshot {
        let calibration: CalibrationStatus
        let touchPosition: Double?
        let handedness: Handedness
        let swings: Int
        let lastSwing: SwingEvent?
        let sensorError: String?
    }

    private struct State {
        var calibration = CalibrationStatus.needed
        var calibrator: Calibrator?
        var tracker: RacketTracker?
        var expectedContact: Microseconds?
        var swingPeak = 0.0
        var swingPeakAt: Microseconds = 0
        var swingLow = Double.infinity
        var detector = SwingDetector()
        var touchPosition: Double?
        var handedness = Handedness.right
        var swings = 0
        var lastSwing: SwingEvent?
        var sensorError: String?
    }

    // The buzz judges a swing with the engine's own settings, so the phone and the Mac agree on a hit.
    private static let engine = GameConfig()
    private static let earlySwing = Microseconds(engine.earlySwing * 1_000_000)
    private static let lateSwing = Microseconds(engine.lateSwing * 1_000_000)
    private static let cleanTiming = Microseconds(engine.cleanTiming * 1_000_000)
    private static let swingThreshold = engine.swingThreshold
    private static let peakFalloff = engine.peakFalloff
    private static let fullSwing = engine.fullSwingSpeed
    private static let riseFrom = engine.swingRiseFrom
    private static let riseLookback = Microseconds(engine.swingRiseLookback * 1_000_000)

    private let state = Mutex(State())

    var snapshot: Snapshot {
        state.withLock { state in
            Snapshot(
                calibration: state.calibration,
                touchPosition: state.touchPosition,
                handedness: state.handedness,
                swings: state.swings,
                lastSwing: state.lastSwing,
                sensorError: state.sensorError
            )
        }
    }

    func calibrate() {
        state.withLock { state in
            state.calibrator = Calibrator()
            state.calibration = .inProgress
        }
    }

    var position: Double? {
        state.withLock { state in
            state.touchPosition
        }
    }

    func recordTouchSwing(_ swing: SwingEvent) {
        state.withLock { state in
            state.swings += 1
            state.lastSwing = swing
        }
    }

    func setTouchPosition(_ position: Double) {
        state.withLock { $0.touchPosition = position }
    }

    func process(_ sample: MotionSample) -> Outcome {
        state.withLock { state in
            var outcome = Outcome()
            switch state.detector.process(sample) {
            case .swing(let swing):
                state.swings += 1
                state.lastSwing = swing
            case .drop, nil:
                break
            }
            if var calibrator = state.calibrator {
                if let result = calibrator.add(sample) {
                    finishCalibration(result, at: sample, in: &state)
                    if case .calibrated = result {
                        outcome.didCalibrate = true
                    }
                } else {
                    state.calibrator = calibrator
                }
            }
            if var tracker = state.tracker {
                let pose = tracker.update(sample)
                state.tracker = tracker
                outcome.pose = pose
                outcome.contact = feelContact(forward: max(pose.bladeVelocity(state.handedness).y, 0), at: sample.time, in: &state)
            }
            return outcome
        }
    }

    func setHandedness(_ handedness: Handedness) {
        state.withLock { $0.handedness = handedness }
    }

    func expectContact(at time: Microseconds) {
        state.withLock { state in
            state.expectedContact = time
            state.swingPeak = 0
            state.swingLow = .infinity
        }
    }

    func reportSensorError(_ error: Error) {
        state.withLock { $0.sensorError = error.localizedDescription }
    }

    private func feelContact(forward: Double, at time: Microseconds, in state: inout State) -> Contact? {
        guard let contact = state.expectedContact else { return nil }
        if time > contact + Self.lateSwing {
            state.expectedContact = nil
            return nil
        }
        guard time + Self.earlySwing >= contact else {
            // Like the Mac, a swing may start climbing a little before the window opens.
            if time + Self.earlySwing + Self.riseLookback >= contact {
                state.swingLow = min(state.swingLow, forward)
            }
            return nil
        }
        if state.swingLow == .infinity {
            state.swingLow = forward
        }
        if forward > state.swingPeak {
            state.swingPeak = forward
            state.swingPeakAt = time
            return nil
        }
        guard state.swingPeak >= Self.swingThreshold, forward < state.swingPeak * Self.peakFalloff else {
            state.swingLow = min(state.swingLow, forward)
            return nil
        }
        // Like the Mac, only a swing that climbed from below half its peak is a stroke; otherwise start over from here.
        guard state.swingLow < state.swingPeak * Self.riseFrom else {
            state.swingPeak = forward
            state.swingLow = forward
            return nil
        }
        state.expectedContact = nil
        let offset = state.swingPeakAt > contact ? state.swingPeakAt - contact : contact - state.swingPeakAt
        return Contact(strength: min(state.swingPeak / Self.fullSwing, 1), isClean: offset <= Self.cleanTiming)
    }

    private func finishCalibration(_ result: CalibrationResult, at sample: MotionSample, in state: inout State) {
        state.calibrator = nil
        switch result {
        case .calibrated:
            state.tracker = RacketTracker(calibratedAt: sample.attitude)
            state.calibration = .calibrated
        case .failed(let failure):
            state.calibration = .failed(failure)
        }
    }
}
