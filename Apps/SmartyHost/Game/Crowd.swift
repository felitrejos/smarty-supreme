import AppKit
import SmartyCore
import RealityKit

@MainActor
final class Crowd {
    private struct Spectator {
        let card: Entity
        let rest: SIMD3<Float>
        let phase: Float
        let rate: Float
        let excitement: Float
        let delay: Float
    }

    private static let rows = 9
    private static let rowDepth: Float = 0.85
    private static let rowRise: Float = 0.42
    private static let firstRowGap: Float = 1.6
    private static let seatSpacing: Float = 0.62
    private static let occupancy = 0.88
    private static let people = 5
    private static let cardSize = SIMD2<Float>(1.1, 1.52)
    private static let feetBelowSeat: Float = 0.45
    private static let spill: Float = 1.05
    private static let spillReach: Float = 8
    private static let brightnessSpread: ClosedRange<Float> = 0.7...1.15
    private static let shades = 6
    private static let breathe: Float = 0.012
    private static let sway: Float = 0.018
    private static let cheerHeight: Float = 0.07
    private static let cheerDuration: Float = 1.6
    private static let cheerSpread: Float = 0.6
    private static let stand = NSColor(red: 0.08, green: 0.055, blue: 0.04, alpha: 1)

    let root = Entity()
    private var spectators: [Spectator] = []
    private var shown: [Int] = []
    private static let idleBatches = 3

    private var time: Float = 0
    private var cheerStartedAt: Float?
    private var frame = 0

    func update(elapsed: TimeInterval, cheer: Bool) {
        time += Float(elapsed)
        if cheer {
            cheerStartedAt = time
        }
        let sinceCheer = cheerStartedAt.map { time - $0 }
        frame += 1
        let batch = frame % Self.idleBatches
        for index in shown where sinceCheer != nil || index % Self.idleBatches == batch {
            let spectator = spectators[index]
            var position = spectator.rest
            let idle = time * spectator.rate + spectator.phase
            position.y += sin(idle) * Self.breathe
            position.x += sin(idle * 0.37) * Self.sway
            if let sinceCheer {
                let local = (sinceCheer - spectator.delay) / Self.cheerDuration
                if local > 0, local < 1 {
                    position.y += abs(sin(local * .pi * 3)) * (1 - local) * Self.cheerHeight * spectator.excitement
                }
            }
            spectator.card.position = position
        }
        if let sinceCheer, sinceCheer > Self.cheerDuration + Self.cheerSpread {
            cheerStartedAt = nil
        }
    }

