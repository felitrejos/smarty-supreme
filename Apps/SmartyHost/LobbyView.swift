import SmartyCore
import SwiftUI

struct LobbyView: View {
    let controller: HostController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let paddles = controller.link.paddles
            let waiting = controller.link.waitingNames
            Form {
                Section {
                    LabeledContent("This Mac", value: controller.name)
                } footer: {
                    Text(footer)
                        .foregroundStyle(controller.networkFailure.latest == nil ? Color.secondary : Color.red)
                }
                ForEach(Side.allCases, id: \.self) { side in
                    Section {
                        if let paddle = paddles.first(where: { $0.side == side }) {
                            PaddleRows(paddle: paddle)
                        } else {
                            Text("No iPhone yet")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Capsule().fill(side.rubberColor).frame(width: 14, height: 3)
                            Text(side.playerName)
                        }
                    }
                }
                Section("Player B’s Screen") {
                    LabeledContent("Mac", value: controller.link.viewerName ?? "None")
                }
                if !waiting.isEmpty {
                    Section("Waiting for a Free Slot") {
                        ForEach(waiting, id: \.self) { Text($0) }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("iPhone Paddles")
    }

    private var footer: String {
        if let failure = controller.networkFailure.latest {
            return "This Mac can’t be found on the local network: \(failure)"
        }
        return "Open Smarty Paddle on an iPhone on the same Wi‑Fi. It joins this Mac on its own."
    }
}

private struct PaddleRows: View {
    private static let roundTripTarget: Microseconds = 15_000
    private static let updateRateTarget = 55

    let paddle: HostLink.ConnectedPaddle
    private let sortedRoundTrips: [Microseconds]

    init(paddle: HostLink.ConnectedPaddle) {
        self.paddle = paddle
        sortedRoundTrips = paddle.roundTrips.sorted()
    }

    var body: some View {
        LabeledContent("iPhone", value: paddle.name)
        LabeledContent("Round trip") {
            Measurement(text: roundTripText, meetsTarget: roundTripMeetsTarget)
        }
        LabeledContent("Tilt updates") {
            Measurement(
                text: "\(paddle.pointerRate) a second",
                meetsTarget: paddle.position == nil ? nil : paddle.pointerRate >= Self.updateRateTarget
            )
        }
        LabeledContent("Paddle") {
            PositionBar(position: paddle.position)
                .frame(width: 160)
        }
        LabeledContent("Calibration", value: paddle.isCalibrated ? "Done" : "Not calibrated")
        LabeledContent("Ready", value: paddle.isReady ? "Yes" : "No")
        LabeledContent("Swings", value: swingText)
    }

    private var roundTripMeetsTarget: Bool? {
        guard let worst = percentile(0.95) else { return nil }
        return worst <= Self.roundTripTarget
    }

    private var roundTripText: String {
        guard let typical = percentile(0.5), let worst = percentile(0.95) else { return "Measuring…" }
        return String(format: "%.1f ms, 95%% under %.1f ms", Double(typical) / 1_000, Double(worst) / 1_000)
    }

    private var swingText: String {
        guard let swing = paddle.lastSwing else { return "None yet" }
        return "\(paddle.swingCount), last at \(Int(swing.strength * 100))% strength"
    }

    private func percentile(_ fraction: Double) -> Microseconds? {
        guard !sortedRoundTrips.isEmpty else { return nil }
        return sortedRoundTrips[Int((Double(sortedRoundTrips.count - 1) * fraction).rounded())]
    }
}

private struct Measurement: View {
    let text: String
    let meetsTarget: Bool?

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .monospacedDigit()
            if let meetsTarget {
                Image(systemName: meetsTarget ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(meetsTarget ? Color.green : Color.orange)
                    .help(meetsTarget ? "Within the link target" : "Outside the link target")
                    .accessibilityLabel(meetsTarget ? "Within the link target" : "Outside the link target")
            }
        }
    }
}

private struct PositionBar: View {
    let position: Double?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let position {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * 0.18)
                        .offset(x: position * geometry.size.width * 0.82)
                }
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Paddle position")
        .accessibilityValue(position.map { "\(Int($0 * 100)) percent across" } ?? "No position yet")
    }
}
