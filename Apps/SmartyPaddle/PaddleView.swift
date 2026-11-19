import SmartyCore
import SwiftUI

struct PaddleView: View {
    let controller: PaddleController
    let isMotionAvailable: Bool

    @State private var thermalState = ProcessInfo.processInfo.thermalState

    var body: some View {
        TimelineView(.animation(minimumInterval: isHot ? Self.hotFrameInterval : nil)) { _ in
            content(controller.sensing.snapshot)
        }
        .background(Paddle.Tone.backdrop)
        .preferredColorScheme(.dark)
        .defersSystemGestures(on: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: RunLoop.main)) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    private static let hotFrameInterval: TimeInterval = 0.1

    private var isHot: Bool {
        thermalState == .serious || thermalState == .critical
    }

    private var state: GameStateUpdate? {
        controller.link.gameState
    }

    private var isPaired: Bool {
        if case .paired = controller.link.status { true } else { false }
    }

    private func content(_ snapshot: PaddleSensing.Snapshot) -> some View {
        RubberFace(side: state?.side ?? .playerA, swings: snapshot.swings) {
            VStack(spacing: 0) {
                Text(state.map { $0.side.playerName.uppercased() } ?? "SMARTY SUPREME")
                    .font(Paddle.Typeface.label)
                    .tracking(3)
                    .foregroundStyle(Paddle.Tone.cream.opacity(0.75))
                Spacer(minLength: 0)
                centre(snapshot)
                Spacer(minLength: 0)
                footer(snapshot)
                    .frame(minHeight: 56)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if isMotionAvailable, snapshot.calibration == .calibrated {
                    controller.sensing.calibrate()
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { drag in
                if !isMotionAvailable, TouchInput.isSwing(across: drag.translation.width, down: drag.translation.height) {
                    controller.swipeSwing()
                }
            })
        }
        .padding(10)
    }

    @ViewBuilder
    private func centre(_ snapshot: PaddleSensing.Snapshot) -> some View {
        if let error = snapshot.sensorError {
            Message(title: "SENSOR ERROR", detail: error)
        } else if !isPaired {
            connection
        } else if isMotionAvailable, snapshot.calibration != .calibrated {
            calibration(snapshot.calibration)
        } else if let state {
            match(state, snapshot: snapshot)
        }
    }

    private var connection: some View {
        let failure = controller.networkFailure.latest
        return switch controller.link.status {
        case .searching:
            Message(title: "LOOKING FOR YOUR MAC", detail: failure.map { _ in "Allow Local Network for Smarty Paddle in Settings." } ?? "Open Smarty Supreme on the same Wi‑Fi.")
        case .handshaking:
            Message(title: "CONNECTING", detail: nil)
        case .refused(.versionMismatch):
            Message(title: "UPDATE NEEDED", detail: "Update Smarty Supreme on both devices.")
        case .refused(.gameFull):
            Message(title: "GAME FULL", detail: "You’ll join when a place frees up.")
        case .refused, .paired:
            Message(title: "DISCONNECTED", detail: nil)
        }
    }

    private func calibration(_ status: PaddleSensing.CalibrationStatus) -> some View {
        VStack(spacing: 28) {
            switch status {
            case .inProgress:
                Message(title: "HOLD STILL", detail: nil)
            case .failed(.handMoved):
                Message(title: "HOLD IT LIKE A BAT", detail: "Your hand moved. Try again.")
            case .failed(.notUpright):
                Message(title: "HOLD IT LIKE A BAT", detail: "Top pointing up. Try again.")
            case .needed, .calibrated:
                Message(title: "HOLD IT LIKE A BAT", detail: "Screen toward you, top up.")
            }
            PrimaryButton(title: "CALIBRATE", action: controller.sensing.calibrate)
                .disabled(status == .inProgress)
                .opacity(status == .inProgress ? 0.4 : 1)
        }
    }

    @ViewBuilder
    private func match(_ state: GameStateUpdate, snapshot: PaddleSensing.Snapshot) -> some View {
        switch state.phase {
        case .calibrating, .lobby:
            PrimaryButton(title: "READY") { controller.link.setReady(true) }
        case .ready:
            Message(title: "READY", detail: "Starting when both players are.")
        case .serving, .rally, .pointScored:
            Score(state: state)
        case .paused:
            VStack(spacing: 28) {
                Message(title: "PAUSED", detail: state.canResume ? nil : "Waiting for the other player.")
                if state.canResume {
                    PrimaryButton(title: "CONTINUE") { controller.link.requestPause(false) }
                }
            }
        case .gameOver:
            VStack(spacing: 12) {
                Message(title: state.winner == state.side ? "YOU WON" : "YOU LOST", detail: nil)
                Score(state: state)
            }
        }
        if !isMotionAvailable {
            GeometryReader { geometry in
                Groove(position: snapshot.touchPosition)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                        controller.dragPaddle(to: drag.location.x, across: geometry.size.width)
                    })
            }
            .frame(height: Paddle.grooveHeight)
            .padding(.top, 32)
        }
    }

    @ViewBuilder
    private func footer(_ snapshot: PaddleSensing.Snapshot) -> some View {
        if state?.connectionIsSlow == true {
            Hint("Slow connection. Move closer to the router.", tone: Paddle.Tone.warning)
        } else if isHot {
            Hint("Your iPhone is hot. Play is unaffected.", tone: Paddle.Tone.warning)
        } else if let state, isPaired, !isMotionAvailable || snapshot.calibration == .calibrated {
            switch state.phase {
            case .serving, .rally, .pointScored:
                QuietButton(title: "PAUSE") { controller.link.requestPause(true) }
            case .ready:
                QuietButton(title: "NOT READY") { controller.link.setReady(false) }
            case .calibrating, .lobby:
                if isMotionAvailable, snapshot.calibration == .calibrated {
                    Hint("Double-tap to recalibrate", tone: Paddle.Tone.cream.opacity(0.6))
                }
            case .paused, .gameOver:
                EmptyView()
            }
        }
    }
}

