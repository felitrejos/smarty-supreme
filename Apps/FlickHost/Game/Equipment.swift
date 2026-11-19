import AppKit
import FlickCore
import RealityKit

@MainActor
enum Equipment {
    enum Size {
        static let metresPerTableLength: Float = 2.74
        static let tableHeight: Float = 0.76
        static let topThickness: Float = 0.025
        static let apronDepth: Float = 0.07
        static let legSide: Float = 0.07
        static let netHeight: Float = 0.1525
        static let netOverhang: Float = 0.1525
        static let ballRadius: Float = 0.02
        static let bladeWidth: Float = 0.15
        static let bladeHeight: Float = 0.158
        static let bladeThickness: Float = 0.0058
        static let rubberThickness: Float = 0.0015
        static let handleLength: Float = 0.1
        static let grip: Float = 0.13
        static let pipRepeats: Float = 4.5
        static let floorRadius: Float = 16
        static let courtLength: Float = 12
        static let courtWidth: Float = 8.4
        static let surroundHeight: Float = 0.7
        static let surroundPanel: Float = 2
        static let fillIntensity: Float = 420
    }

    enum Tone {
        static let lamp = NSColor(red: 1.0, green: 0.8, blue: 0.56, alpha: 1)
        static let celluloid = NSColor(red: 0.96, green: 0.94, blue: 0.87, alpha: 1)
        static let iron = NSColor(white: 0.08, alpha: 1)
        static let room = NSColor(red: 0.03, green: 0.025, blue: 0.02, alpha: 1)
        static let apron = NSColor(red: 0.05, green: 0.13, blue: 0.1, alpha: 1)
        static let surround = NSColor(red: 0.17, green: 0.23, blue: 0.32, alpha: 1)
    }

    @MainActor
    struct Materials {
        let top: PhysicallyBasedMaterial
        let frame: PhysicallyBasedMaterial
        let apron: PhysicallyBasedMaterial
        let surround: PhysicallyBasedMaterial
        let adverts: [PhysicallyBasedMaterial]
        let blade: PhysicallyBasedMaterial
        let floor: PhysicallyBasedMaterial
        let fog: UnlitMaterial
        let iron: PhysicallyBasedMaterial
        let pips: TextureResource
        let wear: TextureResource
        let stamp: PhysicallyBasedMaterial
        let net: PhysicallyBasedMaterial
        let shadow: UnlitMaterial

        static func make(tableWidth: Float) async throws -> Materials {
            async let topImage = Textures.tableTop(widthMetres: Double(tableWidth), seed: 7)
            async let pipsImage = Textures.pimpledRubber()
            async let wearImage = Textures.rubberWear(seed: 12)
            async let stampImage = Textures.makersStamp()
            async let netImage = Textures.netMesh(cellsAcross: 122, cellsDown: 10)
            async let shadowImage = Textures.softShadow()
            async let fogImage = Textures.floorFog()

            var top = PhysicallyBasedMaterial()
            top.baseColor = .init(texture: .init(try await Textures.texture(await topImage, .color)))
            top.roughness = 0.68
            top.clearcoat = 0.08
            top.clearcoatRoughness = 0.5

            var frame = try await Textures.surface("coated_pine")
            frame.clearcoat = 0.45
            frame.clearcoatRoughness = 0.3

            let blade = try await Textures.surface("plywood")

            var apron = PhysicallyBasedMaterial()
            apron.baseColor = .init(tint: Tone.apron)
            apron.roughness = 0.45
            apron.clearcoat = 0.4

            var surround = try await Textures.surface("black_painted_planks", repeats: 2)
            surround.baseColor = .init(tint: Tone.surround)
            surround.clearcoat = 0.7
            surround.clearcoatRoughness = 0.35
            var adverts: [PhysicallyBasedMaterial] = []
            for advert in Self.adverts {
                var board = surround
                board.baseColor = .init(texture: .init(try await Textures.texture(await Textures.advert(advert), .color)))
                board.textureCoordinateTransform = .init()
                adverts.append(board)
            }

            let floor = try await Textures.surface("old_wooden_floor_02", repeats: Size.floorRadius)

            var fog = UnlitMaterial()
            fog.color = .init(tint: Tone.room, texture: .init(try await Textures.texture(await fogImage, .color)))
            fog.blending = .transparent(opacity: 1.0)

            var iron = PhysicallyBasedMaterial()
            iron.baseColor = .init(tint: Tone.iron)
            iron.metallic = 0.8
            iron.roughness = 0.45

            var net = PhysicallyBasedMaterial()
            net.baseColor = .init(texture: .init(try await Textures.texture(await netImage, .color, mipmaps: false)))
            net.roughness = 0.9
            net.opacityThreshold = 0.5
            net.faceCulling = .none

            var shadow = UnlitMaterial()
            shadow.color = .init(tint: .white, texture: .init(try await Textures.texture(await shadowImage, .color)))
            shadow.blending = .transparent(opacity: 1.0)

            return Materials(
                top: top,
                frame: frame,
                apron: apron,
                surround: surround,
                adverts: adverts,
                blade: blade,
                floor: floor,
                fog: fog,
                iron: iron,
                pips: try await Textures.texture(await pipsImage, .normal),
                wear: try await Textures.texture(await wearImage, .color),
                stamp: try await stampMaterial(await stampImage),
                net: net,
                shadow: shadow
            )
        }

