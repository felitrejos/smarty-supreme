import FixtureTools
import FlickCore
import Testing

struct RecordingSplitTests {
    @Test func cutsAtSeventyPercentOfTheDuration() throws {
        let recording = makeRecording(activity: .still, swings: Array(repeating: nil, count: 101))
        let split = try DatasetSplit.split(recording)
        #expect(split.tuning.frames == Array(recording.frames[..<70]))
        #expect(split.holdout.frames == Array(recording.frames[70...]))
        #expect(split.holdout.activity == .still)
        #expect(split.holdout.participant == 1)
    }

    @Test func movesTheCutToTheNearestGapSoNoSwingIsCutInHalf() throws {
        var swings: [Int?] = Array(repeating: nil, count: 101)
        for index in 65..<75 {
            swings[index] = 4
        }
        let recording = makeRecording(activity: .swings(.forehand, .soft), swings: swings)
        let split = try DatasetSplit.split(recording)
        #expect(split.tuning.frames.count == 75)
        #expect(split.holdout.frames.allSatisfy { $0.swing == nil })
    }

    @Test func cutsByTimeEvenWhenFramesAreUnevenlySpaced() throws {
        let early = makeRecording(activity: .still, swings: Array(repeating: nil, count: 10)).frames
        let late = makeRecording(activity: .still, swings: Array(repeating: nil, count: 10)).frames.map { frame in
            RecordedFrame(motion: shifted(frame.motion, by: 1_000_000), swing: nil)
        }
        let recording = Recording(activity: .still, participant: 1, frames: early + late)
        let split = try DatasetSplit.split(recording)
        #expect(split.tuning.frames == early)
        #expect(split.holdout.frames == late)
    }

    @Test func failsWhenEveryFrameIsInsideASwing() {
        let recording = makeRecording(activity: .swings(.forehand, .soft), swings: Array(repeating: 1, count: 20))
        #expect(throws: RecordingSplitError.noGapToCutAt) {
            try DatasetSplit.split(recording)
        }
    }
}
