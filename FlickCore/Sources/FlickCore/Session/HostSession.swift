public final class HostSession {
    public enum Controller: Equatable, Sendable {
        case phone
        case computer
        case local
    }

    public let config: SessionConfig
    public private(set) var game: GameState
    public private(set) var stage = MatchStage.lobby
    public private(set) var usesSideCamera = false

    private let mode: MatchMode
    private let link: HostLink
    private let clock: any MonotonicClock
    private var computer: AIController?
    private var timeline: StepTimeline
    private var input = HostLink.Input(paddles: [:], vacant: [], viewerName: nil)
    private var lastAdvanceAt: Microseconds
    private var unsimulatedSeconds = 0.0
    private var pendingCommand: GameCommand?
    private var pendingSwings: [Swing] = []
    private var matchPhones: Set<Side> = []
    private var reconnectDeadlines: [Side: Microseconds] = [:]
    private var heldInterruption: Interruption?
    private var viewerJoined = false
    private var autoServes: [Side: Int] = [:]
    private var sentStates: [Side: GameStateUpdate] = [:]

    public init(
        link: HostLink,
        clock: any MonotonicClock,
        mode: MatchMode,
        seed: UInt64,
        aiSeed: UInt64,
        config: SessionConfig = SessionConfig(),
        gameConfig: GameConfig = GameConfig()
    ) {
        self.link = link
        self.clock = clock
        self.mode = mode
        self.config = config
        game = GameState(seed: seed, config: gameConfig)
        let now = clock.now
        timeline = StepTimeline(step: 0, at: now, stepsPerSecond: gameConfig.stepsPerSecond)
        lastAdvanceAt = now
        link.setPlayableSides(Set(mode.phoneSides))
        link.holdSlots(false)
        link.resetReadiness()
        if case .computer(let difficulty) = mode {
            computer = AIController(side: .playerB, profile: difficulty.profile, seed: aiSeed)
            begin()
        }
    }

    public func controller(of side: Side) -> Controller {
        if side == .playerB, computer != nil { return .computer }
        return phoneTarget(for: side) == nil ? .local : .phone
    }

    public func readiness(of side: Side) -> Readiness {
        guard let paddle = input.paddles[side] else { return .noPhone }
        guard paddle.isCalibrated else { return .needsCalibration }
        guard paddle.isReady else { return .notReady }
        guard let roundTrip = paddle.roundTrip else { return .measuring }
        return roundTrip > config.roundTripLimit ? .tooSlow(roundTrip: roundTrip) : .ready(roundTrip: roundTrip)
    }

    public func isReady(_ side: Side) -> Bool {
        if case .ready = readiness(of: side) { return true }
        return false
    }

    public func isPointerStale(_ side: Side) -> Bool {
        guard matchPhones.contains(side), let lastPointerAt = input.paddles[side]?.lastPointerAt else { return false }
        return lastPointerAt + config.pointerStaleAfter < clock.now
    }

    public func startNow() {
        switch stage {
        case .lobby, .countdown: begin()
        case .playing, .interrupted, .over: return
        }
    }

    public func swapSides() {
        switch stage {
        case .lobby, .countdown:
            link.swapSides()
            link.resetReadiness()
            stage = .lobby
        case .playing, .interrupted, .over:
            return
        }
    }

    public func fillVacancy(_ side: Side, with peer: PeerID) {
        link.fillVacancy(side, with: peer)
    }

    public func pause() {
        if stage == .playing {
            interrupt(.byHost)
        }
    }

    public func resume() {
        guard case .interrupted(let interruption) = stage else { return }
        switch interruption {
        case .phoneLost:
            for side in reconnectDeadlines.keys {
                matchPhones.remove(side)
            }
            reconnectDeadlines.removeAll()
        case .viewerLost:
            usesSideCamera = true
        case .byHost, .byPlayer, .pointerLost, .serveTimeouts:
            break
        }
        heldInterruption = nil
        resumePlay()
    }

    public func advance(local: LocalInput) -> [GameEvent] {
        input = link.takeInput()
        let now = clock.now
        let gap = now - lastAdvanceAt
        lastAdvanceAt = now
        updateStage(at: now)
        guard hasStarted else {
            publish(haptics: [])
            return []
        }
        if gap <= config.longestFrame {
            queuePhoneSwings()
        }
        pendingSwings += local.swings.filter { controller(of: $0.side) == .local }
        unsimulatedSeconds += Double(min(gap, config.longestFrame)) / 1_000_000
        let stepDuration = 1 / Double(game.config.stepsPerSecond)
        var events: [GameEvent] = []
        var haptics: [(Side, HapticKind)] = []
        while unsimulatedSeconds >= stepDuration {
            unsimulatedSeconds -= stepDuration
            let stepInput = nextInput(local: local)
            let stepEvents = game.step(stepInput)
            haptics += hapticsAndServeTimeouts(for: stepEvents, swings: stepInput.swings)
            events += stepEvents
        }
        timeline.mark(step: game.step, at: now)
        if case .gameOver = game.phase, stage != .over {
            stage = .over
            link.holdSlots(false)
        }
        askAboutServeTimeouts()
        publish(haptics: haptics)
        return events
    }

    private var hasStarted: Bool {
        switch stage {
        case .lobby, .countdown: false
        case .playing, .interrupted, .over: true
        }
    }

    private func begin() {
        stage = .playing
        link.holdSlots(true)
    }

    private func updateStage(at now: Microseconds) {
        switch stage {
        case .lobby:
            if mode == .twoPlayers, Side.allCases.allSatisfy(isReady) {
                stage = .countdown(until: now + config.countdown)
            }
        case .countdown(let until):
            if !Side.allCases.allSatisfy(isReady) {
                stage = .lobby
            } else if now >= until {
                begin()
            }
        case .playing, .interrupted:
            followThePlayers(at: now)
        case .over:
            return
        }
    }

    private func followThePlayers(at now: Microseconds) {
        for side in mode.phoneSides where input.paddles[side]?.position != nil {
            matchPhones.insert(side)
            reconnectDeadlines[side] = nil
        }
        for side in matchPhones where input.vacant.contains(side) && reconnectDeadlines[side] == nil {
            reconnectDeadlines[side] = now + config.reconnectWindow
        }
        if input.viewerName != nil {
            viewerJoined = true
        }
        for side in mode.phoneSides {
            for request in input.paddles[side]?.pauseRequests ?? [] {
                handlePauseRequest(request, from: side)
            }
        }
        if let (side, deadline) = reconnectDeadlines.min(by: { $0.value < $1.value }) {
            if deadline <= now {
                pendingCommand = .forfeit(side)
            } else {
                waitForPhone(side, until: deadline)
            }
            return
        }
        if case .interrupted(let interruption) = stage {
            settle(interruption)
        }
        guard stage == .playing else { return }
        if let side = matchPhones.first(where: { side in
            input.paddles[side]?.lastPointerAt.map { $0 + config.pointerLostAfter < now } ?? false
        }) {
            interrupt(.pointerLost(side))
        } else if viewerJoined, input.viewerName == nil, !usesSideCamera {
            interrupt(.viewerLost(continued: []))
        }
    }

    private func waitForPhone(_ side: Side, until deadline: Microseconds) {
        switch stage {
        case .interrupted(.phoneLost):
            stage = .interrupted(.phoneLost(side, until: deadline))
        case .interrupted(let interruption):
            heldInterruption = interruption
            stage = .interrupted(.phoneLost(side, until: deadline))
        case .playing:
            interrupt(.phoneLost(side, until: deadline))
        case .lobby, .countdown, .over:
            return
        }
    }

    private func settle(_ interruption: Interruption) {
        switch interruption {
        case .phoneLost:
            if let held = heldInterruption {
                heldInterruption = nil
                stage = .interrupted(held)
                settle(held)
            } else {
                resumePlay()
            }
        case .viewerLost:
            if input.viewerName != nil {
                resumePlay()
            }
        case .byHost, .byPlayer, .pointerLost, .serveTimeouts:
            return
        }
    }

    private func handlePauseRequest(_ pause: Bool, from side: Side) {
        guard matchPhones.contains(side) else { return }
        if pause {
            if stage == .playing {
                interrupt(.byPlayer(side))
            }
            return
        }
        guard case .interrupted(let current) = stage else { return }
        if case .phoneLost = current {
            if let held = heldInterruption, held.canBeResumed(by: side) {
                heldInterruption = afterContinue(held, from: side)
            }
            return
        }
        guard current.canBeResumed(by: side) else { return }
        if let remaining = afterContinue(current, from: side) {
            stage = .interrupted(remaining)
        } else {
            if case .viewerLost = current {
                usesSideCamera = true
            }
            resumePlay()
        }
    }

    private func afterContinue(_ interruption: Interruption, from side: Side) -> Interruption? {
        guard case .viewerLost(let continued) = interruption else { return nil }
        let everyone = continued.union([side])
        return matchPhones.isSubset(of: everyone) ? nil : .viewerLost(continued: everyone)
    }

    private func interrupt(_ interruption: Interruption) {
        if stage == .playing {
            pendingCommand = .pause
        }
        stage = .interrupted(interruption)
    }

    private func resumePlay() {
        stage = .playing
        pendingCommand = .resume
    }

    private func phoneTarget(for side: Side) -> Double? {
        guard mode.phoneSides.contains(side), let position = input.paddles[side]?.position else { return nil }
        return side == .playerA ? position : 1 - position
    }

    private func queuePhoneSwings() {
        for side in Side.allCases where controller(of: side) == .phone {
            for swing in input.paddles[side]?.swings ?? [] {
                let step = swing.macPeakTime.map(timeline.step(at:)) ?? game.step
                pendingSwings.append(Swing(side: side, step: step, strength: swing.strength, aim: 0))
            }
        }
    }

    private func nextInput(local: LocalInput) -> StepInput {
        let command = pendingCommand
        let move = command == .pause ? nil : computer?.move(in: game)
        defer {
            pendingCommand = nil
            pendingSwings.removeAll()
        }
        return StepInput(
            targetA: target(for: .playerA, local: local),
            targetB: computer == nil ? target(for: .playerB, local: local) : move?.target,
            swings: pendingSwings + (move?.swing.map { [$0] } ?? []),
            command: command
        )
    }

    private func target(for side: Side, local: LocalInput) -> Double? {
        phoneTarget(for: side) ?? local.targets[side]
    }

    private func hapticsAndServeTimeouts(for events: [GameEvent], swings: [Swing]) -> [(Side, HapticKind)] {
        let isOver = events.contains { if case .gameOver = $0 { true } else { false } }
        var haptics: [(Side, HapticKind)] = []
        for event in events {
            switch event {
            case .served(let side):
                if swings.contains(where: { $0.side == side }) {
                    autoServes[side] = 0
                    haptics.append((side, .hit))
                } else {
                    autoServes[side, default: 0] += 1
                }
            case .hit(let side, _, _):
                haptics.append((side, .hit))
            case .whiff(let side):
                haptics.append((side, .miss))
            case .pointScored(let winner, _) where !isOver:
                haptics.append((winner, .point))
            case .gameOver(let winner):
                haptics.append((winner, .win))
            default:
                break
            }
        }
        return haptics
    }

    private func askAboutServeTimeouts() {
        guard stage == .playing,
              let side = matchPhones.first(where: { autoServes[$0, default: 0] >= config.serveTimeoutsBeforeAsking }) else { return }
        autoServes[side] = 0
        interrupt(.serveTimeouts(side))
    }

    private func publish(haptics: [(Side, HapticKind)]) {
        for (side, kind) in haptics where controller(of: side) == .phone {
            link.send(.haptic(kind), to: side)
        }
        for side in mode.phoneSides {
            guard let paddle = input.paddles[side] else {
                sentStates[side] = nil
                continue
            }
            let update = gameState(for: side, paddle: paddle)
            if sentStates[side] != update {
                sentStates[side] = update
                link.send(.gameState(update), to: side)
            }
        }
        if input.viewerName != nil {
            link.sendToViewer(snapshot)
        }
    }

    private func gameState(for side: Side, paddle: HostLink.PaddleInput) -> GameStateUpdate {
        let phase: GamePhase
        var canResume = false
        switch stage {
        case .lobby:
            switch readiness(of: side) {
            case .needsCalibration: phase = .calibrating
            case .ready: phase = .ready
            case .noPhone, .notReady, .measuring, .tooSlow: phase = .lobby
            }
        case .countdown:
            phase = .ready
        case .interrupted(let interruption):
            phase = .paused
            if case .phoneLost = interruption {
                canResume = heldInterruption?.canBeResumed(by: side) ?? false
            } else {
                canResume = interruption.canBeResumed(by: side)
            }
        case .playing, .over:
            phase = GamePhase(game.phase)
        }
        return GameStateUpdate(
            phase: phase,
            scoreA: scoreByte(game.score.a),
            scoreB: scoreByte(game.score.b),
            side: side,
            serving: server,
            canResume: canResume,
            connectionIsSlow: paddle.roundTrip.map { $0 > config.roundTripWarning } ?? false,
            winner: winner
        )
    }

    private var winner: Side? {
        if case .gameOver(let winner) = game.phase { return winner }
        return nil
    }

    private var server: Side {
        if case .serving(let side, _) = game.phase { return side }
        return game.score.server(firstServer: game.config.firstServer, target: game.config.winningScore, servesPerTurn: game.config.servesPerTurn)
    }

    private var tablePhase: GamePhase {
        switch stage {
        case .lobby: .lobby
        case .countdown: .ready
        case .playing, .interrupted, .over: GamePhase(game.phase)
        }
    }

    private var snapshot: TableSnapshot {
        TableSnapshot(
            step: game.step,
            ball: SIMD2<Float>(game.ball.position),
            velocity: SIMD2<Float>(game.ball.velocity),
            shotStart: SIMD2<Float>(game.shotStart),
            paddleA: Float(game.paddleX(of: .playerA)),
            paddleB: Float(game.paddleX(of: .playerB)),
            phase: tablePhase,
            scoreA: scoreByte(game.score.a),
            scoreB: scoreByte(game.score.b),
            serving: server,
            rally: UInt32(game.rally),
            winner: winner
        )
    }

    private func scoreByte(_ score: Int) -> UInt8 {
        UInt8(min(score, Int(UInt8.max)))
    }
}
