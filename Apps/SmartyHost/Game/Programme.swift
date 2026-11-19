import SwiftUI

enum Programme {
    static let paper = Color(red: 0.95, green: 0.91, blue: 0.83)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let navy = Color(red: 0.08, green: 0.13, blue: 0.23)
    static let card = Color(red: 0.05, green: 0.05, blue: 0.05)
    static let cornerRadius: CGFloat = 6

    static func title(_ size: CGFloat) -> Font {
        .custom("Futura-Bold", size: size)
    }

    static func body(_ size: CGFloat) -> Font {
        .custom("Futura-Medium", size: size)
    }

    static func figure(_ size: CGFloat) -> Font {
        .custom("Futura-CondensedExtraBold", size: size)
    }
}

private struct ProgrammeCard: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Programme.cornerRadius, style: .continuous)
        content
            .environment(\.colorScheme, .light)
            .foregroundStyle(Programme.ink)
            .tint(Programme.navy)
            .background(Programme.paper, in: shape)
            .overlay(shape.inset(by: 5).strokeBorder(Programme.ink.opacity(0.75), lineWidth: 1))
            .overlay(shape.strokeBorder(Programme.ink.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
    }
}

extension View {
    func programmeCard() -> some View {
        modifier(ProgrammeCard())
    }
}

struct FlipCard: View {
    let value: Int
    let size: CGFloat

    var body: some View {
        Text("\(value)")
            .font(Programme.figure(size))
            .monospacedDigit()
            .foregroundStyle(Programme.paper)
            .contentTransition(.numericText())
            .frame(minWidth: size * 0.9)
            .padding(.horizontal, size * 0.18)
            .padding(.vertical, size * 0.06)
            .background(Programme.card, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                Rectangle()
                    .fill(.black.opacity(0.7))
                    .frame(height: 1.5)
            }
    }
}
