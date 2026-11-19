import SmartyTestSupport
import Testing

struct ManualClockTests {
    @Test func advancesByDurationAndToInstant() {
        let clock = ManualClock()
        #expect(clock.now == 0)
        clock.advance(by: 16_667)
        #expect(clock.now == 16_667)
        clock.advance(to: 50_000)
        #expect(clock.now == 50_000)
    }
}
