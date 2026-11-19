import FlickCore
import Synchronization

final class PaddleSensing: Sendable {
    enum CalibrationStatus: Equatable {
        case needed
        case inProgress
        case calibrated
        case failed(CalibrationFailure)
    }

    struct Outcome {
        var swing: SwingEvent?
        var calibratedWith: Sensitivity?
    }

    struct Snapshot {
        let sensitivity: Sensitivity
        let calibration: CalibrationStatus
        let reading: PointerReading?
        let swings: Int
        let lastSwing: SwingEvent?
        let lastDropAt: Microseconds?
        let latestSampleAt: Microseconds?
        let sensorError: String?
    }

    private struct State {
        var sensitivity = Sensitivity.low
        var calibration = CalibrationStatus.needed
        var calibrator: Calibrator?
        var mapper: PointerMapper?
        var detector = SwingDetector()
        var reading: PointerReading?
        var swings = 0
        var lastSwing: SwingEvent?
        var lastDropAt: Microseconds?
        var latestSampleAt: Microseconds?
        var sensorError: String?
    }

    private let state = Mutex(State())

    var snapshot: Snapshot {
        state.withLock { state in
            Snapshot(
                sensitivity: state.sensitivity,
                calibration: state.calibration,
                reading: state.reading,
                swings: state.swings,
                lastSwing: state.lastSwing,
                lastDropAt: state.lastDropAt,
                latestSampleAt: state.latestSampleAt,
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
            guard case .position(let position) = state.reading else { return nil }
            return position
        }
    }

    func setSensitivity(_ sensitivity: Sensitivity) -> Bool {
        state.withLock { state in
            state.sensitivity = sensitivity
            guard let mapper = state.mapper else { return false }
            state.mapper = PointerMapper(neutralRollDegrees: mapper.neutralRollDegrees, sensitivity: sensitivity)
            return true
        }
    }

    func process(_ sample: MotionSample) -> Outcome {
        state.withLock { state in
            var outcome = Outcome()
            state.latestSampleAt = sample.time
            switch state.detector.process(sample) {
            case .swing(let swing):
                state.swings += 1
                state.lastSwing = swing
                outcome.swing = swing
            case .drop:
                state.lastDropAt = sample.time
            case nil:
                break
            }
            if var calibrator = state.calibrator {
                if let result = calibrator.add(sample) {
                    finishCalibration(result, in: &state)
                    if case .calibrated = result {
                        outcome.calibratedWith = state.sensitivity
                    }
                } else {
                    state.calibrator = calibrator
                }
            }
            if var mapper = state.mapper {
                state.reading = mapper.update(sample, holding: state.detector.isMidSwing)
                state.mapper = mapper
            }
            return outcome
        }
    }

    func reportSensorError(_ error: Error) {
        state.withLock { $0.sensorError = error.localizedDescription }
    }

    private func finishCalibration(_ result: CalibrationResult, in state: inout State) {
        state.calibrator = nil
        switch result {
        case .calibrated(let neutral):
            state.mapper = PointerMapper(neutralRollDegrees: neutral, sensitivity: state.sensitivity)
            state.calibration = .calibrated
        case .failed(let failure):
            state.calibration = .failed(failure)
        }
    }
}
