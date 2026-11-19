public enum Stroke: String, CaseIterable, Sendable {
    case forehand
    case backhand
}

public enum SwingStrength: String, CaseIterable, Sendable {
    case soft
    case medium
    case hard
}

public enum NonSwingActivity: String, CaseIterable, Sendable {
    case walking
    case pickUpPutDown = "pickup-putdown"
    case typing
    case handOver = "hand-over"
    case wavingWhileTalking = "waving"
}

public enum Activity: Hashable, Sendable {
    case swings(Stroke, SwingStrength)
    case nonSwing(NonSwingActivity)
    case still

    public static let all: [Activity] =
        Stroke.allCases.flatMap { stroke in SwingStrength.allCases.map { .swings(stroke, $0) } }
        + NonSwingActivity.allCases.map(Activity.nonSwing)
        + [.still]

    public var code: String {
        switch self {
        case .swings(let stroke, let strength): "\(stroke.rawValue)-\(strength.rawValue)"
        case .nonSwing(let activity): activity.rawValue
        case .still: "still"
        }
    }

    public init?(code: String) {
        guard let match = Self.all.first(where: { $0.code == code }) else { return nil }
        self = match
    }

    public var isSwings: Bool {
        if case .swings = self { return true }
        return false
    }
}

public struct RecordedFrame: Equatable, Sendable {
    public let motion: MotionSample
    public let swing: Int?

    public init(motion: MotionSample, swing: Int?) {
        self.motion = motion
        self.swing = swing
    }
}

public struct Recording: Equatable, Sendable {
    public static let participants = 1...3

    public let activity: Activity
    public let participant: Int
    public let frames: [RecordedFrame]

    public init(activity: Activity, participant: Int, frames: [RecordedFrame]) {
        self.activity = activity
        self.participant = participant
        self.frames = frames
    }
}

public struct RecordingBuilder: Sendable {
    private struct SwingPress: Sendable {
        let start: Microseconds
        var end: Microseconds?
    }

    public let activity: Activity
    public let participant: Int
    public private(set) var samples: [MotionSample] = []
    private var presses: [SwingPress] = []

    public init(activity: Activity, participant: Int) {
        self.activity = activity
        self.participant = participant
    }

    public var swingCount: Int {
        presses.count
    }

    public var isSwinging: Bool {
        presses.last.map { $0.end == nil } ?? false
    }

    public var recording: Recording {
        var pressIndex = 0
        let frames = samples.map { motion in
            while pressIndex < presses.count, let end = presses[pressIndex].end, end <= motion.time {
                pressIndex += 1
            }
            let isInsidePress = pressIndex < presses.count && presses[pressIndex].start <= motion.time
            return RecordedFrame(motion: motion, swing: isInsidePress ? pressIndex + 1 : nil)
        }
        return Recording(activity: activity, participant: participant, frames: frames)
    }

    public mutating func beginSwing(at time: Microseconds) {
        presses.append(SwingPress(start: time))
    }

    public mutating func endSwing(at time: Microseconds) {
        presses[presses.count - 1].end = time
    }

    public mutating func record(_ motion: MotionSample) {
        samples.append(motion)
    }
}
