import FlickCore
import FlickTestSupport
import Testing

struct LobbyFlowTests {
    @Test func aTwoPlayerMatchStartsThreeSecondsAfterBothPlayersAreReady() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        let phoneB = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        #expect(harness.session.stage == .lobby)

        phoneA.setReady(true)
        phoneB.setReady(true)
        harness.run(for: 100_000)
        guard case .countdown(let startsAt) = harness.session.stage else {
            Issue.record("Expected the countdown, got \(harness.session.stage)")
            return
        }
        harness.run(until: { $0.clock.now >= startsAt - 20_000 })
        #expect(harness.session.stage == .countdown(until: startsAt))

        harness.run(for: 40_000)
        #expect(harness.session.stage == .playing)
    }

    @Test func aPlayerWhoTakesBackReadyStopsTheCountdown() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        let phoneB = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        phoneA.setReady(true)
        phoneB.setReady(true)
        harness.run(for: 1_000_000)

        phoneB.setReady(false)
        harness.run(for: 3_000_000)

        #expect(harness.session.stage == .lobby)
    }

    @Test func aRoundTripAboveOneHundredMillisecondsBlocksReady() {
        let harness = SessionHarness(mode: .twoPlayers, conditions: LinkConditions(latency: 60_000))
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        let phoneB = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 6_000_000)

        phoneA.setReady(true)
        phoneB.setReady(true)
        harness.run(for: 4_000_000)

        #expect(harness.session.stage == .lobby)
        #expect(phoneA.gameState?.phase == .lobby)
    }

    @Test func eachPhoneIsToldItsSideAndWhereTheLobbyStands() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: nil, calibrated: false)
        let phoneB = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        phoneB.setReady(true)
        harness.run(for: 100_000)

        #expect(phoneA.gameState?.phase == .calibrating)
        #expect(phoneA.gameState?.side == .playerA)
        #expect(phoneB.gameState?.phase == .ready)
        #expect(phoneB.gameState?.side == .playerB)
    }

    @Test func sidesSwapInTheLobbyButNotOnceTheMatchHasStarted() {
        let harness = SessionHarness(mode: .twoPlayers)
        _ = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 100_000)

        harness.session.swapSides()
        #expect(harness.link.host.paddles.map(\.name) == ["Phone B", "Phone A"])

        harness.session.startNow()
        harness.run(for: 100_000)
        harness.session.swapSides()
        #expect(harness.link.host.paddles.map(\.name) == ["Phone B", "Phone A"])
    }

    @Test func swappingSidesAsksBothPlayersToBeReadyAgain() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        let phoneB = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        phoneA.setReady(true)
        phoneB.setReady(true)
        harness.run(for: 100_000)

        harness.session.swapSides()
        harness.run(for: 100_000)

        #expect(harness.session.stage == .lobby)
        #expect(phoneA.gameState?.phase == .lobby)
        #expect(phoneA.gameState?.side == .playerB)
    }

    @Test func aPhoneOnASlowConnectionIsToldSo() {
        let harness = SessionHarness(mode: .twoPlayers, conditions: LinkConditions(latency: 30_000))
        let phone = harness.addPhone("Phone A", holding: 0.5)
        harness.run(for: 6_000_000)

        #expect(phone.gameState?.connectionIsSlow == true)
    }

    @Test func againstTheComputerASecondPhoneIsToldTheGameIsFull() {
        let harness = SessionHarness(mode: .computer(.medium))
        _ = harness.addPhone("Phone A", holding: 0.5)
        let second = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 200_000)

        #expect(second.status == .refused(.gameFull))
    }

    @Test func aMatchAgainstTheComputerStartsAtOnce() {
        let harness = SessionHarness(mode: .computer(.medium))
        harness.run(for: 100_000)

        #expect(harness.session.stage == .playing)
        #expect(harness.session.game.step > 0)
    }
}

struct TwoPlayerMatchTests {
    @Test func aTwentyHitRallyCompletesOverASlowLossyLink() {
        let harness = SessionHarness(mode: .twoPlayers, conditions: LinkConditions(latency: 20_000, jitter: 5_000, unreliableLossRate: 0.05))
        harness.addBot("Phone A", side: .playerA)
        harness.addBot("Phone B", side: .playerB)
        harness.run(for: 2_000_000)
        harness.session.startNow()

        let events = harness.run(until: { $0.session.game.rally >= 20 || $0.session.game.score != Score(a: 0, b: 0) }, limit: 100_000_000)

        #expect(harness.session.game.rally >= 20)
        #expect(harness.session.game.score == Score(a: 0, b: 0))
        #expect(events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
    }

