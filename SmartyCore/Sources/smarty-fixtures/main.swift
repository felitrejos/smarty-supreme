import FixtureTools
import SmartyCore
import Foundation

let usage = """
    Usage:
      smarty-fixtures summary <recordings folder>
      smarty-fixtures split <recordings folder> <output folder>
    """

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case "summary" where arguments.count == 2:
        let recordings = try loadRecordings(in: URL(filePath: arguments[1]))
        print(report(for: DatasetSummary(recordings: recordings.map(\.recording))))
    case "split" where arguments.count == 3:
        try split(URL(filePath: arguments[1]), into: URL(filePath: arguments[2]))
    default:
        print(usage)
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

struct LoadedRecording {
    let name: String
    let recording: Recording
}

struct FixtureFileError: Error, CustomStringConvertible {
    let description: String
}

func loadRecordings(in folder: URL) throws -> [LoadedRecording] {
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "csv" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return try files.map { file in
        do {
            let recording = try RecordingCSV.decode(String(contentsOf: file, encoding: .utf8))
            return LoadedRecording(name: file.lastPathComponent, recording: recording)
        } catch {
            throw FixtureFileError(description: "\(file.lastPathComponent): \(error)")
        }
    }
}

func split(_ recordingsFolder: URL, into outputFolder: URL) throws {
    let tuningFolder = outputFolder.appending(path: "tuning")
    let holdoutFolder = outputFolder.appending(path: "holdout")
    for folder in [tuningFolder, holdoutFolder] where FileManager.default.fileExists(atPath: folder.path()) {
        throw FixtureFileError(description: "\(folder.path()) already exists. The split is done once; delete it to redo it.")
    }
    let recordings = try loadRecordings(in: recordingsFolder)
    let splits = try recordings.map { loaded in
        do {
            return (loaded.name, try DatasetSplit.split(loaded.recording))
        } catch {
            throw FixtureFileError(description: "\(loaded.name): \(error)")
        }
    }
    try FileManager.default.createDirectory(at: tuningFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: holdoutFolder, withIntermediateDirectories: true)
    for (name, split) in splits {
        try RecordingCSV.encode(split.tuning).write(to: tuningFolder.appending(path: name), atomically: true, encoding: .utf8)
        try RecordingCSV.encode(split.holdout).write(to: holdoutFolder.appending(path: name), atomically: true, encoding: .utf8)
    }
    print("Split \(splits.count) recordings into \(tuningFolder.path()) and \(holdoutFolder.path())")
}

func report(for summary: DatasetSummary) -> String {
    var lines = ["Swings (target \(DatasetSummary.swingsPerCell) per cell)"]
    lines.append("  " + "".padding(toLength: 14, withPad: " ", startingAt: 0)
        + SwingStrength.allCases.map { $0.rawValue.leftPadded(to: 8) }.joined())
    for participant in Recording.participants {
        for stroke in Stroke.allCases {
            let label = "P\(participant) \(stroke.rawValue)".padding(toLength: 14, withPad: " ", startingAt: 0)
            let counts = SwingStrength.allCases.map { strength in
                let cell = SwingCell(participant: participant, stroke: stroke, strength: strength)
                return String(summary.swings[cell, default: 0]).leftPadded(to: 8)
            }
            lines.append("  " + label + counts.joined())
        }
    }
    lines.append("")
    lines.append("Not swings (target \(minutesAndSeconds(DatasetSummary.nonSwingTimePerActivity)) each)")
    for activity in NonSwingActivity.allCases {
        let time = minutesAndSeconds(summary.nonSwingTime[activity, default: 0])
        lines.append("  " + activity.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0) + time.leftPadded(to: 6))
    }
    lines.append("")
    lines.append("Still (target \(minutesAndSeconds(DatasetSummary.stillTarget)))  \(minutesAndSeconds(summary.stillTime))")
    lines.append("")
    let shortfalls = summary.shortfalls
    lines.append(shortfalls.isEmpty ? "Complete: yes" : "Complete: no, \(shortfalls.count) targets short")
    lines.append(contentsOf: shortfalls.map { "  " + describe($0) })
    return lines.joined(separator: "\n")
}

func describe(_ shortfall: Shortfall) -> String {
    switch shortfall {
    case .swings(let cell, let have):
        "P\(cell.participant) \(cell.stroke.rawValue) \(cell.strength.rawValue): \(have) of \(DatasetSummary.swingsPerCell) swings"
    case .nonSwing(let activity, let have):
        "\(activity.rawValue): \(minutesAndSeconds(have)) of \(minutesAndSeconds(DatasetSummary.nonSwingTimePerActivity))"
    case .still(let have):
        "still: \(minutesAndSeconds(have)) of \(minutesAndSeconds(DatasetSummary.stillTarget))"
    }
}

func minutesAndSeconds(_ time: Microseconds) -> String {
    let seconds = Int(time / 1_000_000)
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

extension String {
    func leftPadded(to width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }
}
