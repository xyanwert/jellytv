import SwiftUI
import JellyTVKit

/// A focus ring styled as a diffused LED tube: layered, increasingly-blurred
/// accent strokes build the outward bloom, and a near-white hot core sits on
/// top — like a neon strip, not a hard outline. The wide accent shadow on the
/// styles below completes it as light cast on the surrounding "wall".
struct LEDRing: View {
    var cornerRadius: CGFloat
    var accent: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.stroke(accent.opacity(0.8), lineWidth: 11).blur(radius: 16)
            shape.stroke(accent, lineWidth: 5.5).blur(radius: 5)
            shape.stroke(accent.opacity(0.9), lineWidth: 3.5).blur(radius: 1.6)
            shape.stroke(.white.opacity(0.92), lineWidth: 1.7).blur(radius: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// The resting-state cousin of `LEDRing`: the same stacked-stroke recipe —
/// widest and blurriest outside, a hot near-white core inside — dialled down
/// from the focus ring's shout to something a control can wear all the time,
/// plus one wide stroke clipped inside the shape so it reads as lit from
/// within rather than merely outlined.
///
/// Works on any insettable shape, so a capsule bar and a play disc can carry
/// the same light. `intensity` scales the whole effect: a small disc needs
/// noticeably less than a full-width bar or it blooms into a smudge.
struct NeonTube<S: InsettableShape>: View {
    var shape: S
    var accent: Color
    var intensity: Double = 1

    var body: some View {
        ZStack {
            shape.stroke(accent.opacity(0.40 * intensity), lineWidth: 9).blur(radius: 13)
            shape.stroke(accent.opacity(0.70 * intensity), lineWidth: 3.2).blur(radius: 4)
            shape.stroke(accent.opacity(0.95), lineWidth: 1.4)
            shape.stroke(.white.opacity(0.50 * intensity), lineWidth: 0.7)
            shape.stroke(accent.opacity(0.34 * intensity), lineWidth: 14)
                .blur(radius: 10)
                .clipShape(shape)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Lights text the way `NeonTube` lights an edge — two shadows, tight and
    /// wide, in the tube's own colour.
    func neonGlow(_ accent: Color, intensity: Double = 1) -> some View {
        shadow(color: accent.opacity(0.85 * intensity), radius: 7)
            .shadow(color: accent.opacity(0.45 * intensity), radius: 18)
    }
}

/// Shared tvOS focus treatment: a punchy scale-up, a diffused-LED ring, and a
/// springy pop — deliberately loud so focus reads at a glance from across a
/// room, not a subtle nudge you have to look for.
struct FocusScaleStyle: ButtonStyle {
    var scale: CGFloat = 1.06
    var cornerRadius: CGFloat = 14
    var outline: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, scale: scale, cornerRadius: cornerRadius, outline: outline)
    }

    private struct Content: View {
        #if os(tvOS)
        @Environment(\.isFocused) private var focused: Bool
        #endif
        @EnvironmentObject private var theme: Theme
        let configuration: FocusScaleStyle.Configuration
        let scale: CGFloat
        let cornerRadius: CGFloat
        let outline: Bool

        var body: some View {
            #if os(tvOS)
            configuration.label
                .scaleEffect((focused ? scale : 1) * (configuration.isPressed ? 0.95 : 1))
                .overlay {
                    if outline && focused {
                        // Outset a touch so the tube wraps the control with a
                        // small air gap (radius grows with the outset to stay
                        // concentric).
                        LEDRing(cornerRadius: cornerRadius + 4, accent: theme.accent)
                            .padding(-4)
                            .transition(.opacity)
                    }
                }
                // Soft room-glow: the lamp's light falling on the UI around it.
                .shadow(color: theme.accent.opacity(outline && focused ? 0.7 : 0), radius: focused ? 38 : 0)
                .shadow(color: .white.opacity(!outline && focused ? 0.35 : 0), radius: focused ? 14 : 0)
                .shadow(color: .black.opacity(focused ? 0.55 : 0.3),
                        radius: focused ? 26 : 10, y: focused ? 14 : 6)
                .animation(.spring(response: 0.26, dampingFraction: 0.6), value: focused)
            #else
            // Touch has no resting "focused" state to loudly announce — just
            // a light press-down dip, full-strength otherwise.
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            #endif
        }
    }
}

/// Focus highlight for full-width list rows (Settings categories, Sign Out):
/// an accent-tinted background lift plus a left accent bar, layered on top of
/// any persistent "this is the selected one" state (`isActive`) a caller wants.
struct RowFocusStyle: ButtonStyle {
    var isActive: Bool = false
    var cornerRadius: CGFloat = 14
    /// tvOS focus scale, anchored leading so a row grows to the right. Pass
    /// `1` for a row that sits inside a card its *parent* draws: the tint
    /// below and the parent's background/stroke don't scale with the label,
    /// so at 1.03 a 1200pt row's trailing chip and chevron land ~36pt outside
    /// the card (Settings → Libraries). The tint, bar and glow carry focus on
    /// their own there — the scale only ever showed up as the misalignment.
    var scale: CGFloat = 1.03

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, isActive: isActive,
                cornerRadius: cornerRadius, scale: scale)
    }

