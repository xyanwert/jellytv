import SwiftUI
import JellyTVKit

/// Shared tvOS focus treatment: a punchy scale-up, a bright accent-colored glow
/// ring, and a springy pop — deliberately loud so focus reads at a glance from
/// across a room, not a subtle nudge you have to look for.
struct FocusScaleStyle: ButtonStyle {
    var scale: CGFloat = 1.06
    var cornerRadius: CGFloat = 14
    var outline: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, scale: scale, cornerRadius: cornerRadius, outline: outline)
    }

    private struct Content: View {
        @Environment(\.isFocused) private var focused: Bool
        @EnvironmentObject private var theme: Theme
        let configuration: FocusScaleStyle.Configuration
        let scale: CGFloat
        let cornerRadius: CGFloat
        let outline: Bool

        var body: some View {
            configuration.label
                .scaleEffect((focused ? scale : 1) * (configuration.isPressed ? 0.95 : 1))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.accent, lineWidth: 3)
                        .opacity(outline && focused ? 1 : 0)
                )
                // Bright accent glow (when `outline`) layered on a white halo that
                // always shows on focus, so even non-outlined controls still pop.
                .shadow(color: theme.accent.opacity(outline && focused ? 0.9 : 0), radius: focused ? 28 : 0)
                .shadow(color: .white.opacity(focused ? 0.35 : 0), radius: focused ? 14 : 0)
                .shadow(color: .black.opacity(focused ? 0.55 : 0.3),
                        radius: focused ? 26 : 10, y: focused ? 14 : 6)
                .animation(.spring(response: 0.26, dampingFraction: 0.6), value: focused)
        }
    }
}

/// Focus highlight for full-width list rows (Settings categories, Sign Out):
/// an accent-tinted background lift plus a left accent bar, layered on top of
/// any persistent "this is the selected one" state (`isActive`) a caller wants.
struct RowFocusStyle: ButtonStyle {
    var isActive: Bool = false
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, isActive: isActive, cornerRadius: cornerRadius)
    }

    private struct Content: View {
        @Environment(\.isFocused) private var focused: Bool
        @EnvironmentObject private var theme: Theme
        let configuration: ButtonStyle.Configuration
        let isActive: Bool
        let cornerRadius: CGFloat

        var body: some View {
            configuration.label
                .scaleEffect(focused ? 1.03 : 1, anchor: .leading)
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
        }
    }
}

/// Focus treatment for media cards: no white ring — the focused card grows and
/// gains a little saturation/contrast plus a glow in its own color, while
/// unfocused cards sit slightly dimmer, so the focused one clearly reads as active.
struct CardFocusStyle: ButtonStyle {
    var glow: Color
    var scale: CGFloat = 1.12

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, glow: glow, scale: scale)
    }

    private struct Content: View {
        @Environment(\.isFocused) private var focused: Bool
        let configuration: CardFocusStyle.Configuration
        let glow: Color
        let scale: CGFloat

        var body: some View {
            configuration.label
                .saturation(focused ? 1.28 : 0.7)
                .brightness(focused ? 0.05 : -0.13)
                .contrast(focused ? 1.12 : 0.95)
                .scaleEffect((focused ? scale : 0.96) * (configuration.isPressed ? 0.97 : 1))
                .shadow(color: glow.opacity(focused ? 0.8 : 0), radius: focused ? 32 : 0, y: 10)
                .shadow(color: .black.opacity(focused ? 0.6 : 0.25), radius: focused ? 36 : 10, y: focused ? 22 : 6)
                .animation(.easeOut(duration: 0.2), value: focused)
        }
    }
}

/// Left-aligned row/section title.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Typography.section)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 56)
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
