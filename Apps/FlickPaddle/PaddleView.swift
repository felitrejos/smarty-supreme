import FlickCore
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

    private var side: Side {
        controller.link.gameState?.side ?? .playerA
    }

    private func content(_ snapshot: PaddleSensing.Snapshot) -> some View {
        VStack(spacing: 0) {
            PaddleFace(side: side, tilt: tilt(snapshot), swings: snapshot.swings) {
                VStack(spacing: 14) {
                    Stamp()
                    LinkHeader(link: controller.link, launchedAt: controller.launchedAt, networkFailure: controller.networkFailure.latest)
                    if isHot {
                        Text("Your iPhone is hot. The screen updates less often; play is unaffected.")
                            .font(Paddle.Typeface.note)
                            .foregroundStyle(Paddle.Tone.warning)
                            .multilineTextAlignment(.center)
                    }
                    if let state = controller.link.gameState {
                        MatchPanel(state: state, controller: controller)
                    }
                    Spacer(minLength: 0)
                    playArea(snapshot)
                    if isMotionAvailable {
                        SensitivityPicker(selected: snapshot.sensitivity, select: controller.setSensitivity)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 34)
                .padding(.bottom, 28)
            }
            Handle {
                if isMotionAvailable {
                    Button(action: controller.sensing.calibrate) {
                        Text(snapshot.calibration == .inProgress ? "HOLD STILL" : "CALIBRATE")
                            .font(Paddle.Typeface.handle)
                            .tracking(2)
                            .foregroundStyle(Paddle.Tone.ink)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .disabled(snapshot.calibration == .inProgress)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func tilt(_ snapshot: PaddleSensing.Snapshot) -> Double {
        guard case .position(let position) = snapshot.reading else { return 0 }
        return (position - 0.5) * Paddle.maximumTilt * 2
    }

    @ViewBuilder
    private func playArea(_ snapshot: PaddleSensing.Snapshot) -> some View {
        let area = VStack(spacing: 14) {
            Text(isMotionAvailable ? status(snapshot) : "Drag along the groove to move, swipe up to swing.")
                .font(Paddle.Typeface.body)
                .foregroundStyle(Paddle.Tone.cream)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
            if isMotionAvailable {
                Groove(reading: snapshot.reading)
            } else {
                GeometryReader { geometry in
                    Groove(reading: snapshot.reading)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                            controller.dragPaddle(to: drag.location.x, across: geometry.size.width)
                        })
                }
                .frame(height: Paddle.grooveHeight)
            }
            if let swing = snapshot.lastSwing {
                Text("\(snapshot.swings) \(snapshot.swings == 1 ? "SWING" : "SWINGS") · LAST \(Int(swing.strength * 100))%")
                    .font(Paddle.Typeface.small)
                    .tracking(1.5)
                    .foregroundStyle(Paddle.Tone.cream.opacity(0.7))
            }
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

enum Paddle {
    static let maximumTilt = 7.0
    static let grooveHeight: CGFloat = 26
    static let rim: CGFloat = 9

    enum Tone {
        static let backdrop = Color(red: 0.05, green: 0.04, blue: 0.035)
        static let cream = Color(red: 0.95, green: 0.91, blue: 0.82)
        static let gold = Color(red: 0.86, green: 0.71, blue: 0.42)
        static let ink = Color(red: 0.13, green: 0.08, blue: 0.05)
        static let warning = Color(red: 1, green: 0.72, blue: 0.4)
        static let woodLight = Color(red: 0.78, green: 0.58, blue: 0.38)
        static let woodDark = Color(red: 0.48, green: 0.31, blue: 0.18)
    }

    enum Typeface {
        static let stamp = Font.custom("Futura-CondensedExtraBold", size: 30)
        static let score = Font.custom("Futura-CondensedExtraBold", size: 64)
        static let title = Font.custom("Futura-Bold", size: 17)
        static let body = Font.custom("Futura-Medium", size: 16)
        static let note = Font.custom("Futura-Medium", size: 13)
        static let small = Font.custom("Futura-Bold", size: 11)
        static let handle = Font.custom("Futura-Bold", size: 14)
    }

    static func rubber(_ side: Side) -> Color {
        side.rubberColor
    }
}

private struct PaddleFace<Content: View>: View {
    let side: Side
    let tilt: Double
    let swings: Int
    @ViewBuilder let content: Content

    @State private var flash = 0.0
    @State private var pulse = 1.0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 150, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Paddle.Tone.woodLight, Paddle.Tone.woodDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            Pips(color: Paddle.rubber(side))
                .clipShape(shape.inset(by: Paddle.rim))
                .overlay(shape.inset(by: Paddle.rim).strokeBorder(.black.opacity(0.45), lineWidth: 1.5))
            shape.inset(by: Paddle.rim)
                .fill(RadialGradient(colors: [.white.opacity(0.14), .clear], center: .init(x: 0.35, y: 0.2), startRadius: 0, endRadius: 420))
            shape.inset(by: Paddle.rim).fill(.white.opacity(flash))
            content
        }
        .scaleEffect(pulse)
        .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 0, z: 1), anchor: .bottom)
        .shadow(color: .black.opacity(0.6), radius: 18, y: 10)
        .onChange(of: swings) {
            flash = 0.28
            pulse = 1.035
            withAnimation(.easeOut(duration: 0.35)) {
                flash = 0
                pulse = 1
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
                    context.fill(Path(ellipseIn: pip.insetBy(dx: 1.1, dy: 1.1).offsetBy(dx: -0.5, dy: -0.6)), with: .color(.white.opacity(0.12)))
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

private struct Handle<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 30, bottomTrailingRadius: 30, topTrailingRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Paddle.Tone.woodDark, Paddle.Tone.woodLight, Paddle.Tone.woodDark], startPoint: .leading, endPoint: .trailing))
            content
        }
        .frame(width: 150, height: 74)
    }
}

