import SmartyCore
import Testing

struct ClockSyncTests {
    private static let peerAhead: Microseconds = 5_000_000

    @Test func symmetricDelayGivesTheOffsetWithinOneMillisecond() throws {
        var sync = ClockSync()
        sync.add(exchange(macSentAt: 1_000_000, outbound: 10_000, held: 300, inbound: 10_000))
        let offset = try #require(sync.peerAheadOfMac)
        #expect(abs(offset - Int64(Self.peerAhead)) <= 1_000)
        #expect(sync.macTime(forPeerTime: 9_000_000) == 9_000_000 - Microseconds(offset))
    }

    @Test func theSampleWithTheLowestRoundTripWins() throws {
        var sync = ClockSync()
        sync.add(exchange(macSentAt: 1_000_000, outbound: 40_000, held: 0, inbound: 2_000))
        sync.add(exchange(macSentAt: 2_000_000, outbound: 3_000, held: 0, inbound: 3_000))
        sync.add(exchange(macSentAt: 3_000_000, outbound: 2_000, held: 0, inbound: 30_000))
        #expect(sync.peerAheadOfMac == Int64(Self.peerAhead))
    }

    @Test func roundTripsAboveOneHundredMillisecondsAreIgnored() {
        var sync = ClockSync()
        sync.add(exchange(macSentAt: 1_000_000, outbound: 60_000, held: 0, inbound: 60_000))
        #expect(sync.peerAheadOfMac == nil)
    }

    @Test func onlyTheLastTenSamplesCount() throws {
        var sync = ClockSync()
        sync.add(exchange(macSentAt: 1_000_000, outbound: 1_000, held: 0, inbound: 1_000))
        for index in 1...10 {
            sync.add(exchange(macSentAt: 1_000_000 + Microseconds(index) * 1_000_000, outbound: 20_000, held: 0, inbound: 2_000))
        }
        #expect(sync.peerAheadOfMac == Int64(Self.peerAhead) + 9_000)
    }

    @Test func reportsTheRoundTripOfEachExchange() {
        var sync = ClockSync()
        let roundTrip = sync.add(exchange(macSentAt: 1_000_000, outbound: 7_000, held: 500, inbound: 5_000))
        #expect(roundTrip == 12_000)
    }

    private func exchange(macSentAt: Microseconds, outbound: Microseconds, held: Microseconds, inbound: Microseconds) -> ClockExchange {
        let peerReceivedAt = macSentAt + outbound + Self.peerAhead
        let peerSentAt = peerReceivedAt + held
        return ClockExchange(
            macSentAt: macSentAt,
            peerReceivedAt: peerReceivedAt,
            peerSentAt: peerSentAt,
            macReceivedAt: macSentAt + outbound + held + inbound
        )!
    }
}
