import CoreHaptics
import SmartyCore
import UIKit

@MainActor
final class HapticPlayer {
    private static let lightestHit = 0.45
    private static let cleanSharpness: Float = 1
    private static let edgeSharpness: Float = 0.1
    private static let edgeIntensity: Float = 0.7
    private static let rattleIntensity: Float = 0.35
    private static let rattleDelay: TimeInterval = 0.015
    private static let rattleLength: TimeInterval = 0.05

    private let contact = UIImpactFeedbackGenerator(style: .rigid)
    private let whiff = UIImpactFeedbackGenerator(style: .soft)
    private let outcome = UINotificationFeedbackGenerator()
    private let engine = try? CHHapticEngine()

    func prepare() {
        contact.prepare()
        whiff.prepare()
        outcome.prepare()
        engine?.resetHandler = { [engine] in try? engine?.start() }
        try? engine?.start()
    }

    // A clean hit is one crisp, sharp tap; an edge is a dull knock with a short rattle, like a ball off the blade's wood.
    func playHit(strength: Double, isClean: Bool) {
        let intensity = Float(Self.lightestHit + (1 - Self.lightestHit) * strength)
        let events = isClean
            ? [Self.transient(intensity: intensity, sharpness: Self.cleanSharpness, at: 0)]
            : [
                Self.transient(intensity: intensity * Self.edgeIntensity, sharpness: Self.edgeSharpness, at: 0),
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * Self.rattleIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: Self.edgeSharpness),
                    ],
                    relativeTime: Self.rattleDelay,
                    duration: Self.rattleLength
                ),
            ]
        guard let engine, let pattern = try? CHHapticPattern(events: events, parameters: []), let player = try? engine.makePlayer(with: pattern) else {
            play(.hit, swingStrength: strength)
            return
        }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    private static func transient(intensity: Float, sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    func play(_ kind: HapticKind, swingStrength: Double?) {
        switch kind {
        case .hit:
            contact.impactOccurred(intensity: Self.lightestHit + (1 - Self.lightestHit) * (swingStrength ?? 0))
            contact.prepare()
        case .miss:
            whiff.impactOccurred(intensity: 0.5)
            whiff.prepare()
        case .point:
            outcome.notificationOccurred(.success)
            outcome.prepare()
        case .win:
            outcome.notificationOccurred(.success)
            contact.impactOccurred(intensity: 1)
            outcome.prepare()
        }
    }
}