    private struct Content: View {
        #if os(tvOS)
        @Environment(\.isFocused) private var focused: Bool
        #endif
        @EnvironmentObject private var theme: Theme
        let configuration: ButtonStyle.Configuration
        let isActive: Bool
        let cornerRadius: CGFloat
        let scale: CGFloat

        var body: some View {
            #if os(tvOS)
            configuration.label
                .scaleEffect(focused ? scale : 1, anchor: .leading)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(focused ? theme.accent.opacity(0.22) : (isActive ? Palette.text(0.06) : .clear))
                )
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 4, height: 28)
                        .opacity(focused || isActive ? 1 : 0)
                        .padding(.leading, 4)
                }
                .shadow(color: theme.accent.opacity(focused ? 0.55 : 0), radius: focused ? 24 : 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: focused)
            #else
            // No focus concept on touch — `isActive` alone carries the
            // persistent "this is the selected row" look; a tap just dips.
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1, anchor: .leading)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isActive ? theme.accent.opacity(0.22) : (configuration.isPressed ? Palette.text(0.06) : .clear))
                )
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 4, height: 28)
                        .opacity(isActive ? 1 : 0)
                        .padding(.leading, 4)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            #endif
        }
    }
}

/// Focus treatment for media cards: no white ring — the focused card grows and
/// gains a glow in its own color, while unfocused cards sit slightly dimmer,
/// so the focused one clearly reads as active.
///
/// Deliberately avoids `.saturation`/`.brightness`/`.contrast`: those are
/// Core Image filter passes, not simple layer properties, so — unlike
/// `.shadow`/`.blur` with a radius of 0 — SwiftUI can't optimize them away at
/// an "identity" value; every visible card paints through the CIFilter
/// pipeline every frame, focused or not. A ScrollView full of cards (Home
/// rows, library grids) was running that continuously just to scroll, which
/// reads as fine on a simulator/current-gen Apple TV's GPU but visibly lags
/// focus movement on older hardware (e.g. Apple TV HD / 1st-gen 4K). `.opacity`
/// is a plain alpha blend — cheap — and, like the shadows below, is zeroed at
/// rest so only the one actually-focused card pays for the glow/lift at all.
struct CardFocusStyle: ButtonStyle {
    var glow: Color
    var scale: CGFloat = 1.12

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, glow: glow, scale: scale)
    }

    private struct Content: View {
        #if os(tvOS)
        @Environment(\.isFocused) private var focused: Bool
        #endif
        let configuration: CardFocusStyle.Configuration
        let glow: Color
        let scale: CGFloat

        var body: some View {
            #if os(tvOS)
            configuration.label
                .opacity(focused ? 1 : 0.82)
                .scaleEffect((focused ? scale : 0.96) * (configuration.isPressed ? 0.97 : 1))
                .shadow(color: glow.opacity(focused ? 0.8 : 0), radius: focused ? 32 : 0, y: 10)
                .shadow(color: .black.opacity(focused ? 0.6 : 0), radius: focused ? 36 : 0, y: focused ? 22 : 0)
                .animation(.easeOut(duration: 0.2), value: focused)
            #else
            // No resting "focused" state on touch — cards sit at full
            // strength always, with just a press-down dip for tap feedback.
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            #endif
        }
    }
}

/// Left-aligned row/section title.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(DeviceClass.current == .phone ? Typography.font(19, .heavy) : Typography.section)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, DeviceClass.current == .phone ? 20 : 56)
    }
}

/// Gradient circular avatar with the user's initial.
struct Avatar: View {
    let initial: String
    var size: CGFloat = 48

    var body: some View {
        Text(initial)
            .font(Typography.font(size * 0.42, .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [Color(OKLCH(l: 0.65, c: 0.16, h: 20)), Color(OKLCH(l: 0.5, c: 0.14, h: 320))],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: Circle()
            )
    }
}

/// Rounded icon tile used by settings rows.
struct IconTile: View {
    let systemName: String
    var color: Color = Palette.text(0.85)
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Palette.text(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
