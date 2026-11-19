import SmartyCore
import UIKit

@MainActor
final class HapticPlayer {
    private static let lightestHit = 0.45

    private let contact = UIImpactFeedbackGenerator(style: .rigid)
    private let whiff = UIImpactFeedbackGenerator(style: .soft)
    private let outcome = UINotificationFeedbackGenerator()

    func prepare() {
        contact.prepare()
        whiff.prepare()
        outcome.prepare()
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
