import FlickCore
import FlickTestSupport
import Testing

#if DEBUG
private let isOptimized = false
#else
private let isOptimized = true
#endif

@Suite(.enabled(if: isOptimized, "Run in release: swift test -c release --filter SoakTests"))
struct SoakTests {
    private static let minutes = 30
    private static let warmUpMinutes = 2
    private static let memoryGrowthLimit: Int64 = 5_000_000
    private static let recoveryLimit: Microseconds = 3_000_000

    @Test func thirtyMinutesOfPlayWithDropsPausesAndALostScreenStaysHealthy() throws {
        let harness = SessionHarness(mode: .twoPlayers, conditions: LinkConditions(latency: 10_000, jitter: 5_000, unreliableLossRate: 0.02))
        harness.addBot("Phone A", side: .playerA, missRate: 0.1)
        harness.addBot("Phone B", side: .playerB, missRate: 0.12)
        let phoneB = harness.phone("Phone B")
        _ = harness.addViewer("Studio Mac")
        harness.run(for: 2_000_000)
        harness.session.startNow()

        var games = 0
        var memoryAfterWarmUp: UInt64?
        for minute in 0..<Self.minutes {
            if minute == Self.warmUpMinutes {
                memoryAfterWarmUp = ResourceSample.current().memoryBytes
            }
            disrupt(harness, minute: minute, phoneB: phoneB)
            for _ in 0..<6 {
                harness.run(for: 10_000_000)
                if case .gameOver(let winner) = harness.session.game.phase {
                    #expect(harness.session.game.score[winner] >= harness.session.game.config.winningScore, "Game \(games + 1) ended without being won on points")
                    games += 1
                    harness.startNewSession(mode: .twoPlayers)
                    harness.session.startNow()
                    harness.run(for: 100_000)
                }
            }
            #expect(harness.session.stage == .playing, "Stuck after minute \(minute): \(harness.session.stage)")
            #expect(Side.allCases.allSatisfy { harness.session.controller(of: $0) == .phone }, "A phone stopped playing after minute \(minute)")
        }
        let growth = Int64(ResourceSample.current().memoryBytes) - Int64(try #require(memoryAfterWarmUp))
        print("Soak: \(games) games in \(Self.minutes) simulated minutes, memory grew \(Double(growth) / 1_000_000) MB after warm-up")

        #expect(games >= 3)
        #expect(growth < Self.memoryGrowthLimit)
    }

    private func disrupt(_ harness: SessionHarness, minute: Int, phoneB: PaddleLink) {
        guard harness.session.stage == .playing else { return }
        switch minute % 4 {
        case 1:
            harness.link.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
            harness.run(for: 1_000_000)
            expectInterruption(harness) { if case .phoneLost(.playerA, _) = $0 { true } else { false } }
            harness.run(for: 4_000_000)
            harness.link.network.connect(PeerID("Phone A"), LinkHarness.hostID)
        case 2:
            phoneB.requestPause(true)
            harness.run(for: 1_000_000)
            expectInterruption(harness) { $0 == .byPlayer(.playerB) }
            harness.run(for: 2_000_000)
            phoneB.requestPause(false)
        case 3:
            harness.link.network.disconnect(PeerID("Studio Mac"), LinkHarness.hostID)
            harness.run(for: 1_000_000)
            expectInterruption(harness) { if case .viewerLost = $0 { true } else { false } }
            harness.run(for: 3_000_000)
            harness.link.network.connect(PeerID("Studio Mac"), LinkHarness.hostID)
        default:
            return
        }
        harness.run(until: { $0.session.stage == .playing }, limit: Self.recoveryLimit)
    }

    private func expectInterruption(_ harness: SessionHarness, matching expected: (Interruption) -> Bool) {
        guard case .interrupted(let interruption) = harness.session.stage, expected(interruption) else {
            Issue.record("Expected the disruption to interrupt the match, got \(harness.session.stage)")
            return
        }
    }
}
