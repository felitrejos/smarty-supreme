import RealityKit

@MainActor
final class ContactRing {
    private static let largest: Float = 0.55
    private static let smallest: Float = 0.1
    private static let lead: Float = 0.45

    let root: ModelEntity

    init(material: UnlitMaterial, facing: simd_quatf) {
        root = ModelEntity(mesh: .generatePlane(width: 1, height: 1), materials: [material])
        root.orientation = facing
        root.isEnabled = false
    }

    func show(at contact: (position: SIMD3<Float>, secondsAway: Float)?) {
        guard let contact, contact.secondsAway < Self.lead else {
            root.isEnabled = false
            return
        }
        root.isEnabled = true
        root.position = contact.position
        root.scale = .init(repeating: Self.smallest + (Self.largest - Self.smallest) * max(contact.secondsAway, 0) / Self.lead)
    }
}
