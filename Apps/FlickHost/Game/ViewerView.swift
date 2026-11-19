import FlickCore
import RealityKit
import SwiftUI

struct ViewerView: View {
    let viewer: ViewerMatch
    let stats: FrameStats
    let showsFrameTimes: Bool

    @State private var stage = Stage()

    var body: some View {
        RealityView { [viewer, stats, stage] content in
            content.camera = .virtual
            do {
                let scene = try await TableScene(config: viewer.config)
                content.add(scene.root)
                scene.show(.playerBEnd, animated: false)
                stage.scene = scene
                stage.updates = content.subscribe(to: SceneEvents.Update.self) { event in
                    if let pose = viewer.pose() {
                        scene.update(to: pose, elapsed: event.deltaTime)
                    }
                    stats.record(event.deltaTime)
                }
            } catch {
                stage.failure = "The table couldn’t be set up: \(error.localizedDescription)"
            }
        }
        .overlay(alignment: .top) {
            Scoreboard(score: viewer.score, server: nil, leading: .playerB, name: \.playerName)
                .padding(.top, 16)
        }
        .overlay {
            if let notice {
                VStack(spacing: 8) {
                    Text(notice.title)
                        .font(.title3.weight(.semibold))
                    if let detail = notice.detail {
                        Text(detail)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 22)
                .frame(maxWidth: 420)
                .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsFrameTimes {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(delayText)
                        .foregroundStyle(.secondary)
                    ResourceLine(stats: stats)
                }
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(16)
            }
        }
        .navigationTitle("Flick Pong")
        .navigationSubtitle("Player B’s Screen")
    }

    private var notice: (title: String, detail: String?)? {
        if let failure = stage.failure {
            return (failure, nil)
        }
        switch viewer.status {
        case .searching:
            return ("Looking for the host Mac…", viewer.networkFailure.latest.map { "Allow Local Network access for Flick Pong in System Settings. (\($0))" } ?? "Open Flick Pong on the other Mac, on the same Wi‑Fi.")
        case .handshaking:
            return ("Connecting…", nil)
        case .refused(.gameFull):
            return ("The host already has a screen for Player B", "Choose File › Use as Player B’s Screen again to stop.")
        case .refused(.versionMismatch):
            return ("Update needed", "The other Mac runs a different version of Flick Pong. Update both.")
        case .refused:
            return ("The host ended the session", nil)
        case .paired:
            break
        }
        switch viewer.phase {
        case .lobby, .calibrating: return ("Waiting for players", "The match starts on the host Mac.")
        case .ready: return ("Get ready", nil)
        case .paused: return ("Paused", nil)
        case .gameOver: return (viewer.winner.map { "\($0.playerName) wins" } ?? "Game over", nil)
        case .serving, .rally, .pointScored: return nil
        }
    }

    private var delayText: String {
        guard let delay = viewer.delayPercentile95 else { return "Measuring delay behind the host…" }
        return String(format: "95%% of frames within %.1f ms of the host", Double(delay) / 1_000)
    }
}
