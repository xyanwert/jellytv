import SwiftUI
import JellyTVKit

// Bridges the `hexCrumble` Metal shader into SwiftUI's insertion/removal
// transition system. When the hero's backdrop `.id` changes inside a
// `withAnimation`, SwiftUI drives `progress` through the Animatable modifier
// below, which feeds it to the shader via `.layerEffect`.

extension AnyTransition {
    /// Honeycomb shatter. The outgoing image breaks apart along a diagonal
    /// wave — cracks flash in the accent color, tiles pop, tumble and sag
    /// under gravity — while the incoming image's tiles fly in just behind
    /// the wave and settle with a small ease-out-back overshoot.
    static func hexCrumble(canvasSize: CGSize, accent: Color) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: HexCrumbleModifier(progress: 0, assemble: true, canvasSize: canvasSize, accent: accent),
                identity: HexCrumbleModifier(progress: 1, assemble: true, canvasSize: canvasSize, accent: accent)
            ),
            removal: .modifier(
                active: HexCrumbleModifier(progress: 0, assemble: false, canvasSize: canvasSize, accent: accent),
                identity: HexCrumbleModifier(progress: 1, assemble: false, canvasSize: canvasSize, accent: accent)
            )
        )
    }
}

private struct HexCrumbleModifier: ViewModifier, Animatable {
    var progress: Double        // 1 = seated/intact, 0 = fully scattered
    var assemble: Bool
    var canvasSize: CGSize
    var accent: Color

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.hexCrumble(
                .float(Float(progress)),
                .float(assemble ? 1.0 : 0.0),
                .float2(canvasSize),
                .color(accent)
            ),
            // Must cover the shader's max tile flight (~440pt drift + gravity
            // sag, inflated by the shrink-factor resampling) or tiles clip.
            maxSampleOffset: CGSize(width: 540, height: 440)
        )
    }
}

extension HeroTransitionStyle {
    /// The SwiftUI transition backing this style.
    func anyTransition(canvasSize: CGSize, accent: Color) -> AnyTransition {
        switch self {
        case .crumble: return .hexCrumble(canvasSize: canvasSize, accent: accent)
        case .fade: return .opacity
        }
    }

    /// Master clock for the backdrop swap. The crumble choreographs its own
    /// per-tile easing inside the shader, so it wants a linear master clock;
    /// fade keeps a standard ease.
    var animation: Animation {
        switch self {
        case .crumble: return .linear(duration: 1.25)
        case .fade: return .easeInOut(duration: 0.8)
        }
    }
}
