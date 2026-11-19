import FlickCore
import FlickTestSupport
import Foundation
import Synchronization
import Testing

struct LinkTests {
    @Test func pairingHandshakeSucceeds() {
        let harness = LinkHarness()
        let phone = harness.addPhone("Phone A")
        harness.run(for: 200_000)

        #expect(phone.status == .paired(hostName: "Mac"))
        #expect(phone.pairedAt != nil)
        #expect(harness.host.paddles.map(\.name) == ["Phone A"])
        #expect(harness.host.paddles.map(\.side) == [.playerA])
    }

    @Test func hostRefusesAPhoneOnAnotherProtocolVersion() throws {
        let harness = LinkHarness()
        let oldPhone = harness.addRawPeer("Old phone")
        harness.run(for: 50_000)

        var hello = MessageCodec.encode(Packet(sequence: 0, sentAt: 0, message: .hello(name: "Old phone")))
        hello[0] = MessageCodec.protocolVersion + 1
        try oldPhone.transport.send(hello, to: LinkHarness.hostID, on: .reliable)
        harness.run(for: 50_000)

        #expect(try oldPhone.inbox.messages() == [.bye(.versionMismatch)])
        #expect(harness.host.paddles.isEmpty)
    }

    @Test func phoneRefusesAHostOnAnotherProtocolVersion() throws {
        let clock = ManualClock()
        let network = LoopbackNetwork(clock: clock, seed: 1)
        let relay = EventRelay()
        let phoneTransport = network.join(as: PeerID("Phone A"), onEvent: relay.forward)
        let phone = PaddleLink(name: "Phone A", transport: phoneTransport, clock: clock, onHaptic: { _ in })
        relay.connect(phone.handle)
        let oldHost = network.join(as: PeerID("Old Mac")) { _ in }
        network.connect(PeerID("Phone A"), PeerID("Old Mac"))
        network.advance(by: 10_000)

        var ack = MessageCodec.encode(Packet(sequence: 0, sentAt: 0, message: .helloAck(name: "Old Mac")))
        ack[0] = MessageCodec.protocolVersion + 1
        try oldHost.send(ack, to: PeerID("Phone A"), on: .reliable)
        network.advance(by: 10_000)

        #expect(phone.status == .refused(.versionMismatch))
    }

    @Test func thirdPhoneIsToldTheGameIsFullAndTakesTheFreedSlot() {
        let harness = LinkHarness()
        let first = harness.addPhone("Phone A")
        harness.run(for: 50_000)
        let second = harness.addPhone("Phone B")
        harness.run(for: 50_000)
        let third = harness.addPhone("Phone C")
        harness.run(for: 50_000)

        #expect(first.status == .paired(hostName: "Mac"))
        #expect(second.status == .paired(hostName: "Mac"))
        #expect(third.status == .refused(.gameFull))
        #expect(harness.host.waitingNames == ["Phone C"])

        harness.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 50_000)

