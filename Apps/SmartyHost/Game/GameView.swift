import AppKit
import SmartyCore
import Observation
import RealityKit
import SwiftUI

@MainActor
@Observable
final class Stage {
    var scene: TableScene?
    var failure: String?
    @ObservationIgnored var updates: EventSubscription?
    @ObservationIgnored let feed = PoseFeed()
    @ObservationIgnored private var forecastFlight: UInt64?
    @ObservationIgnored private var forecastSteps: [Side: (step: UInt64, position: SIMD3<Double>)] = [:]

    func forecasts(for game: GameState) -> [Side: TablePose.Forecast] {
        if forecastFlight != game.flightNumber {
            forecastFlight = game.flightNumber
            forecastSteps = [:]
            for side in Side.allCases {
                if let contact = game.predictedContact(for: side) {
                    forecastSteps[side] = (game.step + contact.stepsAway, contact.position)
                }
            }
        }
        var forecasts: [Side: TablePose.Forecast] = [:]
        let stepsPerSecond = Double(game.config.stepsPerSecond)
        if case .rally = game.phase {
            for (side, contact) in forecastSteps where contact.step >= game.step {
                forecasts[side] = TablePose.Forecast(secondsAway: Double(contact.step - game.step) / stepsPerSecond, position: contact.position)
            }
        }
        for side in Side.allCases {
            if let strike = game.predictedServeStrike(for: side) {
                forecasts[side] = TablePose.Forecast(secondsAway: Double(strike.stepsAway) / stepsPerSecond, position: strike.position)
            }
        }
        return forecasts
    }
}

@MainActor
final class PoseFeed {
    private static let backlog = 8

    var isListening = false {
        didSet {
            if !isListening {
                pending.removeAll()
            }
        }
    }

    private var pending: [(pose: TablePose, elapsed: TimeInterval)] = []

    func push(_ pose: TablePose, elapsed: TimeInterval) {
        guard isListening else { return }
        pending.append((pose, elapsed))
        if pending.count > Self.backlog {
            pending.removeFirst()
        }
    }

    func drain() -> [(pose: TablePose, elapsed: TimeInterval)] {
        defer { pending.removeAll() }
        return pending
    }
}

struct GameView: View {
    let match: Match
    let stats: FrameStats
    let showsFrameTimes: Bool

