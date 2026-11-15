import FlickCore
import FlickTestSupport
import Foundation
import Synchronization
import Testing

struct LoopbackNetworkTests {
    @Test func connectingNotifiesBothPeers() {
        let harness = Harness()
        harness.network.advance(by: 0)
        #expect(harness.phoneInbox.events == [.connected(Harness.host)])
        #expect(harness.hostInbox.events == [.connected(Harness.phone)])
    }

    @Test func packetArrivesAfterLatencyAndClockReadsArrivalTime() throws {
        let harness = Harness(conditions: LinkConditions(latency: 20_000))
        try harness.phone.send(packet(7), to: Harness.host, on: .reliable)

        harness.network.advance(by: 19_999)
        #expect(harness.hostInbox.receivedIndices.isEmpty)

        harness.network.advance(by: 1)
        let arrival = try #require(harness.hostInbox.received.first)
        #expect(arrival.event == .received(packet(7), from: Harness.phone))
        #expect(arrival.at == 20_000)
    }

    @Test func overdueDeliveryArrivesWithoutMovingTheClockBackwards() {
        let harness = Harness()
        harness.clock.advance(by: 10)
        harness.network.advance(by: 0)
        #expect(harness.hostInbox.all == [Inbox.Entry(at: 10, event: .connected(Harness.phone))])
        #expect(harness.clock.now == 10)
    }

    @Test func arrivalsSpreadAcrossLatencyPlusOrMinusJitter() throws {
        let harness = Harness(conditions: LinkConditions(latency: 20_000, jitter: 5_000))
        for index in 0..<1_000 {
            try harness.phone.send(packet(UInt32(index)), to: Harness.host, on: .unreliable)
            harness.network.advance(by: 1_000)
        }
        harness.network.advance(by: 100_000)
        let delays = zip(harness.hostInbox.received, harness.hostInbox.receivedIndices).map { entry, index in
            entry.at - Microseconds(index) * 1_000
        }
        #expect(delays.count == 1_000)
        #expect(delays.allSatisfy { (15_000...25_000).contains($0) })
        #expect(delays.min()! < 15_500)
        #expect(delays.max()! > 24_500)
    }

    @Test func sendingToAPeerThatIsNotConnectedThrows() {
        let harness = Harness()
        let stranger = harness.network.join(as: PeerID("Phone B")) { _ in }
        #expect(throws: TransportError.notConnected(Harness.host)) {
            try stranger.send(packet(1), to: Harness.host, on: .reliable)
        }
    }

    @Test func reliableChannelDeliversEverythingInOrderDespiteJitterAndLoss() throws {
        let harness = Harness(conditions: LinkConditions(latency: 20_000, jitter: 5_000, unreliableLossRate: 0.5))
        for index in 0..<500 {
            try harness.phone.send(packet(UInt32(index)), to: Harness.host, on: .reliable)
            harness.network.advance(by: 1_000)
        }
        harness.network.advance(by: 100_000)
        #expect(harness.hostInbox.receivedIndices == Array(0..<500))
    }

    @Test func unreliableChannelDropsAboutTheConfiguredShare() throws {
        let harness = Harness(conditions: LinkConditions(latency: 10_000, unreliableLossRate: 0.05))
        for index in 0..<10_000 {
            try harness.phone.send(packet(UInt32(index)), to: Harness.host, on: .unreliable)
            harness.network.advance(by: 1_000)
        }
        harness.network.advance(by: 100_000)
        #expect((9_400...9_600).contains(harness.hostInbox.receivedIndices.count))
    }

    @Test func unreliableChannelCanReorderUnderJitter() throws {
        let harness = Harness(conditions: LinkConditions(latency: 20_000, jitter: 5_000))
        for index in 0..<200 {
            try harness.phone.send(packet(UInt32(index)), to: Harness.host, on: .unreliable)
            harness.network.advance(by: 1_000)
        }
        harness.network.advance(by: 100_000)
        let indices = harness.hostInbox.receivedIndices
        #expect(indices.sorted() == Array(0..<200))
        #expect(indices != Array(0..<200))
    }

    @Test func sameSeedReproducesEveryDelivery() throws {
        let conditions = LinkConditions(latency: 20_000, jitter: 5_000, unreliableLossRate: 0.1)
        let first = try jitteryRun(conditions: conditions, seed: 7)
        let repeated = try jitteryRun(conditions: conditions, seed: 7)
        let otherSeed = try jitteryRun(conditions: conditions, seed: 8)
        #expect(first == repeated)
        #expect(first != otherSeed)
    }

    @Test func disconnectDropsPacketsInFlightAndNotifiesBothPeers() throws {
        let harness = Harness(conditions: LinkConditions(latency: 20_000))
        for channel in [Channel.reliable, .unreliable] {
            try harness.phone.send(packet(1), to: Harness.host, on: channel)
            try harness.host.send(packet(1), to: Harness.phone, on: channel)
        }
        harness.network.advance(by: 10_000)

        harness.network.disconnect(Harness.phone, Harness.host)
        harness.network.advance(by: 50_000)

        #expect(harness.hostInbox.events == [.connected(Harness.phone), .disconnected(Harness.phone)])
        #expect(harness.phoneInbox.events == [.connected(Harness.host), .disconnected(Harness.host)])
        #expect(throws: TransportError.notConnected(Harness.host)) {
            try harness.phone.send(packet(2), to: Harness.host, on: .reliable)
        }
    }

    @Test func handlerCanReplyWhileBeingDelivered() throws {
        let clock = ManualClock()
        let network = LoopbackNetwork(clock: clock, conditions: LinkConditions(latency: 20_000), seed: 1)
        let phoneInbox = Inbox(clock: clock)
        let phone = network.join(as: Harness.phone, onEvent: phoneInbox.record)
        let hostTransport = Mutex<LoopbackTransport?>(nil)
        let host = network.join(as: Harness.host) { event in
            guard case .received(let payload, let sender) = event else { return }
            let transport = hostTransport.withLock { $0 }
            do {
                try transport?.send(payload, to: sender, on: .unreliable)
            } catch {
                Issue.record(error)
            }
        }
        hostTransport.withLock { $0 = host }
        network.connect(Harness.phone, Harness.host)

        try phone.send(packet(9), to: Harness.host, on: .unreliable)
        network.advance(by: 50_000)

        let echo = try #require(phoneInbox.received.first)
        #expect(echo.event == .received(packet(9), from: Harness.host))
        #expect(echo.at == 40_000)
    }
}

