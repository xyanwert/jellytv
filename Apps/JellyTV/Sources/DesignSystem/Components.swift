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
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: -4)
                        .stroke(Color.white.opacity(outline && focused ? 0.9 : 0), lineWidth: 3)
                )
                .shadow(color: .black.opacity(focused ? 0.6 : 0.35),
                        radius: focused ? 30 : 14, y: focused ? 18 : 8)
                .animation(.easeOut(duration: 0.18), value: focused)
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

/// A library chip; adult libraries get the accent-tinted treatment + 18+ badge.
struct LibraryChip: View {
    let library: Library
    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button {} label: {
            HStack(spacing: 10) {
                Text(library.name)
                    .font(Typography.font(19, .semibold))
                    .foregroundStyle(library.isAdult ? Color(hex: "#FFD9DC") : Palette.text(0.75))
                if library.isAdult {
                    Text("18+")
                        .font(Typography.font(13, .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(library.isAdult ? theme.accent.opacity(0.12) : Palette.text(0.06), in: Capsule())
            .overlay(Capsule().stroke(library.isAdult ? theme.accent.opacity(0.4) : Palette.text(0.1), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 999))
    }
}

/// The centered top-bar navigation pill.
struct NavPill: View {
    let tabs: [String]
    @Binding var active: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, label in
                Button { active = index } label: {
                    Text(label)
                        .font(Typography.font(22, .semibold))
                        .foregroundStyle(index == active ? Palette.screen : Palette.text(0.65))
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(index == active ? Color.white : Color.clear, in: Capsule())
                }
                .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 999))
            }
        }
        .padding(8)
        .background(Palette.text(0.06), in: Capsule())
        .overlay(Capsule().stroke(Palette.text(0.08), lineWidth: 1))
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
