import AppKit
import FlickCore
import ImageIO
import RealityKit

struct TablePose {
    struct Contact {
        let side: Side
        let strength: Double
        let isWhiff: Bool
    }

    enum Outcome {
        case point
        case win
    }

    private static let serveStrength = 0.4
    private static let viewerHitStrength = 0.6

    let ball: SIMD2<Double>
    let velocity: SIMD2<Double>
    let shotStartY: Double
    let paddleA: Double
    let paddleB: Double
    let isRally: Bool
    let contacts: [Contact]
    let outcome: Outcome?
    let dimmed: Set<Side>

    init(game: GameState, events: [GameEvent], dimmed: Set<Side>) {
        ball = game.ball.position
        velocity = game.ball.velocity
        shotStartY = game.shotStart.y
        paddleA = game.paddleX(of: .playerA)
        paddleB = game.paddleX(of: .playerB)
        if case .rally = game.phase {
            isRally = true
        } else {
            isRally = false
        }
        contacts = events.compactMap { event in
            switch event {
            case .served(let side): Contact(side: side, strength: Self.serveStrength, isWhiff: false)
            case .hit(let side, let strength, _): Contact(side: side, strength: strength, isWhiff: false)
            case .whiff(let side): Contact(side: side, strength: 0, isWhiff: true)
            default: nil
            }
        }
        if events.contains(where: { if case .gameOver = $0 { true } else { false } }) {
            outcome = .win
        } else if events.contains(where: { if case .pointScored = $0 { true } else { false } }) {
            outcome = .point
        } else {
            outcome = nil
        }
        self.dimmed = dimmed
    }

    init(frame: ViewerDisplay.Frame, previous: ViewerDisplay.Frame?) {
        ball = frame.ball
        velocity = frame.velocity
        shotStartY = frame.shotStart.y
        paddleA = frame.paddleA
        paddleB = frame.paddleB
        isRally = frame.phase == .rally
        let hitter: Side = frame.velocity.y > 0 ? .playerA : .playerB
        if let previous, frame.rally > previous.rally || (previous.phase == .serving && frame.phase == .rally) {
            contacts = [Contact(side: hitter, strength: Self.viewerHitStrength, isWhiff: false)]
        } else {
            contacts = []
        }
        if let previous, previous.phase != .gameOver, frame.phase == .gameOver {
            outcome = .win
        } else if let previous, frame.scoreA + frame.scoreB > previous.scoreA + previous.scoreB {
            outcome = .point
        } else {
            outcome = nil
        }
        dimmed = []
    }

    var speed: Double {
        simd_length(velocity)
    }

    func paddleX(of side: Side) -> Double {
        side == .playerA ? paddleA : paddleB
    }
}

@MainActor
final class TableScene {
    private typealias Size = Equipment.Size

    private enum Arc {
        static let paddleHeight: Float = 0.17
        static let firstApex: Float = 0.24
        static let secondApex: Float = 0.12
        static let bounceAt: Float = 0.7
    }

    private enum Swing {
        static let duration: TimeInterval = 0.28
        static let strikeShare = 0.3
        static let tilt: Float = 0.95
        static let whiffStrength = 0.3
    }

    private enum Impact {
        static let glowDuration: TimeInterval = 0.18
        static let glowGrowth: Float = 3
        static let glowOpacity: Float = 0.6
        static let trailLength = 6
        static let trailOpacity: Float = 0.3
        static let trailFromSpeed = 0.7
        static let trailFullSpeed = 1.5
    }

    private struct SwingState {
        var elapsed: TimeInterval
        let strength: Double
    }

    private static let dimmedOpacity: Float = 0.35
    private static let maximumLean: Float = 30 * .pi / 180
    private static let paddleBehindFace: Float = 0.03
    private static let panWidth: Float = 0.7

    let root = Entity()
    private let camera = PerspectiveCamera()
    private let ball = Equipment.ball()
    private let glow = Equipment.ghostBall()
    private let trail = (0..<Impact.trailLength).map { _ in Equipment.ghostBall() }
    private let sounds: SoundBoard
    private var paddles: [(side: Side, root: Entity, pivot: Entity)] = []
    private var swings: [Side: SwingState] = [:]
    private var glowElapsed: TimeInterval?
    private var ballTrail: [SIMD3<Float>] = []
    private var lastProgress: Float?
    private var view = CameraView.playerAEnd
    private let config: GameConfig

    init(config: GameConfig) async throws {
        self.config = config
        sounds = try SoundBoard()
        let width = Float(config.tableWidth) * Size.metresPerTableLength
        let materials = try await Equipment.Materials.make(tableWidth: width)
        let studio = try await Self.studioLight()

        root.addChild(Equipment.backdrop(materials))
        let lit = Entity()
        lit.addChild(Equipment.contactShadow(materials, width: width))
        lit.addChild(try Equipment.table(materials, width: width))
        lit.addChild(ball)
        for side in Side.allCases {
            let paddle = try Equipment.paddle(materials, rubber: NSColor(side.rubberColor))
            if side == .playerB {
                paddle.root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            }
            lit.addChild(paddle.root)
            paddles.append((side, paddle.root, paddle.pivot))
        }
        root.addChild(studio)
        root.addChild(lit)
        root.addChild(glow)
        for ghost in trail {
            root.addChild(ghost)
        }
        Self.receiveLight(from: studio, in: lit)
        root.addChild(Self.keyLight())
        camera.camera.fieldOfViewInDegrees = 34
        root.addChild(camera)
        show(.playerAEnd, animated: false)
    }

    func show(_ view: CameraView, animated: Bool) {
        self.view = view
        let placement = Entity()
        let (position, target) = Self.placement(for: view)
        placement.look(at: target, from: position, relativeTo: nil)
        if animated {
            camera.move(to: placement.transform, relativeTo: nil, duration: 1.1, timingFunction: .easeInOut)
        } else {
            camera.transform = placement.transform
        }
    }

