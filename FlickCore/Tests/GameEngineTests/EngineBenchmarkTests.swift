import FlickCore
import Testing

struct EngineBenchmarkTests {
    @Test func engineStepStaysUnderOneTenthOfAMillisecondAtThe99thPercentile() {
        var random = SplitMix64(seed: 5)
        var game = GameState(seed: 5)
        let clock = ContinuousClock()
        var durations: [Duration] = []
        durations.reserveCapacity(100_000)
        for _ in 0..<100_000 {
            var input = StepInput(targetA: Double.random(in: 0...1, using: &random), targetB: Double.random(in: 0...1, using: &random))
            if Int.random(in: 0..<30, using: &random) == 0 {
                let side: Side = Bool.random(using: &random) ? .playerA : .playerB
                input.swings = [Swing(side: side, step: game.step, strength: 0.5, aim: 0)]
            }
            let start = clock.now
            _ = game.step(input)
            durations.append(clock.now - start)
        }
        durations.sort()
        let p50 = durations[durations.count / 2]
        let p99 = durations[durations.count * 99 / 100]
        print("Engine step: p50 \(p50), p99 \(p99) over \(durations.count) steps")
        #expect(p99 < .microseconds(100))
    }
}
