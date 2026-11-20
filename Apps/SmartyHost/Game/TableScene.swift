import AppKit
import OSLog
import SmartyCore
import ImageIO
import RealityKit

struct TablePose {
    struct Contact {
        let side: Side
        let strength: Double
        let isWhiff: Bool
        var isClean = true
    }

    struct Forecast {
        let secondsAway: Double
        let position: SIMD3<Double>
    }

    enum Outcome {
        case point
        case win
    }

    private static let serveStrength = 0.4
    private static let viewerHitStrength = 0.6

    var step: UInt64
    var ball: SIMD3<Double>
    var velocity: SIMD3<Double>
    var spin: SIMD3<Double>
    var paddleA: Double
    var paddleB: Double
    var isRally: Bool
    var contacts: [Contact]
    var bounced: Bool
    var netHitSpeed: Double?
    var rewound = false
    var stances: [Side: Stance]
    var outcome: Outcome?
    var dimmed: Set<Side>
    var score: Score
    var rackets: [Side: RacketSample]
    var racketAges: [Side: Double]
    var forecasts: [Side: Forecast]
    var strokes: [Side: Double]

    init(game: GameState, events: [GameEvent], dimmed: Set<Side>, forecasts: [Side: Forecast], stances: [Side: Stance]) {
        self.stances = stances
        step = game.step
        ball = game.ball.position
        velocity = game.ball.velocity
        spin = game.ball.spin
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
            case .hit(let side, let strength, _): Contact(side: side, strength: strength, isWhiff: false, isClean: !events.contains(.edgeHit(side)))
            case .whiff(let side): Contact(side: side, strength: 0, isWhiff: true)
            default: nil
            }
        }
        bounced = events.contains { if case .bounce = $0 { true } else { false } }
        netHitSpeed = events.contains(.net) ? simd_length(game.ball.velocity) : nil
        outcome = Self.outcome(of: events)
        self.dimmed = dimmed
        score = game.score
        rackets = Dictionary(uniqueKeysWithValues: Side.allCases.compactMap { side in game.racket(of: side).map { (side, $0) } })
        racketAges = rackets.mapValues { Double(game.step) - Double($0.step) }.mapValues { max($0, 0) / Double(game.config.stepsPerSecond) }
        self.forecasts = forecasts
        strokes = Dictionary(events.compactMap { event in
            if case .stroke(let side, let timing) = event { (side, timing) } else { nil }
        }, uniquingKeysWith: { $1 })
    }

    init(frame: ViewerDisplay.Frame, previous: ViewerDisplay.Frame?) {
        step = 0
        ball = frame.ball
        velocity = frame.velocity
        spin = .zero
        paddleA = frame.paddleA
        paddleB = frame.paddleB
        isRally = frame.phase == .rally
        let hitter: Side = frame.velocity.y > 0 ? .playerA : .playerB
        if let previous, frame.rally > previous.rally || (previous.phase == .serving && frame.phase == .rally) {
            contacts = [Contact(side: hitter, strength: Self.viewerHitStrength, isWhiff: false)]
        } else {
            contacts = []
        }
        bounced = previous.map { $0.velocity.z < 0 && frame.velocity.z > 0 && frame.ball.z < 0.1 } ?? false
        netHitSpeed = nil
        stances = [:]
        if let previous, previous.phase != .gameOver, frame.phase == .gameOver {
            outcome = .win
        } else if let previous, frame.scoreA + frame.scoreB > previous.scoreA + previous.scoreB {
            outcome = .point
        } else {
            outcome = nil
        }
        dimmed = []
        score = Score(a: frame.scoreA, b: frame.scoreB)
        rackets = [:]
        racketAges = [:]
        forecasts = [:]
        strokes = [:]
    }

    var speed: Double {
        simd_length(velocity)
    }

    func paddleX(of side: Side) -> Double {
        side == .playerA ? paddleA : paddleB
    }

    private static func outcome(of events: [GameEvent]) -> Outcome? {
        if events.contains(where: { if case .gameOver = $0 { true } else { false } }) {
            return .win
        }
        if events.contains(where: { if case .pointScored = $0 { true } else { false } }) {
            return .point
        }
        return nil
    }
}