    @Test func playerAsPhoneNeverMovesOrSwingsForPlayerB() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.3)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        var random = SplitMix64(seed: 3)


        var settled = false
        let events = harness.run(for: 8_000_000) { harness in
            harness.holdings["Phone A"] = Double.random(in: 0...1, using: &random)
            if Int.random(in: 0..<20, using: &random) == 0 {
                phoneA.sendSwing(SwingEvent(peakTime: harness.clock.now, peakAcceleration: 4, peakRotationRate: 6, direction: SIMD3(0, 0, 1), strength: 0.5))
            }
            if harness.clock.now > 3_000_000 {
                settled = true
                #expect(abs(harness.session.game.paddlePosition(of: .playerB) - 0.7) < 1e-6)
            }
        }

        #expect(settled)
        #expect(!events.contains { if case .hit(.playerB, _, _) = $0 { true } else { false } })
        #expect(!events.contains(.whiff(.playerB)))
    }

    @Test func aPlayerWhoPausesIsTheOnlyPhoneThatCanResume() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        let phoneB = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)

        phoneA.requestPause(true)
        harness.run(for: 200_000)
        #expect(harness.session.stage == .interrupted(.byPlayer(.playerA)))
        #expect(harness.session.game.phase == .paused)
        #expect(phoneA.gameState?.canResume == true)
        #expect(phoneB.gameState?.canResume == false)

        phoneB.requestPause(false)
        harness.run(for: 200_000)
        #expect(harness.session.stage == .interrupted(.byPlayer(.playerA)))

        phoneA.requestPause(false)
        harness.run(for: 200_000)
        #expect(harness.session.stage == .playing)
    }

    @Test func theMacCanResumeAPlayersPause() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)
        phoneA.requestPause(true)
        harness.run(for: 200_000)

        harness.session.resume()
        harness.run(for: 200_000)

        #expect(harness.session.stage == .playing)
        #expect(harness.session.game.phase != .paused)
    }

    @Test func threeServeTimeoutsInARowAskThatPlayerIfTheyAreStillPlaying() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        harness.addBot("Phone B", side: .playerB)
        harness.run(for: 2_000_000)
        harness.session.startNow()

        let events = harness.run(until: { if case .interrupted = $0.session.stage { true } else { false } }, limit: 120_000_000)

        #expect(harness.session.stage == .interrupted(.serveTimeouts(.playerA)))
        #expect(events.filter { $0 == .served(.playerA) }.count == 3)
        #expect(phoneA.gameState?.canResume == true)
    }

    @Test func aPaddleDimsAfterAQuarterSecondWithoutPointerAndTheGamePausesAfterTwo() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)

        harness.holdings["Phone A"] = nil
        harness.run(for: 200_000)
        #expect(!harness.session.isPointerStale(.playerA))
        harness.run(for: 100_000)
        #expect(harness.session.isPointerStale(.playerA))
        #expect(harness.session.stage == .playing)

        harness.run(for: 1_800_000)
        #expect(harness.session.stage == .interrupted(.pointerLost(.playerA)))

        harness.holdings["Phone A"] = 0.5
        phoneA.requestPause(false)
        harness.run(for: 200_000)
        #expect(harness.session.stage == .playing)
        #expect(!harness.session.isPointerStale(.playerA))
    }
}

struct InterruptionOrderTests {
    @Test func aPauseInForceSurvivesTheOtherPhoneDroppingAndComingBack() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)
        phoneA.requestPause(true)
        harness.run(for: 200_000)

        harness.link.network.disconnect(PeerID("Phone B"), LinkHarness.hostID)
        harness.run(for: 500_000)
        guard case .interrupted(.phoneLost(.playerB, _)) = harness.session.stage else {
            Issue.record("Expected the game to wait for Player B, got \(harness.session.stage)")
            return
        }
        harness.link.network.connect(PeerID("Phone B"), LinkHarness.hostID)
        harness.run(for: 500_000)

        #expect(harness.session.stage == .interrupted(.byPlayer(.playerA)))
        #expect(harness.session.game.phase == .paused)
    }

    @Test func aContinueTappedAsTheOtherPhoneDropsIsKept() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)
        phoneA.requestPause(true)
        harness.run(for: 200_000)

        phoneA.requestPause(false)
        harness.link.network.disconnect(PeerID("Phone B"), LinkHarness.hostID)
        harness.run(for: 500_000)
        harness.link.network.connect(PeerID("Phone B"), LinkHarness.hostID)
        harness.run(for: 500_000)

        #expect(harness.session.stage == .playing)
    }

    @Test func withBothPhonesGoneThePlayerWhoLeftFirstForfeitsFirst() {
        let harness = SessionHarness(mode: .twoPlayers)
        let phoneA = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)

        harness.link.network.disconnect(PeerID("Phone B"), LinkHarness.hostID)
        let bLeftAt = harness.clock.now
        harness.run(for: 10_000_000)
        harness.link.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 1_000_000)
        guard case .interrupted(.phoneLost(.playerB, let until)) = harness.session.stage else {
            Issue.record("Expected the game to wait for Player B first, got \(harness.session.stage)")
            return
        }
        #expect(until <= bLeftAt + harness.session.config.reconnectWindow + SessionHarness.frameMicroseconds)

        harness.link.network.connect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(until: { $0.clock.now >= bLeftAt + 30_500_000 }, limit: 40_000_000)

        #expect(harness.session.game.phase == .gameOver(winner: .playerA))
        #expect(phoneA.gameState?.winner == .playerA)
    }
}

