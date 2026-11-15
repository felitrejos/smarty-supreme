import FlickCore
import Foundation
import MultipeerConnectivity
import Synchronization

final class MultipeerTransport: NSObject, Transport, @unchecked Sendable {
    enum Mode {
        case advertise
        case browse
    }

    private struct State {
        var isRunning = false
        var isInviting = false
        var connected: [PeerID: ImmutablePeerID] = [:]
    }

    private static let serviceType = "flickpong"
    private static let invitationTimeout: TimeInterval = 10

    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser?
    private let browser: MCNearbyServiceBrowser?
    private let onEvent: TransportEventHandler
    private let onFailure: @Sendable (Error) -> Void
    private let state = Mutex(State())

    init(mode: Mode, onEvent: @escaping TransportEventHandler, onFailure: @escaping @Sendable (Error) -> Void) {
        let localPeer = MCPeerID(displayName: UUID().uuidString)
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        switch mode {
        case .advertise:
            advertiser = MCNearbyServiceAdvertiser(peer: localPeer, discoveryInfo: nil, serviceType: Self.serviceType)
            browser = nil
        case .browse:
            advertiser = nil
            browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.serviceType)
        }
        self.onEvent = onEvent
        self.onFailure = onFailure
        super.init()
        session.delegate = self
        advertiser?.delegate = self
        browser?.delegate = self
    }

    func start() {
        state.withLock { state in
            guard !state.isRunning else { return }
            state.isRunning = true
            advertiser?.startAdvertisingPeer()
            browser?.startBrowsingForPeers()
        }
    }

    func stop() {
        let wasRunning = state.withLock { state in
            guard state.isRunning else { return false }
            state.isRunning = false
            state.isInviting = false
            advertiser?.stopAdvertisingPeer()
            browser?.stopBrowsingForPeers()
            return true
        }
        if wasRunning {
            session.disconnect()
        }
    }

    func send(_ payload: Data, to peer: PeerID, on channel: Channel) throws(TransportError) {
        guard let target = state.withLock({ $0.connected[peer] })?.peerID else { throw .notConnected(peer) }
        do {
            try session.send(payload, toPeers: [target], with: channel == .reliable ? .reliable : .unreliable)
        } catch {
            throw .notConnected(peer)
        }
    }
}

private struct ImmutablePeerID: @unchecked Sendable {
    let peerID: MCPeerID
}

extension MultipeerTransport: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange change: MCSessionState) {
        let peer = PeerID(peerID.displayName)
        switch change {
        case .connected:
            let connected = ImmutablePeerID(peerID: peerID)
            state.withLock { state in
                state.connected[peer] = connected
                state.isInviting = false
            }
            onEvent(.connected(peer))
        case .notConnected:
            let wasConnected = state.withLock { state in
                let wasConnected = state.connected.removeValue(forKey: peer) != nil
                state.isInviting = false
                if state.isRunning, state.connected.isEmpty, let browser {
                    browser.stopBrowsingForPeers()
                    browser.startBrowsingForPeers()
                }
                return wasConnected
            }
            if wasConnected {
                onEvent(.disconnected(peer))
            }
        case .connecting:
            return
        @unknown default:
            return
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onEvent(.received(data, from: PeerID(peerID.displayName)))
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        onFailure(error)
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let shouldInvite = state.withLock { state in
            guard state.isRunning, !state.isInviting, state.connected.isEmpty else { return false }
            state.isInviting = true
            return true
        }
        if shouldInvite {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: Self.invitationTimeout)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        onFailure(error)
    }
}