    func update(to pose: TablePose, elapsed: TimeInterval) {
        let arc = arc(for: pose)
        let ballPosition: SIMD3<Float> = [sceneX(pose.ball.x), Size.tableHeight + arc.height, sceneZ(pose.ball.y)]
        for contact in pose.contacts {
            swings[contact.side] = SwingState(elapsed: 0, strength: contact.isWhiff ? Swing.whiffStrength : contact.strength)
            if !contact.isWhiff {
                sounds.play(.paddle(strength: contact.strength), pan: pan(at: pose.ball))
                glowElapsed = 0
            }
        }
        switch pose.outcome {
        case .point: sounds.play(.point, pan: 0)
        case .win: sounds.play(.win, pan: 0)
        case nil: break
        }
        if let progress = arc.progress, let lastProgress, lastProgress < Arc.bounceAt, progress >= Arc.bounceAt {
            sounds.play(.table, pan: pan(at: pose.ball))
        }
        lastProgress = arc.progress
        for paddle in paddles {
            let side = paddle.side
            let behind = side == .playerA ? Self.paddleBehindFace : -Self.paddleBehindFace
            paddle.root.position = [sceneX(pose.paddleX(of: side)), Size.tableHeight + Arc.paddleHeight, sceneZ(config.paddleFaceY(of: side)) + behind]
            let swing = simd_quatf(angle: -swingAngle(side, elapsed: elapsed), axis: [1, 0, 0])
            paddle.pivot.orientation = simd_quatf(angle: -lean(of: side, in: pose), axis: [0, 0, 1]) * swing
            paddle.root.components.set(OpacityComponent(opacity: pose.dimmed.contains(side) ? Self.dimmedOpacity : 1))
        }
        ball.position = ballPosition
        updateGlow(at: ballPosition, elapsed: elapsed)
        updateTrail(behind: ballPosition, speed: pose.isRally ? pose.speed : 0)
    }

    private func lean(of side: Side, in pose: TablePose) -> Float {
        let tablePosition = config.position(ofPaddleX: pose.paddleX(of: side))
        let ownPosition = side == .playerA ? tablePosition : 1 - tablePosition
        return Float(ownPosition - 0.5) * 2 * Self.maximumLean
    }

    private func swingAngle(_ side: Side, elapsed: TimeInterval) -> Float {
        guard var swing = swings[side] else { return 0 }
        swing.elapsed += elapsed
        guard swing.elapsed < Swing.duration else {
            swings[side] = nil
            return 0
        }
        swings[side] = swing
        let progress = swing.elapsed / Swing.duration
        let shape = progress < Swing.strikeShare
            ? sin(.pi / 2 * progress / Swing.strikeShare)
            : 0.5 * (1 + cos(.pi * (progress - Swing.strikeShare) / (1 - Swing.strikeShare)))
        return Swing.tilt * Float(shape * (0.7 + 0.6 * swing.strength))
    }

    private func updateGlow(at position: SIMD3<Float>, elapsed: TimeInterval) {
        guard let started = glowElapsed else { return }
        let now = started + elapsed
        guard now < Impact.glowDuration else {
            glowElapsed = nil
            glow.isEnabled = false
            return
        }
        glowElapsed = now
        let progress = Float(now / Impact.glowDuration)
        glow.isEnabled = true
        glow.position = position
        glow.scale = .init(repeating: 1 + Impact.glowGrowth * progress)
        glow.components.set(OpacityComponent(opacity: Impact.glowOpacity * (1 - progress)))
    }

    private func updateTrail(behind position: SIMD3<Float>, speed: Double) {
        let strength = Float(min(max((speed - Impact.trailFromSpeed) / (Impact.trailFullSpeed - Impact.trailFromSpeed), 0), 1))
        ballTrail.insert(position, at: 0)
        if ballTrail.count > trail.count {
            ballTrail.removeLast()
        }
        for (index, ghost) in trail.enumerated() {
            let fade = 1 - Float(index) / Float(trail.count)
            ghost.isEnabled = strength > 0 && index < ballTrail.count
            guard ghost.isEnabled else { continue }
            ghost.position = ballTrail[index]
            ghost.scale = .init(repeating: 0.4 + 0.5 * fade)
            ghost.components.set(OpacityComponent(opacity: Impact.trailOpacity * fade * strength))
        }
    }

    private func pan(at ball: SIMD2<Double>) -> Float {
        let across = Float(ball.x / config.tableWidth * 2 - 1)
        let along = Float(ball.y / config.tableLength * 2 - 1)
        switch view {
        case .playerAEnd: return across * Self.panWidth
        case .playerBEnd: return -across * Self.panWidth
        case .side: return along * Self.panWidth
        }
    }

    private func arc(for pose: TablePose) -> (height: Float, progress: Float?) {
        guard pose.isRally else { return (Arc.paddleHeight, nil) }
        let receiver = pose.velocity.y > 0 ? Side.playerB : Side.playerA
        let start = pose.shotStartY
        let end = config.paddleFaceY(of: receiver)
        let progress = Float(min(max((pose.ball.y - start) / (end - start), 0), 1.3))
        if progress < Arc.bounceAt {
            let u = progress / Arc.bounceAt
            return (Arc.paddleHeight * (1 - u) + Size.ballRadius * u + Arc.firstApex * 4 * u * (1 - u), progress)
        }
        let v = (progress - Arc.bounceAt) / (1 - Arc.bounceAt)
        return (Size.ballRadius * (1 - v) + Arc.paddleHeight * v + Arc.secondApex * 4 * v * (1 - v), progress)
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
