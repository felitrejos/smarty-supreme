import AppKit
import FlickCore
import RealityKit

@MainActor
enum Equipment {
    enum Size {
        static let metresPerTableLength: Float = 2.74
        static let tableHeight: Float = 0.76
        static let topThickness: Float = 0.025
        static let netHeight: Float = 0.1525
        static let netOverhang: Float = 0.1525
        static let ballRadius: Float = 0.02
        static let bladeWidth: Float = 0.15
        static let bladeHeight: Float = 0.158
        static let bladeThickness: Float = 0.0058
        static let rubberThickness: Float = 0.0021
        static let handleLength: Float = 0.1
    }

    @MainActor
    struct Materials {
        let top: PhysicallyBasedMaterial
        let aluminium: PhysicallyBasedMaterial
        let graphite: PhysicallyBasedMaterial
        let wood: PhysicallyBasedMaterial
        let rubberNormal: TextureResource
        let net: PhysicallyBasedMaterial
        let shadow: UnlitMaterial
        let backdrop: UnlitMaterial

        static func make(tableWidth: Float) async throws -> Materials {
            async let topImage = Textures.tableTop(widthMetres: Double(tableWidth), seed: 7)
            async let woodImage = Textures.woodGrain(seed: 8)
            async let rubberImage = Textures.rubberGrain(seed: 9)
            async let netImage = Textures.netMesh(cellsAcross: 122, cellsDown: 10)
            async let shadowImage = Textures.softShadow()
            async let backdropImage = Textures.backdrop()

            var top = PhysicallyBasedMaterial()
            top.baseColor = .init(texture: .init(try await Textures.texture(await topImage, .color)))
            top.roughness = 0.58
            top.clearcoat = 0.12
            top.clearcoatRoughness = 0.4

            var aluminium = PhysicallyBasedMaterial()
            aluminium.baseColor = .init(tint: NSColor(white: 0.7, alpha: 1))
            aluminium.metallic = 1.0
            aluminium.roughness = 0.32

            var graphite = PhysicallyBasedMaterial()
            graphite.baseColor = .init(tint: NSColor(white: 0.13, alpha: 1))
            graphite.metallic = 0.85
            graphite.roughness = 0.35

            var wood = PhysicallyBasedMaterial()
            wood.baseColor = .init(texture: .init(try await Textures.texture(await woodImage, .color)))
            wood.roughness = 0.5
            wood.clearcoat = 0.4
            wood.clearcoatRoughness = 0.3

            var net = PhysicallyBasedMaterial()
            net.baseColor = .init(texture: .init(try await Textures.texture(await netImage, .color, mipmaps: false)))
            net.roughness = 0.9
            net.opacityThreshold = 0.5
            net.faceCulling = .none

            var shadow = UnlitMaterial()
            shadow.color = .init(tint: .white, texture: .init(try await Textures.texture(await shadowImage, .color)))
            shadow.blending = .transparent(opacity: 1.0)

            var backdrop = UnlitMaterial()
            backdrop.color = .init(tint: .white, texture: .init(try await Textures.texture(await backdropImage, .color)))

            return Materials(
                top: top,
                aluminium: aluminium,
                graphite: graphite,
                wood: wood,
                rubberNormal: try await Textures.texture(await rubberImage, .normal),
                net: net,
                shadow: shadow,
                backdrop: backdrop
            )
        }

        func rubber(_ color: NSColor) -> PhysicallyBasedMaterial {
            var rubber = PhysicallyBasedMaterial()
            rubber.baseColor = .init(tint: color)
            rubber.normal = .init(texture: .init(rubberNormal))
            rubber.roughness = 0.62
            rubber.clearcoat = 0.18
            rubber.clearcoatRoughness = 0.45
            return rubber
        }
    }

    static func backdrop(_ materials: Materials) -> Entity {
        let sphere = ModelEntity(mesh: .generateSphere(radius: 30), materials: [materials.backdrop])
        sphere.scale = [-1, 1, 1]
        return sphere
    }

    static func contactShadow(_ materials: Materials, width: Float) -> Entity {
        let shadow = ModelEntity(mesh: .generatePlane(width: width * 1.9, depth: Size.metresPerTableLength * 1.25), materials: [materials.shadow])
        shadow.position.y = 0.001
        return shadow
    }

