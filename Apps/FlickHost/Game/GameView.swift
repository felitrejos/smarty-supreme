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
    let match: Match
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
                    let events = match.advance()
                    scene.update(to: TablePose(game: match.game, events: events, dimmed: match.dimmed), elapsed: event.deltaTime)
                    stats.record(event.deltaTime) { match.session.swingLatency.percentile(0.95) }
                }
            } catch {
                stage.failure = "The table couldn’t be set up: \(error.localizedDescription)"
            }
        }
        .accessibilityLabel("Table tennis table")
        .accessibilityValue(subtitle)
        .overlay {
            if showsCard {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .top) {
            Scoreboard(score: match.score, server: server, leading: .playerA, name: match.name(of:))
                .padding(.top, 16)
        }
        .overlay {
            if case .gameOver(let winner) = match.phase {
                WinnerCard(winner: match.name(of: winner), score: match.score, playAgain: match.playAgain)
            } else if case .interrupted(let interruption) = match.stage {
                InterruptionCard(match: match, interruption: interruption)
            } else if !match.hasStarted {
                LobbyCard(match: match)
            } else if let failure = stage.failure {
                Text(failure)
                    .padding(16)
                    .glassPanel(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .overlay(alignment: .bottom) {
            if match.showsControls, !match.isPaused {
                ControlsHint(name: match.name(of:), controls: controls(for:))
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
        .sheet(isPresented: Binding(get: { match.isChoosingNewGame }, set: { if !$0 { match.cancelNewGame() } })) {
            NewGameSheet(setup: match.setup, start: match.start, cancel: match.cancelNewGame)
        }
        .animation(.easeOut(duration: 0.25), value: showsCard)
        .navigationTitle("Flick Pong")
        .navigationSubtitle(subtitle)
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
        .onChange(of: activeState, initial: true) { _, state in
            match.appBecameActive(state != .inactive)
        }
        .onDisappear(perform: match.gameWindowClosed)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).receive(on: RunLoop.main)) { _ in
            match.macWillSleep()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).receive(on: RunLoop.main)) { _ in
            match.macDidWake()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Self.screenLocked).receive(on: RunLoop.main)) { _ in
            match.screenLocked()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Self.screenUnlocked).receive(on: RunLoop.main)) { _ in
            match.screenUnlocked()
        }
        .onChange(of: match.camera) { _, camera in
            stage.scene?.show(camera, animated: true)
        }
    }

    private static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    private var showsCard: Bool {
        match.isPaused || match.isGameOver || !match.hasStarted
    }

    private var server: Side? {
        if case .serving(let side, _) = match.phase { return side }
        return nil
    }

    private func controls(for side: Side) -> PlayerControls {
        switch match.controller(of: side) {
        case .phone: .phone
        case .computer: .computer(match.setup.difficulty)
        case .local: side == .playerA ? .keyboard(move: ["A", "D"], swing: "W") : .keyboard(move: ["←", "→"], swing: "↑")
        }
    }

    private var subtitle: String {
        switch match.stage {
        case .lobby: return "Waiting for players"
        case .countdown: return "Starting"
        case .interrupted: return "Paused"
        case .playing, .over: break
        }
        return switch match.phase {
        case .serving(let server, _): "\(match.name(of: server)) to serve"
        case .rally: match.rally < 2 ? "Rally" : "Rally of \(match.rally)"
        case .pointScored: "Point"
        case .paused: "Paused"
        case .gameOver(let winner): "\(match.name(of: winner)) wins"
        }
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

struct Scoreboard: View {
    let score: Score
    let server: Side?
    let leading: Side
    let name: (Side) -> String

    var body: some View {
        HStack(spacing: 22) {
            player(leading)
            Text("–")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            player(leading.opponent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .glassPanel(Capsule())
        .animation(.snappy, value: score)
    }

    private func player(_ side: Side) -> some View {
        let score = score[side]
        let isServing = server == side
        let name = name(side)
        return HStack(spacing: 10) {
            if side != leading {
                Text("\(score)").scoreFigure()
            }
            VStack(alignment: side == leading ? .trailing : .leading, spacing: 3) {
                Text(name)
                    .font(.callout.weight(.medium))
                Capsule()
                    .fill(side.rubberColor)
                    .frame(width: isServing ? 26 : 14, height: 3)
                    .animation(.easeOut(duration: 0.25), value: isServing)
            }
            if side == leading {
                Text("\(score)").scoreFigure()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(score) points\(isServing ? ", serving" : "")")
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
    let winner: String
    let score: Score
    let playAgain: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("\(winner) wins")
                .font(.title2.weight(.semibold))
            Text("\(max(score.a, score.b))–\(min(score.a, score.b))")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Button("Play Again", action: playAgain)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 26)
        .glassPanel(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private enum PlayerControls {
    case keyboard(move: [String], swing: String)
    case phone
    case computer(Difficulty)
}

private struct ControlsHint: View {
    let name: (Side) -> String
    let controls: (Side) -> PlayerControls

    var body: some View {
        HStack(spacing: 28) {
            hint(for: .playerA)
            Divider().frame(height: 22)
            hint(for: .playerB)
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassPanel(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Side.allCases.map(spokenHint).joined(separator: " "))
    }

    @ViewBuilder
    private func hint(for side: Side) -> some View {
        HStack(spacing: 8) {
            Text(name(side))
                .font(.callout.weight(.medium))
            switch controls(side) {
            case .keyboard(let move, let swing):
                HStack(spacing: 3) {
                    ForEach(move, id: \.self) { Keycap(label: $0) }
                }
                Text("move")
                    .foregroundStyle(.secondary)
                Keycap(label: swing)
                Text("swing")
                    .foregroundStyle(.secondary)
            case .phone:
                Image(systemName: "iphone")
                    .foregroundStyle(.secondary)
                Text("Tilt to move, swing to hit")
                    .foregroundStyle(.secondary)
            case .computer(let difficulty):
                Text(difficulty.title)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func spokenHint(for side: Side) -> String {
        switch controls(side) {
        case .keyboard(let move, let swing):
            "\(name(side)) moves with \(move.joined(separator: " and ")) and swings with \(swing)."
        case .phone:
            "\(name(side)) tilts the iPhone to move and swings it to hit."
        case .computer(let difficulty):
            "\(name(side)) plays at \(difficulty.title) difficulty."
        }
    }
}

private struct NewGameSheet: View {
    @State private var setup: MatchSetup
    private let start: (MatchSetup) -> Void
    private let cancel: () -> Void

    init(setup: MatchSetup, start: @escaping (MatchSetup) -> Void, cancel: @escaping () -> Void) {
        _setup = State(initialValue: setup)
        self.start = start
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Game")
                .font(.headline)
                .padding([.horizontal, .top], 20)
            Form {
                Picker("Opponent", selection: $setup.opponent) {
                    ForEach(Opponent.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Picker("Difficulty", selection: $setup.difficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(setup.opponent != .computer)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Start") { start(setup) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .trailing, spacing: 2) {
            Text(frameText)
                .foregroundStyle(meetsBudget ? Color.secondary : Color.orange)
            ResourceLine(stats: stats)
            if let latency = stats.swingLatency95 {
                Text(String(format: "Swings reach the game 95%% within %.0f ms, plus a frame to the screen", Double(latency) / 1_000))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassPanel(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var meetsBudget: Bool {
        guard let percentile = stats.percentile99 else { return true }
        return percentile <= FrameStats.budget && stats.dropped == 0
    }

    private var frameText: String {
        guard let percentile = stats.percentile99 else { return "Measuring frames…" }
        return String(format: "99%% of frames under %.1f ms · %ld dropped · last %.0f s", percentile * 1_000, stats.dropped, stats.measured)
    }
}

struct ResourceLine: View {
    let stats: FrameStats

    var body: some View {
        if let cpu = stats.cpuShare {
            Text(String(format: "CPU %.0f%% of a core · memory %.0f MB, %+.1f MB since the first frame", cpu * 100, Double(stats.memoryBytes) / 1_000_000, Double(stats.memoryGrowth) / 1_000_000))
                .foregroundStyle(withinBudget(cpu) ? Color.secondary : Color.orange)
        }
    }

    private func withinBudget(_ cpu: Double) -> Bool {
        cpu <= FrameStats.cpuBudget && stats.memoryGrowth < FrameStats.memoryGrowthBudget
    }
}
