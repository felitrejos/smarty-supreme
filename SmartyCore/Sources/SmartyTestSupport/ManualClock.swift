import SmartyCore
import Synchronization

public final class ManualClock: MonotonicClock {
    private let current: Mutex<Microseconds>

    public init() {
        current = Mutex(0)
    }

    public var now: Microseconds {
        current.withLock { $0 }
    }

    public func advance(by duration: Microseconds) {
        current.withLock { $0 += duration }
    }

    public func advance(to instant: Microseconds) {
        current.withLock {
            precondition(instant >= $0, "ManualClock cannot move backwards")
            $0 = instant
        }
    }
}
