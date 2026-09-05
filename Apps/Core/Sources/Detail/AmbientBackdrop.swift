import SwiftUI
import JellyTVKit

#if os(tvOS)
/// The film's wide art, alive behind the one-sheet: a slow 24-second drift
/// (a 10% zoom and a few points of travel, back and forth) and, when TMDB has
/// given us more than the one backdrop Jellyfin keeps, a crossfade to the
/// next every twelve seconds. Held well back — a third of full strength, and
/// darkened where the text column and the cast band sit — so it is
/// atmosphere under the bloom, not a second picture competing with the poster.
///
/// **Compositor work only.** The drift is a `scaleEffect`/`offset` animation
/// and the crossfade is opacity; nothing here is a shader. The crumble on
/// Home had just been cut to a tenth of its GPU cost, and this page would be
/// the wrong place to spend it again.
struct AmbientBackdrop: View {
    let urls: [String]
    let fallback: LinearGradient

    @State private var index = 0
    @State private var drift = false

    private static let slideSeconds: Double = 12
    private static let maxSlides = 6

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(slides.enumerated()), id: \.offset) { position, url in
                    CachedHeroImage(urlString: url, fallback: fallback)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(position == index ? 1 : 0)
                }
            }
            .animation(.easeInOut(duration: 2.4), value: index)
            .scaleEffect(drift ? 1.10 : 1.0)
            .offset(x: drift ? -geo.size.width * 0.018 : geo.size.width * 0.018, y: drift ? -10 : 10)
            .animation(.easeInOut(duration: 24).repeatForever(autoreverses: true), value: drift)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(scrims)
            .opacity(0.34)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { drift = true }
        .task(id: slides.count) {
            guard slides.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.slideSeconds))
                guard !Task.isCancelled else { return }
                index = (index + 1) % slides.count
            }
        }
    }

    private var slides: [String] { Array(urls.prefix(Self.maxSlides)) }

    /// Darker where the reading happens: the text column on the left third
    /// and the cast band along the foot.
    private var scrims: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.75), location: 0.0),
                    .init(color: .black.opacity(0.35), location: 0.45),
                    .init(color: .clear, location: 0.85),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.55),
                    .init(color: .black.opacity(0.7), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}
#endif