enum Paddle {
    static let grooveHeight: CGFloat = 26
    static let rim: CGFloat = 9

    enum Tone {
        static let backdrop = Color(red: 0.05, green: 0.04, blue: 0.035)
        static let cream = Color(red: 0.95, green: 0.91, blue: 0.82)
        static let ink = Color(red: 0.13, green: 0.08, blue: 0.05)
        static let warning = Color(red: 1, green: 0.72, blue: 0.4)
        static let woodLight = Color(red: 0.78, green: 0.58, blue: 0.38)
        static let woodDark = Color(red: 0.48, green: 0.31, blue: 0.18)
    }

    enum Typeface {
        static let score = Font.custom("Futura-CondensedExtraBold", size: 96)
        static let title = Font.custom("Futura-Bold", size: 24)
        static let detail = Font.custom("Futura-Medium", size: 16)
        static let label = Font.custom("Futura-Bold", size: 12)
        static let button = Font.custom("Futura-Bold", size: 17)
    }
}

private struct RubberFace<Content: View>: View {
    let side: Side
    let swings: Int
    @ViewBuilder let content: Content

    @State private var flash = 0.0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 56, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Paddle.Tone.woodLight, Paddle.Tone.woodDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            Pips(color: side.rubberColor)
                .clipShape(shape.inset(by: Paddle.rim))
            shape.inset(by: Paddle.rim)
                .fill(LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            shape.inset(by: Paddle.rim).fill(.white.opacity(flash))
            content
        }
        .onChange(of: swings) {
            flash = 0.2
            withAnimation(.easeOut(duration: 0.3)) {
                flash = 0
            }
        }
    }
}

private struct Pips: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
            let spacing: CGFloat = 7
            let radius: CGFloat = 2.05
            var row = 0
            var y: CGFloat = 0
            while y < size.height + spacing {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
                while x < size.width + spacing {
                    let pip = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: pip.offsetBy(dx: 0.6, dy: 0.8)), with: .color(.black.opacity(0.35)))
                    context.fill(Path(ellipseIn: pip), with: .color(color))
                    context.fill(Path(ellipseIn: pip.insetBy(dx: 1.1, dy: 1.1).offsetBy(dx: -0.5, dy: -0.6)), with: .color(.white.opacity(0.1)))
                    x += spacing
                }
                y += spacing * 0.866
                row += 1
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

private struct Message: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(Paddle.Typeface.title)
                .tracking(2)
                .foregroundStyle(Paddle.Tone.cream)
            if let detail {
                Text(detail)
                    .font(Paddle.Typeface.detail)
                    .foregroundStyle(Paddle.Tone.cream.opacity(0.75))
            }
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.5), radius: 6)
        .accessibilityElement(children: .combine)
    }
}

private struct Score: View {
    let state: GameStateUpdate

    var body: some View {
        let mine = Int(state.side == .playerA ? state.scoreA : state.scoreB)
        let theirs = Int(state.side == .playerA ? state.scoreB : state.scoreA)
        HStack(spacing: 20) {
            Text("\(mine)")
            Text("–").foregroundStyle(Paddle.Tone.cream.opacity(0.4))
            Text("\(theirs)")
        }
        .font(Paddle.Typeface.score)
        .monospacedDigit()
        .foregroundStyle(Paddle.Tone.cream)
        .shadow(color: .black.opacity(0.5), radius: 8)
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You \(mine), opponent \(theirs)")
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Paddle.Typeface.button)
                .tracking(2)
                .foregroundStyle(Paddle.Tone.ink)
                .frame(maxWidth: 240, minHeight: 56)
                .background(Paddle.Tone.cream, in: Capsule())
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct QuietButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Paddle.Typeface.label)
                .tracking(2)
                .foregroundStyle(Paddle.Tone.cream.opacity(0.85))
                .padding(.horizontal, 22)
                .frame(minHeight: 44)
                .overlay(Capsule().strokeBorder(Paddle.Tone.cream.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct Hint: View {
    let text: String
    let tone: Color

    init(_ text: String, tone: Color) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(Paddle.Typeface.detail)
            .foregroundStyle(tone)
            .multilineTextAlignment(.center)
    }
}

private struct Groove: View {
    let position: Double?

    var body: some View {
        GeometryReader { geometry in
            let puck = geometry.size.width * 0.2
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.35))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                if let position {
                    Capsule()
                        .fill(Paddle.Tone.cream)
                        .frame(width: puck)
                        .padding(4)
                        .offset(x: position * (geometry.size.width - puck - 8))
                }
            }
        }
        .frame(height: Paddle.grooveHeight)
        .accessibilityLabel("Paddle position")
    }
}
