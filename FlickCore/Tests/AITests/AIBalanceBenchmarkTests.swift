import FlickCore
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
}
