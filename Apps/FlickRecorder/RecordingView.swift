import FlickCore
import SwiftUI

struct RecordingView: View {
    let recording: LiveRecording
    let onStop: () -> Void

    @State private var isHolding = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let progress = recording.progress
            VStack(spacing: 0) {
                header(progress)
                if recording.activity.isSwings {
                    holdArea(swings: progress.swings)
                } else {
                    timedArea(progress)
                }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func header(_ progress: LiveRecording.Progress) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.activity.title)
                    .font(.headline)
                Text("\(clock(progress.duration)) · \(sampleRate(progress)) Hz")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let error = progress.sensorError {
                    Text("Sensor error: \(error)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button("Stop", action: onStop)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding()
    }

    private func holdArea(swings: Int) -> some View {
        ZStack {
            Rectangle()
                .fill(isHolding ? Color.accentColor : Color(.secondarySystemBackground))
            VStack(spacing: 12) {
                Text("\(swings)")
                    .font(.system(size: 96, weight: .semibold, design: .rounded).monospacedDigit())
                Text(isHolding ? "Swing" : "Hold anywhere while you swing")
                    .font(.title3)
            }
            .foregroundStyle(isHolding ? .white : .primary)
        }
        .overlay {
            HoldSurface(
                onPress: { time in
                    isHolding = true
                    recording.beginSwing(at: time)
                },
                onRelease: { time in
                    isHolding = false
                    recording.endSwing(at: time)
                }
            )
        }
        .accessibilityLabel("Swing area, \(swings) swings recorded")
    }

    private func timedArea(_ progress: LiveRecording.Progress) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(clock(progress.duration))
                .font(.system(size: 96, weight: .semibold, design: .rounded).monospacedDigit())
            Text(recording.activity.instructions)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    private func clock(_ duration: Microseconds) -> String {
        let seconds = Int(duration / 1_000_000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func sampleRate(_ progress: LiveRecording.Progress) -> Int {
        guard progress.duration > 0 else { return 0 }
        return Int((Double(progress.frames - 1) / (Double(progress.duration) / 1_000_000)).rounded())
    }
}