struct ReconnectTests {
    @Test func aPhoneThatDropsMidRallyPausesAndResumesWithTheSameStateWithinThreeSecondsOfReconnecting() throws {
        let harness = SessionHarness(mode: .twoPlayers, conditions: LinkConditions(latency: 20_000))
        harness.addBot("Phone A", side: .playerA)
        harness.addBot("Phone B", side: .playerB)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(until: { $0.session.game.rally >= 2 })

        harness.link.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 200_000)
        guard case .interrupted(.phoneLost(.playerA, _)) = harness.session.stage else {
            Issue.record("Expected the game to wait for Player A, got \(harness.session.stage)")
            return
        }
        let paused = harness.session.game
        #expect(paused.phase == .paused)
        harness.run(for: 10_000_000)
        #expect(harness.session.game == paused)

        harness.link.network.connect(PeerID("Phone A"), LinkHarness.hostID)
        let reconnectedAt = harness.clock.now
        var lastPausedState = paused
        harness.run(until: { harness in
            if harness.session.game.phase == .paused {
                lastPausedState = harness.session.game
            }
            return harness.session.stage == .playing
        })

        #expect(harness.clock.now - reconnectedAt <= 3_000_000)
        #expect(lastPausedState == paused)
    }

    @Test func aPhoneThatStaysAwayForThirtySecondsForfeitsWithTheScoreSoFar() {
        let harness = SessionHarness(mode: .twoPlayers)
        harness.addBot("Phone A", side: .playerA)
        _ = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(until: { $0.session.game.score != Score(a: 0, b: 0) }, limit: 60_000_000)
        let score = harness.session.game.score

        harness.link.network.disconnect(PeerID("Phone B"), LinkHarness.hostID)
        harness.run(for: 29_000_000)
        #expect(harness.session.stage != .over)

        harness.run(for: 1_500_000)
        #expect(harness.session.stage == .over)
        #expect(harness.session.game.phase == .gameOver(winner: .playerA))
        #expect(harness.session.game.score == score)
    }

    @Test func aForfeitTellsThePhoneAndTheViewerWhoWon() throws {
        let harness = SessionHarness(mode: .twoPlayers)
        _ = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.5)
        let viewer = harness.addViewer("Studio Mac")
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)

        harness.link.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 31_000_000)

        #expect(harness.session.game.phase == .gameOver(winner: .playerB))
        #expect(try #require(viewer.latest).snapshot.winner == .playerB)
    }

    @Test func aDifferentPhoneTakesTheEmptySlotOnlyOnceTheMacConfirms() {
        let harness = SessionHarness(mode: .twoPlayers)
        _ = harness.addPhone("Phone A", holding: 0.5)
        _ = harness.addPhone("Phone B", holding: 0.5)
        harness.run(for: 2_000_000)
        harness.session.startNow()
        harness.run(for: 500_000)
        harness.link.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 200_000)
        let stranger = harness.addPhone("Phone C", holding: 0.6)
        harness.run(for: 2_000_000)

        #expect(stranger.status == .refused(.gameFull))
        #expect(harness.link.host.waitingNames == ["Phone C"])

        harness.session.fillVacancy(.playerA, with: PeerID("Phone C"))
        harness.run(for: 500_000)

        #expect(stranger.status == .paired(hostName: "Mac"))
        #expect(harness.session.stage == .playing)
    }

    @Test func againstTheComputerAPhoneThatDropsOutPausesTheGame() {
        let harness = SessionHarness(mode: .computer(.easy))
        _ = harness.addPhone("Phone A", holding: 0.5)
        harness.run(for: 1_000_000)

        harness.link.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 200_000)

        guard case .interrupted(.phoneLost(.playerA, _)) = harness.session.stage else {
            Issue.record("Expected the game to wait for Player A, got \(harness.session.stage)")
            return
        }
    }
}

