import SwiftUI
import JellyTVKit

// Bridges the `hexCrumble` Metal shader into SwiftUI's insertion/removal
// transition system. When the hero's backdrop `.id` changes inside a
// `withAnimation`, SwiftUI drives `progress` 0→1 through the Animatable
// modifier below, which feeds it to the shader via `.layerEffect`.

extension AnyTransition {
    /// Per-tile crumble transition. Asymmetric so the outgoing image
    /// disassembles while the incoming one assembles (complementary tile
    /// schedules via `invertDelay`), keeping both co-present.
    static func hexCrumble(canvasWidth: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: HexCrumbleModifier(progress: 0, invertDelay: false, canvasWidth: canvasWidth),
                identity: HexCrumbleModifier(progress: 1, invertDelay: false, canvasWidth: canvasWidth)
            ),
            removal: .modifier(
                active: HexCrumbleModifier(progress: 0, invertDelay: true, canvasWidth: canvasWidth),
                identity: HexCrumbleModifier(progress: 1, invertDelay: true, canvasWidth: canvasWidth)
            )
        )
    }
}

private struct HexCrumbleModifier: ViewModifier, Animatable {
    var progress: Double
    var invertDelay: Bool
    var canvasWidth: CGFloat

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.hexCrumble(
                .float(Float(progress)),
                .float(invertDelay ? 1.0 : 0.0),
                .float(Float(canvasWidth))
            ),
            // Must cover the shader's max tile drift (~320px) or tiles clip.
            // Kept tight so SwiftUI's shader backing texture stays small.
            maxSampleOffset: CGSize(width: 440, height: 160)
        )
    }
}

extension HeroTransitionStyle {
    /// The SwiftUI transition backing this style.
    func anyTransition(canvasWidth: CGFloat) -> AnyTransition {
        switch self {
        case .crumble: return .hexCrumble(canvasWidth: canvasWidth)
        case .fade: return .opacity
        }
    }
}
