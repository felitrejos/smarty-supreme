import AppKit
import CoreGraphics
import CoreText
import Foundation
import SmartyCore
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

    @MainActor
    static func surface(_ name: String, repeats: Float = 1) async throws -> PhysicallyBasedMaterial {
        func load(_ kind: String, _ semantic: TextureResource.Semantic) async throws -> TextureResource {
            let url = Bundle.main.url(forResource: kind, withExtension: "jpg", subdirectory: "Textures/\(name)")!
            return try await TextureResource(contentsOf: url, options: .init(semantic: semantic))
        }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(texture: .init(try await load("Diffuse", .color)))
        material.roughness = .init(texture: .init(try await load("Rough", .raw)))
        material.normal = .init(texture: .init(try await load("nor_gl", .normal)))
        material.textureCoordinateTransform = .init(scale: [repeats, repeats])
        return material
    }

    @MainActor
    static func texture(_ image: CGImage, _ semantic: TextureResource.Semantic, mipmaps: Bool = true) async throws -> TextureResource {
        try await TextureResource(image: image, withName: nil, options: .init(semantic: semantic, mipmapsMode: mipmaps ? .allocateAndGenerateAll : .none))
    }

    @concurrent
    static func tableTop(widthMetres: Double, seed: UInt64) async -> CGImage {
        var random = SplitMix64(seed: seed)
        let canvas = Canvas(width: 1536, height: 2760)
        let context = canvas.context
        context.setFillColor(red: 0.04, green: 0.4, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        for _ in 0..<90_000 {
            let lighter = Bool.random(using: &random)
            context.setFillColor(gray: lighter ? 1 : 0, alpha: lighter ? 0.025 : 0.05)
            context.fill(CGRect(x: Double.random(in: 0..<Double(canvas.width), using: &random), y: Double.random(in: 0..<Double(canvas.height), using: &random), width: 2, height: 2))
        }
        let pixelsPerMetre = Double(canvas.width) / widthMetres
        let edge = 0.02 * pixelsPerMetre
        let centre = 0.003 * pixelsPerMetre
        context.setFillColor(red: 0.93, green: 0.91, blue: 0.84, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: Double(canvas.width), height: edge))
        context.fill(CGRect(x: 0, y: Double(canvas.height) - edge, width: Double(canvas.width), height: edge))
        context.fill(CGRect(x: 0, y: 0, width: edge, height: Double(canvas.height)))
        context.fill(CGRect(x: Double(canvas.width) - edge, y: 0, width: edge, height: Double(canvas.height)))
        context.fill(CGRect(x: (Double(canvas.width) - centre) / 2, y: 0, width: centre, height: Double(canvas.height)))
        return canvas.image
    }

    @concurrent
    static func pimpledRubber() async -> CGImage {
        let size = 512
        let pips = 16
        let spacing = Float(size) / Float(pips)
        let radius = spacing * 0.36
        let canvas = Canvas(width: size, height: size, colorSpace: CGColorSpace.linearSRGB)
        let bytesPerRow = canvas.context.bytesPerRow
        let pixels = canvas.context.data!.bindMemory(to: UInt8.self, capacity: size * bytesPerRow)
        for row in 0..<size {
            for column in 0..<size {
                let lane = Int(Float(row) / spacing)
                let shift = lane.isMultiple(of: 2) ? 0 : spacing / 2
                let x = (Float(column) + shift).truncatingRemainder(dividingBy: spacing) - spacing / 2
                let y = Float(row).truncatingRemainder(dividingBy: spacing) - spacing / 2
                let distance = (x * x + y * y).squareRoot()
                var normal = SIMD3<Float>(0, 0, 1)
                if distance < radius, distance > radius * 0.55 {
                    let slope = (distance - radius * 0.55) / (radius * 0.45)
                    normal = simd_normalize(SIMD3(x / distance * slope * 1.6, -y / distance * slope * 1.6, 1))
                }
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
    static func filmGrain(seed: UInt64) async -> CGImage {
        var random = SplitMix64(seed: seed)
        let size = 256
        let canvas = Canvas(width: size, height: size)
        let bytesPerRow = canvas.context.bytesPerRow
        let pixels = canvas.context.data!.bindMemory(to: UInt8.self, capacity: size * bytesPerRow)
        for row in 0..<size {
            for column in 0..<size {
                let value = UInt8.random(in: 0...255, using: &random)
                let offset = row * bytesPerRow + column * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
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
    static func floorFog() async -> CGImage {
        let canvas = Canvas(width: 512, height: 512)
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1)] as CFArray,
            locations: [0, 0.4, 1]
        )!
        canvas.context.drawRadialGradient(gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0, endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [.drawsAfterEndLocation])
        return canvas.image
    }

    @concurrent
    static func scoreCard(_ number: Int) async -> CGImage {
        let canvas = Canvas(width: 256, height: 320)
        let context = canvas.context
        context.setFillColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 320))
        context.setFillColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        context.fill(CGRect(x: 0, y: 158, width: 256, height: 4))
        let text = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont(name: "Futura-CondensedExtraBold", size: 230) ?? NSFont.boldSystemFont(ofSize: 230),
            .foregroundColor: NSColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: (256 - bounds.width) / 2 - bounds.minX, y: (320 - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, context)
        return canvas.image
    }

    struct Advert: Sendable {
        let words: String
        let font: String
        let board: (Double, Double, Double)
        let ink: (Double, Double, Double)
    }

    @concurrent
    static func advert(_ advert: Advert) async -> CGImage {
        let canvas = Canvas(width: 1024, height: 360)
        let context = canvas.context
        context.setFillColor(red: advert.board.0, green: advert.board.1, blue: advert.board.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 360))
        context.setStrokeColor(red: advert.ink.0, green: advert.ink.1, blue: advert.ink.2, alpha: 0.85)
        context.setLineWidth(6)
        context.stroke(CGRect(x: 22, y: 22, width: 980, height: 316))
        let ink = NSColor(red: advert.ink.0, green: advert.ink.1, blue: advert.ink.2, alpha: 1)
        var size: CGFloat = 170
        var line: CTLine
        repeat {
            let text = NSAttributedString(string: advert.words, attributes: [
                .font: NSFont(name: advert.font, size: size) ?? NSFont.boldSystemFont(ofSize: size),
                .foregroundColor: ink,
                .kern: size * 0.06,
            ])
            line = CTLineCreateWithAttributedString(text)
            size -= 6
        } while CTLineGetImageBounds(line, context).width > 900
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: (1024 - bounds.width) / 2 - bounds.minX, y: (360 - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, context)
        return canvas.image
    }

    @concurrent
    static func rubberWear(seed: UInt64) async -> CGImage {
        var random = SplitMix64(seed: seed)
        let canvas = Canvas(width: 512, height: 512)
        let context = canvas.context
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        for _ in 0..<26 {
            let radius = Double.random(in: 30...120, using: &random)
            let centre = CGPoint(x: Double.random(in: 0..<512, using: &random), y: Double.random(in: 0..<512, using: &random))
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                colors: [CGColor(gray: 0.55, alpha: Double.random(in: 0.25...0.6, using: &random)), CGColor(gray: 0.55, alpha: 0)] as CFArray,
                locations: [0, 1]
            )!
            context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
        }
        for _ in 0..<30_000 {
            context.setFillColor(gray: Double.random(in: 0.7...1, using: &random), alpha: 0.35)
            context.fill(CGRect(x: Double.random(in: 0..<512, using: &random), y: Double.random(in: 0..<512, using: &random), width: 1.5, height: 1.5))
        }
        return canvas.image
    }

    @concurrent
    static func makersStamp() async -> CGImage {
        let canvas = Canvas(width: 512, height: 120)
        let context = canvas.context
        context.clear(CGRect(x: 0, y: 0, width: 512, height: 120))
        let text = NSAttributedString(string: "SMARTY · HARDBAT", attributes: [
            .font: NSFont(name: "Futura-Bold", size: 64) ?? NSFont.boldSystemFont(ofSize: 64),
            .foregroundColor: NSColor(red: 0.86, green: 0.71, blue: 0.42, alpha: 1),
            .kern: 6,
        ])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: (512 - bounds.width) / 2 - bounds.minX, y: (120 - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, context)
        return canvas.image
    }

    @concurrent
    static func celluloidBall() async -> CGImage {
        var random = SplitMix64(seed: 38)
        let canvas = Canvas(width: 1024, height: 512)
        let context = canvas.context
        context.setFillColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        for _ in 0..<40 {
            let centre = CGPoint(x: Double.random(in: 0..<1024, using: &random), y: Double.random(in: 0..<512, using: &random))
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                colors: [CGColor(red: 0.9, green: 0.86, blue: 0.76, alpha: 0.18), CGColor(red: 0.9, green: 0.86, blue: 0.76, alpha: 0)] as CFArray,
                locations: [0, 1]
            )!
            context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: Double.random(in: 30...110, using: &random), options: [])
        }
        context.setFillColor(red: 0.78, green: 0.74, blue: 0.64, alpha: 1)
        context.fill(CGRect(x: 0, y: 254, width: 1024, height: 3))
        context.setFillColor(red: 1, green: 0.99, blue: 0.95, alpha: 0.9)
        context.fill(CGRect(x: 0, y: 257, width: 1024, height: 1.5))
        let ink = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.9)
        func stamp(_ words: String, size: CGFloat, kern: CGFloat, centre: CGPoint) {
            let text = NSAttributedString(string: words, attributes: [
                .font: NSFont(name: "Futura-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size),
                .foregroundColor: ink,
                .kern: kern,
            ])
            let line = CTLineCreateWithAttributedString(text)
            context.textPosition = .zero
            let bounds = CTLineGetImageBounds(line, context)
            context.textPosition = CGPoint(x: centre.x - bounds.width / 2 - bounds.minX, y: centre.y - bounds.height / 2 - bounds.minY)
            CTLineDraw(line, context)
        }
        stamp("SMARTY", size: 30, kern: 3, centre: CGPoint(x: 256, y: 318))
        stamp("★★★", size: 24, kern: 4, centre: CGPoint(x: 256, y: 288))
        stamp("★★★", size: 24, kern: 4, centre: CGPoint(x: 768, y: 226))
        return canvas.image
    }

    @concurrent
    static func contactRing() async -> CGImage {
        let canvas = Canvas(width: 256, height: 256)
        let context = canvas.context
        context.clear(CGRect(x: 0, y: 0, width: 256, height: 256))
        context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.setLineWidth(9)
        context.strokeEllipse(in: CGRect(x: 14, y: 14, width: 228, height: 228))
        context.setLineWidth(3)
        context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.5)
        context.strokeEllipse(in: CGRect(x: 104, y: 104, width: 48, height: 48))
        return canvas.image
    }
}
