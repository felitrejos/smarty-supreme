import CoreGraphics
import FlickCore
import RealityKit

enum Textures {
    private struct Canvas {
        let context: CGContext
        let width: Int
        let height: Int

        init(width: Int, height: Int, colorSpace: CFString = CGColorSpace.sRGB) {
            self.width = width
            self.height = height
            context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: colorSpace)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
        }

        var image: CGImage {
            context.makeImage()!
        }
    }

    private static let neighbours = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]

    @MainActor
    static func texture(_ image: CGImage, _ semantic: TextureResource.Semantic, mipmaps: Bool = true) async throws -> TextureResource {
        try await TextureResource(image: image, withName: nil, options: .init(semantic: semantic, mipmapsMode: mipmaps ? .allocateAndGenerateAll : .none))
    }

    @concurrent
    static func tableTop(widthMetres: Double, seed: UInt64) async -> CGImage {
        var random = SplitMix64(seed: seed)
        let canvas = Canvas(width: 1536, height: 2760)
        let context = canvas.context
        context.setFillColor(red: 0.075, green: 0.12, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        for _ in 0..<90_000 {
            let lighter = Bool.random(using: &random)
            context.setFillColor(gray: lighter ? 1 : 0, alpha: lighter ? 0.025 : 0.05)
            context.fill(CGRect(x: Double.random(in: 0..<Double(canvas.width), using: &random), y: Double.random(in: 0..<Double(canvas.height), using: &random), width: 2, height: 2))
        }
        let pixelsPerMetre = Double(canvas.width) / widthMetres
        let edge = 0.02 * pixelsPerMetre
        let centre = 0.003 * pixelsPerMetre
        context.setFillColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: Double(canvas.width), height: edge))
        context.fill(CGRect(x: 0, y: Double(canvas.height) - edge, width: Double(canvas.width), height: edge))
        context.fill(CGRect(x: 0, y: 0, width: edge, height: Double(canvas.height)))
        context.fill(CGRect(x: Double(canvas.width) - edge, y: 0, width: edge, height: Double(canvas.height)))
        context.fill(CGRect(x: (Double(canvas.width) - centre) / 2, y: 0, width: centre, height: Double(canvas.height)))
        return canvas.image
    }

    @concurrent
    static func woodGrain(seed: UInt64) async -> CGImage {
        var random = SplitMix64(seed: seed)
        let canvas = Canvas(width: 1024, height: 1024)
        let context = canvas.context
        context.setFillColor(red: 0.80, green: 0.64, blue: 0.45, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        for _ in 0..<260 {
            let x = Double.random(in: 0..<Double(canvas.width), using: &random)
            let amplitude = Double.random(in: 3...18, using: &random)
            let frequency = Double.random(in: 0.003...0.012, using: &random)
            let phase = Double.random(in: 0...(2 * .pi), using: &random)
            let darker = Bool.random(using: &random)
            context.setStrokeColor(red: darker ? 0.55 : 0.88, green: darker ? 0.40 : 0.72, blue: darker ? 0.26 : 0.52, alpha: Double.random(in: 0.15...0.45, using: &random))
            context.setLineWidth(Double.random(in: 0.8...4, using: &random))
            context.move(to: CGPoint(x: x, y: 0))
            for y in stride(from: 0.0, through: Double(canvas.height), by: 8) {
                context.addLine(to: CGPoint(x: x + sin(y * frequency + phase) * amplitude, y: y))
            }
            context.strokePath()
        }
        return canvas.image
    }

    @concurrent
    static func rubberGrain(seed: UInt64) async -> CGImage {
        var random = SplitMix64(seed: seed)
        let size = 512
        var heights = (0..<size * size).map { _ in Float.random(in: 0...1, using: &random) }
        for _ in 0..<2 {
            var blurred = heights
            for row in 0..<size {
                for column in 0..<size {
                    var total: Float = 0
                    for (across, down) in neighbours {
                        total += heights[((row + down + size) % size) * size + (column + across + size) % size]
                    }
                    blurred[row * size + column] = total / Float(neighbours.count)
                }
            }
            heights = blurred
        }
        let canvas = Canvas(width: size, height: size, colorSpace: CGColorSpace.linearSRGB)
        let bytesPerRow = canvas.context.bytesPerRow
        let pixels = canvas.context.data!.bindMemory(to: UInt8.self, capacity: size * bytesPerRow)
        let strength: Float = 6
        for row in 0..<size {
            for column in 0..<size {
                let slopeAcross = heights[row * size + (column + 1) % size] - heights[row * size + (column + size - 1) % size]
                let slopeDown = heights[((row + 1) % size) * size + column] - heights[((row + size - 1) % size) * size + column]
                let normal = simd_normalize(SIMD3<Float>(-slopeAcross * strength, slopeDown * strength, 1))
                let offset = row * bytesPerRow + column * 4
                pixels[offset] = UInt8((normal.x * 0.5 + 0.5) * 255)
                pixels[offset + 1] = UInt8((normal.y * 0.5 + 0.5) * 255)
                pixels[offset + 2] = UInt8((normal.z * 0.5 + 0.5) * 255)
                pixels[offset + 3] = 255
            }
        }
        return canvas.image
    }

    @concurrent
    static func netMesh(cellsAcross: Int, cellsDown: Int) async -> CGImage {
        let cell = 18
        let line = 2
        let canvas = Canvas(width: cellsAcross * cell + line, height: cellsDown * cell + line)
        let context = canvas.context
        context.clear(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        context.setFillColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
        for column in 0...cellsAcross {
            context.fill(CGRect(x: column * cell, y: 0, width: line, height: canvas.height))
        }
        for row in 0...cellsDown {
            context.fill(CGRect(x: 0, y: row * cell, width: canvas.width, height: line))
        }
        return canvas.image
    }

    @concurrent
    static func softShadow() async -> CGImage {
        let canvas = Canvas(width: 512, height: 512)
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [CGColor(gray: 0, alpha: 0.55), CGColor(gray: 0, alpha: 0.18), CGColor(gray: 0, alpha: 0)] as CFArray,
            locations: [0, 0.45, 1]
        )!
        canvas.context.drawRadialGradient(gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0, endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [])
        return canvas.image
    }

    @concurrent
    static func backdrop() async -> CGImage {
        let canvas = Canvas(width: 8, height: 1024)
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [
                CGColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1),
                CGColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1),
                CGColor(red: 0.30, green: 0.30, blue: 0.31, alpha: 1),
                CGColor(red: 0.12, green: 0.12, blue: 0.125, alpha: 1),
            ] as CFArray,
            locations: [0, 0.42, 0.5, 0.62]
        )!
        canvas.context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [.drawsAfterEndLocation])
        return canvas.image
    }
}
