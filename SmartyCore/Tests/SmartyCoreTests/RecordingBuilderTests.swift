import SmartyCore
import Testing
import simd

struct RecordingBuilderTests {
    @Test func labelsFramesBySampleTimeWhateverOrderTheyArriveIn() {
        var builder = RecordingBuilder(activity: .swings(.backhand, .hard), participant: 3)
        builder.record(motion(at: 0))
        builder.record(motion(at: 20_000))
        builder.beginSwing(at: 15_000)
        builder.record(motion(at: 30_000))
        builder.endSwing(at: 35_000)
        builder.record(motion(at: 40_000))
        builder.beginSwing(at: 45_000)
        builder.record(motion(at: 50_000))
        builder.endSwing(at: 55_000)
        builder.record(motion(at: 60_000))

        let recording = builder.recording
        #expect(recording.frames.map(\.swing) == [nil, 1, 1, nil, 2, nil])
        #expect(recording.activity == .swings(.backhand, .hard))
        #expect(recording.participant == 3)
        #expect(builder.swingCount == 2)
    }

    @Test func aSwingThatIsStillOpenCoversEveryLaterFrame() {
        var builder = RecordingBuilder(activity: .swings(.forehand, .soft), participant: 1)
        builder.beginSwing(at: 5_000)
        builder.record(motion(at: 0))
        builder.record(motion(at: 10_000))
        builder.record(motion(at: 20_000))
        #expect(builder.isSwinging)
        #expect(builder.recording.frames.map(\.swing) == [nil, 1, 1])
    }
}

private func motion(at time: Microseconds) -> MotionSample {
    MotionSample(
        time: time,
        userAcceleration: .zero,
        rotationRate: .zero,
        attitude: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1),
        gravity: SIMD3(0, -1, 0)
    )
}
