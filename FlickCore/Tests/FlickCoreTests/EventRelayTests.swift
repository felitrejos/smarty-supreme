import FlickCore
import Foundation
import Synchronization
import Testing

struct EventRelayTests {
    @Test func forwardingManyEventsDoesNotDeepenTheCallStack() {
        let depths = Mutex<[Int]>([])
        let relay = EventRelay()
        relay.connect { _ in
            depths.withLock { $0.append(Thread.callStackSymbols.count) }
        }

        for _ in 0..<1_000 {
            relay.forward(.connected(PeerID("Phone")))
        }

        let recorded = depths.withLock { $0 }
        #expect(recorded.count == 1_000)
        #expect(recorded.first == recorded.last)
    }
}
