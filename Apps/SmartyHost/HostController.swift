import SmartyCore
import Foundation
import Observation
import SystemConfiguration

@MainActor
@Observable
final class HostController {
    enum Role {
        case host
        case viewer(ViewerMatch)
    }

    private static let tickInterval: TimeInterval = 0.1
    private static let longestName = 40

    let link: HostLink
    let match: Match
    let name: String
    let networkFailure = NetworkFailure()
    private(set) var role = Role.host

    @ObservationIgnored private let transport: MultipeerTransport
    @ObservationIgnored private var tickTimer: Timer?

    init() {
        let relay = EventRelay()
        let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac"
        name = String(computerName.prefix(Self.longestName))
        transport = MultipeerTransport(mode: .advertise, onEvent: relay.forward, onFailure: networkFailure.record)
        link = HostLink(name: name, transport: transport, clock: SystemClock())
        match = Match(link: link, clock: SystemClock(), defaults: .standard)
        relay.connect(link.handle)
    }

    var isViewer: Bool {
        if case .viewer = role { return true }
        return false
    }

    func start() {
        guard tickTimer == nil, !isViewer else { return }
        transport.start()
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [link] _ in
            link.tick()
        }
    }

    func setViewer(_ viewing: Bool) {
        guard viewing != isViewer else { return }
        if viewing {
            tickTimer?.invalidate()
            tickTimer = nil
            transport.stop()
            let viewer = ViewerMatch(name: name)
            role = .viewer(viewer)
            viewer.start()
        } else {
            if case .viewer(let viewer) = role {
                viewer.stop()
            }
            role = .host
            start()
        }
    }
}
