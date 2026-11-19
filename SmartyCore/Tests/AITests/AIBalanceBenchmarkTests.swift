import SmartyCore
import Testing

#if DEBUG
private let isOptimized = false
#else
private let isOptimized = true
#endif

@Suite(.enabled(if: isOptimized, "Run in release: swift test -c release --filter AIBalanceBenchmarkTests"))
struct AIBalanceBenchmarkTests {
    private static let games = 1_000

    @Test(arguments: [
        (Difficulty.easy, 0.05...0.2),
        (Difficulty.medium, 0.4...0.6),
        (Difficulty.hard, 0.75...0.95),
    ])
    func aiWinsTheTargetShareOfGamesAgainstTheScriptedAveragePlayer(difficulty: Difficulty, target: ClosedRange<Double>) {
        var wins = 0
        var points = 0
        for game in 0..<Self.games {
            var duel = Duel(seed: UInt64(game) &* 7_919 &+ 11, playerA: .scriptedAverage, playerB: difficulty.profile)
            _ = duel.playToTheEnd()
            if duel.winner == .playerB {
                wins += 1
            }
            points += duel.game.score.a + duel.game.score.b
        }
        let share = Double(wins) / Double(Self.games)
        print("AI balance \(difficulty): won \(wins) of \(Self.games) games (\(share)), \(Double(points) / Double(Self.games)) points a game")

        #expect(target.contains(share))
    }

    @Test func aimingAwayWinsMoreAgainstAPlayerWithAWeakSide() {
        let weakness = Duel.Weakness(lane: .left, missShare: 0.1)
        var straight = Difficulty.medium.profile
        straight.aimsAwayShare = 0
        var without = 0
        var with = 0
        for game in 0..<Self.games {
            let seed = UInt64(game) &* 7_919 &+ 23
            var plain = Duel(seed: seed, playerA: .scriptedAverage, playerB: straight, weaknessA: weakness)
            var steered = Duel(seed: seed, playerA: .scriptedAverage, playerB: Difficulty.medium.profile, weaknessA: weakness)
            _ = plain.playToTheEnd()
            _ = steered.playToTheEnd()
            without += plain.winner == .playerB ? 1 : 0
            with += steered.winner == .playerB ? 1 : 0
        }
        let gain = Double(with - without) / Double(Self.games)
        print("Aiming away: Medium won \(without) of \(Self.games) without it and \(with) with it (\(gain * 100) points)")

        #expect(gain >= 0.04)
    }
}