        private static let adverts = [
            Textures.Advert(words: "OpenAI · SAN FRANCISCO", font: "Futura-Bold", board: (0.09, 0.13, 0.2), ink: (0.93, 0.88, 0.76)),
            Textures.Advert(words: "NVIDIA", font: "Futura-CondensedExtraBold", board: (0.24, 0.36, 0.12), ink: (0.95, 0.92, 0.8)),
            Textures.Advert(words: "Claude is good for you", font: "Didot-Bold", board: (0.08, 0.07, 0.06), ink: (0.88, 0.8, 0.6)),
            Textures.Advert(words: "HUGGING FACE", font: "GillSans-UltraBold", board: (0.88, 0.75, 0.3), ink: (0.12, 0.1, 0.08)),
            Textures.Advert(words: "DEEPMIND", font: "Futura-CondensedExtraBold", board: (0.55, 0.1, 0.08), ink: (0.96, 0.9, 0.78)),
            Textures.Advert(words: "ANTHROPIC", font: "GillSans-Bold", board: (0.88, 0.84, 0.74), ink: (0.6, 0.25, 0.12)),
            Textures.Advert(words: "MISTRAL · PARIS", font: "Didot-Bold", board: (0.9, 0.82, 0.45), ink: (0.1, 0.1, 0.12)),
            Textures.Advert(words: "PERPLEXITY", font: "Futura-Bold", board: (0.12, 0.25, 0.18), ink: (0.95, 0.9, 0.78)),
            Textures.Advert(words: "CURSOR", font: "GillSans-UltraBold", board: (0.09, 0.13, 0.2), ink: (0.86, 0.71, 0.42)),
        ]

        private static func stampMaterial(_ image: CGImage) async throws -> PhysicallyBasedMaterial {
            var stamp = PhysicallyBasedMaterial()
            stamp.baseColor = .init(texture: .init(try await Textures.texture(image, .color)))
            stamp.metallic = 0.6
            stamp.roughness = 0.45
            stamp.opacityThreshold = 0.4
            return stamp
        }

        func rubber(_ color: NSColor) -> PhysicallyBasedMaterial {
            var rubber = PhysicallyBasedMaterial()
            rubber.baseColor = .init(tint: color, texture: .init(wear))
            rubber.normal = .init(texture: .init(pips))
            rubber.textureCoordinateTransform = .init(scale: [Size.pipRepeats, Size.pipRepeats])
            rubber.roughness = 0.74
            return rubber
        }
    }

