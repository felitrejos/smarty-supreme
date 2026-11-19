import SmartyCore
import Foundation
import Synchronization

final class LiveRecording: Identifiable, Sendable {
    struct Progress {
        let swings: Int
        let frames: Int
        let duration: Microseconds
        let sensorError: String?
    }

    let id = UUID()
    let activity: Activity
    private let builder: Mutex<RecordingBuilder>
    private let sensorError = Mutex<String?>(nil)

    init(activity: Activity, participant: Int) {
        self.activity = activity
        builder = Mutex(RecordingBuilder(activity: activity, participant: participant))
    }

    var progress: Progress {
        let error = sensorError.withLock { $0 }
        return builder.withLock { builder in
            let samples = builder.samples
            let duration = samples.last.map { $0.time - samples[0].time } ?? 0
            return Progress(swings: builder.swingCount, frames: samples.count, duration: duration, sensorError: error)
        }
    }

    func record(_ motion: MotionSample) {
        builder.withLock { $0.record(motion) }
    }

    func beginSwing(at time: Microseconds) {
        builder.withLock { $0.beginSwing(at: time) }
    }

    func endSwing(at time: Microseconds) {
        builder.withLock { $0.endSwing(at: time) }
    }

    func finish(at time: Microseconds) -> Recording {
        builder.withLock { builder in
            if builder.isSwinging {
                builder.endSwing(at: time)
            }
            return builder.recording
        }
    }

    func reportSensorError(_ error: Error) {
        sensorError.withLock { $0 = error.localizedDescription }
    }
}