    @State private var stage = Stage()
    @FocusState private var isFocused: Bool
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        HStack(spacing: 0) {
            arena
            if match.camera == .split {
                Rectangle()
                    .fill(Programme.ink)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                PlayerBArena(feed: stage.feed, config: match.game.config)
            }
        }
        .overlay {
            FilmLook()
                .ignoresSafeArea()
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
            if match.showsTutorial, match.hasStarted {
                HowToPlayCard { match.showsTutorial = false }
            } else if case .gameOver(let winner) = match.phase {
                WinnerCard(winner: match.name(of: winner), score: match.score, playAgain: match.playAgain)
            } else if case .interrupted(let interruption) = match.stage {
                InterruptionCard(match: match, interruption: interruption)
            } else if !match.hasStarted {
                HStack(alignment: .top, spacing: 20) {
                    HowToPlayCard()
                    LobbyCard(match: match)
                }

            } else if let failure = stage.failure {
                Text(failure)
                    .font(Programme.body(13))
                    .padding(20)
                    .programmeCard()
            }
        }
        .overlay(alignment: .bottom) {
            StrokeCard(stroke: match.lastStroke)
                .padding(.bottom, 92)
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
                PerformanceLine(stats: stats)
                    .padding(16)
            }
        }
        .animation(.easeOut(duration: 0.3), value: match.showsControls)
        .sheet(isPresented: Binding(get: { match.isChoosingNewGame }, set: { if !$0 { match.cancelNewGame() } })) {
            NewGameSheet(setup: match.setup, start: match.start, cancel: match.cancelNewGame)
        }
        .animation(.easeOut(duration: 0.25), value: showsCard)
        .navigationTitle("Smarty Supreme")
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
            stage.scene?.show(camera, halfScreen: camera == .split, animated: true)
        }
    }

    private var arena: some View {
        RealityView { [match, stats, stage] content in
            content.camera = .virtual
            do {
                let scene = try await TableScene(config: match.game.config)
                content.add(scene.root)
                scene.show(match.camera, halfScreen: match.camera == .split, animated: false)
                stage.scene = scene
                stage.updates = content.subscribe(to: SceneEvents.Update.self) { event in
                    let events = match.advance()
                    let stances = Dictionary(uniqueKeysWithValues: Side.allCases.compactMap { side in match.session.settledStance(of: side).map { (side, $0) } })
                    let pose = TablePose(game: match.game, events: events, dimmed: match.dimmed, forecasts: stage.forecasts(for: match.game), stances: stances)
                    scene.update(to: pose, elapsed: event.deltaTime)
                    stage.feed.push(pose, elapsed: event.deltaTime)
                    stats.record(event.deltaTime)
                }
            } catch {
                stage.failure = "The table couldn’t be set up: \(error.localizedDescription)"
            }
        }
    }

    private static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    private var showsCard: Bool {
        match.isPaused || match.isGameOver || !match.hasStarted || match.showsTutorial
    }

    private var server: Side? {
        if case .serving(let side, _) = match.phase { return side }
        return nil
    }

    private func controls(for side: Side) -> PlayerControls {
        switch match.controller(of: side) {
        case .phone: .phone
        case .computer: .computer(match.setup.difficulty)
        case .local: side == .playerA ? .keyboard(aim: ["A", "D"], swing: "W") : .keyboard(aim: ["←", "→"], swing: "↑")
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

private struct PlayerBArena: View {
    let feed: PoseFeed
    let config: GameConfig

    @State private var stage = Stage()

    var body: some View {
        RealityView { [feed, config, stage] content in
            content.camera = .virtual
            do {
                let scene = try await TableScene(config: config, playsSounds: false)
                content.add(scene.root)
                scene.show(.playerBEnd, halfScreen: true, animated: false)
                stage.scene = scene
                stage.updates = content.subscribe(to: SceneEvents.Update.self) { _ in
                    for (pose, elapsed) in feed.drain() {
                        scene.update(to: pose, elapsed: elapsed)
                    }
                }
            } catch {
                stage.failure = error.localizedDescription
            }
        }
        .onAppear { feed.isListening = true }
        .onDisappear { feed.isListening = false }
        .accessibilityLabel("Player B’s end of the table")
    }
}

private struct StrokeCard: View {
    private static let shownFor: Duration = .milliseconds(1_100)

    let stroke: StrokeTiming?

    @State private var shown: StrokeTiming?

    var body: some View {
        ZStack {
            if let shown {
                Text(shown.label)
                    .font(Programme.title(13))
                    .tracking(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .programmeCard()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: shown)
        .task(id: stroke) {
            guard let stroke else { return }
            shown = stroke
            try? await Task.sleep(for: Self.shownFor)
            if shown == stroke {
                shown = nil
            }
        }
        .allowsHitTesting(false)
    }
}

struct Scoreboard: View {
    let score: Score
    let server: Side?
    let leading: Side
    let name: (Side) -> String

    var body: some View {
        HStack(spacing: 14) {
            player(leading)
            Image(systemName: "star.fill")
                .font(.system(size: 9))
                .foregroundStyle(Programme.paper.opacity(0.7))
                .accessibilityHidden(true)
            player(leading.opponent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Programme.navy, in: RoundedRectangle(cornerRadius: Programme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Programme.cornerRadius - 2, style: .continuous).inset(by: 4).strokeBorder(Programme.paper.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        .animation(.snappy, value: score)
    }

    private func player(_ side: Side) -> some View {
        let score = score[side]
        let isServing = server == side
        let name = name(side)
        return HStack(spacing: 12) {
            if side != leading {
                FlipCard(value: score, size: 32)
            }
            VStack(alignment: side == leading ? .trailing : .leading, spacing: 4) {
                Text(name.uppercased())
                    .font(Programme.title(12))
                    .tracking(1.2)
                    .foregroundStyle(Programme.paper)
                Capsule()
                    .fill(side.rubberColor)
                    .frame(width: isServing ? 26 : 12, height: 3)
                    .animation(.easeOut(duration: 0.25), value: isServing)
            }
            if side == leading {
                FlipCard(value: score, size: 32)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(score) points\(isServing ? ", serving" : "")")
    }
}

private struct WinnerCard: View {
    let winner: String
    let score: Score
    let playAgain: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("★ ★ ★")
                .font(Programme.title(13))
                .accessibilityHidden(true)
            Text("\(winner) wins".uppercased())
                .font(Programme.title(24))
                .tracking(1.5)
            HStack(spacing: 10) {
                FlipCard(value: max(score.a, score.b), size: 54)
                FlipCard(value: min(score.a, score.b), size: 54)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(max(score.a, score.b)) to \(min(score.a, score.b))")
            Button("Play Again", action: playAgain)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .programmeCard()
    }
}

private enum PlayerControls {
    case keyboard(aim: [String], swing: String)
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
        .font(Programme.body(13))
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .programmeCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Side.allCases.map(spokenHint).joined(separator: " "))
    }

    @ViewBuilder
    private func hint(for side: Side) -> some View {
        HStack(spacing: 8) {
            Text(name(side).uppercased())
                .font(Programme.title(12))
                .tracking(1)
            switch controls(side) {
            case .keyboard(let aim, let swing):
                HStack(spacing: 3) {
                    ForEach(aim, id: \.self) { Keycap(label: $0) }
                }
                Text("aim")
                    .foregroundStyle(.secondary)
                Keycap(label: swing)
                Text("swing")
                    .foregroundStyle(.secondary)
            case .phone:
                Image(systemName: "iphone")
                    .foregroundStyle(.secondary)
                Text("Swing it like a paddle")
                    .foregroundStyle(.secondary)
            case .computer(let difficulty):
                Text(difficulty.title)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func spokenHint(for side: Side) -> String {
        switch controls(side) {
        case .keyboard(let aim, let swing):
            "\(name(side)) aims with \(aim.joined(separator: " and ")) and swings with \(swing) as the ball comes."
        case .phone:
            "\(name(side)) swings the iPhone like a paddle."
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

struct PerformanceLine: View {
    let stats: FrameStats

    var body: some View {
        if let fps = stats.framesPerSecond, let cpu = stats.cpuShare {
            Text(String(format: "%.0f fps · CPU %.0f%%", fps, cpu * 100))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.35), in: Capsule())
        }
    }
}
