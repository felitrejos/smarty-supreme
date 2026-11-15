import RealityKit
import simd

@MainActor
struct MeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var coordinates: [SIMD2<Float>] = []
    private var indices: [UInt32] = []

    mutating func vertex(_ position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>) -> UInt32 {
        positions.append(position)
        normals.append(simd_normalize(normal))
        coordinates.append(uv)
        return UInt32(positions.count - 1)
    }

    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        let facing = normals[Int(a)] + normals[Int(b)] + normals[Int(c)]
        let winding = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
        indices += simd_dot(winding, facing) >= 0 ? [a, b, c] : [a, c, b]
    }

    mutating func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) {
        triangle(a, b, c)
        triangle(a, c, d)
    }

    func mesh(named name: String) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(coordinates)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

@MainActor
enum Geometry {
    private struct CurveFrame {
        let point: SIMD2<Float>
        let tangent: SIMD2<Float>

        var normal: SIMD2<Float> {
            SIMD2(-tangent.y, tangent.x)
        }

        func position(x: Float, offset: Float) -> SIMD3<Float> {
            let shifted = point + normal * offset
            return [x, shifted.y, shifted.x]
        }

        func normal3(sign: Float) -> SIMD3<Float> {
            let facing = normal * sign
            return [0, facing.y, facing.x]
        }
    }

    private static let handleSquareness: Float = 0.7
    private static let handleSections = 28
    private static let handleSegments = 40
    private static let bladeOutlinePoints = 120
    private static let bladeSquareness: Float = 2.35

    static func sweptBlade(along curve: [SIMD2<Float>], width: Float, thickness: Float) throws -> MeshResource {
        var builder = MeshBuilder()
        let frames = curve.indices.map { index in
            let previous = curve[max(index - 1, 0)]
            let next = curve[min(index + 1, curve.count - 1)]
            return CurveFrame(point: curve[index], tangent: simd_normalize(next - previous))
        }
        let halfWidth = width / 2
        let halfThickness = thickness / 2
        for index in frames.indices.dropLast() {
            let frame = frames[index]
            let nextFrame = frames[index + 1]
            let startV = Float(index) / Float(frames.count - 1)
            let endV = Float(index + 1) / Float(frames.count - 1)
            for sign: Float in [1, -1] {
                let offset = sign * halfThickness
                let a = builder.vertex(frame.position(x: -halfWidth, offset: offset), normal: frame.normal3(sign: sign), uv: [0, startV])
                let b = builder.vertex(frame.position(x: halfWidth, offset: offset), normal: frame.normal3(sign: sign), uv: [1, startV])
                let c = builder.vertex(nextFrame.position(x: halfWidth, offset: offset), normal: nextFrame.normal3(sign: sign), uv: [1, endV])
                let d = builder.vertex(nextFrame.position(x: -halfWidth, offset: offset), normal: nextFrame.normal3(sign: sign), uv: [0, endV])
                builder.quad(a, b, c, d)
            }
            for side: Float in [-1, 1] {
                let outward: SIMD3<Float> = [side, 0, 0]
                let a = builder.vertex(frame.position(x: side * halfWidth, offset: halfThickness), normal: outward, uv: [0, startV])
                let b = builder.vertex(frame.position(x: side * halfWidth, offset: -halfThickness), normal: outward, uv: [1, startV])
                let c = builder.vertex(nextFrame.position(x: side * halfWidth, offset: -halfThickness), normal: outward, uv: [1, endV])
                let d = builder.vertex(nextFrame.position(x: side * halfWidth, offset: halfThickness), normal: outward, uv: [0, endV])
                builder.quad(a, b, c, d)
            }
        }
        for (frame, sign) in [(frames[0], Float(-1)), (frames[frames.count - 1], Float(1))] {
            let outward: SIMD3<Float> = [0, frame.tangent.y * sign, frame.tangent.x * sign]
            let corners = [(-halfWidth, halfThickness), (halfWidth, halfThickness), (halfWidth, -halfThickness), (-halfWidth, -halfThickness)]
                .map { builder.vertex(frame.position(x: $0.0, offset: $0.1), normal: outward, uv: [0, 0]) }
            builder.quad(corners[0], corners[1], corners[2], corners[3])
        }
        return try builder.mesh(named: "blade")
    }

