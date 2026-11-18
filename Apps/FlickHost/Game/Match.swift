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
    case keyboard

    var title: String {
        switch self {
        case .computer: "Computer"
        case .keyboard: "Second Player on This Keyboard"
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
    private static let longestFrame = 0.1

    private enum Direction {
        case left
        case right
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

    @ObservationIgnored private(set) var game: GameState
    private(set) var setup: MatchSetup
    private(set) var score = Score(a: 0, b: 0)
    private(set) var phase: GameState.Phase
    private(set) var rally = 0
    private(set) var isPhonePlaying = false
    private var controlsRequested = true
    var camera = CameraView.playerAEnd
    var isChoosingNewGame = false

    @ObservationIgnored private let link: HostLink
    @ObservationIgnored private let clock: any MonotonicClock
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var computer: AIController?
    @ObservationIgnored private var timeline: StepTimeline
    @ObservationIgnored private var heldA: Set<Direction> = []
    @ObservationIgnored private var heldB: Set<Direction> = []
    @ObservationIgnored private var pendingSwings: [Swing] = []
    @ObservationIgnored private var pendingCommand: GameCommand?
    @ObservationIgnored private var phoneTarget: Double?
    @ObservationIgnored private var phoneSwung = false
    @ObservationIgnored private var unsimulatedTime = 0.0
    @ObservationIgnored private var pausedForNewGame = false

    init(link: HostLink, clock: any MonotonicClock, defaults: UserDefaults) {
        self.link = link
        self.clock = clock
        self.defaults = defaults
        setup = MatchSetup.saved(in: defaults)
        let game = GameState(seed: Self.freshSeed())
        self.game = game
        timeline = StepTimeline(step: 0, at: clock.now, stepsPerSecond: game.config.stepsPerSecond)
        phase = .serving(.playerA, since: 0)
        computer = Self.computer(for: setup)
        publish()
    }

    var isPaused: Bool {
        phase == .paused
    }

    var isGameOver: Bool {
        if case .gameOver = phase { return true }
        return false
    }

    var showsControls: Bool {
        isPaused || (controlsRequested && !isGameOver)
    }

    func name(of side: Side) -> String {
        side == .playerB && setup.opponent == .computer ? "Computer" : side.playerName
    }

    func playsOnKeyboard(_ side: Side) -> Bool {
        side == .playerA ? !isPhonePlaying : setup.opponent == .keyboard
    }

    func advance(by elapsed: TimeInterval) -> [GameEvent] {
        let now = clock.now
        takePhoneInput(keepingSwings: elapsed <= Self.longestFrame)
        unsimulatedTime += min(elapsed, Self.longestFrame)
        let stepDuration = 1 / Double(game.config.stepsPerSecond)
        var events: [GameEvent] = []
        while unsimulatedTime >= stepDuration {
            unsimulatedTime -= stepDuration
            events += game.step(nextInput())
        }
        timeline.mark(step: game.step, at: now)
        if events.contains(where: { if case .served = $0 { true } else { false } }) {
            controlsRequested = false
        }
        sendHaptics(for: events)
        publish()
        return events
    }

    func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]), let key = key(for: press) else { return .ignored }
        guard playsOnKeyboard(key.side) else { return .handled }
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

    func chooseNewGame() {
        let willBePaused = pendingCommand.map { $0 == .pause } ?? isPaused
        if !willBePaused, !isGameOver {
            pendingCommand = .pause
            pausedForNewGame = true
        }
        isChoosingNewGame = true
    }

    func cancelNewGame() {
        isChoosingNewGame = false
        if pausedForNewGame {
            pendingCommand = .resume
            pausedForNewGame = false
        }
    }

    func start(_ newSetup: MatchSetup) {
        isChoosingNewGame = false
        pausedForNewGame = false
        newSetup.save(in: defaults)
        setup = newSetup
        playAgain()
    }

    func playAgain() {
        game = GameState(seed: Self.freshSeed())
        computer = Self.computer(for: setup)
        timeline = StepTimeline(step: 0, at: clock.now, stepsPerSecond: game.config.stepsPerSecond)
        pendingSwings.removeAll()
        pendingCommand = nil
        controlsRequested = true
        publish()
    }

    func togglePause() {
        pendingCommand = isPaused ? .resume : .pause
    }

    func showControls() {
        controlsRequested = true
    }

    func releaseAllKeys() {
        heldA.removeAll()
        heldB.removeAll()
    }

    private func takePhoneInput(keepingSwings: Bool) {
        let phone = link.takeInput()[.playerA]
        guard let phone, let position = phone.position else {
            if isPhonePlaying {
                stopPhonePlay()
            }
            return
        }
        if !isPhonePlaying {
            isPhonePlaying = true
            releaseAllKeys()
        }
        phoneTarget = position
        phoneSwung = keepingSwings && !phone.swings.isEmpty
        guard keepingSwings else { return }
        for swing in phone.swings {
            let step = swing.macPeakTime.map(timeline.step(at:)) ?? game.step
            pendingSwings.append(Swing(side: .playerA, step: step, strength: swing.strength, aim: 0))
        }
    }

    private func stopPhonePlay() {
        isPhonePlaying = false
        phoneTarget = nil
        phoneSwung = false
        pausedForNewGame = false
        if !isGameOver {
            pendingCommand = .pause
        }
    }

    private func sendHaptics(for events: [GameEvent]) {
        guard isPhonePlaying else { return }
        let isOver = events.contains { if case .gameOver = $0 { true } else { false } }
        for event in events {
            switch event {
            case .served(.playerA) where phoneSwung, .hit(.playerA, _, _):
                link.send(.hit, to: .playerA)
            case .whiff(.playerA):
                link.send(.miss, to: .playerA)
            case .pointScored(.playerA, _) where !isOver:
                link.send(.point, to: .playerA)
            case .gameOver(.playerA):
                link.send(.win, to: .playerA)
            default:
                break
            }
        }
    }

    private func publish() {
        if score != game.score {
            score = game.score
        }
        if phase != game.phase {
            phase = game.phase
        }
        if rally != game.rally {
            rally = game.rally
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
        let held = side == .playerA ? heldA : heldB
        pendingSwings.append(Swing(side: side, step: game.step, strength: Self.keyboardStrength, aim: steering(held) * Self.keyboardAim))
    }

    private func nextInput() -> StepInput {
        defer {
            pendingSwings.removeAll()
            pendingCommand = nil
        }
        let move = pendingCommand == .pause ? nil : computer?.move(in: game)
        return StepInput(
            targetA: isPhonePlaying ? phoneTarget : keyboardTarget(for: .playerA, held: heldA),
            targetB: computer == nil ? keyboardTarget(for: .playerB, held: heldB) : move?.target,
            swings: pendingSwings + (move?.swing.map { [$0] } ?? []),
            command: pendingCommand
        )
    }

    private func keyboardTarget(for side: Side, held: Set<Direction>) -> Double {
        switch steering(held) {
        case ..<0: 0
        case 0: game.paddlePosition(of: side)
        default: 1
        }
    }

    private func steering(_ held: Set<Direction>) -> Double {
        (held.contains(.right) ? 1 : 0) - (held.contains(.left) ? 1 : 0)
    }

    private static func computer(for setup: MatchSetup) -> AIController? {
        guard setup.opponent == .computer else { return nil }
        return AIController(side: .playerB, profile: setup.difficulty.profile, seed: freshSeed())
    }

    private static func freshSeed() -> UInt64 {
        UInt64.random(in: 0...UInt64.max)
    }
}
