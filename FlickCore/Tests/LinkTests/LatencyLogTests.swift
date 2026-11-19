import FlickCore
import Testing

struct LatencyLogTests {
    @Test func reportsTheNinetyFifthPercentileOfWhatItHolds() {
        var log = LatencyLog(capacity: 100)
        for value in 1...100 {
            log.add(Microseconds(value * 1_000))
        }

        #expect(log.percentile(0.95) == 95_000)
        #expect(log.percentile(0.5) == 50_000)
    }

    @Test func keepsOnlyTheMostRecentValues() {
        var log = LatencyLog(capacity: 3)
        for value: Microseconds in [90_000, 80_000, 1_000, 2_000, 3_000] {
            log.add(value)
        }

        #expect(log.percentile(1) == 3_000)
    }

    @Test func anEmptyLogHasNoPercentile() {
        #expect(LatencyLog(capacity: 3).percentile(0.95) == nil)
    }
}
