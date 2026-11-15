import simd

public struct SwingEvent: Equatable, Sendable {
    public let peakTime: Microseconds
    public let peakAcceleration: Double
    public let peakRotationRate: Double
    public let direction: SIMD3<Double>
    public let strength: Double

    public init(peakTime: Microseconds, peakAcceleration: Double, peakRotationRate: Double, direction: SIMD3<Double>, strength: Double) {
        self.peakTime = peakTime
        self.peakAcceleration = peakAcceleration
        self.peakRotationRate = peakRotationRate
        self.direction = direction
        self.strength = strength
    }
}

public enum SwingDetectorEvent: Equatable, Sendable {
    case swing(SwingEvent)
    case drop
}

public struct SwingDetector: Sendable {
    private struct Spike: Sendable {
        let start: Microseconds
        let uprightness: Double
        var peak: MotionSample
        var peakAcceleration: Double
        var peakRotationRate: Double

        init(_ sample: MotionSample, acceleration: Double) {
            start = sample.time
            uprightness = sample.uprightness
            peak = sample
            peakAcceleration = acceleration
            peakRotationRate = simd_length(sample.rotationRate)
        }

        var riseTime: Microseconds {
            peak.time - start
        }

        mutating func include(_ sample: MotionSample, acceleration: Double) {
            if acceleration >= peakAcceleration {
                peak = sample
                peakAcceleration = acceleration
            }
            peakRotationRate = max(peakRotationRate, simd_length(sample.rotationRate))
        }
    }

    private enum State: Sendable {
        case idle
        case rising(Spike)
        case cooldown(until: Microseconds)
        case settling
    }

    private let config: SwingConfig
    private var state = State.idle
    private var lowGravitySince: Microseconds?
    private var isFalling = false

    public init(config: SwingConfig = SwingConfig()) {
        self.config = config
    }

    public var isMidSwing: Bool {
        if case .rising = state { return true }
        return false
    }

    private var isArmedOrRising: Bool {
        switch state {
        case .idle, .rising: true
        case .cooldown, .settling: false
        }
    }

    public mutating func process(_ sample: MotionSample) -> SwingDetectorEvent? {
        if let fall = trackFreeFall(sample) {
            return fall
        }
        let acceleration = simd_length(sample.userAcceleration)
        if acceleration > config.ceiling, isArmedOrRising {
            state = .settling
            return .drop
        }
        switch state {
        case .idle:
            if acceleration > config.onThreshold {
                state = .rising(Spike(sample, acceleration: acceleration))
            }
        case .rising(var spike):
            spike.include(sample, acceleration: acceleration)
            if spike.riseTime >= config.minimumRiseTime,
               acceleration <= config.reportFraction * spike.peakAcceleration {
                return report(spike, at: sample.time)
            }
            if acceleration < config.offThreshold {
                state = .idle
                return nil
            }
            state = sample.time - spike.start >= config.maximumDuration ? .settling : .rising(spike)
        case .cooldown(let until):
            if sample.time >= until {
                state = acceleration < config.offThreshold ? .idle : .settling
            }
        case .settling:
            if acceleration < config.offThreshold {
                state = .idle
            }
        }
        return nil
    }

    private mutating func trackFreeFall(_ sample: MotionSample) -> SwingDetectorEvent? {
        let totalAcceleration = simd_length(sample.userAcceleration + sample.gravity)
        guard totalAcceleration < config.freeFallThreshold else {
            lowGravitySince = nil
            if isFalling {
                isFalling = false
                state = .cooldown(until: sample.time + config.cooldown)
            }
            return nil
        }
        let since = lowGravitySince ?? sample.time
        lowGravitySince = since
        guard !isFalling, sample.time - since >= config.freeFallDuration else { return nil }
        isFalling = true
        state = .settling
        return .drop
    }

    private mutating func report(_ spike: Spike, at time: Microseconds) -> SwingDetectorEvent? {
        state = .settling
        guard spike.peakRotationRate >= config.minimumRotationRate,
              spike.uprightness >= config.minimumUprightness else { return nil }
        state = .cooldown(until: time + config.cooldown)
        return .swing(SwingEvent(
            peakTime: spike.peak.time,
            peakAcceleration: spike.peakAcceleration,
            peakRotationRate: spike.peakRotationRate,
            direction: simd_normalize(spike.peak.attitude.act(spike.peak.userAcceleration)),
            strength: config.strength(forPeakAcceleration: spike.peakAcceleration)
        ))
    }
}
