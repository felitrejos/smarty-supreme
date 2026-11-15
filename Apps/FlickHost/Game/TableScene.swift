import AppKit
import FlickCore
import ImageIO
import RealityKit

@MainActor
final class TableScene {
    private typealias Size = Equipment.Size

    private enum Arc {
        static let paddleHeight: Float = 0.17
        static let firstApex: Float = 0.24
        static let secondApex: Float = 0.12
        static let bounceAt: Float = 0.7
    }

    private static let swingDuration: TimeInterval = 0.22
    private static let swingTilt: Float = 0.95
    private static let paddleBehindFace: Float = 0.03

    let root = Entity()
    private let camera = PerspectiveCamera()
    private let ball = Equipment.ball()
    private var paddles: [(side: Side, root: Entity, pivot: Entity)] = []
    private var swingElapsed: [Side: TimeInterval] = [:]
    private let config: GameConfig

    init(config: GameConfig) async throws {
        self.config = config
        let width = Float(config.tableWidth) * Size.metresPerTableLength
        let materials = try await Equipment.Materials.make(tableWidth: width)
        let studio = try await Self.studioLight()

        root.addChild(Equipment.backdrop(materials))
        let lit = Entity()
        lit.addChild(Equipment.contactShadow(materials, width: width))
        lit.addChild(try Equipment.table(materials, width: width))
        lit.addChild(ball)
        for side in Side.allCases {
            let paddle = try Equipment.paddle(materials, rubber: side.rubberNSColor)
            if side == .playerB {
                paddle.root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            }
            lit.addChild(paddle.root)
            paddles.append((side, paddle.root, paddle.pivot))
        }
        root.addChild(studio)
        root.addChild(lit)
        Self.receiveLight(from: studio, in: lit)
        root.addChild(Self.keyLight())
        camera.camera.fieldOfViewInDegrees = 34
        root.addChild(camera)
        show(.playerAEnd, animated: false)
    }

    func show(_ view: CameraView, animated: Bool) {
        let placement = Entity()
        let (position, target) = Self.placement(for: view)
        placement.look(at: target, from: position, relativeTo: nil)
        if animated {
            camera.move(to: placement.transform, relativeTo: nil, duration: 1.1, timingFunction: .easeInOut)
        } else {
            camera.transform = placement.transform
        }
    }

    func update(from game: GameState, events: [GameEvent], elapsed: TimeInterval) {
        for event in events {
            switch event {
            case .hit(let side, _, _), .whiff(let side), .served(let side):
                swingElapsed[side] = 0
            default:
                break
            }
        }
        for paddle in paddles {
            let side = paddle.side
            let behind = side == .playerA ? Self.paddleBehindFace : -Self.paddleBehindFace
            paddle.root.position = [sceneX(game.paddleX(of: side)), Size.tableHeight + Arc.paddleHeight, sceneZ(config.paddleFaceY(of: side)) + behind]
            paddle.pivot.orientation = simd_quatf(angle: -Self.swingTilt * swingProgress(side, elapsed: elapsed), axis: [1, 0, 0])
        }
        let position = game.ball.position
        ball.position = [sceneX(position.x), Size.tableHeight + ballHeight(in: game), sceneZ(position.y)]
    }

    private func swingProgress(_ side: Side, elapsed: TimeInterval) -> Float {
        guard let swing = swingElapsed[side] else { return 0 }
        let advanced = swing + elapsed
        guard advanced < Self.swingDuration else {
            swingElapsed[side] = nil
            return 0
        }
        swingElapsed[side] = advanced
        return Float(sin(.pi * advanced / Self.swingDuration))
    }

    private func ballHeight(in game: GameState) -> Float {
        guard case .rally = game.phase else { return Arc.paddleHeight }
        let receiver = game.ball.velocity.y > 0 ? Side.playerB : Side.playerA
        let start = game.shotStart.y
        let end = config.paddleFaceY(of: receiver)
        let progress = Float(min(max((game.ball.position.y - start) / (end - start), 0), 1.3))
        if progress < Arc.bounceAt {
            let u = progress / Arc.bounceAt
            return Arc.paddleHeight * (1 - u) + Size.ballRadius * u + Arc.firstApex * 4 * u * (1 - u)
        }
        let v = (progress - Arc.bounceAt) / (1 - Arc.bounceAt)
        return Size.ballRadius * (1 - v) + Arc.paddleHeight * v + Arc.secondApex * 4 * v * (1 - v)
    }

    private func sceneX(_ x: Double) -> Float {
        Float(x - config.tableWidth / 2) * Size.metresPerTableLength
    }

    private func sceneZ(_ y: Double) -> Float {
        Float(config.tableLength / 2 - y) * Size.metresPerTableLength
    }

    private static func placement(for view: CameraView) -> (SIMD3<Float>, SIMD3<Float>) {
        switch view {
        case .playerAEnd: ([0, 1.9, 3.2], [0, 0.62, -0.25])
        case .playerBEnd: ([0, 1.9, -3.2], [0, 0.62, 0.25])
        case .side: ([3.9, 2.3, 0], [0, 0.55, 0])
        }
    }

    private static func studioLight() async throws -> Entity {
        let url = Bundle.main.url(forResource: "studio_small_09_2k", withExtension: "hdr")!
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldAllowFloat: true] as CFDictionary)!
        let environment = try await EnvironmentResource(equirectangular: image, withName: "studio")
        let light = Entity()
        light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: -0.4))
        light.orientation = simd_quatf(angle: .pi * 0.15, axis: [0, 1, 0])
        return light
    }

    private static func receiveLight(from light: Entity, in entity: Entity) {
        if entity is ModelEntity {
            entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        }
        for child in entity.children {
            receiveLight(from: light, in: child)
        }
    }

    private static func keyLight() -> Entity {
        let light = DirectionalLight()
        light.light.intensity = 1600
        light.shadow = DirectionalLightComponent.Shadow(maximumDistance: 7, depthBias: 1.5)
        light.look(at: [0, 0, 0], from: [0.8, 6, 1.2], relativeTo: nil)
        return light
    }
}
