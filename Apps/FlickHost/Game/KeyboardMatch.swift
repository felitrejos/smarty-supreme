import FlickCore
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

@MainActor
@Observable
final class KeyboardMatch {
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
    }

    @ObservationIgnored private(set) var game = GameState(seed: KeyboardMatch.freshSeed())
    private(set) var score = Score(a: 0, b: 0)
    private(set) var phase: GameState.Phase
    private(set) var rally = 0
    private var controlsRequested = true
    var camera = CameraView.playerAEnd

    @ObservationIgnored private var heldA: Set<Direction> = []
    @ObservationIgnored private var heldB: Set<Direction> = []
    @ObservationIgnored private var pendingSwings: [Swing] = []
    @ObservationIgnored private var pendingCommand: GameCommand?
    @ObservationIgnored private var unsimulatedTime = 0.0

    init() {
        phase = .serving(.playerA, since: 0)
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

    func advance(by elapsed: TimeInterval) -> [GameEvent] {
        unsimulatedTime += min(elapsed, Self.longestFrame)
        let stepDuration = 1 / Double(game.config.stepsPerSecond)
        var events: [GameEvent] = []
        while unsimulatedTime >= stepDuration {
            unsimulatedTime -= stepDuration
            events += game.step(nextInput())
        }
        if events.contains(where: { if case .served = $0 { true } else { false } }) {
            controlsRequested = false
        }
        publish()
        return events
    }

    func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]), let key = key(for: press) else { return .ignored }
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

    func newGame() {
        game = GameState(seed: Self.freshSeed())
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
        return StepInput(
            targetA: target(for: .playerA, held: heldA),
            targetB: target(for: .playerB, held: heldB),
            swings: pendingSwings,
            command: pendingCommand
        )
    }

    private func target(for side: Side, held: Set<Direction>) -> Double {
        switch steering(held) {
        case ..<0: 0
        case 0: game.paddlePosition(of: side)
        default: 1
        }
    }

    private func steering(_ held: Set<Direction>) -> Double {
        (held.contains(.right) ? 1 : 0) - (held.contains(.left) ? 1 : 0)
    }

    private static func freshSeed() -> UInt64 {
        UInt64.random(in: 0...UInt64.max)
    }
}
