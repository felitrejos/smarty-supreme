import FlickCore

public struct SplitRecording: Equatable, Sendable {
    public let tuning: Recording
    public let holdout: Recording
}

public enum RecordingSplitError: Error, Equatable {
    case noGapToCutAt
}

public enum DatasetSplit {
    private static let tuningShare = 0.7

    public static func split(_ recording: Recording) throws(RecordingSplitError) -> SplitRecording {
        let frames = recording.frames
        let start = frames[0].motion.time
        let duration = frames[frames.count - 1].motion.time - start
        let cutTime = start + Microseconds((Double(duration) * tuningShare).rounded())

        func distanceFromCut(_ index: Int) -> Microseconds {
            let time = frames[index].motion.time
            return time > cutTime ? time - cutTime : cutTime - time
        }

        let gaps = frames.indices.dropFirst().filter { frames[$0].swing == nil }
        guard let cut = gaps.min(by: { (distanceFromCut($0), $0) < (distanceFromCut($1), $1) }) else {
            throw .noGapToCutAt
        }
        return SplitRecording(
            tuning: Recording(activity: recording.activity, participant: recording.participant, frames: Array(frames[..<cut])),
            holdout: Recording(activity: recording.activity, participant: recording.participant, frames: Array(frames[cut...]))
        )
    }
}
