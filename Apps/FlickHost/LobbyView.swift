import FlickCore
import SwiftUI

struct LobbyView: View {
    let controller: HostController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let paddles = controller.link.paddles
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Flick Pong")
                        .font(.largeTitle.weight(.semibold))
                    Text(subtitle(paddleCount: paddles.count))
                        .foregroundStyle(controller.networkFailure.latest == nil ? Color.secondary : Color.red)
                }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Side.allCases, id: \.self) { side in
                        SlotCard(side: side, paddle: paddles.first { $0.side == side })
                    }
                }
                let waiting = controller.link.waitingNames
                if !waiting.isEmpty {
                    Text("Waiting for a free slot: \(waiting.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func subtitle(paddleCount: Int) -> String {
        if let failure = controller.networkFailure.latest {
            return "Can't advertise on the local network: \(failure)"
        }
        if paddleCount == 0 {
            return "Open Flick Paddle on an iPhone on the same Wi-Fi. It connects to \(controller.name) on its own."
        }
        return "Advertising as \(controller.name)"
    }
}

private struct SlotCard: View {
    let side: Side
    let paddle: HostLink.ConnectedPaddle?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(side == .playerA ? Color.blue : Color.orange)
                    .frame(width: 10, height: 10)
                Text(side == .playerA ? "Player A" : "Player B")
                    .font(.headline)
                Spacer()
                Text(paddle?.name ?? "Empty")
                    .foregroundStyle(.secondary)
            }
            if let paddle {
                metrics(paddle)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metrics(_ paddle: HostLink.ConnectedPaddle) -> some View {
        let roundTrips = RoundTripSummary(paddle.roundTrips)
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Round trip")
                    .foregroundStyle(.secondary)
                Text(roundTrips.description)
                    .monospacedDigit()
                Target(met: roundTrips.p95.map { $0 <= 15_000 }, label: "p95 ≤ 15 ms")
            }
            GridRow {
                Text("Clock offset")
                    .foregroundStyle(.secondary)
                Text(paddle.peerAheadOfMac.map { String(format: "%+.1f ms", Double($0) / 1_000) } ?? "Syncing…")
                    .monospacedDigit()
                Text("")
            }
            GridRow {
                Text("Pointer")
                    .foregroundStyle(.secondary)
                Text("\(paddle.pointerRate) per second")
                    .monospacedDigit()
                Target(met: paddle.position == nil ? nil : paddle.pointerRate >= 55, label: "≥ 55")
            }
            GridRow {
                Text("Position")
                    .foregroundStyle(.secondary)
                PositionBar(position: paddle.position)
                    .gridCellColumns(2)
            }
            GridRow {
                Text("Calibration")
                    .foregroundStyle(.secondary)
                Text(paddle.sensitivity.map { "±\(Int($0.rangeDegrees))°" } ?? "Not yet")
                Text("")
            }
            GridRow {
                Text("Swings")
                    .foregroundStyle(.secondary)
                Text(swingText(paddle))
                    .monospacedDigit()
                Text("")
            }
        }
    }

    private func swingText(_ paddle: HostLink.ConnectedPaddle) -> String {
        guard let swing = paddle.lastSwing else { return "\(paddle.swingCount)" }
        return "\(paddle.swingCount), last at \(Int(swing.strength * 100))% strength"
    }
}

private struct Target: View {
    let met: Bool?
    let label: String

    var body: some View {
        Label(label, systemImage: met == true ? "checkmark.circle.fill" : met == false ? "xmark.circle.fill" : "circle.dashed")
            .foregroundStyle(met == true ? Color.green : met == false ? Color.red : Color.secondary)
            .font(.caption)
    }
}

private struct PositionBar: View {
    let position: Double?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                if let position {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * 0.15)
                        .offset(x: position * geometry.size.width * 0.85)
                }
            }
        }
        .frame(height: 12)
    }
}

private struct RoundTripSummary {
    let last: Microseconds?
    let p50: Microseconds?
    let p95: Microseconds?
    let count: Int

    init(_ roundTrips: [Microseconds]) {
        let sorted = roundTrips.sorted()
        last = roundTrips.last
        p50 = Self.percentile(0.5, of: sorted)
        p95 = Self.percentile(0.95, of: sorted)
        count = roundTrips.count
    }

    var description: String {
        guard let last, let p50, let p95 else { return "Measuring…" }
        return String(format: "%.1f ms now · p50 %.1f · p95 %.1f · %d samples", milliseconds(last), milliseconds(p50), milliseconds(p95), count)
    }

    private func milliseconds(_ value: Microseconds) -> Double {
        Double(value) / 1_000
    }

    private static func percentile(_ fraction: Double, of sorted: [Microseconds]) -> Microseconds? {
        guard !sorted.isEmpty else { return nil }
        return sorted[Int((Double(sorted.count - 1) * fraction).rounded())]
    }
}
