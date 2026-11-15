import FlickCore
import SwiftUI

struct SensorTestView: View {
    let motion: MotionService

    @State private var sensing = PaddleSensing()

    var body: some View {
        NavigationStack {
            Group {
                if motion.isAvailable {
                    TimelineView(.animation) { _ in
                        content(sensing.snapshot)
                    }
                } else {
                    ContentUnavailableView(
                        "Motion sensors unavailable",
                        systemImage: "iphone.slash",
                        description: Text("Run the paddle on an iPhone to test swings and tilt.")
                    )
                }
            }
            .navigationTitle("Sensor test")
        }
        .onAppear {
            guard motion.isAvailable else { return }
            motion.start(onSample: sensing.process, onError: sensing.reportSensorError)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            motion.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func content(_ snapshot: PaddleSensing.Snapshot) -> some View {
        VStack(spacing: 28) {
            Text(status(snapshot))
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
            PaddleTrack(reading: snapshot.reading)
            SwingPanel(snapshot: snapshot)
            Spacer()
            Picker("Sensitivity", selection: Binding(get: { snapshot.sensitivity }, set: sensing.setSensitivity)) {
                ForEach(Sensitivity.allCases, id: \.self) { sensitivity in
                    Text("\(Int(sensitivity.rangeDegrees))°").tag(sensitivity)
                }
            }
            .pickerStyle(.segmented)
            Button(action: sensing.calibrate) {
                Text(snapshot.calibration == .inProgress ? "Hold still…" : "Calibrate")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(snapshot.calibration == .inProgress)
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: sensing.calibrate)
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
                .font(.system(size: 72, weight: .semibold, design: .rounded).monospacedDigit())
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
