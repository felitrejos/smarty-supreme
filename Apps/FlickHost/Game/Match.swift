import FlickCore
import Foundation
import Observation
import SwiftUI

enum CameraView: CaseIterable {
    case playerAEnd
    case playerBEnd
    case side

    var title: String {
        switch self {
        case .playerAEnd: "Player A’s End"
        case .playerBEnd: "Player B’s End"
        case .side: "Side View"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .playerAEnd: "1"
        case .playerBEnd: "2"
        case .side: "3"
        }
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
    private static let keyboardStrength = 0.6
    private static let keyboardAim = 0.6

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
    private var controlsRequested = true
    var camera = CameraView.playerAEnd
    var isChoosingNewGame = false

    @ObservationIgnored let link: HostLink
    @ObservationIgnored private let clock: any MonotonicClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var heldA: Set<Direction> = []
    @ObservationIgnored private var heldB: Set<Direction> = []
    @ObservationIgnored private var pendingSwings: [Swing] = []
    private var holds: Set<Hold> = []

    init(link: HostLink, clock: any MonotonicClock, defaults: UserDefaults) {
        self.link = link
        self.clock = clock
        self.defaults = defaults
        let setup = MatchSetup.saved(in: defaults)
        self.setup = setup
        let session = Self.session(for: setup, link: link, clock: clock)
        self.session = session
        phase = session.game.phase
        publish()
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
        isPaused || (controlsRequested && stage == .playing)
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
            local.targets[side] = keyboardTarget(for: side)
        }
        local.swings = pendingSwings
        pendingSwings.removeAll()
        let wasWaiting = !hasStarted
        let events = session.advance(local: local)
        if isHeld {
            session.hold()
        }
        if events.contains(where: { if case .served = $0 { true } else { false } }) {
            controlsRequested = false
        }
        publish()
        if wasWaiting, stage == .playing, setup.opponent == .player {
            camera = link.viewerName == nil ? .side : .playerAEnd
        }
        if session.usesSideCamera, camera != .side {
            camera = .side
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
        controlsRequested = true
        camera = .playerAEnd
        publish()
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

    func swapSides() {
        session.swapSides()
        publish()
    }

    func letWaitingPhonePlay(_ side: Side, peer: PeerID) {
        session.fillVacancy(side, with: peer)
    }

    func readiness(of side: Side) -> Readiness {
        session.readiness(of: side)
    }

    func showControls() {
        controlsRequested = true
    }

    func releaseAllKeys() {
        heldA.removeAll()
        heldB.removeAll()
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
        pendingSwings.append(Swing(side: side, step: session.game.step, strength: Self.keyboardStrength, aim: steering(held(side)) * Self.keyboardAim))
    }

    private func held(_ side: Side) -> Set<Direction> {
        side == .playerA ? heldA : heldB
    }

    private func keyboardTarget(for side: Side) -> Double {
        switch steering(held(side)) {
        case ..<0: 0
        case 0: session.game.paddlePosition(of: side)
        default: 1
        }
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
