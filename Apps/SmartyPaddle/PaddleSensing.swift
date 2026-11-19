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
    }

    struct Snapshot {
        let calibration: CalibrationStatus
        let touchPosition: Double?
        let swings: Int
        let lastSwing: SwingEvent?
        let sensorError: String?
    }

    private struct State {
        var calibration = CalibrationStatus.needed
        var calibrator: Calibrator?
        var tracker: RacketTracker?
        var detector = SwingDetector()
        var touchPosition: Double?
        var swings = 0
        var lastSwing: SwingEvent?
        var sensorError: String?
    }

    private let state = Mutex(State())

    var snapshot: Snapshot {
        state.withLock { state in
            Snapshot(
                calibration: state.calibration,
                touchPosition: state.touchPosition,
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
                outcome.pose = tracker.update(sample)
                state.tracker = tracker
            }
            return outcome
        }
    }

    func reportSensorError(_ error: Error) {
        state.withLock { $0.sensorError = error.localizedDescription }
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
