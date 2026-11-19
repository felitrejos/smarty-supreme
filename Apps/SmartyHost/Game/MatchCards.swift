import SmartyCore
import SwiftUI

struct LobbyCard: View {
    let match: Match

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let paddles = match.link.paddles
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Programme.title(22))
                        .contentTransition(.numericText())
                    Text("Calibrate each iPhone, then tap Ready on it. The match starts \(seconds(match.session.config.countdown)) seconds after both players are ready.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Side.allCases, id: \.self) { side in
                        slot(side, name: paddles.first { $0.side == side }?.name)
                    }
                    Divider()
                    screenSlot
                }
                HStack {
                    Button("Swap Sides", action: match.swapSides)
                        .disabled(paddles.isEmpty)
                    Spacer()
                    Button("Start Now", action: match.startNow)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 440)
            .programmeCard()
        }
    }

    private var title: String {
        guard case .countdown(let until) = match.stage else { return "Waiting for Players" }
        return "Starting in \(seconds(until - min(until, SystemClock().now)))"
    }

    private func seconds(_ duration: Microseconds) -> Int {
        Int((Double(duration) / 1_000_000).rounded(.up))
    }

    private func slot(_ side: Side, name: String?) -> some View {
        let status = status(of: side)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Capsule()
                .fill(side.rubberColor)
                .frame(width: 4, height: 30)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 10 }
            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? side.playerName)
                    .font(Programme.title(14))
                Text(status.text)
                    .font(Programme.body(13))
                    .foregroundStyle(status.tint ?? .secondary)
            }
            Spacer()
            if let symbol = status.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(status.tint ?? .secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.playerName): \(name ?? "no iPhone"). \(status.text)")
    }

    private var screenSlot: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "display")
                .foregroundStyle(.secondary)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.link.viewerName ?? "Player B’s Screen")
                    .font(Programme.title(14))
                Text(match.link.viewerName == nil ? "Optional. On a second Mac, choose File › Use as Player B’s Screen." : "Shows the match from Player B’s end")
                    .font(Programme.body(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func status(of side: Side) -> (text: String, symbol: String?, tint: Color?) {
        switch match.readiness(of: side) {
        case .noPhone:
            return ("No iPhone yet. If you start now, \(side == .playerA ? "A, D and W" : "the arrow keys") play this side.", nil, nil)
        case .needsCalibration:
            return ("Calibrate on the iPhone", "iphone", nil)
        case .notReady:
            return ("Tap Ready on the iPhone", nil, nil)
        case .measuring:
            return ("Measuring the connection…", nil, nil)
        case .tooSlow(let roundTrip):
            return ("Connection too slow to start (\(milliseconds(roundTrip)) ms)", "exclamationmark.triangle.fill", .orange)
        case .ready(let roundTrip) where roundTrip > match.session.config.roundTripWarning:
            return ("Ready, slow connection (\(milliseconds(roundTrip)) ms)", "checkmark.circle.fill", .orange)
        case .ready:
            return ("Ready", "checkmark.circle.fill", .green)
        }
    }

    private func milliseconds(_ duration: Microseconds) -> Int {
        Int((Double(duration) / 1_000).rounded())
    }
}

struct InterruptionCard: View {
    let match: Match
    let interruption: Interruption

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: 12) {
                Text(title)
                    .font(Programme.title(19))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if case .phoneLost(let side, _) = interruption {
                    ForEach(match.link.waiting, id: \.peer) { phone in
                        Button("Let \(phone.name) Play as \(side.playerName)") {
                            match.letWaitingPhonePlay(side, peer: phone.peer)
                        }
                    }
                }
                resumeButton
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 420)
            .programmeCard()
        }
    }

    private var title: String {
        switch interruption {
        case .byHost, .onHold: "Paused"
        case .byPlayer(let side): "\(side.playerName) paused"
        case .pointerLost(let side): "\(side.playerName)’s paddle stopped"
        case .serveTimeouts(let side): "Is \(side.playerName) still playing?"
        case .phoneLost(let side, _): "Waiting for \(side.playerName)’s iPhone"
        case .viewerLost: "Player B’s screen disconnected"
        }
    }

    private var detail: String {
        switch interruption {
        case .byHost:
            "Resume when you’re ready."
        case .onHold:
            "Play resumes when you come back to Smarty Supreme."
        case .byPlayer(let side):
            "\(side.playerName) can resume from their iPhone, or you can resume here."
        case .pointerLost(let side):
            "\(side.playerName)’s iPhone stopped sending its tilt. Hold it upright, then tap Continue on it."
        case .serveTimeouts(let side):
            "\(side.playerName) let \(match.session.config.serveTimeoutsBeforeAsking) serves in a row time out. Tap Continue on the iPhone to play on."
        case .phoneLost(let side, let until):
            "\(side.playerName) forfeits in \(secondsLeft(until)) s unless the iPhone reconnects."
        case .viewerLost:
            "Waiting for it to come back. Both players can tap Continue to play on with the side view."
        }
    }

    @ViewBuilder
    private var resumeButton: some View {
        switch interruption {
        case .phoneLost:
            Button("Play On With the Keyboard", action: match.playOnWithoutTheMissingDevice)
        case .viewerLost:
            Button("Switch to the Side View", action: match.playOnWithoutTheMissingDevice)
        case .byHost, .onHold, .byPlayer, .pointerLost, .serveTimeouts:
            Button("Resume", action: match.togglePause)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func secondsLeft(_ until: Microseconds) -> Int {
        Int((Double(until - min(until, SystemClock().now)) / 1_000_000).rounded(.up))
    }
}
