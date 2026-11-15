import AppKit
import FlickCore
import Observation
import RealityKit
import SwiftUI

@MainActor
@Observable
final class Stage {
    var scene: TableScene?
    var failure: String?
    @ObservationIgnored var updates: EventSubscription?
}

struct GameView: View {
    let match: KeyboardMatch
    let stats: FrameStats
    let showsFrameTimes: Bool

    @State private var stage = Stage()
    @FocusState private var isFocused: Bool
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        RealityView { [match, stats, stage] content in
            content.camera = .virtual
            do {
                let scene = try await TableScene(config: match.game.config)
                content.add(scene.root)
                scene.show(match.camera, animated: false)
                stage.scene = scene
                stage.updates = content.subscribe(to: SceneEvents.Update.self) { event in
                    let events = match.advance(by: event.deltaTime)
                    scene.update(from: match.game, events: events, elapsed: event.deltaTime)
                    stats.record(event.deltaTime)
                }
            } catch {
                stage.failure = "The table couldn’t be set up: \(error.localizedDescription)"
            }
        }
        .overlay(alignment: .top) {
            Scoreboard(score: match.score, server: server)
                .padding(.top, 16)
        }
        .overlay {
            if case .gameOver(let winner) = match.phase {
                WinnerCard(winner: winner, score: match.score, newGame: match.newGame)
            } else if let failure = stage.failure {
                Text(failure)
                    .padding(16)
                    .glassPanel(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .overlay(alignment: .bottom) {
            if match.showsControls {
                ControlsHint()
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsFrameTimes {
                FrameTimes(stats: stats)
                    .padding(16)
            }
        }
        .animation(.easeOut(duration: 0.3), value: match.showsControls)
        .navigationTitle("Flick Pong")
        .navigationSubtitle(subtitle)
        .accessibilityLabel("Table tennis table")
        .accessibilityValue(subtitle)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: [.down, .up]) { press in
            match.handle(press)
        }
        .onTapGesture {
            isFocused = true
        }
        .defaultFocus($isFocused, true)
        .onChange(of: isFocused) { _, focused in
            if !focused {
                match.releaseAllKeys()
            }
        }
        .onChange(of: activeState) { _, state in
            if state != .key {
                match.releaseAllKeys()
            }
        }
        .onChange(of: match.camera) { _, camera in
            stage.scene?.show(camera, animated: true)
        }
    }

    private var server: Side? {
        if case .serving(let side, _) = match.phase { return side }
        return nil
    }

    private var subtitle: String {
        switch match.phase {
        case .serving(let server, _): "\(server.playerName) to serve"
        case .rally: match.rally < 2 ? "Rally" : "Rally of \(match.rally)"
        case .pointScored: "Point"
        case .paused: "Paused"
        case .gameOver(let winner): "\(winner.playerName) wins"
        }
    }
}

extension Side {
    var playerName: String {
        self == .playerA ? "Player A" : "Player B"
    }

    var rubberNSColor: NSColor {
        self == .playerA ? NSColor(red: 0.12, green: 0.36, blue: 0.86, alpha: 1) : NSColor(red: 0.84, green: 0.16, blue: 0.16, alpha: 1)
    }

    var rubberColor: Color {
        Color(nsColor: rubberNSColor)
    }
}

extension View {
    @ViewBuilder
    func glassPanel(_ shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

private struct Scoreboard: View {
    let score: Score
    let server: Side?

    var body: some View {
        HStack(spacing: 22) {
            player(.playerA)
            Text("–")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            player(.playerB)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .glassPanel(Capsule())
        .animation(.snappy, value: score)
    }

    private func player(_ side: Side) -> some View {
        let score = score[side]
        let isServing = server == side
        return HStack(spacing: 10) {
            if side == .playerB {
                Text("\(score)").scoreFigure()
            }
            VStack(alignment: side == .playerA ? .trailing : .leading, spacing: 3) {
                Text(side.playerName)
                    .font(.callout.weight(.medium))
                Capsule()
                    .fill(side.rubberColor)
                    .frame(width: isServing ? 26 : 14, height: 3)
                    .animation(.easeOut(duration: 0.25), value: isServing)
            }
            if side == .playerA {
                Text("\(score)").scoreFigure()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.playerName), \(score) points\(isServing ? ", serving" : "")")
    }

}

private extension Text {
    func scoreFigure() -> some View {
        font(.system(size: 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

private struct WinnerCard: View {
    let winner: Side
    let score: Score
    let newGame: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("\(winner.playerName) wins")
                .font(.title2.weight(.semibold))
            Text("\(max(score.a, score.b))–\(min(score.a, score.b))")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Button("New Game", action: newGame)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 26)
        .glassPanel(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ControlsHint: View {
    var body: some View {
        HStack(spacing: 28) {
            controls(for: .playerA, move: ["A", "D"], swing: "W")
            Divider().frame(height: 22)
            controls(for: .playerB, move: ["←", "→"], swing: "↑")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassPanel(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Player A moves with A and D and swings with W. Player B moves with the left and right arrows and swings with the up arrow.")
    }

    private func controls(for side: Side, move: [String], swing: String) -> some View {
        HStack(spacing: 8) {
            Text(side.playerName)
                .font(.callout.weight(.medium))
            HStack(spacing: 3) {
                ForEach(move, id: \.self) { Keycap(label: $0) }
            }
            Text("move")
                .foregroundStyle(.secondary)
            Keycap(label: swing)
            Text("swing")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.callout.weight(.medium))
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
    }
}

private struct FrameTimes: View {
    let stats: FrameStats

    var body: some View {
        Text(text)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(meetsBudget ? Color.secondary : Color.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassPanel(Capsule())
    }

    private var meetsBudget: Bool {
        guard let percentile = stats.percentile99 else { return true }
        return percentile <= FrameStats.budget && stats.dropped == 0
    }

    private var text: String {
        guard let percentile = stats.percentile99 else { return "Measuring frames…" }
        return String(format: "99%% of frames under %.1f ms · %ld dropped · last %.0f s", percentile * 1_000, stats.dropped, stats.measured)
    }
}
