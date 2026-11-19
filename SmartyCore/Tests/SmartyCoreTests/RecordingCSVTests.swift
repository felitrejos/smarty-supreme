import SmartyCore
import Testing
import simd

struct RecordingCSVTests {
    @Test(arguments: Activity.all)
    func roundTripKeepsEveryField(activity: Activity) throws {
        let swing = activity.isSwings ? 1 : nil
        let recording = Recording(activity: activity, participant: 2, frames: [
            frame(time: 1_000_000, swing: nil),
            frame(time: 1_010_000, swing: swing),
            frame(time: 1_020_000, swing: swing),
        ])
        let decoded = try RecordingCSV.decode(RecordingCSV.encode(recording))
        #expect(decoded == recording)
    }

    @Test func firstLineNamesTheColumns() {
        let recording = Recording(activity: .still, participant: 1, frames: [frame(time: 0, swing: nil)])
        let firstLine = RecordingCSV.encode(recording).split(separator: "\n").first
        #expect(firstLine == "time_us,acc_x,acc_y,acc_z,rot_x,rot_y,rot_z,att_x,att_y,att_z,att_w,grav_x,grav_y,grav_z,activity,participant,swing")
    }

    @Test func roundsSensorValuesToSixDecimals() throws {
        let motion = MotionSample(
            time: 0,
            userAcceleration: SIMD3(0.123_456_7, 0, 0),
            rotationRate: .zero,
            attitude: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1),
            gravity: .zero
        )
        let recording = Recording(activity: .still, participant: 1, frames: [RecordedFrame(motion: motion, swing: nil)])
        let decoded = try RecordingCSV.decode(RecordingCSV.encode(recording))
        #expect(decoded.frames[0].motion.userAcceleration.x == 0.123_457)
    }

    @Test func rejectsAFileWithoutTheHeader() {
        #expect(throws: RecordingCSVError.missingHeader) {
            try RecordingCSV.decode("1,0,0,0,0,0,0,0,0,0,1,0,0,0,still,p1,\n")
        }
    }

    @Test func rejectsAFileWithNoFrames() {
        #expect(throws: RecordingCSVError.noFrames) {
            try RecordingCSV.decode(RecordingCSV.header + "\n")
        }
    }

    @Test func reportsTheLineAndColumnOfABadValue() {
        let text = csv(rows: [
            "0,0,0,0,0,0,0,0,0,0,1,0,0,0,still,p1,",
            "10000,0,abc,0,0,0,0,0,0,0,1,0,0,0,still,p1,",
        ])
        #expect(throws: RecordingCSVError.invalidValue(line: 3, column: "acc_y")) {
            try RecordingCSV.decode(text)
        }
    }

    @Test func rejectsARowWithTheWrongNumberOfColumns() {
        #expect(throws: RecordingCSVError.wrongColumnCount(line: 2)) {
            try RecordingCSV.decode(csv(rows: ["0,0,0,0,0,0,0,0,0,0,1,0,0,0,still,p1"]))
        }
    }

    @Test(arguments: ["running", "forehand-gentle"])
    func rejectsAnUnknownActivity(code: String) {
        #expect(throws: RecordingCSVError.invalidValue(line: 2, column: "activity")) {
            try RecordingCSV.decode(csv(rows: ["0,0,0,0,0,0,0,0,0,0,1,0,0,0,\(code),p1,"]))
        }
    }

    @Test(arguments: ["p0", "p4", "2", "px"])
    func rejectsAParticipantOutsideOneToThree(participant: String) {
        #expect(throws: RecordingCSVError.invalidValue(line: 2, column: "participant")) {
            try RecordingCSV.decode(csv(rows: ["0,0,0,0,0,0,0,0,0,0,1,0,0,0,still,\(participant),"]))
        }
    }

    @Test(arguments: ["0", "-1", "x"])
    func rejectsASwingNumberThatIsNotPositive(swing: String) {
        #expect(throws: RecordingCSVError.invalidValue(line: 2, column: "swing")) {
            try RecordingCSV.decode(csv(rows: ["0,0,0,0,0,0,0,0,0,0,1,0,0,0,forehand-soft,p1,\(swing)"]))
        }
    }

    @Test(arguments: ["walking,p1", "still,p2"])
    func rejectsTwoSessionsInOneFile(secondSession: String) {
        let text = csv(rows: [
            "0,0,0,0,0,0,0,0,0,0,1,0,0,0,still,p1,",
            "10000,0,0,0,0,0,0,0,0,0,1,0,0,0,\(secondSession),",
        ])
        #expect(throws: RecordingCSVError.mixedSessions(line: 3)) {
            try RecordingCSV.decode(text)
        }
    }

    @Test(arguments: ["nan", "inf", "-inf", ""])
    func rejectsSensorValuesThatAreNotFiniteNumbers(value: String) {
        #expect(throws: RecordingCSVError.invalidValue(line: 2, column: "acc_x")) {
            try RecordingCSV.decode(csv(rows: ["0,\(value),0,0,0,0,0,0,0,0,1,0,0,0,still,p1,"]))
        }
    }

    @Test(arguments: ["-5", "1.5", "abc"])
    func rejectsATimeThatIsNotWholeMicroseconds(time: String) {
        #expect(throws: RecordingCSVError.invalidValue(line: 2, column: "time_us")) {
            try RecordingCSV.decode(csv(rows: ["\(time),0,0,0,0,0,0,0,0,0,1,0,0,0,still,p1,"]))
        }
    }

    @Test(arguments: ["still", "walking"])
    func rejectsASwingNumberOutsideASwingRecording(activity: String) {
        #expect(throws: RecordingCSVError.invalidValue(line: 2, column: "swing")) {
            try RecordingCSV.decode(csv(rows: ["0,0,0,0,0,0,0,0,0,0,1,0,0,0,\(activity),p1,1"]))
        }
    }

    @Test func aBlankLineIsReportedAtItsOwnLineNumber() {
        let text = csv(rows: [
            "0,0,0,0,0,0,0,0,0,0,1,0,0,0,still,p1,",
            "",
            "20000,0,0,0,0,0,0,0,0,0,1,0,0,0,still,p1,",
        ])
        #expect(throws: RecordingCSVError.wrongColumnCount(line: 3)) {
            try RecordingCSV.decode(text)
        }
    }

    @Test func rejectsTimeThatDoesNotMoveForward() {
        let text = csv(rows: [
            "10000,0,0,0,0,0,0,0,0,0,1,0,0,0,still,p1,",
            "10000,0,0,0,0,0,0,0,0,0,1,0,0,0,still,p1,",
        ])
        #expect(throws: RecordingCSVError.timeNotIncreasing(line: 3)) {
            try RecordingCSV.decode(text)
        }
    }
}

private func csv(rows: [String]) -> String {
    ([RecordingCSV.header] + rows).joined(separator: "\n") + "\n"
}

private func frame(time: Microseconds, swing: Int?) -> RecordedFrame {
    let motion = MotionSample(
        time: time,
        userAcceleration: SIMD3(0.125, -2.5, 0.000_001),
        rotationRate: SIMD3(4.75, -0.5, 12.25),
        attitude: simd_quatd(ix: 0.1, iy: -0.2, iz: 0.3, r: 0.927_362),
        gravity: SIMD3(0, -0.999_5, -0.031_6)
    )
    return RecordedFrame(motion: motion, swing: swing)
}