    static func bevelledSlab(outline: [SIMD2<Float>], bottom: Float, top: Float, bevel: Float, size: SIMD2<Float>) throws -> MeshResource {
        var builder = MeshBuilder()
        let centre = outline.reduce(SIMD2<Float>(repeating: 0), +) / Float(outline.count)
        func inset(_ point: SIMD2<Float>, by amount: Float) -> SIMD2<Float> {
            let direction = point - centre
            let length = simd_length(direction)
            return centre + direction * ((length - amount) / length)
        }
        func uv(_ point: SIMD2<Float>) -> SIMD2<Float> {
            (point / size) + 0.5
        }
        for (z, faceNormal, shrink) in [(top, Float(1), bevel), (bottom, Float(-1), Float(0))] {
            let middle = builder.vertex([centre.x, centre.y, z], normal: [0, 0, faceNormal], uv: uv(centre))
            let ring = outline.map { point in
                let inner = inset(point, by: shrink)
                return builder.vertex([inner.x, inner.y, z], normal: [0, 0, faceNormal], uv: uv(inner))
            }
            for index in ring.indices {
                builder.triangle(middle, ring[index], ring[(index + 1) % ring.count])
            }
        }
        for index in outline.indices {
            let point = outline[index]
            let next = outline[(index + 1) % outline.count]
            let side = simd_normalize(SIMD3(next.y - point.y, point.x - next.x, 0))
            let startU = Float(index) / Float(outline.count)
            let endU = Float(index + 1) / Float(outline.count)
            let lowerStart = builder.vertex([point.x, point.y, bottom], normal: side, uv: [startU, 0])
            let lowerEnd = builder.vertex([next.x, next.y, bottom], normal: side, uv: [endU, 0])
            let upperEnd = builder.vertex([next.x, next.y, top - bevel], normal: side, uv: [endU, 1])
            let upperStart = builder.vertex([point.x, point.y, top - bevel], normal: side, uv: [startU, 1])
            builder.quad(lowerStart, lowerEnd, upperEnd, upperStart)
            let rounded = simd_normalize(side + SIMD3<Float>(0, 0, 1))
            let innerPoint = inset(point, by: bevel)
            let innerNext = inset(next, by: bevel)
            let edgeStart = builder.vertex([point.x, point.y, top - bevel], normal: rounded, uv: uv(point))
            let edgeEnd = builder.vertex([next.x, next.y, top - bevel], normal: rounded, uv: uv(next))
            let capEnd = builder.vertex([innerNext.x, innerNext.y, top], normal: rounded, uv: uv(innerNext))
            let capStart = builder.vertex([innerPoint.x, innerPoint.y, top], normal: rounded, uv: uv(innerPoint))
            builder.quad(edgeStart, edgeEnd, capEnd, capStart)
        }
        return try builder.mesh(named: "slab")
    }

    static func loftedHandle(length: Float, radius: (Float) -> SIMD2<Float>) throws -> MeshResource {
        var builder = MeshBuilder()
        let segments = handleSegments
        let rings = (0...handleSections).map { section -> [UInt32] in
            let t = Float(section) / Float(handleSections)
            let size = radius(t)
            return (0...segments).map { segment in
                let (point, normal) = superellipse(angle: Float(segment) / Float(segments) * 2 * .pi, size: size)
                return builder.vertex([point.x, -t * length, point.y], normal: [normal.x, 0, normal.y], uv: [Float(segment) / Float(segments), t])
            }
        }
        for section in 0..<handleSections {
            for segment in 0..<segments {
                builder.quad(rings[section][segment], rings[section][segment + 1], rings[section + 1][segment + 1], rings[section + 1][segment])
            }
        }
        for (t, faceNormal) in [(Float(0), Float(1)), (Float(1), Float(-1))] {
            let y = -t * length
            let size = radius(t)
            let centre = builder.vertex([0, y, 0], normal: [0, faceNormal, 0], uv: [0.5, t])
            let ring = (0..<segments).map { segment in
                let point = superellipse(angle: Float(segment) / Float(segments) * 2 * .pi, size: size).point
                return builder.vertex([point.x, y, point.y], normal: [0, faceNormal, 0], uv: [0.5, t])
            }
            for index in ring.indices {
                builder.triangle(centre, ring[index], ring[(index + 1) % ring.count])
            }
        }
        return try builder.mesh(named: "handle")
    }

    static func bladeOutline(width: Float, height: Float) -> [SIMD2<Float>] {
        (0..<bladeOutlinePoints).map { index in
            let angle = Float(index) / Float(bladeOutlinePoints) * 2 * .pi
            let cosine = cos(angle)
            let sine = sin(angle)
            let x = width / 2 * copysign(pow(abs(cosine), 2 / bladeSquareness), cosine)
            let y = height / 2 * copysign(pow(abs(sine), 2 / bladeSquareness), sine)
            return [x, y]
        }
    }

    private static func superellipse(angle: Float, size: SIMD2<Float>) -> (point: SIMD2<Float>, normal: SIMD2<Float>) {
        let cosine = cos(angle)
        let sine = sin(angle)
        let point = SIMD2(
            size.x * copysign(pow(abs(cosine), handleSquareness), cosine),
            size.y * copysign(pow(abs(sine), handleSquareness), sine)
        )
        let gradient = SIMD2(
            copysign(pow(abs(cosine), 1 - handleSquareness), cosine) / size.x,
            copysign(pow(abs(sine), 1 - handleSquareness), sine) / size.y
        )
        return (point, simd_normalize(gradient))
    }
}
