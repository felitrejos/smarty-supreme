import SmartyCore
import Testing

struct StepTimelineTests {
    @Test func aTimeFiftyMillisecondsBeforeTheMarkIsTwelveStepsEarlier() {
        let timeline = StepTimeline(step: 1_000, at: 10_000_000, stepsPerSecond: 240)

        #expect(timeline.step(at: 9_950_000) == 988)
    }

    @Test func aTimeAfterTheMarkIsTheMarkedStep() {
        let timeline = StepTimeline(step: 1_000, at: 10_000_000, stepsPerSecond: 240)

        #expect(timeline.step(at: 10_200_000) == 1_000)
    }

    @Test func aTimeBeforeTheFirstStepIsStepZero() {
        let timeline = StepTimeline(step: 10, at: 10_000_000, stepsPerSecond: 240)

        #expect(timeline.step(at: 0) == 0)
    }

    @Test func markingMovesTheTimelineOn() {
        var timeline = StepTimeline(step: 0, at: 0, stepsPerSecond: 240)
        timeline.mark(step: 240, at: 2_000_000)

        #expect(timeline.step(at: 1_500_000) == 120)
    }
}
