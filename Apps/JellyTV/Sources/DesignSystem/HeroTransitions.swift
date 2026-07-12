import SwiftUI
import JellyTVKit

// The hero backdrop swaps as a *reveal*: the incoming slide is drawn as a solid
// opaque base and the outgoing slide crumbles (or fades) away on top of it,
// driven by `progress` (1 = intact → 0 = gone). Because the new image is always
// present underneath, no black ever shows between shattering cells.

/// Applies the outgoing slide's departure — the `hexCrumble` shader for the
/// crumble style, plain opacity for fade. `Animatable` so `progress` tweens
/// frame-by-frame under `withAnimation`.
struct HeroDepartureModifier: ViewModifier, Animatable {
    var style: HeroTransitionStyle
    var progress: Double          // 1 = intact, 0 = fully gone
    var canvasSize: CGSize
    var accent: Color

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        switch style {
        case .crumble:
            content.layerEffect(
                ShaderLibrary.hexCrumble(
                    .float(Float(progress)),
                    .float2(canvasSize),
                    .color(accent)
                ),
                // Cover the shader's max tile flight (~460pt drift + gravity
                // sag, inflated by the shrink-factor resampling) or tiles clip.
                maxSampleOffset: CGSize(width: 600, height: 560)
            )
        case .fade:
            content.opacity(progress)
        }
    }
}

extension HeroTransitionStyle {
    /// How long the outgoing slide takes to depart. The crumble owns all its
    /// per-tile easing internally, so the driver animates `progress` linearly;
    /// fade wants a standard ease.
    var duration: Double {
        switch self {
        case .crumble: return 1.25
        case .fade: return 0.7
        }
    }

    /// Master curve for driving `progress` 1 → 0.
    var animation: Animation {
        switch self {
        case .crumble: return .linear(duration: duration)
        case .fade: return .easeInOut(duration: duration)
        }
    }
}
