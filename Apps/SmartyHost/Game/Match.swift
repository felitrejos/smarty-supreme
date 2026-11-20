import SmartyCore
import Foundation
import Observation
import SwiftUI

enum CameraView: CaseIterable {
    case playerAEnd
    case playerBEnd
    case split

    var title: String {
        switch self {
        case .playerAEnd: "Player A’s End"
        case .playerBEnd: "Player B’s End"
        case .split: "Split Screen"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .playerAEnd: "1"
        case .playerBEnd: "2"
        case .split: "3"
        }
    }
}

struct StrokeTiming: Equatable {
    static let onTime = 0.025

    let timing: Double
    let number: Int

    var label: String {
        let milliseconds = Int((abs(timing) * 1_000).rounded())
        if abs(timing) <= Self.onTime { return "ON TIME" }
        return timing < 0 ? "EARLY · \(milliseconds) MS" : "LATE · \(milliseconds) MS"
    }
}

enum Opponent: String, CaseIterable {
    case computer
    case player

    var title: String {
        switch self {
        case .computer: "Computer"
        case .player: "Another Player"
        }
    }
}

extension Difficulty {
    var title: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }
}

struct MatchSetup {
    private static let opponentKey = "opponent"
    private static let difficultyKey = "difficulty"

    var opponent: Opponent
    var difficulty: Difficulty

    var mode: MatchMode {
        opponent == .computer ? .computer(difficulty) : .twoPlayers
    }

    static func saved(in defaults: UserDefaults) -> MatchSetup {
        MatchSetup(
            opponent: defaults.string(forKey: opponentKey).flatMap(Opponent.init(rawValue:)) ?? .computer,
            difficulty: defaults.string(forKey: difficultyKey).flatMap(Difficulty.init(rawValue:)) ?? .medium
        )
    }

    func save(in defaults: UserDefaults) {
        defaults.set(opponent.rawValue, forKey: Self.opponentKey)
        defaults.set(difficulty.rawValue, forKey: Self.difficultyKey)
    }
}

@MainActor
@Observable
final class Match {
    private static let keyboardControlsKey = "showsKeyboardControls"
    private static let keyboardStrength = 0.45
    private static let idealLead = 0.25
    private static let leadWeight = 0.25
    private static let largestTimingShare = 0.45

    private enum Direction {
        case left
        case right
    }

    private enum Hold {
        case choosingNewGame
        case appInBackground
        case asleep
        case screenLocked
    }

    private enum Key {
        case move(Side, Direction)
        case swing(Side)

        var side: Side {
            switch self {
            case .move(let side, _), .swing(let side): side
            }
        }
    }

