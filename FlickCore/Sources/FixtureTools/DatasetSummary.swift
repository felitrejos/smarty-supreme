import FlickCore

public struct SwingCell: Hashable, Sendable {
    public let participant: Int
    public let stroke: Stroke
    public let strength: SwingStrength

    public init(participant: Int, stroke: Stroke, strength: SwingStrength) {
        self.participant = participant
        self.stroke = stroke
        self.strength = strength
    }

    public static let all = Recording.participants.flatMap { participant in
        Stroke.allCases.flatMap { stroke in
            SwingStrength.allCases.map { SwingCell(participant: participant, stroke: stroke, strength: $0) }
        }
    }
}

public enum Shortfall: Equatable, Sendable {
    case swings(SwingCell, have: Int)
    case nonSwing(NonSwingActivity, have: Microseconds)
    case still(have: Microseconds)
}

public struct DatasetSummary: Sendable {
    public static let swingsPerCell = 17
    public static let nonSwingTimePerActivity: Microseconds = 180_000_000
    public static let stillTarget: Microseconds = 180_000_000

    public private(set) var swings: [SwingCell: Int] = [:]
    public private(set) var nonSwingTime: [NonSwingActivity: Microseconds] = [:]
    public private(set) var stillTime: Microseconds = 0

    public init(recordings: [Recording]) {
        for recording in recordings {
            switch recording.activity {
            case .swings(let stroke, let strength):
                let cell = SwingCell(participant: recording.participant, stroke: stroke, strength: strength)
                swings[cell, default: 0] += Set(recording.frames.compactMap(\.swing)).count
            case .nonSwing(let activity):
                nonSwingTime[activity, default: 0] += duration(of: recording)
            case .still:
                stillTime += duration(of: recording)
            }
        }
    }

    public var shortfalls: [Shortfall] {
        let swingShortfalls = SwingCell.all.compactMap { cell -> Shortfall? in
            let have = swings[cell, default: 0]
            return have < Self.swingsPerCell ? .swings(cell, have: have) : nil
        }
        let nonSwingShortfalls = NonSwingActivity.allCases.compactMap { activity -> Shortfall? in
            let have = nonSwingTime[activity, default: 0]
            return have < Self.nonSwingTimePerActivity ? .nonSwing(activity, have: have) : nil
        }
        let stillShortfall: [Shortfall] = stillTime < Self.stillTarget ? [.still(have: stillTime)] : []
        return swingShortfalls + nonSwingShortfalls + stillShortfall
    }

    public var isComplete: Bool {
        shortfalls.isEmpty
    }
}

private func duration(of recording: Recording) -> Microseconds {
    recording.frames[recording.frames.count - 1].motion.time - recording.frames[0].motion.time
}
