import FlickCore
import Foundation
import Observation

@MainActor
@Observable
final class FrameStats {
    static let budget: TimeInterval = 1.0 / 120
    static let cpuBudget = 0.2
    static let memoryGrowthBudget: Int64 = 5_000_000
    private static let droppedAfter: TimeInterval = 1.5 / 120
    private static let window: TimeInterval = 60
    private static let summaryInterval: TimeInterval = 0.5

    private(set) var percentile99: TimeInterval?
    private(set) var dropped = 0
    private(set) var measured: TimeInterval = 0
    private(set) var cpuShare: Double?
    private(set) var memoryBytes: UInt64 = 0
    private(set) var memoryGrowth: Int64 = 0
    private(set) var swingLatency95: Microseconds?

    @ObservationIgnored private var frames: [TimeInterval] = []
    @ObservationIgnored private var lastSample: ResourceSample?
    @ObservationIgnored private var firstMemory: UInt64?
    @ObservationIgnored private var sinceSummary: TimeInterval = 0

    func record(_ frame: TimeInterval, swingLatency: () -> Microseconds? = { nil }) {
        frames.append(frame)
        sinceSummary += frame
        guard sinceSummary >= Self.summaryInterval else { return }
        sinceSummary = 0
        summarize()
        sampleResources()
        swingLatency95 = swingLatency()
    }

    private func sampleResources() {
        let sample = ResourceSample.current()
        if let lastSample {
            cpuShare = sample.cpuShare(since: lastSample)
        }
        lastSample = sample
        let first = firstMemory ?? sample.memoryBytes
        firstMemory = first
        memoryBytes = sample.memoryBytes
        memoryGrowth = Int64(sample.memoryBytes) - Int64(first)
    }

    private func summarize() {
        var total = frames.reduce(0, +)
        var dropCount = 0
        while total > Self.window, dropCount < frames.count {
            total -= frames[dropCount]
            dropCount += 1
        }
        frames.removeFirst(dropCount)
        let sorted = frames.sorted()
        percentile99 = sorted.isEmpty ? nil : sorted[Int(Double(sorted.count - 1) * 0.99)]
        dropped = frames.filter { $0 > Self.droppedAfter }.count
        measured = frames.reduce(0, +)
    }
}
