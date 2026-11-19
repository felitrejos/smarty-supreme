import SmartyCore
import Foundation
import Observation

@MainActor
@Observable
final class Referee {
    private static let commentaryKey = "commentary"

    var commentates: Bool {
        didSet { defaults.set(commentates, forKey: Self.commentaryKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock = SystemClock()
    @ObservationIgnored private let announcer = Announcer()
    @ObservationIgnored private var commentator = Commentator(names: [:])

    init(defaults: UserDefaults) {
        self.defaults = defaults
        commentates = defaults.object(forKey: Self.commentaryKey) as? Bool ?? true
    }

    func newGame(names: [Side: String], config: GameConfig, opponent: Side?) {
        commentator = Commentator(names: names, config: config, opponent: opponent, seed: UInt64.random(in: 0...UInt64.max))
    }

    func follow(_ events: [GameEvent], game: GameState) {
        guard commentates else { return }
        let now = clock.now
        commentator.observe(events, at: now)
        guard !announcer.isSpeaking, let line = commentator.next(at: now, duringRally: game.phase == .rally) else { return }
        announcer.say(line.text, as: line.kind == .opponent ? .computer : .referee)
    }
}
