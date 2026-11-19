import SmartyCore
import Foundation
import Testing
import simd

@Suite(.enabled(if: HoldoutSet.isAvailable, "Record the dataset and run smarty-fixtures split to create Fixtures/holdout"))
struct SensingBenchmarkTests {
    @Test func swingDetectionRecallIsAtLeastNinetyFivePercentAndPrecisionNinetyEight() throws {
        let score = try HoldoutSet.recordings().reduce(into: DetectionScore()) { score, recording in
            score.add(recording)
        }
        print("Swing detection on held-out set: recall \(score.recall), precision \(score.precision), \(score.labelled) labelled swings, \(score.detected) detections")
        try #require(score.labelled > 0)
        #expect(score.recall >= 0.95)
        #expect(score.precision >= 0.98)
    }

    @Test func swingIsReportedWithinTwentyMillisecondsOfItsTruePeak() throws {
        let delays = try HoldoutSet.recordings().reduce(into: DetectionScore()) { score, recording in
            score.add(recording)
        }.delays.sorted()
        try #require(!delays.isEmpty)
        let p95 = delays[Int((Double(delays.count - 1) * 0.95).rounded())]
        print("Swing detection delay after the true peak on held-out set: p95 \(p95) µs over \(delays.count) swings")
        #expect(p95 <= 20_000)
    }

    @Test func pointerJitterAtRestIsUnderFourTenthsOfAPercentAtTheHighestSensitivity() throws {
        let stillRecordings = try HoldoutSet.recordings().filter { $0.activity == .still }
        try #require(!stillRecordings.isEmpty)
        let jitters = try stillRecordings.map { recording in
            var mapper = PointerMapper(neutralRollDegrees: recording.frames[0].motion.rollDegrees, sensitivity: .high)
            let positions = recording.frames.compactMap { frame -> Double? in
                guard case .position(let value) = mapper.update(frame.motion, holding: false) else { return nil }
                return value
            }.dropFirst(50)
            try #require(!positions.isEmpty, "A still recording has no upright frames")
            return rootMeanSquareDeviation(Array(positions))
        }
        let worst = jitters.max()!
        print("Pointer jitter at rest on held-out set: worst \(worst * 100)% of table width")
        #expect(worst <= 0.004)
    }
}

enum HoldoutSet {
    static let folder = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../../Fixtures/holdout")
        .standardized

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: folder.path())
    }

    static func recordings() throws -> [Recording] {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "csv" }
        return try files.map { try RecordingCSV.decode(String(contentsOf: $0, encoding: .utf8)) }
    }
}

struct DetectionScore {
    private static let labelMargin: Microseconds = 100_000

    private(set) var labelled = 0
    private(set) var matched = 0
    private(set) var detected = 0
    private(set) var delays: [Int64] = []

    var recall: Double {
        Double(matched) / Double(labelled)
    }

    var precision: Double {
        Double(matched) / Double(detected)
    }

    mutating func add(_ recording: Recording) {
        var windows = labelledSwings(in: recording)
        labelled += windows.count
        var detector = SwingDetector()
        for frame in recording.frames {
            guard case .swing(let swing) = detector.process(frame.motion) else { continue }
            detected += 1
            guard let index = windows.firstIndex(where: { $0.contains(swing.peakTime) }) else { continue }
            matched += 1
            delays.append(Int64(frame.motion.time) - Int64(windows[index].truePeak))
            windows.remove(at: index)
        }
    }

    private struct SwingWindow {
        let start: Microseconds
        let end: Microseconds
        let truePeak: Microseconds

        func contains(_ time: Microseconds) -> Bool {
            time + DetectionScore.labelMargin >= start && time <= end + DetectionScore.labelMargin
        }
    }

    private func labelledSwings(in recording: Recording) -> [SwingWindow] {
        Dictionary(grouping: recording.frames.filter { $0.swing != nil }, by: { $0.swing! })
            .values
            .map { frames in
                let peak = frames.max { simd_length($0.motion.userAcceleration) < simd_length($1.motion.userAcceleration) }!
                return SwingWindow(start: frames.first!.motion.time, end: frames.last!.motion.time, truePeak: peak.motion.time)
            }
            .sorted { $0.start < $1.start }
    }
}

private func rootMeanSquareDeviation(_ values: [Double]) -> Double {
    let mean = values.reduce(0, +) / Double(values.count)
    return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
}