@MainActor
final class TableScene {
    private typealias Size = Equipment.Size

    private enum Reach {
        static let restingHeight: Float = 0.17
        static let lowest: Float = -0.3
        static let highest: Float = 0.9
        static let rate: Float = 8
    }

    private enum Impact {
        static let glowDuration: TimeInterval = 0.18
        static let glowGrowth: Float = 3
        static let glowOpacity: Float = 0.6
        static let trailLength = 6
        static let trailOpacity: Float = 0.3
        static let trailFromSpeed = 6.0
        static let trailFullSpeed = 12.0
    }

    private static let dimmedOpacity: Float = 0.35
    private static let maximumLean: Float = 30 * .pi / 180
    private static let paddleBehindFace: Float = 0.03
    private static let panWidth: Float = 0.7
    private static let farPlane: Float = 100
    private static let rigIntensity: Float = 260_000
    private static let rigHeight: Float = 7
    private static let rigSpots: [SIMD2<Float>] = [[0, 0], [-1.6, -2.6], [1.6, -2.6], [-1.6, 2.6], [1.6, 2.6]]
    private static let umpireTable: SIMD3<Float> = [-1.75, 0, 0]
    private static let courtChairs: [(SIMD3<Float>, Float)] = [([-2.6, 0, 5.2], .pi * 0.85), ([2.6, 0, -5.2], -.pi * 0.15)]
    private static let whiffStrength = 0.3
    private static let paddleRollPerSpeed: Float = 0.08
    private static let maximumRoll: Float = 0.3
    private static let fieldOfView: Float = 34
    private static let halfScreenWidthFieldOfView: Float = 42
    private static let halfScreenTargetHeight: Float = 0.4
    private static let maximumSpin: Float = 30
    private static let crowdViewHalfAngle: Float = 55 * .pi / 180
    private static let driveReturn: Float = 0.18
    private static let longestDrive: Float = 0.4
    private static let ballCatchUp: Float = 0.12
    private static let ballReset: Float = 0.5
    private static let ballFadeIn: Float = 0.3
    private static let frameLog = Logger(subsystem: "com.smartysupreme.host", category: "Frame")
    private static let largestBallCatchUp: Float = 4
    private static let onTimeGlow = NSColor(red: 1, green: 0.97, blue: 0.88, alpha: 1)
    private static let earlyGlow = NSColor(red: 0.55, green: 0.75, blue: 1, alpha: 1)
    private static let lateGlow = NSColor(red: 1, green: 0.62, blue: 0.3, alpha: 1)
    private static let cameraMove: TimeInterval = 1.1
    private static let tableToScene = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
    private static let longestPrediction = 0.015
    private static let batSmoothing: Float = 0.025
    private static let handRate: Float = 12
    private static let netShakePerSpeed: Float = 0.004
    private static let largestNetShake: Float = 0.02
    private static let netShakeFrequency: Float = 7
    private static let netShakeDecay: Float = 0.16
    private static let phoneToBat = simd_quatf(angle: .pi, axis: [0, 1, 0])

    let root = Entity()
    private let camera = PerspectiveCamera()
    private let ball: ModelEntity
    private let glow = Equipment.ghostBall()
    private let trail = (0..<Impact.trailLength).map { _ in Equipment.ghostBall() }
    private let sounds: SoundBoard?
    private let crowd: Crowd
    private var paddles: [(side: Side, root: Entity, pivot: Entity)] = []
    private var motions: [Side: PaddleMotion] = [:]
    private var scoreCards: [Side: ModelEntity] = [:]
    private var shownScore: Score?
    private var cardMaterials: [Int: PhysicallyBasedMaterial] = [:]
    private var glowElapsed: TimeInterval?
    private var net: Entity?
    private var netShake: (elapsed: Float, amplitude: Float)?
    private var ballTrail: [SIMD3<Float>] = []
    private var heights: [Side: Float] = [:]
    private var shownBats: [Side: simd_quatf] = [:]
    private var hands: [Side: Float] = [:]
    private var rings: [Side: ContactRing] = [:]
    private var drives: [Side: SIMD3<Float>] = [:]
    private var drawnBall: SIMD3<Float>?
    private var ballCorrection = SIMD3<Float>.zero
    private var ballShownFor: Float = 1
    private var cameraMoves = 0
    private var view = CameraView.playerAEnd
    private let config: GameConfig