        #expect(third.status == .paired(hostName: "Mac"))
        #expect(harness.host.waitingNames.isEmpty)
        #expect(harness.host.paddles.map(\.name) == ["Phone C", "Phone B"])
    }

    @Test func swingPeakIsConvertedToMacTime() throws {
        let harness = LinkHarness(conditions: LinkConditions(latency: 20_000))
        let phoneAhead: Microseconds = 5_000_000
        let phone = harness.addPhone("Phone A", ahead: phoneAhead)
        harness.run(for: 3_000_000)

        let paddle = try #require(harness.host.paddles.first)
        #expect(paddle.roundTrips.allSatisfy { $0 == 40_000 })
        #expect(paddle.roundTrips.count >= 3)

        let macNow = harness.clock.now
        phone.sendSwing(SwingEvent(
            peakTime: macNow + phoneAhead - 30_000,
            peakAcceleration: 4,
            peakRotationRate: 6,
            direction: SIMD3(0, 0, 1),
            strength: 0.5
        ))
        harness.run(for: 100_000)

        let swing = try #require(harness.host.paddles.first?.lastSwing)
        #expect(swing.macPeakTime == macNow - 30_000)
        #expect(swing.strength == 0.5)
    }

    @Test func pointerKeepsTheNewestPositionWhenPacketsArriveOutOfOrder() throws {
        let harness = LinkHarness(conditions: LinkConditions(latency: 20_000, jitter: 10_000))
        let phone = harness.addPhone("Phone A")
        harness.run(for: 200_000)

        for step in 0..<100 {
            phone.sendPointer(Double(step) / 100)
            harness.network.advance(by: 2_000)
        }
        harness.run(for: 100_000)

        let position = try #require(harness.host.paddles.first?.position)
        #expect(position == Double(Float(0.99)))
    }

    @Test func pointerRateCountsMessagesFromTheLastSecond() throws {
        let harness = LinkHarness()
        let phone = harness.addPhone("Phone A")
        harness.run(for: 100_000)

        for _ in 0..<120 {
            phone.sendPointer(0.5)
            harness.network.advance(by: 16_667)
        }

        let rate = try #require(harness.host.paddles.first?.pointerRate)
        #expect((59...61).contains(rate))
    }

    @Test func calibratedSensitivityReachesTheHost() {
        let harness = LinkHarness()
        let phone = harness.addPhone("Phone A")
        harness.run(for: 100_000)
        phone.announceCalibration(.low)
        harness.run(for: 100_000)
        #expect(harness.host.paddles.first?.sensitivity == .low)
    }

    @Test func calibrationFromBeforePairingReachesTheHostOncePaired() {
        let harness = LinkHarness()
        let phone = harness.addPhone("Phone A")
        phone.announceCalibration(.high)
        harness.run(for: 100_000)
        #expect(harness.host.paddles.first?.sensitivity == .high)
    }

    @Test func phoneSendsNothingButHelloUntilTheHostAccepts() throws {
        let clock = ManualClock()
        let network = LoopbackNetwork(clock: clock, seed: 1)
        let relay = EventRelay()
        let phone = PaddleLink(name: "Phone A", transport: network.join(as: PeerID("Phone A"), onEvent: relay.forward), clock: clock, onHaptic: { _ in })
        relay.connect(phone.handle)
        let silentHost = DataInbox()
        _ = network.join(as: PeerID("Silent Mac"), onEvent: silentHost.record)
        network.connect(PeerID("Phone A"), PeerID("Silent Mac"))
        network.advance(by: 10_000)

        phone.sendPointer(0.3)
        phone.sendSwing(SwingEvent(peakTime: 0, peakAcceleration: 4, peakRotationRate: 6, direction: SIMD3(0, 0, 1), strength: 0.5))
        network.advance(by: 10_000)

        #expect(try silentHost.messages() == [.hello(name: "Phone A")])
    }

    @Test func pongsThatDoNotAnswerTheLatestPingAreIgnored() throws {
        let harness = LinkHarness()
        let phone = harness.addRawPeer("Phone A")
        try phone.send(.hello(name: "Phone A"), sentAt: 0)
        harness.run(for: 50_000)
        let ping = try #require(phone.inbox.packets().first { $0.message == .ping })

        try phone.send(.pong(pingSentAt: ping.sentAt + 999_999, receivedAt: 10), sentAt: 20)
        try phone.send(.pong(pingSentAt: ping.sentAt, receivedAt: 500), sentAt: 100)
        try phone.send(.pong(pingSentAt: ping.sentAt, receivedAt: UInt64.max - 5), sentAt: UInt64.max)
        try phone.send(.pong(pingSentAt: ping.sentAt, receivedAt: 0), sentAt: 10_000_000)
        harness.run(for: 50_000)

        let paddle = try #require(harness.host.paddles.first)
        #expect(paddle.roundTrips.isEmpty)
    }

    @Test(arguments: [0 as Microseconds, UInt64.max])
    func swingPeakTimesThatCannotBeConvertedAreLeftWithoutAMacTime(peakTime: Microseconds) throws {
        let harness = LinkHarness()
        let phone = harness.addPhone("Phone A", ahead: 5_000_000)
        harness.run(for: 2_000_000)
        phone.sendSwing(SwingEvent(peakTime: peakTime, peakAcceleration: 4, peakRotationRate: 6, direction: SIMD3(0, 0, 1), strength: 0.5))
        harness.run(for: 100_000)

        let swing = try #require(harness.host.paddles.first?.lastSwing)
        #expect(swing.macPeakTime == nil)
    }

    @Test func byeFreesTheSlotForTheNextWaitingPhone() {
        let harness = LinkHarness()
        let first = harness.addPhone("Phone A")
        harness.run(for: 50_000)
        _ = harness.addPhone("Phone B")
        harness.run(for: 50_000)
        let third = harness.addPhone("Phone C")
        harness.run(for: 50_000)

        first.leave(.left)
        harness.run(for: 50_000)

        #expect(third.status == .paired(hostName: "Mac"))
        #expect(harness.host.paddles.map(\.name) == ["Phone C", "Phone B"])
    }

    @Test func aRepeatedHelloKeepsOnePaddleAndIsAcknowledgedAgain() throws {
        let harness = LinkHarness()
        let phone = harness.addRawPeer("Phone A")
        try phone.send(.hello(name: "Phone A"), sentAt: 0)
        try phone.send(.hello(name: "Phone A"), sentAt: 1)
        harness.run(for: 50_000)

        #expect(harness.host.paddles.count == 1)
        #expect(try phone.inbox.messages().filter { $0 == .helloAck(name: "Mac") }.count == 2)
    }

    @Test func waitingPhonesAreAdmittedInArrivalOrderAndLeaveTheQueueWhenTheyDisconnect() {
        let harness = LinkHarness()
        let first = harness.addPhone("Phone A")
        _ = first
        harness.run(for: 50_000)
        _ = harness.addPhone("Phone B")
        harness.run(for: 50_000)
        let third = harness.addPhone("Phone C")
        harness.run(for: 50_000)
        let fourth = harness.addPhone("Phone D")
        harness.run(for: 50_000)
        let fifth = harness.addPhone("Phone E")
        harness.run(for: 50_000)
        #expect(harness.host.waitingNames == ["Phone C", "Phone D", "Phone E"])

        harness.network.disconnect(PeerID("Phone D"), LinkHarness.hostID)
        harness.network.disconnect(PeerID("Phone A"), LinkHarness.hostID)
        harness.run(for: 50_000)

        #expect(third.status == .paired(hostName: "Mac"))
        #expect(fourth.status == .searching)
        #expect(fifth.status == .refused(.gameFull))
        #expect(harness.host.waitingNames == ["Phone E"])
    }

    @Test func swingsQueueUntilTheHostTakesThemAlongWithEachSidesPosition() throws {
        let harness = LinkHarness()
        let phoneA = harness.addPhone("Phone A")
        harness.run(for: 50_000)
        let phoneB = harness.addPhone("Phone B")
        harness.run(for: 1_500_000)
        phoneA.sendPointer(0.25)
        phoneB.sendPointer(0.75)
        for strength in [0.2, 0.4] {
            phoneA.sendSwing(SwingEvent(peakTime: harness.clock.now, peakAcceleration: 4, peakRotationRate: 6, direction: SIMD3(0, 0, 1), strength: strength))
        }
        harness.run(for: 50_000)

        let input = harness.host.takeInput()
        let afterwards = harness.host.takeInput()

        #expect(input.paddles[.playerA]?.position == 0.25)
        #expect(input.paddles[.playerA]?.swings.map { Float($0.strength) } == [0.2, 0.4])
        #expect(input.paddles[.playerB]?.position == 0.75)
        #expect(input.paddles[.playerB]?.swings.isEmpty == true)
        #expect(afterwards.paddles[.playerA]?.swings.isEmpty == true)
        #expect(afterwards.paddles[.playerA]?.position == 0.25)
    }

    @Test func aHapticReachesOnlyThePhoneOnThatSide() {
        let harness = LinkHarness()
        let hapticsA = HapticInbox()
        let hapticsB = HapticInbox()
        _ = harness.addPhone("Phone A", onHaptic: hapticsA.record)
        harness.run(for: 50_000)
        _ = harness.addPhone("Phone B", onHaptic: hapticsB.record)
        harness.run(for: 50_000)

        harness.host.send(.haptic(.hit), to: .playerB)
        harness.host.send(.haptic(.win), to: .playerB)
        harness.run(for: 50_000)

        #expect(hapticsA.kinds.isEmpty)
        #expect(hapticsB.kinds == [.hit, .win])
    }

    @Test func roundTripHistoryKeepsTheLastTenMinutes() throws {
        let harness = LinkHarness()
        _ = harness.addPhone("Phone A")
        harness.run(for: 610_000_000)
        #expect(harness.host.paddles.first?.roundTrips.count == 600)
    }
}

