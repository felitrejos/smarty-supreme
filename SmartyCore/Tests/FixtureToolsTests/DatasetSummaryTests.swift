import FixtureTools
import SmartyCore
import Testing

struct DatasetSummaryTests {
    @Test func countsDistinctSwingsPerParticipantStrokeAndStrength() {
        let first = makeRecording(activity: .swings(.forehand, .soft), swings: [nil, 1, 1, nil, 2, nil, 3])
        let second = makeRecording(activity: .swings(.forehand, .soft), swings: [1, nil, 2])
        let other = makeRecording(activity: .swings(.backhand, .soft), swings: [1], participant: 2)

        let summary = DatasetSummary(recordings: [first, second, other])

        #expect(summary.swings[SwingCell(participant: 1, stroke: .forehand, strength: .soft)] == 5)
        #expect(summary.swings[SwingCell(participant: 2, stroke: .backhand, strength: .soft)] == 1)
    }

    @Test func addsUpTimeForEachNonSwingActivityAndForStill() {
        let walking = makeRecording(activity: .nonSwing(.walking), swings: Array(repeating: nil, count: 101))
        let moreWalking = makeRecording(activity: .nonSwing(.walking), swings: Array(repeating: nil, count: 51))
        let still = makeRecording(activity: .still, swings: Array(repeating: nil, count: 11))

        let summary = DatasetSummary(recordings: [walking, moreWalking, still])

        #expect(summary.nonSwingTime[.walking] == 1_500_000)
        #expect(summary.stillTime == 100_000)
    }

    @Test func nothingIsShortOnlyWhenEveryTargetIsMet() {
        var recordings = completeDataset()
        #expect(DatasetSummary(recordings: recordings).shortfalls.isEmpty)

        recordings[0] = makeRecording(activity: .swings(.forehand, .soft), swings: (1...16).map { $0 })
        let summary = DatasetSummary(recordings: recordings)

        #expect(summary.shortfalls == [.swings(SwingCell(participant: 1, stroke: .forehand, strength: .soft), have: 16)])
    }

    @Test func listsMissingTimeForNonSwingActivitiesAndStill() {
        let recordings = completeDataset().filter { recording in
            recording.activity != .still && recording.activity != .nonSwing(.typing)
        }
        let summary = DatasetSummary(recordings: recordings)
        #expect(summary.shortfalls == [.nonSwing(.typing, have: 0), .still(have: 0)])
    }
}

private func completeDataset() -> [Recording] {
    let swingRecordings = Recording.participants.flatMap { participant in
        Activity.all.compactMap { activity -> Recording? in
            guard case .swings = activity else { return nil }
            return makeRecording(activity: activity, swings: (1...17).map { $0 }, participant: participant)
        }
    }
    let threeMinutes = Array<Int?>(repeating: nil, count: 2)
    let timedRecordings = Activity.all.compactMap { activity -> Recording? in
        if case .swings = activity { return nil }
        return makeRecording(activity: activity, swings: threeMinutes, frameInterval: 180_000_000)
    }
    return swingRecordings + timedRecordings
}
