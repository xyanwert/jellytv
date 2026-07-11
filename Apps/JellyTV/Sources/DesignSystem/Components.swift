import SwiftUI
import JellyTVKit

/// Shared tvOS focus treatment: scale up, white outline, and elevated shadow
/// when focused — matching the design's focused-state cards/buttons.
struct FocusScaleStyle: ButtonStyle {
    var scale: CGFloat = 1.06
    var cornerRadius: CGFloat = 14
    var outline: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, scale: scale, cornerRadius: cornerRadius, outline: outline)
    }

    private struct Content: View {
        @Environment(\.isFocused) private var focused: Bool
        let configuration: FocusScaleStyle.Configuration
        let scale: CGFloat
        let cornerRadius: CGFloat
        let outline: Bool

        var body: some View {
            configuration.label
                .scaleEffect((focused ? scale : 1) * (configuration.isPressed ? 0.97 : 1))
                // Soft white halo instead of a hard ring (the design's
                // "0 0 0 6px rgba(255,255,255,0.18)") — reads cleanly even on
                // the white Resume button — plus a dark lift shadow.
                .shadow(color: .white.opacity(outline && focused ? 0.28 : 0), radius: focused ? 12 : 0)
                .shadow(color: .black.opacity(focused ? 0.5 : 0.3),
                        radius: focused ? 22 : 10, y: focused ? 12 : 6)
                .animation(.easeOut(duration: 0.18), value: focused)
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
            .padding(.horizontal, 80)
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
