import Foundation
import simd

public enum RecordingCSVError: Error, Equatable {
    case missingHeader
    case noFrames
    case wrongColumnCount(line: Int)
    case invalidValue(line: Int, column: String)
    case mixedSessions(line: Int)
    case timeNotIncreasing(line: Int)
}

public enum RecordingCSV {
    private static let columns = [
        "time_us",
        "acc_x", "acc_y", "acc_z",
        "rot_x", "rot_y", "rot_z",
        "att_x", "att_y", "att_z", "att_w",
        "grav_x", "grav_y", "grav_z",
        "activity", "participant", "swing",
    ]

    public static let header = columns.joined(separator: ",")

    public static func encode(_ recording: Recording) -> String {
        let session = [recording.activity.code, "p\(recording.participant)"]
        var lines = [header]
        lines.reserveCapacity(recording.frames.count + 1)
        for frame in recording.frames {
            let fields = ["\(frame.motion.time)"]
                + sensorValues(of: frame.motion).map { String(format: "%.6f", $0) }
                + session
                + [frame.swing.map(String.init) ?? ""]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func decode(_ text: String) throws(RecordingCSVError) -> Recording {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        guard lines.first == Substring(header) else { throw .missingHeader }
        guard lines.count > 1 else { throw .noFrames }

        var rows: [Row] = []
        rows.reserveCapacity(lines.count - 1)
        for (offset, line) in lines.dropFirst().enumerated() {
            let lineNumber = offset + 2
            let row = try Row(line, lineNumber: lineNumber)
            if let previous = rows.last {
                guard row.activity == previous.activity, row.participant == previous.participant else {
                    throw .mixedSessions(line: lineNumber)
                }
                guard row.frame.motion.time > previous.frame.motion.time else {
                    throw .timeNotIncreasing(line: lineNumber)
                }
            }
            rows.append(row)
        }
        return Recording(activity: rows[0].activity, participant: rows[0].participant, frames: rows.map(\.frame))
    }

    private static func sensorValues(of motion: MotionSample) -> [Double] {
        let attitude = motion.attitude.vector
        return [
            motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z,
            motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z,
            attitude.x, attitude.y, attitude.z, attitude.w,
            motion.gravity.x, motion.gravity.y, motion.gravity.z,
        ]
    }

    private struct Row {
        let frame: RecordedFrame
        let activity: Activity
        let participant: Int

        init(_ line: Substring, lineNumber: Int) throws(RecordingCSVError) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == columns.count else { throw .wrongColumnCount(line: lineNumber) }

            func invalid(_ column: Int) -> RecordingCSVError {
                .invalidValue(line: lineNumber, column: columns[column])
            }

            guard let time = Microseconds(fields[0]) else { throw invalid(0) }
            var values: [Double] = []
            for column in 1...13 {
                guard let value = Double(fields[column]), value.isFinite else { throw invalid(column) }
                values.append(value)
            }
            guard let activity = Activity(code: String(fields[14])) else { throw invalid(14) }
            guard fields[15].hasPrefix("p"), let participant = Int(fields[15].dropFirst()),
                  Recording.participants.contains(participant) else { throw invalid(15) }
            let swing: Int?
            if fields[16].isEmpty {
                swing = nil
            } else {
                guard activity.isSwings, let number = Int(fields[16]), number > 0 else { throw invalid(16) }
                swing = number
            }

            let motion = MotionSample(
                time: time,
                userAcceleration: SIMD3(values[0], values[1], values[2]),
                rotationRate: SIMD3(values[3], values[4], values[5]),
                attitude: simd_quatd(vector: SIMD4(values[6], values[7], values[8], values[9])),
                gravity: SIMD3(values[10], values[11], values[12])
            )
            frame = RecordedFrame(motion: motion, swing: swing)
            self.activity = activity
            self.participant = participant
        }
    }
}
