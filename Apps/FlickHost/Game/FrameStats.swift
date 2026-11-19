import FlickCore
import Foundation
import Observation

@MainActor
@Observable
final class FrameStats {
    private static let summaryInterval: TimeInterval = 0.5

    private(set) var framesPerSecond: Double?
    private(set) var cpuShare: Double?

    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var sinceSummary: TimeInterval = 0
    @ObservationIgnored private var lastSample: ResourceSample?

    func record(_ frame: TimeInterval) {
        frames += 1
        sinceSummary += frame
        guard sinceSummary >= Self.summaryInterval else { return }
        framesPerSecond = Double(frames) / sinceSummary
        frames = 0
        sinceSummary = 0
        let sample = ResourceSample.current()
        if let lastSample {
            cpuShare = sample.cpuShare(since: lastSample)
        }
        lastSample = sample
    }
}