struct OffsetClock: MonotonicClock {
    let base: ManualClock
    let ahead: Microseconds

    var now: Microseconds {
        base.now + ahead
    }
}

final class DataInbox: Sendable {
    private let received = Mutex<[Data]>([])

    func record(_ event: TransportEvent) {
        guard case .received(let data, _) = event else { return }
        received.withLock { $0.append(data) }
    }

    func packets() throws -> [Packet] {
        try received.withLock { $0 }.map { try MessageCodec.decode($0) }
    }

    func messages() throws -> [Message] {
        try packets().map(\.message)
    }
}

final class HapticInbox: Sendable {
    private let received = Mutex<[HapticKind]>([])

    var kinds: [HapticKind] {
        received.withLock { $0 }
    }

    func record(_ kind: HapticKind) {
        received.withLock { $0.append(kind) }
    }
}

struct RawPeer {
    let transport: LoopbackTransport
    let inbox: DataInbox

    func send(_ message: Message, sentAt: Microseconds) throws {
        let data = MessageCodec.encode(Packet(sequence: 0, sentAt: sentAt, message: message))
        try transport.send(data, to: LinkHarness.hostID, on: message.channel)
    }
}

struct LinkHarness {
    static let hostID = PeerID("Mac")

    let clock = ManualClock()
    let network: LoopbackNetwork
    let host: HostLink

