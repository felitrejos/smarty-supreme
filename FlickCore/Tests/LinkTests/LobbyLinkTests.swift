import FlickCore
import FlickTestSupport
import Testing

struct LobbyLinkTests {
    @Test func readyAndPauseRequestsReachTheHost() {
        let harness = LinkHarness()
        let phone = harness.addPhone("Phone A")
        harness.run(for: 50_000)

        phone.setReady(true)
        phone.requestPause(true)
        phone.requestPause(false)
        harness.run(for: 50_000)
        let input = harness.host.takeInput()
        let afterwards = harness.host.takeInput()

        #expect(input.paddles[.playerA]?.isReady == true)
        #expect(input.paddles[.playerA]?.pauseRequests == [true, false])
        #expect(afterwards.paddles[.playerA]?.pauseRequests.isEmpty == true)
        #expect(afterwards.paddles[.playerA]?.isReady == true)
    }

    @Test func resettingReadinessClearsEveryPhonesReadyFlag() {
        let harness = LinkHarness()
        let phone = harness.addPhone("Phone A")
        harness.run(for: 50_000)
        phone.setReady(true)
        harness.run(for: 50_000)

        harness.host.resetReadiness()

        #expect(harness.host.takeInput().paddles[.playerA]?.isReady == false)
    }

    @Test func whileSlotsAreHeldADroppedPhoneLeavesItsSideVacantAndGetsItBackOnReconnect() throws {
        let harness = LinkHarness()
        let phoneA = harness.addPhone("Phone A")
        harness.run(for: 50_000)
        _ = harness.addPhone("Phone B")
        harness.run(for: 1_500_000)
        let waiting = harness.addPhone("Phone C")
        harness.run(for: 50_000)
        harness.host.holdSlots(true)

        harness.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 50_000)
        let whileGone = harness.host.takeInput()

        #expect(whileGone.vacant == [.playerA])
        #expect(whileGone.paddles[.playerA] == nil)
        #expect(waiting.status == .refused(.gameFull))

        harness.network.connect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 50_000)
        phoneA.sendSwing(SwingEvent(peakTime: harness.clock.now, peakAcceleration: 4, peakRotationRate: 6, direction: SIMD3(0, 0, 1), strength: 0.5))
        harness.run(for: 50_000)
        let back = harness.host.takeInput()

        #expect(phoneA.status == .paired(hostName: "Mac"))
        #expect(back.vacant.isEmpty)
        #expect(harness.host.paddles.first { $0.side == .playerA }?.name == "Phone A")
        #expect(try #require(back.paddles[.playerA]?.swings.first).macPeakTime != nil)
    }

    @Test func aDifferentPhoneTakesAVacantSideOnlyWhenTheMacFillsIt() {
        let harness = LinkHarness()
        _ = harness.addPhone("Phone A")
        harness.run(for: 50_000)
        _ = harness.addPhone("Phone B")
        harness.run(for: 50_000)
        let third = harness.addPhone("Phone C")
        harness.run(for: 50_000)
        harness.host.holdSlots(true)
        harness.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 50_000)

        #expect(third.status == .refused(.gameFull))
        #expect(harness.host.waiting.map(\.name) == ["Phone C"])

        harness.host.fillVacancy(.playerA, with: PeerID("Phone C"))
        harness.run(for: 50_000)

        #expect(third.status == .paired(hostName: "Mac"))
        #expect(harness.host.takeInput().vacant.isEmpty)
        #expect(harness.host.paddles.first { $0.side == .playerA }?.name == "Phone C")
    }

    @Test func releasingTheHoldGivesVacantSidesToWaitingPhones() {
        let harness = LinkHarness()
        _ = harness.addPhone("Phone A")
        harness.run(for: 50_000)
        _ = harness.addPhone("Phone B")
        harness.run(for: 50_000)
        let third = harness.addPhone("Phone C")
        harness.run(for: 50_000)
        harness.host.holdSlots(true)
        harness.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 50_000)

        harness.host.holdSlots(false)
        harness.run(for: 50_000)

        #expect(third.status == .paired(hostName: "Mac"))
        #expect(harness.host.takeInput().vacant.isEmpty)
    }

    @Test func swappingSidesSwapsBothPhones() {
        let harness = LinkHarness()
        _ = harness.addPhone("Phone A")
        harness.run(for: 50_000)
        _ = harness.addPhone("Phone B")
        harness.run(for: 50_000)

        harness.host.swapSides()

        #expect(harness.host.paddles.map(\.name) == ["Phone B", "Phone A"])
    }

    @Test func swappingWithOnePhoneMovesItToTheOtherSide() {
        let harness = LinkHarness()
        _ = harness.addPhone("Phone A")
        harness.run(for: 50_000)

        harness.host.swapSides()

        #expect(harness.host.paddles.map(\.side) == [.playerB])
    }

    @Test func recentRoundTripIsTheMedianOfTheLastFivePings() throws {
        let harness = LinkHarness(conditions: LinkConditions(latency: 30_000, jitter: 25_000))
        _ = harness.addPhone("Phone A")
        harness.run(for: 6_000_000)

        let lastFive = try #require(harness.host.paddles.first).roundTrips.suffix(5).sorted()
        let roundTrip = try #require(harness.host.takeInput().paddles[.playerA]?.roundTrip)

        #expect(Set(lastFive).count > 1)
        #expect(roundTrip == lastFive[2])
    }

    @Test func oneViewerMacIsAcceptedAndASecondIsRefused() throws {
        let harness = LinkHarness()
        let first = harness.addRawPeer("Studio Mac")
        let second = harness.addRawPeer("Other Mac")
        try first.send(.viewerHello(name: "Studio Mac"), sentAt: 0)
        harness.run(for: 50_000)
        try second.send(.viewerHello(name: "Other Mac"), sentAt: 0)
        harness.run(for: 50_000)

        #expect(try first.inbox.messages() == [.helloAck(name: "Mac")])
        #expect(try second.inbox.messages() == [.bye(.gameFull)])
        #expect(harness.host.takeInput().viewerName == "Studio Mac")
        #expect(harness.host.paddles.isEmpty)
    }

    @Test func theViewerGetsSnapshotsAndAnswersToItsPings() throws {
        let harness = LinkHarness()
        let viewer = harness.addRawPeer("Studio Mac")
        try viewer.send(.viewerHello(name: "Studio Mac"), sentAt: 0)
        harness.run(for: 50_000)
        let snapshot = TableSnapshot(step: 7, ball: SIMD2(0.2, 0.5), velocity: SIMD2(0, 1), shotStart: SIMD2(0.2, 0.05), paddleA: 0.2, paddleB: 0.3, phase: .rally, scoreA: 1, scoreB: 2, serving: .playerA, rally: 3, winner: nil)

        harness.host.sendToViewer(snapshot)
        try viewer.send(.ping, sentAt: 777)
        harness.run(for: 50_000)

        let messages = try viewer.inbox.messages()
        #expect(messages.contains(.snapshot(snapshot)))
        #expect(messages.contains { if case .pong(pingSentAt: 777, _) = $0 { true } else { false } })
    }

    @Test func aViewerThatDisconnectsFreesTheScreenSlot() throws {
        let harness = LinkHarness()
        let viewer = harness.addRawPeer("Studio Mac")
        try viewer.send(.viewerHello(name: "Studio Mac"), sentAt: 0)
        harness.run(for: 50_000)

        harness.network.disconnect(PeerID("Studio Mac"), LinkHarness.hostID)
        harness.run(for: 50_000)

        #expect(harness.host.takeInput().viewerName == nil)
    }
}
