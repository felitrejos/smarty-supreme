import CoreImage
import RealityKit

@MainActor
struct Hall {
    private static let lightExponent: Float = -1.7
    private static let backgroundYaw: Float = .pi / 2
    private nonisolated static let backgroundExposure: Float = 0.3
    private nonisolated static let backgroundBlur = 10.0

    let light: Entity
    let background: Entity

    static func load() async throws -> Hall {
        let url = Bundle.main.url(forResource: "circus_arena_4k", withExtension: "hdr")!
        let photo = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])!
        let (sharp, soft) = await render(photo)
        let environment = try await EnvironmentResource(equirectangular: sharp, withName: "arena")
        let light = Entity()
        light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: lightExponent))

        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(try await TextureResource(image: soft, withName: "hallBackground", options: .init(semantic: .color))))
        let background = ModelEntity(mesh: .generateSphere(radius: 30), materials: [material])
        background.scale = [-1, 1, 1]
        background.orientation = simd_quatf(angle: backgroundYaw, axis: [0, 1, 0])
        return Hall(light: light, background: background)
    }

    @concurrent
    private static func render(_ photo: CIImage) async -> (sharp: CGImage, soft: CGImage) {
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
        let extent = photo.extent
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let warm = photo
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.4])
            .applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 3600, y: 0)])
        let sharp = context.createCGImage(warm, from: extent, format: .RGBAh, colorSpace: space)!

        let graded = photo
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.35, kCIInputContrastKey: 1.1])
            .applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 3600, y: 0)])
        let blurred = graded.clampedToExtent().applyingGaussianBlur(sigma: backgroundBlur).cropped(to: extent)
        let darker = blurred.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: backgroundExposure])
        let faded = darker.oriented(.downMirrored)
        let soft = context.createCGImage(faded, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        return (sharp, soft)
    }
}
