import SmartyCore
import Testing
import simd

struct SwingDetectorTests {
    @Test func stillSignalForTenSecondsGivesNothing() {
        var random = SplitMix64(seed: 3)
        var signal = MotionSignal()
        for _ in 0..<1_000 {
            signal.hold(for: 10_000, acceleration: Double.random(in: -0.05...0.05, using: &random))
        }
        #expect(events(for: signal).isEmpty)
    }

    @Test func aSharpSpikeWithWristRotationIsExactlyOneSwing() throws {
        var signal = MotionSignal()
        signal.hold(for: 100_000)
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 500_000)

        let detected = events(for: signal)
        #expect(detected.count == 1)
        guard case .swing(let swing) = try #require(detected.first) else {
            Issue.record("Expected a swing, got \(detected)")
            return
        }
        #expect(swing.peakAcceleration == 3)
        #expect(swing.peakRotationRate == 12)
        #expect(swing.direction == SIMD3(0, 0, 1))
        #expect(abs(swing.strength - (3 - 1.8) / 4.2) < 1e-12)
    }

    @Test func aKnockShorterThanTwentyMillisecondsIsIgnored() {
        var signal = MotionSignal()
        signal.hold(for: 10_000, acceleration: 3, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal).isEmpty)
    }

    @Test func aHardSwingThatPeaksJustAfterCrossingTheThresholdCountsFromWhereTheMotionStarted() throws {
        var signal = MotionSignal()
        signal.hold(for: 100_000)
        for acceleration in [1.2, 1.8, 2.2, 3.5, 7.0, 4.0, 1.5, 0.5] {
            signal.hold(for: 10_000, acceleration: acceleration, rotation: 15)
        }
        signal.hold(for: 500_000)

        let detected = events(for: signal)
        #expect(detected.count == 1)
        guard case .swing(let swing) = try #require(detected.first) else {
            Issue.record("Expected a swing, got \(detected)")
            return
        }
        #expect(swing.peakAcceleration == 7)
    }

    @Test func aSwingThatJumpsToItsPeakWithinOneSampleCounts() throws {
        var signal = MotionSignal()
        signal.hold(for: 100_000, acceleration: 0.3)
        for acceleration in [2.47, 2.96, 1.78, 1.89, 1.83, 0.68] {
            signal.hold(for: 10_000, acceleration: acceleration, rotation: 14)
        }
        signal.hold(for: 500_000)

        let detected = events(for: signal)
        #expect(detected.count == 1)
        guard case .swing(let swing) = try #require(detected.first) else {
            Issue.record("Expected a swing, got \(detected)")
            return
        }
        #expect(swing.peakAcceleration == 2.96)
    }

    @Test func aLightSwingJustOverTwoGCounts() {
        var signal = MotionSignal()
        signal.hold(for: 100_000)
        signal.halfSine(peak: 2.1, lasting: 150_000, rotation: 12)
        signal.hold(for: 500_000)

        #expect(events(for: signal).count == 1)
    }

    @Test func reportsTheSwingOnceAccelerationDropsTenPercentBelowItsPeak() throws {
        var signal = MotionSignal()
        signal.hold(for: 100_000)
        let start = signal.now
        signal.halfSine(peak: 4, lasting: 120_000, rotation: 12)
        signal.hold(for: 500_000)

        var detector = SwingDetector()
        let reportTime = try #require(signal.samples.first { detector.process($0) != nil }).time
        #expect(reportTime == start + 80_000)
    }

    @Test func aDipBeforeTheMinimumDurationDoesNotEndTheSwing() throws {
        var signal = MotionSignal()
        signal.hold(for: 10_000, acceleration: 3, rotation: 12)
        signal.hold(for: 10_000, acceleration: 2.6, rotation: 12)
        signal.hold(for: 10_000, acceleration: 3.5, rotation: 12)
        signal.hold(for: 10_000, acceleration: 4, rotation: 12)
        signal.hold(for: 500_000)

        let detected = events(for: signal)
        #expect(detected.count == 1)
        guard case .swing(let swing) = try #require(detected.first) else {
            Issue.record("Expected a swing")
            return
        }
        #expect(swing.peakAcceleration == 4)
    }

    @Test func accelerationSustainedPastTwoHundredFiftyMillisecondsIsIgnored() {
        var signal = MotionSignal()
        signal.hold(for: 400_000, acceleration: 3, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal).isEmpty)
    }

    @Test func spikeAboveEightGIsADropNotASwing() {
        var signal = MotionSignal()
        signal.hold(for: 80_000, acceleration: 9, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal) == [.drop])
    }

    @Test func aSingleSampleImpactAboveEightGIsADrop() {
        var signal = MotionSignal()
        signal.hold(for: 100_000)
        signal.hold(for: 10_000, acceleration: 12, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal) == [.drop])
    }

    @Test func aRejectedSpikeMustCalmDownBeforeTheNextSwingCounts() {
        var signal = MotionSignal()
        signal.hold(for: 30_000, acceleration: 3, rotation: 1)
        signal.hold(for: 10_000, acceleration: 2.6, rotation: 1)
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal).isEmpty)
    }

    @Test func movementStillGoingWhenTheCooldownEndsMustCalmDownFirst() {
        var signal = MotionSignal()
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 400_000, acceleration: 2, rotation: 12)
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal).count == 1)
    }

    @Test func freeFallIsADropAndTheCatchIsNotASwing() {
        var signal = MotionSignal()
        signal.hold(for: 100_000)
        signal.freeFall(for: 200_000)
        signal.hold(for: 80_000, acceleration: 4, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal) == [.drop])
    }

    @Test func spikeWithoutEnoughRotationIsIgnored() {
        var signal = MotionSignal()
        signal.hold(for: 80_000, acceleration: 3, rotation: 6)
        signal.hold(for: 500_000)
        #expect(events(for: signal).isEmpty)
    }

    @Test func spikeWhileThePhoneLiesFlatIsIgnored() {
        var signal = MotionSignal()
        signal.gravity = MotionSignal.flat
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal).isEmpty)
    }

    @Test func twoPeaksOneHundredFiftyMillisecondsApartAreOneSwing() {
        var signal = MotionSignal()
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 70_000)
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal).count == 1)
    }

    @Test func detectsAgainOnceTheCooldownHasPassed() {
        var signal = MotionSignal()
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 400_000)
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 500_000)
        #expect(events(for: signal).count == 2)
    }

    @Test(arguments: [62_500 as Microseconds, 60_000, 87_500])
    func peakTimeIsWithinOneSampleOfTheTruePeak(halfWidth: Microseconds) throws {
        var signal = MotionSignal()
        signal.hold(for: 100_000)
        let start = signal.now
        signal.halfSine(peak: 4, lasting: 2 * halfWidth, rotation: 12)
        signal.hold(for: 500_000)

        guard case .swing(let swing) = try #require(events(for: signal).first) else {
            Issue.record("Expected a swing")
            return
        }
        let truePeak = start + halfWidth
        let error = swing.peakTime > truePeak ? swing.peakTime - truePeak : truePeak - swing.peakTime
        #expect(error <= MotionSignal.interval)
    }

    @Test func directionIsExpressedInTheReferenceFrame() throws {
        var signal = MotionSignal()
        signal.attitude = simd_quatd(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        signal.hold(for: 80_000, acceleration: 3, rotation: 12)
        signal.hold(for: 500_000)

        guard case .swing(let swing) = try #require(events(for: signal).first) else {
            Issue.record("Expected a swing")
            return
        }
        #expect(simd_distance(swing.direction, SIMD3(1, 0, 0)) < 1e-9)
    }

    @Test(arguments: [(1.8, 0.0), (6.0, 1.0), (3.9, 0.5), (1.0, 0.0), (8.0, 1.0)])
    func strengthMapsOnePointEightToSixGOntoZeroToOne(peak: Double, strength: Double) {
        #expect(abs(SwingConfig().strength(forPeakAcceleration: peak) - strength) < 1e-12)
    }

    @Test func reportsMidSwingOnlyWhileTheSpikeIsRising() {
        var detector = SwingDetector()
        var signal = MotionSignal()
        signal.hold(for: 20_000)
        signal.hold(for: 50_000, acceleration: 3, rotation: 12)
        signal.hold(for: 20_000)
        let states = signal.samples.map { sample in
            _ = detector.process(sample)
            return detector.isMidSwing
        }
        #expect(states == [false, false, true, true, true, true, true, false, false])
    }
}

private func events(for signal: MotionSignal) -> [SwingDetectorEvent] {
    var detector = SwingDetector()
    return signal.samples.compactMap { detector.process($0) }
}
