import FlickCore
import FlickTestSupport
import simd
import Testing

struct ViewerTests {
    @Test func aViewerWithLossySnapshotsShowsTheHostsScoreAndPhaseWithoutTheBallJumping() throws {
        let harness = SessionHarness(mode: .twoPlayers, conditions: LinkConditions(unreliableLossRate: 0.05))
        harness.addBot("Phone A", side: .playerA)
        harness.addBot("Phone B", side: .playerB)
        let viewer = harness.addViewer("Studio Mac")
        harness.run(for: 2_000_000)
        harness.session.startNow()

        var display = ViewerDisplay(config: harness.session.game.config)
        var previous: ViewerDisplay.Frame?
        var worstJump = 0.0
        var rallyFrames = 0
        harness.run(for: 20_000_000) { harness in
            guard let latest = viewer.latest else { return }
            let frame = display.frame(from: latest, at: harness.clock.now)
            defer { previous = frame }
            guard let previous, previous.phase == .rally, frame.phase == .rally, frame.rally >= previous.rally else { return }
            let fastest = max(simd_length(previous.velocity), simd_length(frame.velocity))
            let jump = simd_length(frame.ball - previous.ball) - fastest * SessionHarness.frameSeconds
            worstJump = max(worstJump, jump)
            rallyFrames += 1
        }
        harness.run(for: 200_000)

        let latest = try #require(viewer.latest)
        #expect(rallyFrames > 500)
        #expect(worstJump <= 0.01)
        #expect(Int(latest.snapshot.scoreA) == harness.session.game.score.a)
        #expect(Int(latest.snapshot.scoreB) == harness.session.game.score.b)
        #expect(latest.snapshot.phase == GamePhase(harness.session.game.phase))
    }

    @Test func theViewerFollowsAPauseAndANewMatch() throws {
        let harness = SessionHarness(mode: .computer(.medium))
        let viewer = harness.addViewer("Studio Mac")
        harness.run(for: 3_000_000)
        let playedSteps = try #require(viewer.latest).snapshot.step

        harness.session.pause()
        harness.run(for: 200_000)
        #expect(try #require(viewer.latest).snapshot.phase == .paused)

        harness.startNewSession(mode: .computer(.easy))
        harness.run(for: 200_000)
        #expect(try #require(viewer.latest).snapshot.step < playedSteps)
    }

    @Test func aViewerThatLosesTheHostForgetsTheLastSnapshot() {
        let harness = SessionHarness(mode: .computer(.medium))
        let viewer = harness.addViewer("Studio Mac")
        harness.run(for: 500_000)

        harness.link.network.disconnect(PeerID("Studio Mac"), LinkHarness.hostID)
        harness.run(for: 100_000)

        #expect(viewer.latest == nil)
    }

    @Test func theViewerKeepsOnlyTheNewestSnapshot() throws {
        let harness = SessionHarness(mode: .computer(.medium), conditions: LinkConditions(latency: 20_000, jitter: 15_000))
        let viewer = harness.addViewer("Studio Mac")
        var newest: UInt64 = 0
        var wentBack = false

        harness.run(for: 3_000_000) { _ in
            guard let step = viewer.latest?.snapshot.step else { return }
            wentBack = wentBack || step < newest
            newest = max(newest, step)
        }

        #expect(newest > 0)
        #expect(!wentBack)
    }

    @Test func theViewerMeasuresHowFarBehindTheHostItsSnapshotIs() throws {
        let harness = SessionHarness(mode: .computer(.medium), conditions: LinkConditions(latency: 10_000))
        let viewer = harness.addViewer("Studio Mac", ahead: 5_000_000)
        harness.run(for: 3_000_000)

        let age = try #require(viewer.snapshotAge(at: harness.clock.now + 5_000_000))

        #expect((10_000...10_000 + SessionHarness.frameMicroseconds).contains(age))
    }

    @Test func losingTheViewerPausesAndBothPlayersContinuingSwitchesToTheSideCamera() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        let phoneB = harness.addPhone("Phone B", holding: 0.5)
        _ = harness.addViewer("Studio Mac")
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)

        harness.link.network.disconnect(PeerID("Studio Mac"), LinkHarness.hostID)
        harness.run(for: 100_000)
        guard case .interrupted(.viewerLost) = harness.session.stage else {
            Issue.record("Expected the game to wait for the viewer, got \(harness.session.stage)")
            return
        }

        phoneA.requestPause(false)
        harness.run(for: 100_000)
        #expect(!harness.session.usesSideCamera)
        #expect(phoneA.gameState?.canResume == false)
        #expect(phoneB.gameState?.canResume == true)

        phoneB.requestPause(false)
        harness.run(for: 100_000)
        #expect(harness.session.usesSideCamera)
        #expect(harness.session.stage == .playing)
    }

    @Test func aViewerThatComesBackResumesTheGame() {
        let harness = SessionHarness(mode: .twoPlayers)
        _ = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.5)
        let viewer = harness.addViewer("Studio Mac")
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)
        harness.link.network.disconnect(PeerID("Studio Mac"), LinkHarness.hostID)
        harness.run(for: 5_000_000)

        harness.link.network.connect(PeerID("Studio Mac"), LinkHarness.hostID)
        harness.run(for: 200_000)

        #expect(viewer.status == .paired(hostName: "Mac"))
        #expect(harness.session.stage == .playing)
        #expect(!harness.session.usesSideCamera)
    }
}