private struct Stamp: View {
    var body: some View {
        VStack(spacing: 2) {
            Text("FLICK PONG")
                .font(Paddle.Typeface.stamp)
                .tracking(3)
            Text("HARDBAT · TOURNAMENT")
                .font(Paddle.Typeface.small)
                .tracking(3)
        }
        .foregroundStyle(Paddle.Tone.gold)
        .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flick Pong")
    }
}

private struct SensitivityPicker: View {
    let selected: Sensitivity
    let select: (Sensitivity) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Sensitivity.allCases, id: \.self) { sensitivity in
                Button { select(sensitivity) } label: {
                    Text("\(Int(sensitivity.rangeDegrees))°")
                        .font(Paddle.Typeface.small)
                        .tracking(1)
                        .foregroundStyle(sensitivity == selected ? Paddle.Tone.ink : Paddle.Tone.cream)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(sensitivity == selected ? Paddle.Tone.cream : Paddle.Tone.cream.opacity(0.12), in: Capsule())
                }
                .accessibilityLabel("Tilt range \(Int(sensitivity.rangeDegrees)) degrees")
                .accessibilityAddTraits(sensitivity == selected ? .isSelected : [])
            }
        }
    }
}

private struct MatchPanel: View {
    let state: GameStateUpdate
    let controller: PaddleController

    var body: some View {
        VStack(spacing: 10) {
            if state.connectionIsSlow {
                Text("Slow connection. Turn on Wi‑Fi on both devices and keep them near the router.")
                    .font(Paddle.Typeface.note)
                    .foregroundStyle(Paddle.Tone.warning)
                    .multilineTextAlignment(.center)
            }
            Text("YOU’RE \(state.side.playerName.uppercased())")
                .font(Paddle.Typeface.small)
                .tracking(2)
                .foregroundStyle(Paddle.Tone.cream.opacity(0.8))
            if showsScore {
                HStack(spacing: 18) {
                    Text("\(score(of: state.side))")
                    Text("–").foregroundStyle(Paddle.Tone.cream.opacity(0.5))
                    Text("\(score(of: state.side.opponent))")
                }
                .font(Paddle.Typeface.score)
                .monospacedDigit()
                .foregroundStyle(Paddle.Tone.cream)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("You \(score(of: state.side)), opponent \(score(of: state.side.opponent))")
            }
            action
        }
    }

    @ViewBuilder
    private var action: some View {
        switch state.phase {
        case .calibrating:
            note("Calibrate below, then tap Ready.")
        case .lobby:
            StampedButton(title: "READY", prominent: true) { controller.link.setReady(true) }
        case .ready:
            VStack(spacing: 8) {
                note("Ready. The match starts when both players are.")
                StampedButton(title: "NOT READY", prominent: false) { controller.link.setReady(false) }
            }
        case .serving, .rally, .pointScored:
            StampedButton(title: "PAUSE", prominent: false) { controller.link.requestPause(true) }
        case .paused:
            if state.canResume {
                StampedButton(title: "CONTINUE", prominent: true) { controller.link.requestPause(false) }
            } else {
                note("Paused. Waiting for the other player or the Mac.")
            }
        case .gameOver:
            Text(state.winner == state.side ? "YOU WON" : "YOU LOST")
                .font(Paddle.Typeface.title)
                .tracking(2)
                .foregroundStyle(Paddle.Tone.gold)
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Paddle.Typeface.note)
            .foregroundStyle(Paddle.Tone.cream.opacity(0.8))
            .multilineTextAlignment(.center)
    }
}

private struct StampedButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Paddle.Typeface.title)
                .tracking(2)
                .foregroundStyle(prominent ? Paddle.Tone.ink : Paddle.Tone.cream)
                .frame(maxWidth: 220, minHeight: 48)
                .background(prominent ? Paddle.Tone.cream : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Paddle.Tone.cream, lineWidth: prominent ? 0 : 1.5))
        }
        .buttonStyle(.plain)
    }
}

private struct LinkHeader: View {
    let link: PaddleLink
    let launchedAt: Microseconds
    let networkFailure: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(Paddle.Typeface.small)
                .tracking(2)
                .foregroundStyle(Paddle.Tone.cream)
            if let detail {
                Text(detail)
                    .font(Paddle.Typeface.note)
                    .foregroundStyle(Paddle.Tone.cream.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
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

    private var detail: String? {
        if let networkFailure {
            return "Allow Local Network access for Flick Paddle in Settings › Privacy & Security › Local Network. (\(networkFailure))"
        }
        switch link.status {
        case .paired:
            return nil
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

private struct Groove: View {
    let reading: PointerReading?

    var body: some View {
        GeometryReader { geometry in
            let puck = geometry.size.width * 0.2
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.35))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                if case .position(let position) = reading {
                    Capsule()
                        .fill(Paddle.Tone.cream)
                        .frame(width: puck)
                        .padding(4)
                        .offset(x: position * (geometry.size.width - puck - 8))
                }
            }
        }
        .frame(height: Paddle.grooveHeight)
        .opacity(reading == .notUpright ? 0.4 : 1)
        .accessibilityLabel("Paddle position")
    }
}
