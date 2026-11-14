import FlickCore
import simd

func makeRecording(
    activity: Activity,
    swings: [Int?],
    participant: Int = 1,
    frameInterval: Microseconds = 10_000
) -> Recording {
    let frames = swings.enumerated().map { index, swing in
        let motion = MotionSample(
            time: Microseconds(index) * frameInterval,
            userAcceleration: .zero,
            rotationRate: .zero,
            attitude: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1),
            gravity: SIMD3(0, -1, 0)
        )
        return RecordedFrame(motion: motion, swing: swing)
    }
    return Recording(activity: activity, participant: participant, frames: frames)
}

func shifted(_ motion: MotionSample, by offset: Microseconds) -> MotionSample {
    MotionSample(
        time: motion.time + offset,
        userAcceleration: motion.userAcceleration,
        rotationRate: motion.rotationRate,
        attitude: motion.attitude,
        gravity: motion.gravity
    )
}
