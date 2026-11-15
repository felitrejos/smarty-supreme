import FlickCore
import Foundation
import SystemConfiguration

@MainActor
final class HostController {
    private static let tickInterval: TimeInterval = 0.1
    private static let longestName = 40

    let link: HostLink
    let name: String
    let networkFailure = NetworkFailure()

    private let transport: MultipeerTransport
    private var tickTimer: Timer?

    init() {
        let relay = EventRelay()
        let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac"
        name = String(computerName.prefix(Self.longestName))
        transport = MultipeerTransport(mode: .advertise, onEvent: relay.forward, onFailure: networkFailure.record)
        link = HostLink(name: name, transport: transport, clock: SystemClock())
        relay.connect(link.handle)
    }

    func start() {
        guard tickTimer == nil else { return }
        transport.start()
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [link] _ in
            link.tick()
        }
    }
}