    static func table(_ materials: Materials, width: Float) throws -> Entity {
        let table = Entity()
        let length = Size.metresPerTableLength
        let top = ModelEntity(
            mesh: .generateBox(width: width, height: Size.topThickness, depth: length, cornerRadius: 0.006, splitFaces: true),
            materials: [materials.graphite, materials.top, materials.graphite, materials.graphite, materials.graphite, materials.graphite]
        )
        top.position.y = Size.tableHeight - Size.topThickness / 2
        table.addChild(top)

        let underframe = ModelEntity(mesh: .generateBox(width: width - 0.12, height: 0.035, depth: length - 0.18, cornerRadius: 0.01), materials: [materials.graphite])
        underframe.position.y = Size.tableHeight - Size.topThickness - 0.0175
        table.addChild(underframe)

        let curve = (0...48).map { index -> SIMD2<Float> in
            let t = Float(index) / 48
            let start: SIMD2<Float> = [0.16, 0.02]
            let lift: SIMD2<Float> = [0.16, 0.5]
            let reach: SIMD2<Float> = [0.62, 0.70]
            let end: SIMD2<Float> = [1.02, Size.tableHeight - Size.topThickness - 0.035]
            let u = 1 - t
            return u * u * u * start + 3 * u * u * t * lift + 3 * u * t * t * reach + t * t * t * end
        }
        for side: Float in [1, -1] {
            let mirrored = curve.map { SIMD2($0.x * side, $0.y) }
            let blade = try Geometry.sweptBlade(along: mirrored, width: width - 0.42, thickness: 0.05)
            table.addChild(ModelEntity(mesh: blade, materials: [materials.aluminium]))
        }
        let plinth = ModelEntity(mesh: .generateBox(width: width - 0.36, height: 0.03, depth: 0.46, cornerRadius: 0.012), materials: [materials.aluminium])
        plinth.position.y = 0.015
        table.addChild(plinth)

        table.addChild(net(materials, tableWidth: width))
        return table
    }

    private static func net(_ materials: Materials, tableWidth: Float) -> Entity {
        let net = Entity()
        let netWidth = tableWidth + 2 * Size.netOverhang
        let mesh = ModelEntity(mesh: .generatePlane(width: netWidth, height: Size.netHeight), materials: [materials.net])
        mesh.position.y = Size.tableHeight + Size.netHeight / 2
        net.addChild(mesh)

        var tapeMaterial = PhysicallyBasedMaterial()
        tapeMaterial.baseColor = .init(tint: NSColor(white: 0.95, alpha: 1))
        tapeMaterial.roughness = 0.7
        let tape = ModelEntity(mesh: .generateBox(width: netWidth, height: 0.015, depth: 0.004, cornerRadius: 0.001), materials: [tapeMaterial])
        tape.position.y = Size.tableHeight + Size.netHeight - 0.0075
        net.addChild(tape)

        for side: Float in [-1, 1] {
            let post = ModelEntity(mesh: .generateCylinder(height: Size.netHeight + 0.02, radius: 0.009), materials: [materials.aluminium])
            post.position = [side * netWidth / 2, Size.tableHeight + (Size.netHeight + 0.02) / 2 - 0.02, 0]
            let clamp = ModelEntity(mesh: .generateBox(width: Size.netOverhang + 0.03, height: 0.03, depth: 0.04, cornerRadius: 0.008), materials: [materials.graphite])
            clamp.position = [side * (tableWidth / 2 + Size.netOverhang / 2 - 0.015), Size.tableHeight - 0.012, 0]
            net.addChild(post)
            net.addChild(clamp)
        }
        return net
    }

    static func paddle(_ materials: Materials, rubber color: NSColor) throws -> (root: Entity, pivot: Entity) {
        let root = Entity()
        let pivot = Entity()
        let grip: Float = 0.13
        pivot.position.y = -grip
        root.addChild(pivot)

        let blade = Entity()
        blade.position.y = grip
        pivot.addChild(blade)
        let outline = Geometry.bladeOutline(width: Size.bladeWidth, height: Size.bladeHeight)
        let size = SIMD2(Size.bladeWidth, Size.bladeHeight)
        let halfCore = Size.bladeThickness / 2
        let core = ModelEntity(mesh: try Geometry.bevelledSlab(outline: outline, bottom: -halfCore, top: halfCore, bevel: 0.0006, size: size), materials: [materials.wood])
        blade.addChild(core)

        let rubberOutline = outline.map { $0 * 0.992 }
        let sheet = try Geometry.bevelledSlab(outline: rubberOutline, bottom: halfCore, top: halfCore + Size.rubberThickness, bevel: 0.0012, size: size)
        let front = ModelEntity(mesh: sheet, materials: [materials.rubber(color)])
        front.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        let back = ModelEntity(mesh: sheet, materials: [materials.rubber(NSColor(white: 0.07, alpha: 1))])
        blade.addChild(front)
        blade.addChild(back)

        let handle = ModelEntity(
            mesh: try Geometry.loftedHandle(length: Size.handleLength) { t in
                let flare = t * t
                return [0.0125 + 0.0045 * flare, 0.0105 + 0.0025 * flare]
            },
            materials: [materials.wood]
        )
        handle.position.y = grip - Size.bladeHeight / 2 + 0.012
        pivot.addChild(handle)
        return (root, pivot)
    }

    static func ball() -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: NSColor(white: 0.97, alpha: 1))
        material.roughness = 0.38
        material.clearcoat = 0.5
        material.clearcoatRoughness = 0.3
        return ModelEntity(mesh: .generateSphere(radius: Size.ballRadius), materials: [material])
    }
}