private struct Harness {
    static let phone = PeerID("Phone A")
    static let host = PeerID("Host")

    let clock = ManualClock()
    let network: LoopbackNetwork
    let phone: LoopbackTransport
    let host: LoopbackTransport
    let phoneInbox: Inbox
    let hostInbox: Inbox

    init(conditions: LinkConditions = LinkConditions(), seed: UInt64 = 1) {
        network = LoopbackNetwork(clock: clock, conditions: conditions, seed: seed)
        phoneInbox = Inbox(clock: clock)
        hostInbox = Inbox(clock: clock)
        phone = network.join(as: Self.phone, onEvent: phoneInbox.record)
        host = network.join(as: Self.host, onEvent: hostInbox.record)
        network.connect(Self.phone, Self.host)
    }
}

private final class Inbox: Sendable {
    struct Entry: Equatable {
        let at: Microseconds
        let event: TransportEvent
    }

    private let clock: ManualClock
    private let entries = Mutex<[Entry]>([])

    init(clock: ManualClock) {
        self.clock = clock
    }

    var all: [Entry] {
        entries.withLock { $0 }
    }

    var events: [TransportEvent] {
        all.map(\.event)
    }

    var received: [Entry] {
        all.filter {
            guard case .received = $0.event else { return false }
            return true
        }
    }

    var receivedIndices: [UInt32] {
        received.compactMap {
            guard case .received(let payload, _) = $0.event else { return nil }
            return index(of: payload)
        }
    }

    func record(_ event: TransportEvent) {
        let entry = Entry(at: clock.now, event: event)
        entries.withLock { $0.append(entry) }
    }
}

private func packet(_ index: UInt32) -> Data {
    withUnsafeBytes(of: index.littleEndian) { Data($0) }
}

private func index(of payload: Data) -> UInt32 {
    UInt32(littleEndian: payload.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
}

private func jitteryRun(conditions: LinkConditions, seed: UInt64) throws -> [Inbox.Entry] {
    let harness = Harness(conditions: conditions, seed: seed)
    for index in 0..<100 {
        try harness.phone.send(packet(UInt32(index)), to: Harness.host, on: .unreliable)
        harness.network.advance(by: 2_000)
    }
    harness.network.advance(by: 100_000)
    return harness.hostInbox.all
}
