import FlickCore
import Foundation
import Observation

@MainActor
@Observable
final class ViewerMatch {
    private static let tickInterval: TimeInterval = 0.1
    private static let summaryEvery = 60

    let config = GameConfig()
    let networkFailure = NetworkFailure()
    private(set) var status = ViewerLink.Status.searching
    private(set) var score = Score(a: 0, b: 0)
    private(set) var phase = GamePhase.lobby
    private(set) var winner: Side?
    private(set) var delayPercentile95: Microseconds?

    @ObservationIgnored private let link: ViewerLink
    @ObservationIgnored private let transport: MultipeerTransport
    @ObservationIgnored private let clock = SystemClock()
    @ObservationIgnored private var display: ViewerDisplay
    @ObservationIgnored private var previous: ViewerDisplay.Frame?
    @ObservationIgnored private var delays = DelayHistogram()
    @ObservationIgnored private var framesSinceSummary = 0
    @ObservationIgnored private var tickTimer: Timer?

    init(name: String) {
        let relay = EventRelay()
        let failure = networkFailure
        transport = MultipeerTransport(mode: .browse, onEvent: relay.forward, onFailure: failure.record)
        link = ViewerLink(name: name, transport: transport, clock: SystemClock())
        relay.connect(link.handle)
        display = ViewerDisplay(config: config)
    }

    func start() {
        guard tickTimer == nil else { return }
        transport.start()
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [link] _ in
            link.tick()
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        transport.stop()
    }

    func pose() -> TablePose? {
        let currentStatus = link.status
        if status != currentStatus {
            status = currentStatus
        }
        guard let latest = link.latest else {
            display = ViewerDisplay(config: config)
            previous = nil
            return nil
        }
        let now = clock.now
        let frame = display.frame(from: latest, at: now)
        let pose = TablePose(frame: frame, previous: previous)
        previous = frame
        publish(frame, winner: latest.snapshot.winner)
        record(link.snapshotAge(at: now))
        return pose
    }

    private func publish(_ frame: ViewerDisplay.Frame, winner currentWinner: Side?) {
        let currentScore = Score(a: frame.scoreA, b: frame.scoreB)
        if score != currentScore {
            score = currentScore
        }
        if phase != frame.phase {
            phase = frame.phase
        }
        if winner != currentWinner {
            winner = currentWinner
        }
    }

    private func record(_ age: Microseconds?) {
        guard let age else { return }
        delays.add(age)
        framesSinceSummary += 1
        guard framesSinceSummary >= Self.summaryEvery else { return }
        framesSinceSummary = 0
        delayPercentile95 = delays.percentile(0.95)
    }
}

private struct DelayHistogram {
    private static let bucket: Microseconds = 100
    private static let buckets = 1_000

    private var counts = [Int](repeating: 0, count: buckets)
    private var total = 0

    mutating func add(_ delay: Microseconds) {
        counts[min(Int(delay / Self.bucket), Self.buckets - 1)] += 1
        total += 1
    }

    func percentile(_ fraction: Double) -> Microseconds {
        var remaining = Int((Double(total) * fraction).rounded(.up))
        let below = counts.prefix { count in
            remaining -= count
            return remaining > 0
        }
        return Microseconds(below.count + 1) * Self.bucket
    }
}