    init(config: GameConfig, playsSounds: Bool = true) async throws {
        self.config = config
        sounds = playsSounds ? try SoundBoard() : nil
        let width = Float(config.tableWidth)
        let materials = try await Equipment.Materials.make(tableWidth: width)
        ball = Equipment.ball(materials)
        let hall = try await Hall.load()
        let chair = try await Equipment.model("painted_wooden_chair_01")

        root.addChild(hall.background)
        let lit = Entity()
        lit.addChild(Equipment.floor(materials))
        lit.addChild(Equipment.contactShadow(materials, width: width))
        lit.addChild(Equipment.table(materials, width: width))
        net = lit.findEntity(named: "net")
        lit.addChild(Equipment.surrounds(materials))
        crowd = try await Crowd(courtLength: Size.courtLength, courtWidth: Size.courtWidth, seed: 5)
        root.addChild(crowd.root)
        root.addChild(Equipment.lightingRig(intensity: Self.rigIntensity, height: Self.rigHeight, spots: Self.rigSpots))

        let umpire = Entity()
        umpire.position = Self.umpireTable
        let desk = ModelEntity(mesh: .generateBox(width: 0.5, height: 0.04, depth: 1.0, cornerRadius: 0.005), materials: [materials.frame])
        desk.position.y = 0.74
        umpire.addChild(desk)
        for z: Float in [-0.42, 0.42] {
            for x: Float in [-0.2, 0.2] {
                let leg = ModelEntity(mesh: .generateBox(width: 0.04, height: 0.72, depth: 0.04), materials: [materials.frame])
                leg.position = [x, 0.36, z]
                umpire.addChild(leg)
            }
        }
        for (index, side) in Side.allCases.enumerated() {
            let stand = Equipment.scoreStand(materials)
            stand.root.position = [0, 0.76, index == 0 ? 0.3 : -0.3]
            stand.root.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            umpire.addChild(stand.root)
            scoreCards[side] = stand.card
        }
        let umpireChair = chair.clone(recursive: true)
        umpireChair.position = [-0.55, 0, 0]
        umpireChair.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        umpire.addChild(umpireChair)
        lit.addChild(umpire)
        for (position, turn) in Self.courtChairs {
            let placed = chair.clone(recursive: true)
            placed.position = position
            placed.orientation = simd_quatf(angle: turn, axis: [0, 1, 0])
            lit.addChild(placed)
        }
        lit.addChild(ball)
        var ringMaterial = UnlitMaterial()
        ringMaterial.color = .init(tint: Equipment.Tone.celluloid, texture: .init(try await Textures.texture(await Textures.contactRing(), .color)))
        ringMaterial.blending = .transparent(opacity: 0.8)
        for side in Side.allCases {
            let paddle = try Equipment.paddle(materials, rubber: NSColor(side.rubberColor))
            let facing = side == .playerB ? simd_quatf(angle: .pi, axis: [0, 1, 0]) : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            paddle.root.orientation = facing
            lit.addChild(paddle.root)
            paddles.append((side, paddle.root, paddle.pivot))
            let ring = ContactRing(material: ringMaterial, facing: facing)
            lit.addChild(ring.root)
            rings[side] = ring
        }
        root.addChild(hall.light)
        root.addChild(lit)
        root.addChild(glow)
        for ghost in trail {
            root.addChild(ghost)
        }
        Self.receiveLight(from: hall.light, in: lit)
        camera.camera.fieldOfViewInDegrees = Self.fieldOfView
        camera.camera.far = Self.farPlane
        root.addChild(camera)
        show(.playerAEnd, animated: false)
    }

