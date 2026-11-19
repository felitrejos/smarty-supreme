public enum TouchInput {
    public static let swingStrength = 0.5
    public static let minimumSwipe = 60.0
    public static let maximumSlant = 0.5

    public static func isSwing(across: Double, down: Double) -> Bool {
        -down >= minimumSwipe && abs(across) <= -down * maximumSlant
    }

    public static func swing(at time: Microseconds) -> SwingEvent {
        SwingEvent(peakTime: time, peakAcceleration: 0, peakRotationRate: 0, direction: SIMD3(0, 0, -1), strength: swingStrength)
    }

    public static func position(x: Double, width: Double) -> Double {
        min(max(x / width, 0), 1)
    }
}
