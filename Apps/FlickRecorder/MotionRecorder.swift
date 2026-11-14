import CoreMotion
import FlickCore
import simd

@MainActor
final class MotionRecorder {
    private static let sampleRate = 100.0

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()

    var isAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    func start(_ recording: LiveRecording) {
        manager.deviceMotionUpdateInterval = 1 / Self.sampleRate
        manager.startDeviceMotionUpdates(to: queue) { @Sendable motion, error in
            if let motion {
                recording.record(MotionSample(motion))
            } else if let error {
                recording.reportSensorError(error)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

private extension MotionSample {
    init(_ motion: CMDeviceMotion) {
        let quaternion = motion.attitude.quaternion
        self.init(
            time: microseconds(sinceBoot: motion.timestamp),
            userAcceleration: SIMD3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z),
            rotationRate: SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z),
            attitude: simd_quatd(ix: quaternion.x, iy: quaternion.y, iz: quaternion.z, r: quaternion.w),
            gravity: SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        )
    }
}