    init(conditions: LinkConditions = LinkConditions()) {
        network = LoopbackNetwork(clock: clock, conditions: conditions, seed: 1)
        let relay = EventRelay()
        let transport = network.join(as: Self.hostID, onEvent: relay.forward)
        host = HostLink(name: "Mac", transport: transport, clock: clock)
        relay.connect(host.handle)
    }

    func addPhone(_ name: String, ahead: Microseconds = 0, onHaptic: @escaping @Sendable (HapticKind) -> Void = { _ in }) -> PaddleLink {
        let relay = EventRelay()
        let transport = network.join(as: PeerID(name), onEvent: relay.forward)
        let phone = PaddleLink(name: name, transport: transport, clock: OffsetClock(base: clock, ahead: ahead), onHaptic: onHaptic)
        relay.connect(phone.handle)
        network.connect(PeerID(name), Self.hostID)
        return phone
    }

    func addRawPeer(_ name: String) -> RawPeer {
        let inbox = DataInbox()
        let transport = network.join(as: PeerID(name), onEvent: inbox.record)
        network.connect(PeerID(name), Self.hostID)
        return RawPeer(transport: transport, inbox: inbox)
    }

    func run(for duration: Microseconds) {
        let end = clock.now + duration
        while clock.now < end {
            host.tick()
            network.advance(by: 10_000)
        }
    }
}
