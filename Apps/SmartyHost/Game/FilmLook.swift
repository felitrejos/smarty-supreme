import SwiftUI

struct FilmLook: View {
    private static let frameRate = 24.0
    private static let grainOpacity = 0.04
    private static let grainTile: CGFloat = 256
    private static let vignette = 0.62
    private static let warmth = Color(red: 1, green: 0.86, blue: 0.68)

    @State private var grain: CGImage?

    var body: some View {
        ZStack {
            Self.warmth
                .blendMode(.multiply)
                .opacity(0.35)
            RadialGradient(colors: [.clear, .black.opacity(Self.vignette)], center: .center, startRadius: 180, endRadius: 820)
            if let grain {
                TimelineView(.periodic(from: .now, by: 1 / Self.frameRate)) { context in
                    let tick = context.date.timeIntervalSinceReferenceDate * Self.frameRate
                    let offset = CGSize(width: (tick * 97).truncatingRemainder(dividingBy: Self.grainTile), height: (tick * 61).truncatingRemainder(dividingBy: Self.grainTile))
                    Image(decorative: grain, scale: 1)
                        .resizable(resizingMode: .tile)
                        .offset(offset)
                        .padding(-Self.grainTile)
                        .blendMode(.overlay)
                        .opacity(Self.grainOpacity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            grain = await Textures.filmGrain(seed: 11)
        }
    }
}
