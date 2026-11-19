import FlickCore
import SwiftUI

struct PaddleView: View {
    let controller: PaddleController
    let isMotionAvailable: Bool

    @State private var thermalState = ProcessInfo.processInfo.thermalState

    var body: some View {
        NavigationStack {
            TimelineView(.animation(minimumInterval: isHot ? Self.hotFrameInterval : nil)) { _ in
                content(controller.sensing.snapshot)
            }
            .navigationTitle("Flick Paddle")
        }
        .defersSystemGestures(on: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: RunLoop.main)) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    private static let hotFrameInterval: TimeInterval = 0.1

    private var isHot: Bool {
        thermalState == .serious || thermalState == .critical
    }

    private func content(_ snapshot: PaddleSensing.Snapshot) -> some View {
        VStack(spacing: 24) {
            LinkHeader(link: controller.link, launchedAt: controller.launchedAt, networkFailure: controller.networkFailure.latest)
            if isHot {
                Label("Your iPhone is hot. Play continues at full speed; the screen updates less often.", systemImage: "thermometer.high")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let state = controller.link.gameState {
                MatchPanel(state: state, controller: controller)
            }
            playArea(snapshot)
            if isMotionAvailable {
                Picker("Sensitivity", selection: Binding(get: { snapshot.sensitivity }, set: controller.setSensitivity)) {
                    ForEach(Sensitivity.allCases, id: \.self) { sensitivity in
                        Text("\(Int(sensitivity.rangeDegrees))°").tag(sensitivity)
                    }
                }
                .pickerStyle(.segmented)
                Button(action: controller.sensing.calibrate) {
                    Text(snapshot.calibration == .inProgress ? "Hold still…" : "Calibrate")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(snapshot.calibration == .inProgress)
            }
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            StatsFooter(stats: controller.stats)
        }
    }

    @ViewBuilder
    private func playArea(_ snapshot: PaddleSensing.Snapshot) -> some View {
        let area = VStack(spacing: 24) {
            if isMotionAvailable {
                Text(status(snapshot))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 48)
                PaddleTrack(reading: snapshot.reading)
                SwingPanel(snapshot: snapshot)
            } else {
                Text("No motion sensors here. Drag along the bar to move, and swipe up here to swing.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 48)
                GeometryReader { geometry in
                    PaddleTrack(reading: snapshot.reading)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                            controller.dragPaddle(to: drag.location.x, across: geometry.size.width)
                        })
                }
                .frame(height: 44)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { drag in
            if TouchInput.isSwing(across: drag.translation.width, down: drag.translation.height) {
                controller.swipeSwing()
            }
        })
        if isMotionAvailable {
            area.onTapGesture(count: 2, perform: controller.sensing.calibrate)
        } else {
            area
        }
    }

    private func status(_ snapshot: PaddleSensing.Snapshot) -> String {
        if let error = snapshot.sensorError {
            return "Sensor error: \(error)"
        }
        if let drop = snapshot.lastDropAt, let now = snapshot.latestSampleAt, now - drop < 1_500_000 {
            return "Hold on tight"
        }
        switch snapshot.calibration {
        case .needed:
            return "Hold the phone upright, pointing at the middle of the screen, and tap Calibrate."
        case .inProgress:
            return "Hold still…"
        case .failed(.handMoved):
            return "Your hand moved. Hold still and try again."
        case .failed(.notUpright):
            return "Hold the phone upright and try again."
        case .calibrated:
            return snapshot.reading == .notUpright ? "Hold it upright" : "Tilt to move, swing to hit. Double-tap to recalibrate."
        }
    }
}

private struct MatchPanel: View {
    let state: GameStateUpdate
    let controller: PaddleController