    @ObservationIgnored private(set) var session: HostSession
    private(set) var setup: MatchSetup
    private(set) var score = Score(a: 0, b: 0)
    private(set) var phase: GameState.Phase
    private(set) var rally = 0
    private(set) var stage = MatchStage.lobby
    private(set) var controllerA = HostSession.Controller.local
    private(set) var controllerB = HostSession.Controller.local
    private(set) var dimmed: Set<Side> = []
    var showsKeyboardControls = UserDefaults.standard.object(forKey: Match.keyboardControlsKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsKeyboardControls, forKey: Self.keyboardControlsKey) }
    }
    var showsTutorial = false {
        didSet {
            if showsTutorial, stage == .playing, !isPaused {
                togglePause()
            }
        }
    }
    var camera = CameraView.playerAEnd
    private(set) var lastStroke: StrokeTiming?
    var isChoosingNewGame = false

    @ObservationIgnored let link: HostLink
    let referee: Referee
    @ObservationIgnored private let clock: any MonotonicClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var heldA: Set<Direction> = []
    @ObservationIgnored private var heldB: Set<Direction> = []
    @ObservationIgnored private var pendingSwings: [Swing] = []
    @ObservationIgnored private var readySwings: [Side: (flight: UInt64, at: UInt64, aim: Double)] = [:]
    @ObservationIgnored private var walkTargets: [Side: (flight: UInt64, target: Double)] = [:]
    private var holds: Set<Hold> = []

    init(link: HostLink, clock: any MonotonicClock, defaults: UserDefaults) {
        self.link = link
        self.clock = clock
        self.defaults = defaults
        let setup = MatchSetup.saved(in: defaults)
        self.setup = setup
        let session = Self.session(for: setup, link: link, clock: clock)
        self.session = session
        referee = Referee(defaults: defaults)
        phase = session.game.phase
        publish()
        startCommentary()
    }

    var game: GameState {
        session.game
    }

    var isPaused: Bool {
        if case .interrupted = stage { return true }
        return false
    }

    var isWaitingForADevice: Bool {
        switch stage {
        case .interrupted(.phoneLost), .interrupted(.viewerLost): true
        default: false
        }
    }

    var isGameOver: Bool {
        stage == .over
    }

    var hasStarted: Bool {
        switch stage {
        case .lobby, .countdown: false
        case .playing, .interrupted, .over: true
        }
    }

    var showsControls: Bool {
        isPaused || (showsKeyboardControls && stage == .playing && Side.allCases.contains { controller(of: $0) == .local })
    }

    var isSolo: Bool {
        setup.opponent == .computer
    }

    func name(of side: Side) -> String {
        controller(of: side) == .computer ? "Computer" : side.playerName
    }

    func controller(of side: Side) -> HostSession.Controller {
        side == .playerA ? controllerA : controllerB
    }

    func advance() -> [GameEvent] {
        var local = LocalInput()
        for side in Side.allCases where session.controller(of: side) == .local {
            local.targets[side] = walkTarget(for: side)
            fireReadySwing(for: side)
        }
        local.swings = pendingSwings
        pendingSwings.removeAll()
        let wasWaiting = !hasStarted
        let events = session.advance(local: local)
        if isHeld {
            session.hold()
        }
        referee.follow(events, game: session.game)
        for event in events {
            if case .stroke(let side, let timing) = event {
                lastStroke = StrokeTiming(timing: timing, number: (lastStroke?.number ?? 0) + 1)
            }
        }
        publish()
        if wasWaiting, stage == .playing, setup.opponent == .player {
            camera = link.viewerName == nil ? .split : .playerAEnd
        }
        if session.usesSideCamera, camera != .split {
            camera = .split
        }
        return events
    }

    func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]), let key = key(for: press) else { return .ignored }
        guard session.controller(of: key.side) == .local else { return .handled }
        let isDown = press.phase == .down
        switch key {
        case .move(let side, let direction):
            hold(direction, for: side, isDown)
        case .swing(let side):
            if isDown {
                swing(side)
            }
        }
        return .handled
    }

    var isHeld: Bool {
        !holds.isEmpty
    }

    func chooseNewGame() {
        addHold(.choosingNewGame)
        isChoosingNewGame = true
    }

    func cancelNewGame() {
        isChoosingNewGame = false
        removeHold(.choosingNewGame)
    }

    func appBecameActive(_ isActive: Bool) {
        if isActive {
            removeHold(.appInBackground)
        } else {
            releaseAllKeys()
            addHold(.appInBackground)
        }
    }

    func gameWindowClosed() {
        removeHold(.appInBackground)
    }

    func macWillSleep() {
        addHold(.asleep)
    }

    func macDidWake() {
        removeHold(.asleep)
    }

    func screenLocked() {
        addHold(.screenLocked)
    }

    func screenUnlocked() {
        removeHold(.screenLocked)
    }

    func start(_ newSetup: MatchSetup) {
        isChoosingNewGame = false
        holds.remove(.choosingNewGame)
        newSetup.save(in: defaults)
        setup = newSetup
        playAgain()
    }

    func playAgain() {
        session = Self.session(for: setup, link: link, clock: clock)
        pendingSwings.removeAll()
        releaseAllKeys()
        camera = .playerAEnd
        publish()
        startCommentary()
    }

    func togglePause() {
        guard !isWaitingForADevice else { return }
        if isPaused {
            session.resume()
        } else {
            session.pause()
        }
        publish()
    }

    func playOnWithoutTheMissingDevice() {
        session.resume()
        publish()
    }

    func startNow() {
        session.startNow()
    }

    func letWaitingPhonePlay(_ side: Side, peer: PeerID) {
        session.fillVacancy(side, with: peer)
    }

    func readiness(of side: Side) -> Readiness {
        session.readiness(of: side)
    }

    func releaseAllKeys() {
        heldA.removeAll()
        heldB.removeAll()
    }

    private func startCommentary() {
        let opponent = Side.allCases.first { controller(of: $0) == .computer }
        referee.newGame(names: Dictionary(uniqueKeysWithValues: Side.allCases.map { ($0, name(of: $0)) }), config: session.game.config, opponent: opponent)
    }

    private func addHold(_ reason: Hold) {
        holds.insert(reason)
        session.hold()
        publish()
    }

    private func removeHold(_ reason: Hold) {
        holds.remove(reason)
        guard holds.isEmpty else { return }
        session.releaseHold()
        publish()
    }

    private func publish() {
        let game = session.game
        if score != game.score {
            score = game.score
        }
        if phase != game.phase {
            phase = game.phase
        }
        if rally != game.rally {
            rally = game.rally
        }
        if stage != session.stage {
            stage = session.stage
        }
        let currentA = session.controller(of: .playerA)
        let currentB = session.controller(of: .playerB)
        if controllerA != currentA || controllerB != currentB {
            controllerA = currentA
            controllerB = currentB
            releaseAllKeys()
        }
        let currentDimmed = Set(Side.allCases.filter(session.isPointerStale))
        if dimmed != currentDimmed {
            dimmed = currentDimmed
        }
    }

    private func key(for press: KeyPress) -> Key? {
        switch press.key {
        case .leftArrow: return .move(.playerB, .left)
        case .rightArrow: return .move(.playerB, .right)
        case .upArrow: return .swing(.playerB)
        default: break
        }
        switch press.characters.lowercased() {
        case "a": return .move(.playerA, .left)
        case "d": return .move(.playerA, .right)
        case "w": return .swing(.playerA)
        default: return nil
        }
    }

    private func hold(_ direction: Direction, for side: Side, _ isDown: Bool) {
        if side == .playerA {
            heldA = isDown ? heldA.union([direction]) : heldA.subtracting([direction])
        } else {
            heldB = isDown ? heldB.union([direction]) : heldB.subtracting([direction])
        }
    }

    private func swing(_ side: Side) {
        let game = session.game
        let aim = steering(held(side)) * (facesPlayerBEnd(side) ? -1 : 1)
        if case .serving(side, _) = game.phase {
            pendingSwings.append(Swing(side: side, step: game.step, strength: Self.keyboardStrength, aim: aim))
            return
        }
        guard readySwings[side]?.flight != game.flightNumber, let contact = game.predictedContact(for: side) else { return }
        let config = game.config
        let contactStep = Double(game.step + contact.stepsAway)
        let earliness = Double(contact.stepsAway) / Double(config.stepsPerSecond) - Self.idealLead
        let largest = config.swingWindow * Self.largestTimingShare
        let offset = min(max(-earliness * Self.leadWeight, -largest), largest) * Double(config.stepsPerSecond)
        readySwings[side] = (game.flightNumber, UInt64(max(contactStep + offset, Double(game.step)).rounded()), aim)
    }

    private func fireReadySwing(for side: Side) {
        let game = session.game
        guard let ready = readySwings[side], ready.flight == game.flightNumber, game.step >= ready.at else { return }
        readySwings[side] = nil
        pendingSwings.append(Swing(side: side, step: ready.at, strength: Self.keyboardStrength, aim: ready.aim))
    }

    private func walkTarget(for side: Side) -> Double {
        let game = session.game
        if walkTargets[side]?.flight != game.flightNumber {
            let x = game.predictedContact(for: side)?.position.x ?? game.config.tableWidth / 2
            walkTargets[side] = (game.flightNumber, game.config.position(ofPaddleX: x))
        }
        return walkTargets[side]?.target ?? 0.5
    }

    private func facesPlayerBEnd(_ side: Side) -> Bool {
        side == .playerB && [.split, .playerBEnd].contains(camera)
    }

    private func held(_ side: Side) -> Set<Direction> {
        side == .playerA ? heldA : heldB
    }

    private func steering(_ held: Set<Direction>) -> Double {
        (held.contains(.right) ? 1 : 0) - (held.contains(.left) ? 1 : 0)
    }

    private static func session(for setup: MatchSetup, link: HostLink, clock: any MonotonicClock) -> HostSession {
        HostSession(link: link, clock: clock, mode: setup.mode, seed: freshSeed(), aiSeed: freshSeed())
    }

    private static func freshSeed() -> UInt64 {
        UInt64.random(in: 0...UInt64.max)
    }
}