    init(courtLength: Float, courtWidth: Float, seed: UInt64) async throws {
        var random = SplitMix64(seed: seed)
        var textures: [TextureResource] = []
        for index in 0..<Self.people {
            let url = Bundle.main.url(forResource: "person-\(index)", withExtension: "png", subdirectory: "Crowd")!
            textures.append(try await TextureResource(contentsOf: url, options: .init(semantic: .color)))
        }
        let card = MeshResource.generatePlane(width: Self.cardSize.x, height: Self.cardSize.y)
        var tiers = MeshBuilder()
        let shaded = (0..<Self.shades).map { shade in
            textures.map { texture -> UnlitMaterial in
                var material = UnlitMaterial()
                let brightness = CGFloat(shade + 1) / CGFloat(Self.shades)
                material.color = .init(tint: NSColor(white: brightness, alpha: 1), texture: .init(texture))
                material.opacityThreshold = 0.5
                return material
            }
        }

        let sides: [(centre: SIMD2<Float>, along: SIMD2<Float>, outward: SIMD2<Float>, length: Float)] = [
            ([0, -courtLength / 2], [1, 0], [0, -1], courtWidth + 6),
            ([0, courtLength / 2], [-1, 0], [0, 1], courtWidth + 6),
            ([-courtWidth / 2, 0], [0, 1], [-1, 0], courtLength + 2),
            ([courtWidth / 2, 0], [0, -1], [1, 0], courtLength + 2),
        ]
        for row in 0..<Self.rows {
            for side in sides {
                let facing = atan2(-side.outward.x, -side.outward.y)
                let distance = Self.firstRowGap + Float(row) * Self.rowDepth
                let seat = Float(row) * Self.rowRise + 0.45
                let rowCentre = side.centre + side.outward * distance
                let rowLength = side.length + Float(row) * Self.rowDepth * 2
                tiers.box(centre: [rowCentre.x + side.outward.x * 0.2, seat / 2, rowCentre.y + side.outward.y * 0.2], size: [rowLength, seat, Self.rowDepth], yaw: facing)
                let seats = Int(rowLength / Self.seatSpacing)
                let stagger: Float = row.isMultiple(of: 2) ? 0 : Self.seatSpacing / 2
                for index in 0..<seats {
                    guard Double.random(in: 0..<1, using: &random) < Self.occupancy else { continue }
                    let offset = (Float(index) + 0.5) * Self.seatSpacing + stagger - rowLength / 2 + Float.random(in: -0.1...0.1, using: &random)
                    let spot = rowCentre + side.along * offset
                    let reach = simd_length(spot) / Self.spillReach
                    let light = Self.spill / (1 + reach * reach) * Float.random(in: Self.brightnessSpread, using: &random)
                    let shade = min(max(Int((light * Float(Self.shades)).rounded()) - 1, 0), Self.shades - 1)
                    let scale = Float.random(in: 0.92...1.06, using: &random)
                    let person = ModelEntity(mesh: card, materials: [shaded[shade][Int.random(in: 0..<Self.people, using: &random)]])
                    let rest: SIMD3<Float> = [spot.x, seat - Self.feetBelowSeat + Self.cardSize.y * scale / 2, spot.y]
                    person.position = rest
                    person.scale = [Bool.random(using: &random) ? scale : -scale, scale, scale]
                    person.components.set(BillboardComponent())
                    root.addChild(person)
                    spectators.append(Spectator(
                        card: person,
                        rest: rest,
                        phase: Float.random(in: 0...(2 * .pi), using: &random),
                        rate: Float.random(in: 0.8...1.8, using: &random),
                        excitement: Float.random(in: 0.2...1, using: &random),
                        delay: Float.random(in: 0...Self.cheerSpread, using: &random) + reach * 0.15
                    ))
                }
            }
        }
        var standMaterial = PhysicallyBasedMaterial()
        standMaterial.baseColor = .init(tint: Self.stand)
        standMaterial.roughness = 0.9
        root.addChild(ModelEntity(mesh: try tiers.mesh(named: "stands"), materials: [standMaterial]))
        showAll()
    }

    func showAll() {
        shown = Array(spectators.indices)
        for spectator in spectators {
            spectator.card.isEnabled = true
        }
    }

    func show(onlyWhatIsSeenFrom eye: SIMD3<Float>, looking forward: SIMD3<Float>, within halfAngle: Float) {
        let ahead = simd_normalize(SIMD2(forward.x, forward.z))
        let edge = cos(halfAngle)
        shown = []
        for (index, spectator) in spectators.enumerated() {
            let offset = SIMD2(spectator.rest.x - eye.x, spectator.rest.z - eye.z)
            let isSeen = simd_dot(simd_normalize(offset), ahead) >= edge
            spectator.card.isEnabled = isSeen
            if isSeen {
                shown.append(index)
            }
        }
    }
}

extension MeshBuilder {
    mutating func box(centre: SIMD3<Float>, size: SIMD3<Float>, yaw: Float) {
        let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let half = size / 2
        let faces: [(normal: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>)] = [
            ([1, 0, 0], [0, 0, 1], [0, 1, 0]), ([-1, 0, 0], [0, 0, -1], [0, 1, 0]),
            ([0, 1, 0], [1, 0, 0], [0, 0, -1]), ([0, -1, 0], [1, 0, 0], [0, 0, 1]),
            ([0, 0, 1], [-1, 0, 0], [0, 1, 0]), ([0, 0, -1], [1, 0, 0], [0, 1, 0]),
        ]
        for face in faces {
            let normal = rotation.act(face.normal)
            let corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { (a: Float, b: Float) -> UInt32 in
                let local = (face.normal + face.u * a + face.v * b) * half
                return vertex(centre + rotation.act(local), normal: normal, uv: [(a + 1) / 2, (b + 1) / 2])
            }
            quad(corners[0], corners[1], corners[2], corners[3])
        }
    }
}
