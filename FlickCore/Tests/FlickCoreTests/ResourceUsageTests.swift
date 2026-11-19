import FlickCore
import Testing

struct ResourceUsageTests {
    @Test func cpuShareIsProcessorTimeOverWallTime() {
        let start = ResourceSample(cpuSeconds: 10, wallSeconds: 100, memoryBytes: 0)
        let end = ResourceSample(cpuSeconds: 10.5, wallSeconds: 102, memoryBytes: 0)

        #expect(end.cpuShare(since: start) == 0.25)
    }

    @Test func readingTheProcessShowsWorkAndMemory() {
        let before = ResourceSample.current()
        var total = 0.0
        for value in 0..<3_000_000 {
            total += Double(value).squareRoot()
        }
        let after = ResourceSample.current()

        #expect(total > 0)
        #expect(after.cpuSeconds > before.cpuSeconds)
        #expect(after.wallSeconds > before.wallSeconds)
        #expect(after.memoryBytes > 1_000_000)
    }
}
