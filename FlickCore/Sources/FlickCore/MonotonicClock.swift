public typealias Microseconds = UInt64

public protocol MonotonicClock: Sendable {
    var now: Microseconds { get }
}