    var body: some View {
        VStack(spacing: 12) {
            if state.connectionIsSlow {
                Label("Slow connection. Turn on Wi‑Fi on both devices and keep them near the router.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Capsule()
                    .fill(state.side.rubberColor)
                    .frame(width: 18, height: 4)
                Text("You’re \(state.side.playerName)")
                    .font(.headline)
                Spacer()
                if showsScore {
                    Text("\(score(of: state.side)) – \(score(of: state.side.opponent))")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .accessibilityLabel("You \(score(of: state.side)), opponent \(score(of: state.side.opponent))")
                }
            }
            action
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var action: some View {
        switch state.phase {
        case .calibrating:
            Text("Calibrate below, then tap Ready.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .lobby:
            wideButton("Ready", prominent: true) { controller.link.setReady(true) }
        case .ready:
            VStack(spacing: 8) {
                Label("Ready. The match starts when both players are.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                wideButton("Not Ready", prominent: false) { controller.link.setReady(false) }
            }
        case .serving, .rally, .pointScored:
            wideButton("Pause", prominent: false) { controller.link.requestPause(true) }
        case .paused:
            if state.canResume {
                wideButton("Continue", prominent: true) { controller.link.requestPause(false) }
            } else {
                Text("Paused. Waiting for the other player or the Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .gameOver:
            Text(state.winner == state.side ? "You won" : "You lost")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var showsScore: Bool {
        switch state.phase {
        case .calibrating, .lobby, .ready: false
        case .serving, .rally, .pointScored, .paused, .gameOver: true
        }
    }

    private func score(of side: Side) -> Int {
        Int(side == .playerA ? state.scoreA : state.scoreB)
    }

    @ViewBuilder
    private func wideButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: action) { Text(title).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else {
            Button(action: action) { Text(title).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }
}

private struct StatsFooter: View {
    let stats: DeviceStats

    var body: some View {
        if let cpu = stats.cpuShare {
            Text(text(cpu: cpu))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(stats.isWithinBudget(cpu: cpu) ? Color.secondary : Color.orange)
        }
    }

    private func text(cpu: Double) -> String {
        let cpuText = String(format: "CPU %.0f%% of a core", cpu * 100)
        guard let drop = stats.batteryDrop else { return cpuText }
        return cpuText + String(format: " · battery −%.0f%% in %.0f min unplugged", drop * 100, stats.batteryMinutes)
    }
}

private struct LinkHeader: View {
    let link: PaddleLink
    let launchedAt: Microseconds
    let networkFailure: String?

    var body: some View {
        VStack(spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var title: String {
        switch link.status {
        case .searching: "Looking for your Mac…"
        case .handshaking: "Connecting…"
        case .paired(let hostName): "Connected to \(hostName)"
        case .refused(.versionMismatch): "Update needed"
        case .refused(.gameFull): "Game full"
        case .refused: "Disconnected"
        }
    }

    private var symbol: String {
        switch link.status {
        case .paired: "checkmark.circle.fill"
        case .refused: "exclamationmark.triangle.fill"
        case .searching, .handshaking: "antenna.radiowaves.left.and.right"
        }
    }

    private var detail: String? {
        if let networkFailure {
            return "Allow Local Network access for Flick Paddle in Settings › Privacy & Security › Local Network. (\(networkFailure))"
        }
        switch link.status {
        case .paired:
            guard let pairedAt = link.pairedAt else { return nil }
            return String(format: "Paired %.1f s after opening", Double(pairedAt - launchedAt) / 1_000_000)
        case .refused(.versionMismatch):
            return "This Mac runs a different version of Flick Pong. Update both apps."
        case .refused(.gameFull):
            return "Two players are already in. You'll join when a slot frees up."
        case .refused:
            return "The Mac ended the session."
        case .searching:
            return "Open Flick Pong on your Mac, on the same Wi-Fi."
        case .handshaking:
            return nil
        }
    }
}

private struct PaddleTrack: View {
    let reading: PointerReading?

    var body: some View {
        GeometryReader { geometry in
            let paddleWidth = geometry.size.width * 0.18
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.secondarySystemBackground))
                if case .position(let position) = reading {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: paddleWidth)
                        .offset(x: position * (geometry.size.width - paddleWidth))
                }
            }
        }
        .frame(height: 28)
        .opacity(reading == .notUpright ? 0.4 : 1)
        .accessibilityLabel("Paddle position")
    }
}

private struct SwingPanel: View {
    let snapshot: PaddleSensing.Snapshot

    var body: some View {
        VStack(spacing: 8) {
            Text("\(snapshot.swings)")
                .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
            Text(snapshot.swings == 1 ? "swing" : "swings")
                .foregroundStyle(.secondary)
            if let swing = snapshot.lastSwing {
                ProgressView(value: swing.strength)
                    .frame(maxWidth: 200)
                Text(String(format: "Last: %.1f g, %.1f rad/s, strength %d%%", swing.peakAcceleration, swing.peakRotationRate, Int(swing.strength * 100)))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
