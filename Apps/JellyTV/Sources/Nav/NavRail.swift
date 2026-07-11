import SwiftUI
import JellyTVKit

/// A single rail-selectable target. Distinct from `NavDestination`: `.libraries`
/// isn't a destination (it's a submenu-open flag RootView tracks separately),
/// but it still needs its own active/inactive icon styling in the rail.
enum RailTarget: Hashable {
    case home, search, movies, tv, libraries, settings
}

/// The persistent 118pt-wide left navigation rail, present on Home and Settings:
/// an app-mark tile with the server-status dot, five nav icons, and a pinned
/// settings icon at the bottom.
struct NavRail: View {
    let destination: NavDestination
    let isLibrariesOpen: Bool
    let isServerConnected: Bool
    let onSelect: (RailTarget) -> Void

    @EnvironmentObject private var theme: Theme

    private var activeTarget: RailTarget {
        if isLibrariesOpen { return .libraries }
        switch destination {
        case .home: return .home
        case .settings: return .settings
        case .search: return .search
        case .movies: return .movies
        case .tv: return .tv
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            appMark
            Spacer(minLength: 36)
            VStack(spacing: 14) {
                railButton(.home) { NavIcons.home(color: $0) }
                railButton(.search) { NavIcons.search(color: $0) }
                railButton(.movies) { NavIcons.movies(color: $0) }
                railButton(.tv) { NavIcons.tv(color: $0) }
                railButton(.libraries) { NavIcons.libraries(color: $0) }
            }
            Spacer(minLength: 36)
            railButton(.settings) { NavIcons.cog(color: $0) }
        }
        .padding(.vertical, 34)
        .frame(width: 118)
        .frame(maxHeight: .infinity)
        .background(railBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.text(0.08)).frame(width: 1)
        }
    }

    private var railBackground: Color {
        Color(hex: "#06080E").opacity(isLibrariesOpen ? 0.85 : 0.5)
    }

    private var appMark: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "drop.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(width: 66, height: 66)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 6)
            StatusDot(isConnected: isServerConnected)
                .offset(x: 6, y: 6)
        }
    }

    @ViewBuilder
    private func railButton<Icon: View>(_ target: RailTarget, @ViewBuilder icon: @escaping (Color) -> Icon) -> some View {
        let active = activeTarget == target
        Button { onSelect(target) } label: {
            icon(active ? .white : Palette.text(0.5))
        }
        .buttonStyle(RailIconButtonStyle(isActive: active, accent: theme.accent))
        .frame(width: 118)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(theme.accent)
                .frame(width: 4, height: 30)
                .opacity(active ? 1 : 0)
                .padding(.leading, 12)
        }
    }
}

/// Rail icon button chrome: a persistent active/inactive tint (accent vs.
/// dimmed) plus the app's usual transient focus scale/shadow on top.
private struct RailIconButtonStyle: ButtonStyle {
    let isActive: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, isActive: isActive, accent: accent)
    }

    private struct Content: View {
        @Environment(\.isFocused) private var focused: Bool
        let configuration: ButtonStyle.Configuration
        let isActive: Bool
        let accent: Color

        var body: some View {
            configuration.label
                .frame(width: 60, height: 60)
                .background(
                    isActive ? accent.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(isActive ? accent.opacity(0.35) : Palette.text(0.08), lineWidth: 1)
                )
                .scaleEffect((focused ? 1.08 : 1.0) * (configuration.isPressed ? 0.96 : 1))
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: focused ? 16 : 0, y: focused ? 8 : 0)
                .animation(.easeOut(duration: 0.18), value: focused)
                .animation(.easeOut(duration: 0.18), value: isActive)
        }
    }
}