    func show(_ view: CameraView, halfScreen: Bool = false, animated: Bool) {
        self.view = view
        camera.camera.fieldOfViewOrientation = halfScreen ? .horizontal : .vertical
        camera.camera.fieldOfViewInDegrees = halfScreen ? Self.halfScreenWidthFieldOfView : Self.fieldOfView
        let placement = Entity()
        var (position, target) = Self.placement(for: view)
        if halfScreen {
            target.y = Self.halfScreenTargetHeight
        }
        placement.look(at: target, from: position, relativeTo: nil)
        cameraMoves += 1
        let forward = simd_normalize(target - position)
        if animated {
            crowd.showAll()
            camera.move(to: placement.transform, relativeTo: nil, duration: Self.cameraMove, timingFunction: .easeInOut)
            let move = cameraMoves
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.cameraMove))
                guard let self, cameraMoves == move else { return }
                crowd.show(onlyWhatIsSeenFrom: position, looking: forward, within: Self.crowdViewHalfAngle)
            }
        } else {
            camera.transform = placement.transform
            crowd.show(onlyWhatIsSeenFrom: position, looking: forward, within: Self.crowdViewHalfAngle)
        }
    }

    func update(to pose: TablePose, elapsed: TimeInterval) {
        var ballPosition = scenePoint(pose.ball)
        // A hit confirmed after the ball passed the bat replays its flight; ease the drawn ball onto it instead of jumping.
        if pose.contacts.contains(where: { !$0.isWhiff }) || pose.rewound, let drawnBall, simd_distance(drawnBall, ballPosition) < Self.largestBallCatchUp {
            ballCorrection = drawnBall - ballPosition
        }
        ballCorrection *= exp(-Float(elapsed) / Self.ballCatchUp)
        ballPosition += ballCorrection
        if let drawnBall, !pose.isRally, simd_distance(drawnBall, ballPosition) > Self.ballReset {
            ballShownFor = 0
        }
        ballShownFor += Float(elapsed)
        ball.components.set(OpacityComponent(opacity: min(ballShownFor / Self.ballFadeIn, 1)))
        if let drawnBall, pose.isRally {
            let moved = simd_distance(drawnBall, ballPosition)
            let expected = Float(pose.speed * elapsed) * 1.5 + 0.05
            if moved > expected {
                Self.frameLog.info("ball jump \(Int(moved * 100), privacy: .public) cm, expected \(Int(expected * 100), privacy: .public) cm, frame \(Int(elapsed * 1_000), privacy: .public) ms, rally \(pose.isRally, privacy: .public), contacts \(pose.contacts.count, privacy: .public), correction \(Int(simd_length(self.ballCorrection) * 100), privacy: .public) cm")
            }
        }
        drawnBall = ballPosition
        if !pose.contacts.isEmpty {
            let timing = pose.strokes.values.first
            let tone = timing.map { abs($0) <= StrokeTiming.onTime ? Self.onTimeGlow : ($0 < 0 ? Self.earlyGlow : Self.lateGlow) } ?? Equipment.Tone.celluloid
            var material = UnlitMaterial(color: tone)
            material.blending = .transparent(opacity: 1.0)
            glow.model?.materials = [material]
        }
        for contact in pose.contacts {
            if pose.rackets[contact.side] == nil {
                motions[contact.side]?.hit(strength: Float(contact.isWhiff ? Self.whiffStrength : contact.strength))
            }
            if !contact.isWhiff {
                sounds?.play(.paddle(strength: contact.strength, isClean: contact.isClean), pan: pan(at: pose.ball))
                glowElapsed = 0
            }
        }
        if pose.bounced {
            sounds?.play(.table, pan: pan(at: pose.ball))
        }
        if let speed = pose.netHitSpeed {
            sounds?.play(.net, pan: pan(at: pose.ball))
            netShake = (0, min(Float(speed) * Self.netShakePerSpeed, Self.largestNetShake))
        }
        shakeNet(elapsed: Float(elapsed))
        switch pose.outcome {
        case .point: sounds?.play(.point, pan: 0)
        case .win: sounds?.play(.win, pan: 0)
        case nil: break
        }
        crowd.update(elapsed: elapsed, cheer: pose.outcome != nil)
        showScore(pose.score)
        let seconds = Float(max(elapsed, 1e-4))
        for paddle in paddles {
            place(paddle, in: pose, elapsed: seconds)
        }
        spinBall(to: ballPosition, spin: pose.spin, elapsed: Float(elapsed))
        updateGlow(at: ballPosition, elapsed: elapsed)
        updateTrail(behind: ballPosition, speed: pose.isRally ? pose.speed : 0)
    }

    private func place(_ paddle: (side: Side, root: Entity, pivot: Entity), in pose: TablePose, elapsed: Float) {
        let side = paddle.side
        let mirror: Float = side == .playerA ? 1 : -1
        let target = sceneX(pose.paddleX(of: side))
        var motion = motions[side] ?? PaddleMotion(x: target)
        let forecast = pose.forecasts[side]
        let across = (sceneX(pose.ball.x) - motion.x) * mirror
        let contactAcross = forecast.map { (sceneX($0.position.x) - motion.x) * mirror }
        motion.update(target: target, ballAcross: across, contactAcross: contactAcross, secondsToContact: forecast.map { Float($0.secondsAway) }, elapsed: elapsed)
        motions[side] = motion
        let wanted = forecast.map { min(max(Float($0.position.z), Reach.lowest), Reach.highest) } ?? Reach.restingHeight
        let height = (heights[side] ?? Reach.restingHeight) + (wanted - (heights[side] ?? Reach.restingHeight)) * min(Reach.rate * elapsed, 1)
        heights[side] = height
        if let racket = pose.rackets[side] {
            let blade = racket.bladeVelocity
            var drive = drives[side] ?? .zero
            drive += SIMD3(Float(blade.x) * mirror, Float(blade.z), -Float(blade.y) * mirror) * elapsed
            drive *= exp(-elapsed / Self.driveReturn)
            if simd_length(drive) > Self.longestDrive {
                drive = simd_normalize(drive) * Self.longestDrive
            }
            drives[side] = drive
            let age = min(pose.racketAges[side] ?? 0, Self.longestPrediction)
            let turned = simd_length(racket.angularVelocity) * age
            let ahead = turned > 0 ? simd_quatd(angle: turned, axis: simd_normalize(racket.angularVelocity)) * racket.orientation : racket.orientation
            let orientation = simd_quatf(ix: Float(ahead.imag.x), iy: Float(ahead.imag.y), iz: Float(ahead.imag.z), r: Float(ahead.real))
            let target = Self.tableToScene * orientation * Self.phoneToBat
            let shown = shownBats[side].map { simd_slerp($0, target, 1 - exp(-elapsed / Self.batSmoothing)) } ?? target
            shownBats[side] = shown
            let stance = pose.isRally ? pose.stances[side] ?? racket.stance : racket.stance
            let hand = Float(ArmModel.restingHand(stance, racket.handedness).x) * mirror
            let shownHand = (hands[side] ?? hand) + (hand - (hands[side] ?? hand)) * min(Self.handRate * elapsed, 1)
            hands[side] = shownHand
            paddle.root.position = [motion.x + shownHand, Size.tableHeight + height, sceneZ(config.contactY(of: side)) + Self.paddleBehindFace * mirror]
            paddle.pivot.position = SIMD3(0, -Size.grip, 0) + drive
            paddle.pivot.orientation = shown
            rings[side]?.show(at: forecast.map { (scenePoint($0.position), Float($0.secondsAway)) })
        } else {
            rings[side]?.show(at: nil)
            paddle.root.position = [motion.x, Size.tableHeight + height, sceneZ(config.contactY(of: side)) + Self.paddleBehindFace * mirror]
            let speed = motion.lateralSpeed * mirror
            let roll = min(max(speed * Self.paddleRollPerSpeed, -Self.maximumRoll), Self.maximumRoll)
            let stroke = motion.pose()
            let tilt = -lean(of: side, in: pose) - roll
            paddle.pivot.position = SIMD3(Size.grip * sin(tilt) * motion.reachWeight, -Size.grip, 0) + stroke.offset
            paddle.pivot.orientation = simd_quatf(angle: tilt, axis: [0, 0, 1]) * stroke.orientation
        }
        paddle.root.components.set(OpacityComponent(opacity: pose.dimmed.contains(side) ? Self.dimmedOpacity : 1))
    }

    private func showScore(_ score: Score) {
        guard score != shownScore else { return }
        shownScore = score
        for side in Side.allCases {
            let points = score[side]
            if let material = cardMaterials[points] {
                scoreCards[side]?.model?.materials = [material]
            } else {
                Task { [weak self] in
                    let image = await Textures.scoreCard(points)
                    guard let self, let texture = try? await Textures.texture(image, .color) else { return }
                    var material = PhysicallyBasedMaterial()
                    material.baseColor = .init(texture: .init(texture))
                    material.roughness = 0.8
                    material.faceCulling = .none
                    cardMaterials[points] = material
                    if shownScore?[side] == points {
                        scoreCards[side]?.model?.materials = [material]
                    }
                }
            }
        }
    }

    private func lean(of side: Side, in pose: TablePose) -> Float {
        let tablePosition = config.position(ofPaddleX: pose.paddleX(of: side))
        let ownPosition = side == .playerA ? tablePosition : 1 - tablePosition
        return Float(ownPosition - 0.5) * 2 * Self.maximumLean
    }

    private func shakeNet(elapsed: Float) {
        guard let shake = netShake, let net else { return }
        let t = shake.elapsed + elapsed
        let envelope = exp(-t / Self.netShakeDecay)
        net.position.z = shake.amplitude * envelope * sin(2 * .pi * Self.netShakeFrequency * t)
        netShake = envelope < 0.02 ? nil : (t, shake.amplitude)
        if netShake == nil {
            net.position.z = 0
        }
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

    private func spinBall(to position: SIMD3<Float>, spin: SIMD3<Double>, elapsed: Float) {
        ball.position = position
        let axis = sceneVector(spin)
        let rate = simd_length(axis)
        guard rate > 0.01, elapsed > 0 else { return }
        let shown = min(rate * Float(config.timeScale), Self.maximumSpin)
        ball.orientation = simd_quatf(angle: shown * elapsed, axis: axis / rate) * ball.orientation
    }

    private func pan(at ball: SIMD3<Double>) -> Float {
        let across = Float(ball.x / config.tableWidth * 2 - 1)
        let along = Float(ball.y / config.tableLength * 2 - 1)
        switch view {
        case .playerAEnd: return across * Self.panWidth
        case .playerBEnd: return -across * Self.panWidth
        case .split: return along * Self.panWidth
        }
    }

    private func sceneX(_ x: Double) -> Float {
        Float(x - config.tableWidth / 2)
    }

    private func sceneZ(_ y: Double) -> Float {
        Float(config.tableLength / 2 - y)
    }

    private func scenePoint(_ point: SIMD3<Double>) -> SIMD3<Float> {
        [sceneX(point.x), Size.tableHeight + Float(point.z), sceneZ(point.y)]
    }

    private func sceneVector(_ vector: SIMD3<Double>) -> SIMD3<Float> {
        [Float(vector.x), Float(vector.z), -Float(vector.y)]
    }

    private static func placement(for view: CameraView) -> (SIMD3<Float>, SIMD3<Float>) {
        switch view {
        case .playerAEnd, .split: ([0, 1.7, 3.8], [0, 0.68, -0.5])
        case .playerBEnd: ([0, 1.7, -3.8], [0, 0.68, 0.5])
        }
    }

    private static func receiveLight(from light: Entity, in entity: Entity) {
        if entity is ModelEntity {
            entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        }
        for child in entity.children {
            receiveLight(from: light, in: child)
        }
    }
}
