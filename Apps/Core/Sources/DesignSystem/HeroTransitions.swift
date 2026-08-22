import SwiftUI
import JellyTVKit

// The hero backdrop swaps as a *reveal*: the incoming slide is drawn as a solid
// opaque base and the outgoing slide crumbles (or fades) away on top of it,
// driven by `progress` (1 = intact → 0 = gone). Because the new image is always
// present underneath, no black ever shows between shattering cells.

/// Applies the outgoing slide's departure — the `hexCrumble` shader for the
/// crumble style, plain opacity for fade. `Animatable` so `progress` tweens
/// frame-by-frame under `withAnimation`.
///
/// STEP 7 (continued) — this is where HomeView's `withAnimation(style.animation)
/// { departProgress = 0 }` actually lands. Because this modifier conforms to
/// `Animatable`, SwiftUI does NOT re-invoke `HomeView.body`/`imageStack` on
/// every frame of that animation — it interpolates `progress` on its own and
/// calls this `body(content:)` directly with each intermediate value. That's
/// what makes the crumble smooth without re-running the whole view tree 60
/// times a second — but it's also exactly the mechanism that caused the
/// earlier "flash" bug: anything read from a plain `let`/computed property
/// elsewhere in `imageStack` (rather than a real `@State`) would be frozen at
/// whatever it was on the LAST full body run, not updated per-frame like
/// `progress` is here.
struct HeroDepartureModifier: ViewModifier, Animatable {
    var style: HeroTransitionStyle
    var progress: Double          // 1 = intact, 0 = fully gone
    var canvasSize: CGSize
    var accent: Color
    var time: Double              // absolute time for ember animation

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        switch style {
        case .crumble:
            // Every frame: re-run the hex-shatter shader against the CURRENT
            // interpolated `progress`. At progress ≈ 1 (the very start) the
            // shader is expected to hand back the image completely untouched
            // — full opacity, no cracks — which is what keeps the outgoing
            // slide fully covering the base the instant the reveal begins.
            content.layerEffect(
                ShaderLibrary.hexCrumble(
                    .float(Float(progress)),
                    .float2(canvasSize),
                    .color(accent),
                    .float(Float(time))
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

/// Applies heat haze distortion to the incoming slide during the crumble
/// transition. The haze peaks mid-transition and fades at start/end.
struct HeroHeatHazeModifier: ViewModifier {
    var progress: Double
    var canvasSize: CGSize
    var time: Double

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.heatHaze(
                .float(Float(progress)),
                .float2(canvasSize),
                .float(Float(time))
            ),
            maxSampleOffset: CGSize(width: 20, height: 20)
        )
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