final class SessionHarness {
    static let frameMicroseconds: Microseconds = 8_333
    static let frameSeconds = Double(frameMicroseconds) / 1_000_000

    let link: LinkHarness
    private(set) var session: HostSession
    var holdings: [String: Double] = [:]
    var local = LocalInput()
    private var phones: [String: PaddleLink] = [:]
    private var bots: [String: PhoneBot] = [:]
    private var viewers: [ViewerLink] = []

    init(mode: MatchMode, conditions: LinkConditions = LinkConditions()) {
        link = LinkHarness(conditions: conditions)
        session = HostSession(link: link.host, clock: link.clock, mode: mode, seed: 11, aiSeed: 12)
    }

    var clock: ManualClock {
        link.clock
    }

    func startNewSession(mode: MatchMode) {
        session = HostSession(link: link.host, clock: link.clock, mode: mode, seed: 21, aiSeed: 22)
    }

    func addPhone(_ name: String, holding position: Double?, calibrated: Bool = true) -> PaddleLink {
        let phone = link.addPhone(name)
        phones[name] = phone
        holdings[name] = position
        run(for: 50_000)
        if calibrated {
            phone.announceCalibration(.medium)
        }
        return phone
    }

    func addViewer(_ name: String, ahead: Microseconds = 0) -> ViewerLink {
        let relay = EventRelay()
        let transport = link.network.join(as: PeerID(name), onEvent: relay.forward)
        let viewer = ViewerLink(name: name, transport: transport, clock: OffsetClock(base: clock, ahead: ahead))
        relay.connect(viewer.handle)
        link.network.connect(PeerID(name), LinkHarness.hostID)
        viewers.append(viewer)
        return viewer
    }

    func addBot(_ name: String, side: Side) {
        _ = addPhone(name, holding: 0.5)
        bots[name] = PhoneBot(side: side)
    }

    @discardableResult
    func run(for duration: Microseconds, everyFrame: (SessionHarness) -> Void = { _ in }) -> [GameEvent] {
        let end = clock.now + duration
        var events: [GameEvent] = []
        while clock.now < end {
            events += frame()
            everyFrame(self)
        }
        return events
    }

    @discardableResult
    func run(
        until done: (SessionHarness) -> Bool,
        limit: Microseconds = 20_000_000,
        everyFrame: (SessionHarness) -> Void = { _ in }
    ) -> [GameEvent] {
        let end = clock.now + limit
        var events: [GameEvent] = []
        while clock.now < end {
            events += frame()
            everyFrame(self)
            if done(self) { return events }
        }
        Issue.record("Condition not reached within \(limit) µs")
        return events
    }

    private func frame() -> [GameEvent] {
        for (name, phone) in phones {
            if var bot = bots[name] {
                bot.play(session.game, phone: phone, now: clock.now)
                bots[name] = bot
            } else if let position = holdings[name] {
                phone.sendPointer(position)
            }
        }
        link.host.tick()
        for viewer in viewers {
            viewer.tick()
        }
        let events = session.advance(local: local)
        link.network.advance(by: Self.frameMicroseconds)
        return events
    }
}

struct PhoneBot {
    let side: Side
    private var swungAtRally: Int?
    private var servedFor: UInt64?

    init(side: Side) {
        self.side = side
    }

    mutating func play(_ game: GameState, phone: PaddleLink, now: Microseconds) {
        let config = game.config
        var target = game.paddlePosition(of: side)
        switch game.phase {
        case .serving(side, let since) where servedFor != since:
            servedFor = since
            phone.sendSwing(swing(at: now))
        case .rally where game.ball.velocity.y * (side == .playerA ? -1 : 1) > 0:
            let path = BallPath(ball: game.ball, config: config)
            let face = config.paddleFaceY(of: side)
            let zoneMiddle = face + (side == .playerA ? 1 : -1) * config.zoneDepth(forSpeed: game.ball.speed) / 2
            if let seconds = path.secondsUntil(y: zoneMiddle) {
                target = config.position(ofPaddleX: path.position(after: seconds).x)
                if seconds < SessionHarness.frameSeconds, swungAtRally != game.rally {
                    swungAtRally = game.rally
                    phone.sendSwing(swing(at: now + Microseconds(seconds * 1_000_000)))
                }
            }
        default:
            break
        }
        phone.sendPointer(side == .playerA ? target : 1 - target)
    }

    private func swing(at time: Microseconds) -> SwingEvent {
        SwingEvent(peakTime: time, peakAcceleration: 4, peakRotationRate: 6, direction: SIMD3(0, 0, 1), strength: 0.5)
    }
}
