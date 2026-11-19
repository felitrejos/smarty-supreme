import FlickCore
import Foundation
import Testing

struct PointerMapperTests {
    @Test func neutralRollMapsToTheMiddle() {
        #expect(positions(rollDegrees: 7, neutral: 7, sensitivity: .medium).last == .position(0.5))
    }

    @Test(arguments: [
        (20.0, 1.0), (-20.0, 0.0), (35.0, 1.0), (-35.0, 0.0), (10.0, 0.75),
    ])
    func rollAcrossTheRangeMapsAcrossTheTableAndClampsBeyondIt(roll: Double, position: Double) throws {
        let reading = try #require(positions(rollDegrees: roll, neutral: 0, sensitivity: .medium).last)
        guard case .position(let value) = reading else {
            Issue.record("Expected a position, got \(reading)")
            return
        }
        #expect(abs(value - position) < 1e-9)
    }

    @Test(arguments: Sensitivity.allCases)
    func sensitivitySetsTheRollThatReachesTheEdge(sensitivity: Sensitivity) {
        let reading = positions(rollDegrees: sensitivity.rangeDegrees, neutral: 0, sensitivity: sensitivity).last
        #expect(reading == .position(1))
    }

    @Test func aPhoneThatHasNeverBeenUprightGivesNoPosition() {
        var mapper = PointerMapper(neutralRollDegrees: 0, sensitivity: .medium)
        var signal = MotionSignal()
        signal.gravity = MotionSignal.flat
        signal.hold(for: 10_000)
        #expect(mapper.update(signal.samples[0], holding: false) == .notUpright)
    }

    @Test func aSwingThatTipsThePhoneBackKeepsThePaddleWhereItWas() {
        var mapper = PointerMapper(neutralRollDegrees: 0, sensitivity: .medium)
        var signal = MotionSignal()
        signal.tilt(rollDegrees: 10, for: 500_000)
        let upright = signal.samples.count
        signal.gravity = MotionSignal.flat
        signal.hold(for: 500_000)
        let readings = signal.samples.map { mapper.update($0, holding: false) }
        let before = readings[upright - 1]

        #expect(readings[upright...].allSatisfy { $0 == before })
    }

    @Test func stayingTiltedForThreeQuartersOfASecondPausesThePaddle() {
        var mapper = PointerMapper(neutralRollDegrees: 0, sensitivity: .medium)
        var signal = MotionSignal()
        signal.tilt(rollDegrees: 10, for: 500_000)
        let upright = signal.samples.count
        signal.gravity = MotionSignal.flat
        signal.hold(for: 1_000_000)
        let readings = signal.samples.map { mapper.update($0, holding: false) }
        let tilted = readings[upright...]

        #expect(tilted.prefix(74).allSatisfy { $0 != .notUpright })
        #expect(tilted.dropFirst(75).allSatisfy { $0 == .notUpright })
    }

    @Test func holdsThePositionFromBeforeTheSwing() throws {
        var mapper = PointerMapper(neutralRollDegrees: 0, sensitivity: .medium)
        var signal = MotionSignal()
        signal.tilt(rollDegrees: 10, for: 500_000)
        signal.tilt(rollDegrees: -15, for: 200_000)
        let samples = signal.samples
        let before = samples[..<50].map { mapper.update($0, holding: false) }.last
        let during = samples[50...].map { mapper.update($0, holding: true) }
        #expect(during.allSatisfy { $0 == before })
    }

    @Test func settlesWithinFortyMillisecondsAfterAStep() {
        var mapper = PointerMapper(neutralRollDegrees: 0, sensitivity: .medium)
        var signal = MotionSignal()
        signal.tilt(rollDegrees: 0, for: 500_000)
        signal.tilt(rollDegrees: 10, for: 500_000)
        let readings = signal.samples.map { mapper.update($0, holding: false) }
        let target = 0.75
        let tolerance = 0.05 * (target - 0.5)
        let afterForty = readings[(50 + 4)...]
        #expect(afterForty.allSatisfy { reading in
            guard case .position(let value) = reading else { return false }
            return abs(value - target) <= tolerance
        })
    }

    @Test func keepsJitterUnderFourTenthsOfAPercentForTwoTenthsOfADegreeOfNoise() {
        var random = SplitMix64(seed: 11)
        var mapper = PointerMapper(neutralRollDegrees: 0, sensitivity: .high)
        var signal = MotionSignal()
        signal.tilt(rollDegrees: 0, for: 60_000_000) {
            gaussian(using: &random) * 0.2
        }
        let values = signal.samples.dropFirst(500).compactMap { sample -> Double? in
            guard case .position(let value) = mapper.update(sample, holding: false) else { return nil }
            return value
        }
        #expect(rootMeanSquareDeviation(values) < 0.004)
    }
}

struct CalibratorTests {
    @Test func averagesRollOverHalfASecond() throws {
        var calibrator = Calibrator()
        var signal = MotionSignal()
        signal.tilt(rollDegrees: 4, for: 250_000)
        signal.tilt(rollDegrees: 6, for: 260_000)
        let result = try #require(signal.samples.lazy.compactMap { calibrator.add($0) }.first)
        guard case .calibrated(let neutral) = result else {
            Issue.record("Expected calibration, got \(result)")
            return
        }
        #expect(abs(neutral - 5) < 0.1)
    }

    @Test func rejectsWhenRollVariesMoreThanThreeDegrees() {
        var calibrator = Calibrator()
        var signal = MotionSignal()
        signal.tilt(rollDegrees: 0, for: 250_000)
        signal.tilt(rollDegrees: 3.5, for: 260_000)
        #expect(signal.samples.compactMap { calibrator.add($0) } == [.failed(.handMoved)])
    }

    @Test func rejectsWhenThePhoneIsNotUpright() {
        var calibrator = Calibrator()
        var signal = MotionSignal()
        signal.gravity = MotionSignal.flat
        signal.hold(for: 510_000)
        #expect(signal.samples.compactMap { calibrator.add($0) } == [.failed(.notUpright)])
    }
}

private func positions(rollDegrees: Double, neutral: Double, sensitivity: Sensitivity) -> [PointerReading] {
    var mapper = PointerMapper(neutralRollDegrees: neutral, sensitivity: sensitivity)
    var signal = MotionSignal()
    signal.tilt(rollDegrees: rollDegrees, for: 100_000)
    return signal.samples.map { mapper.update($0, holding: false) }
}

private func gaussian(using random: inout SplitMix64) -> Double {
    let first = Double.random(in: Double.leastNonzeroMagnitude..<1, using: &random)
    let second = Double.random(in: 0..<1, using: &random)
    return (-2 * log(first)).squareRoot() * cos(2 * .pi * second)
}

private func rootMeanSquareDeviation(_ values: [Double]) -> Double {
    let mean = values.reduce(0, +) / Double(values.count)
    let squares = values.map { ($0 - mean) * ($0 - mean) }
    return (squares.reduce(0, +) / Double(values.count)).squareRoot()
}