    static func floor(_ materials: Materials) -> Entity {
        let size = Size.floorRadius * 2
        let floor = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [materials.floor])
        floor.position.y = -0.002
        let fog = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [materials.fog])
        fog.position.y = 0.002
        floor.addChild(fog)
        return floor
    }

    static func contactShadow(_ materials: Materials, width: Float) -> Entity {
        let shadow = ModelEntity(mesh: .generatePlane(width: width * 1.7, depth: Size.metresPerTableLength * 1.2), materials: [materials.shadow])
        shadow.position.y = 0.001
        return shadow
    }

    static func table(_ materials: Materials, width: Float) -> Entity {
        let table = Entity()
        let length = Size.metresPerTableLength
        let top = ModelEntity(
            mesh: .generateBox(width: width, height: Size.topThickness, depth: length, cornerRadius: 0.003, splitFaces: true),
            materials: [materials.frame, materials.top, materials.frame, materials.frame, materials.frame, materials.frame]
        )
        top.position.y = Size.tableHeight - Size.topThickness / 2
        table.addChild(top)

        let apronY = Size.tableHeight - Size.topThickness - Size.apronDepth / 2
        for side: Float in [-1, 1] {
            let long = ModelEntity(mesh: .generateBox(width: 0.022, height: Size.apronDepth, depth: length - 0.04), materials: [materials.apron])
            long.position = [side * (width / 2 - 0.011), apronY, 0]
            let short = ModelEntity(mesh: .generateBox(width: width, height: Size.apronDepth, depth: 0.022), materials: [materials.apron])
            short.position = [0, apronY, side * (length / 2 - 0.011)]
            table.addChild(long)
            table.addChild(short)
        }
        let legHeight = Size.tableHeight - Size.topThickness - 0.03
        for end: Float in [-0.62, -0.06, 0.06, 0.62] {
            let z = end * length
            for across: Float in [-1, 1] {
                let leg = ModelEntity(mesh: .generateBox(width: Size.legSide, height: legHeight, depth: 0.05, cornerRadius: 0.006), materials: [materials.frame])
                leg.position = [across * (width / 2 - 0.16), legHeight / 2, z * 0.62]
                table.addChild(leg)
                let foot = ModelEntity(mesh: .generateBox(width: 0.08, height: 0.035, depth: 0.32, cornerRadius: 0.01), materials: [materials.frame])
                foot.position = [across * (width / 2 - 0.16), 0.018, z * 0.62]
                table.addChild(foot)
            }
            let rail = ModelEntity(mesh: .generateBox(width: width - 0.32, height: 0.05, depth: 0.04), materials: [materials.frame])
            rail.position = [0, 0.22, z * 0.62]
            table.addChild(rail)
        }
        let spine = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.05, depth: length * 0.8), materials: [materials.frame])
        spine.position = [0, 0.22, 0]
        table.addChild(spine)

        table.addChild(net(materials, tableWidth: width))
        return table
    }

    static func model(_ name: String) async throws -> Entity {
        let url = Bundle.main.url(forResource: "\(name)_1k", withExtension: "usdc", subdirectory: "Models/\(name)")!
        return try await Entity(contentsOf: url)
    }

    static func surrounds(_ materials: Materials) -> Entity {
        let surrounds = Entity()
        let halfLength = Size.courtLength / 2
        let halfWidth = Size.courtWidth / 2
        var next = 0
        func run(from start: SIMD2<Float>, to end: SIMD2<Float>) {
            let span = simd_distance(start, end)
            let panels = Int((span / Size.surroundPanel).rounded(.up))
            let direction = (end - start) / span
            let length = span / Float(panels)
            for index in 0..<panels {
                let centre = start + direction * (Float(index) + 0.5) * length
                let advert = materials.adverts[next % materials.adverts.count]
                next += 1
                let panel = ModelEntity(
                    mesh: .generateBox(width: length - 0.03, height: Size.surroundHeight, depth: 0.04, cornerRadius: 0.004, splitFaces: true),
                    materials: [advert, materials.surround, advert, materials.surround, materials.surround, materials.surround]
                )
                panel.position = [centre.x, Size.surroundHeight / 2, centre.y]
                panel.orientation = simd_quatf(angle: atan2(-direction.y, direction.x), axis: [0, 1, 0])
                let rail = ModelEntity(mesh: .generateBox(width: length - 0.02, height: 0.03, depth: 0.06, cornerRadius: 0.006), materials: [materials.frame])
                rail.position.y = Size.surroundHeight / 2 + 0.015
                panel.addChild(rail)
                surrounds.addChild(panel)
            }
        }
        run(from: [-halfWidth, -halfLength], to: [halfWidth, -halfLength])
        run(from: [-halfWidth, halfLength], to: [halfWidth, halfLength])
        run(from: [-halfWidth, -halfLength], to: [-halfWidth, halfLength])
        run(from: [halfWidth, -halfLength], to: [halfWidth, halfLength])
        return surrounds
    }

    static func lightingRig(intensity: Float, height: Float, spots: [SIMD2<Float>]) -> Entity {
        let rig = Entity()
        for (index, spot) in spots.enumerated() {
            let light = SpotLight()
            light.light.color = Tone.lamp
            light.light.intensity = intensity
            light.light.innerAngleInDegrees = 30
            light.light.outerAngleInDegrees = 70
            light.light.attenuationRadius = height * 2.5
            if index == 0 {
                light.shadow = SpotLightComponent.Shadow()
            }
            light.position = [spot.x, height, spot.y]
            light.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            rig.addChild(light)
        }
        for end: Float in [-1, 1] {
            let fill = DirectionalLight()
            fill.light.color = Tone.lamp
            fill.light.intensity = Size.fillIntensity
            fill.look(at: .zero, from: [0.4 * end, 2.2, 6 * end], relativeTo: nil)
            rig.addChild(fill)
        }
        return rig
    }

    static func scoreStand(_ materials: Materials) -> (root: Entity, card: ModelEntity) {
        let root = Entity()
        let post = ModelEntity(mesh: .generateCylinder(height: 0.32, radius: 0.008), materials: [materials.iron])
        post.position.y = 0.16
        root.addChild(post)
        let card = ModelEntity(mesh: .generatePlane(width: 0.2, height: 0.25), materials: [UnlitMaterial(color: .black)])
        card.position.y = 0.42
        root.addChild(card)
        return (root, card)
    }

    private static func net(_ materials: Materials, tableWidth: Float) -> Entity {
        let net = Entity()
        let netWidth = tableWidth + 2 * Size.netOverhang
        let mesh = ModelEntity(mesh: .generatePlane(width: netWidth, height: Size.netHeight), materials: [materials.net])
        mesh.position.y = Size.tableHeight + Size.netHeight / 2
        net.addChild(mesh)

        var tapeMaterial = PhysicallyBasedMaterial()
        tapeMaterial.baseColor = .init(tint: Tone.celluloid)
        tapeMaterial.roughness = 0.8
        let tape = ModelEntity(mesh: .generateBox(width: netWidth, height: 0.015, depth: 0.004, cornerRadius: 0.001), materials: [tapeMaterial])
        tape.position.y = Size.tableHeight + Size.netHeight - 0.0075
        net.addChild(tape)

        for side: Float in [-1, 1] {
            let post = ModelEntity(mesh: .generateCylinder(height: Size.netHeight + 0.02, radius: 0.008), materials: [materials.iron])
            post.position = [side * netWidth / 2, Size.tableHeight + (Size.netHeight + 0.02) / 2 - 0.02, 0]
            let clamp = ModelEntity(mesh: .generateBox(width: Size.netOverhang + 0.03, height: 0.03, depth: 0.04, cornerRadius: 0.004), materials: [materials.iron])
            clamp.position = [side * (tableWidth / 2 + Size.netOverhang / 2 - 0.015), Size.tableHeight - 0.012, 0]
            net.addChild(post)
            net.addChild(clamp)
        }
        return net
    }

    static func paddle(_ materials: Materials, rubber color: NSColor) throws -> (root: Entity, pivot: Entity) {
        let root = Entity()
        let pivot = Entity()
        let grip = Size.grip
        pivot.position.y = -grip
        root.addChild(pivot)

        let blade = Entity()
        blade.position.y = grip
        pivot.addChild(blade)
        let outline = Geometry.bladeOutline(width: Size.bladeWidth, height: Size.bladeHeight)
        let size = SIMD2(Size.bladeWidth, Size.bladeHeight)
        let halfCore = Size.bladeThickness / 2
        let core = ModelEntity(mesh: try Geometry.bevelledSlab(outline: outline, bottom: -halfCore, top: halfCore, bevel: 0.0008, size: size), materials: [materials.blade])
        blade.addChild(core)

        let rubberOutline = outline.map { $0 * 0.985 }
        let sheet = try Geometry.bevelledSlab(outline: rubberOutline, bottom: halfCore, top: halfCore + Size.rubberThickness, bevel: 0.0004, size: size)
        let front = ModelEntity(mesh: sheet, materials: [materials.rubber(color)])
        front.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        let back = ModelEntity(mesh: sheet, materials: [materials.rubber(color)])
        blade.addChild(front)
        blade.addChild(back)
        let surface = halfCore + Size.rubberThickness + 0.0003
        for face: Float in [-1, 1] {
            let stamp = ModelEntity(mesh: .generatePlane(width: 0.06, height: 0.014), materials: [materials.stamp])
            stamp.position = [0, -Size.bladeHeight / 2 + 0.03, face * surface]
            stamp.orientation = simd_quatf(angle: face < 0 ? .pi : 0, axis: [0, 1, 0])
            blade.addChild(stamp)
            let cheek = ModelEntity(mesh: .generateBox(width: 0.034, height: 0.032, depth: 0.004, cornerRadius: 0.0015), materials: [materials.frame])
            cheek.position = [0, -Size.bladeHeight / 2 - 0.004, face * (halfCore + 0.002)]
            blade.addChild(cheek)
        }

        let handle = ModelEntity(
            mesh: try Geometry.loftedHandle(length: Size.handleLength) { t in
                let flare = t * t * t
                return [0.012 + 0.006 * flare, 0.0095 + 0.003 * flare]
            },
            materials: [materials.frame]
        )
        handle.position.y = grip - Size.bladeHeight / 2 + 0.012
        pivot.addChild(handle)
        return (root, pivot)
    }

    static func ghostBall() -> ModelEntity {
        var material = UnlitMaterial(color: Tone.celluloid)
        material.blending = .transparent(opacity: 1.0)
        let ghost = ModelEntity(mesh: .generateSphere(radius: Size.ballRadius), materials: [material])
        ghost.isEnabled = false
        return ghost
    }

    static func ball() -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: Tone.celluloid)
        material.roughness = 0.3
        material.clearcoat = 0.6
        material.clearcoatRoughness = 0.25
        return ModelEntity(mesh: .generateSphere(radius: Size.ballRadius), materials: [material])
    }
}
