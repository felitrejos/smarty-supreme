import SwiftUI

struct HowToPlayCard: View {
    private static let stepDuration = 4.5

    var close: (() -> Void)?

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let index = Int(time / Self.stepDuration) % Lesson.allCases.count
            let lesson = Lesson.allCases[index]
            let progress = time.truncatingRemainder(dividingBy: Self.stepDuration) / Self.stepDuration
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("How to Play")
                        .font(Programme.title(22))
                    Spacer()
                    Text("\(index + 1) of \(Lesson.allCases.count)")
                        .font(Programme.body(13))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let close {
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close How to Play")
                    }
                }
                LessonPicture(lesson: lesson, progress: progress)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title)
                        .font(Programme.title(15))
                    Text(lesson.detail)
                        .font(Programme.body(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            }
            .padding(24)
            .frame(width: 340)
            .programmeCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("How to play, step \(index + 1): \(lesson.title). \(lesson.detail)")
        }
    }
}

private enum Lesson: CaseIterable {
    case stand
    case calibrate
    case strokes
    case serve
    case timing

    var title: String {
        switch self {
        case .stand: "Face the Mac"
        case .calibrate: "Hold it like a bat"
        case .strokes: "Forehand or backhand"
        case .serve: "Toss, then serve"
        case .timing: "Swing as the ring closes"
        }
    }

    var detail: String {
        switch self {
        case .stand: "Stand where you can swing freely, about 1.5 to 2.5 m back. Distance doesn’t matter to the game, but facing the Mac does."
        case .calibrate: "Screen toward you, top up, facing the Mac. Tap Calibrate and hold still. Double-tap the phone to do it again."
        case .strokes: "Show the screen to yourself for a forehand. Turn it so the screen faces the table for a backhand."
        case .serve: "Tap the phone’s screen to toss the ball, then swing as it falls. Forehand and backhand curve it opposite ways; chop down for backspin."
        case .timing: "The ring shrinks onto the ball. Swing as it closes: early pulls the ball cross-court, late sends it down the line."
        }
    }
}

private struct LessonPicture: View {
    let lesson: Lesson
    let progress: Double

    var body: some View {
        switch lesson {
        case .stand: stand
        case .calibrate: calibrate
        case .strokes: strokes
        case .serve: serve
        case .timing: timing
        }
    }

    private var stand: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.table.tennis")
                .font(.system(size: 64, weight: .regular))
                .scaleEffect(x: -1)
                .offset(x: 3 * sin(progress * 4 * .pi))
            VStack(spacing: 6) {
                Text("1.5–2.5 m")
                    .font(Programme.body(12))
                    .monospacedDigit()
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(height: 1)
            }
            .frame(width: 90)
            Image(systemName: "display")
                .font(.system(size: 56, weight: .regular))
        }
        .foregroundStyle(Programme.ink)
    }

    private var calibrate: some View {
        let pulse = 1 + 0.06 * sin(progress * 6 * .pi)
        return VStack(spacing: 14) {
            Phone(showsBack: false)
            Text("CALIBRATE")
                .font(Programme.title(11))
                .foregroundStyle(Programme.paper)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Programme.navy, in: Capsule())
                .scaleEffect(pulse)
        }
    }

    private var strokes: some View {
        let turn = smoothstep((progress - 0.4) / 0.2)
        let angle = turn * 180
        let isBackhand = angle > 90
        return VStack(spacing: 12) {
            TableEdge()
            Phone(showsBack: isBackhand)
                .rotation3DEffect(.degrees(isBackhand ? angle - 180 : angle), axis: (0, 1, 0), perspective: 0.5)
            Text(isBackhand ? "BACKHAND" : "FOREHAND")
                .font(Programme.title(12))
                .foregroundStyle(Programme.navy)
        }
    }

    private var serve: some View {
        let tap = progress < 0.2 ? smoothstep(progress / 0.2) : 0
        let swing = smoothstep((progress - 0.62) / 0.1)
        let ballHeight = tossHeight(at: progress)
        let away = smoothstep((progress - 0.7) / 0.15)
        return ZStack(alignment: .bottom) {
            Ball()
                .offset(x: 40, y: -40 - ballHeight - 120 * away)
                .scaleEffect(1 - 0.5 * away)
                .opacity(1 - away)
            Phone(showsBack: false)
                .overlay {
                    Circle()
                        .stroke(Programme.paper, lineWidth: 2)
                        .frame(width: 10 + 30 * tap, height: 10 + 30 * tap)
                        .opacity(progress < 0.2 ? 1 - tap : 0)
                }
                .rotation3DEffect(.degrees(-55 * swing), axis: (1, 0, 0), perspective: 0.4)
                .offset(y: 18 * swing)
        }
        .frame(height: 180, alignment: .bottom)
    }

    private var timing: some View {
        let close = min(progress / 0.6, 1)
        let swing = smoothstep((progress - 0.55) / 0.1)
        return HStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Programme.navy.opacity(0.7), lineWidth: 2)
                    .frame(width: 22 + 88 * (1 - close), height: 22 + 88 * (1 - close))
                    .opacity(progress < 0.7 ? 1 : 0)
                Ball()
            }
            .frame(width: 120, height: 120)
            Phone(showsBack: false)
                .rotation3DEffect(.degrees(-40 * swing), axis: (0, 1, 0), perspective: 0.5)
        }
        .overlay(alignment: .bottom) {
            Text("CLEAN")
                .font(Programme.title(12))
                .foregroundStyle(Programme.navy)
                .opacity(progress > 0.62 && progress < 0.95 ? 1 : 0)
        }
    }

    private func tossHeight(at progress: Double) -> Double {
        let start = 0.2
        let end = 0.7
        guard progress > start else { return 0 }
        let t = min((progress - start) / (end - start), 1)
        return 64 * 4 * t * (1 - t)
    }

    private func smoothstep(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

private struct Phone: View {
    let showsBack: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape
                .fill(showsBack ? Programme.paper : Programme.ink)
            shape
                .strokeBorder(Programme.ink, lineWidth: 2)
            if showsBack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Programme.ink, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                    .padding(7)
            } else {
                Capsule()
                    .fill(Programme.paper.opacity(0.85))
                    .frame(width: 16, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
            }
        }
        .frame(width: 56, height: 112)
        .accessibilityHidden(true)
    }
}

private struct Ball: View {
    var body: some View {
        Circle()
            .fill(Programme.paper)
            .overlay(Circle().strokeBorder(Programme.ink, lineWidth: 1.5))
            .frame(width: 16, height: 16)
    }
}

private struct TableEdge: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("TABLE")
                .font(Programme.title(10))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Programme.navy)
                .frame(width: 150, height: 6)
        }
    }
}
