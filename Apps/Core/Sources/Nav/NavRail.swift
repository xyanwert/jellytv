import SwiftUI
import JellyTVKit

/// A single rail-selectable target. Distinct from `NavDestination`: `.libraries`
/// isn't a destination (it's a submenu-open flag RootView tracks separately),
/// but it still needs its own active/inactive icon styling in the rail.
/// `.animeLibrary`/`.lateNight` are unreachable as direct rail icons on tvOS
/// (there, they're rows inside the `.libraries` submenu — see `activeTarget`
/// below) but ARE direct icons in iOS's rail body, which has no submenu.
enum RailTarget: Hashable {
    case home, search, movies, tv, libraries, settings
    case animeLibrary, lateNight
}

/// The persistent 118pt-wide left navigation rail, present on Home and Settings:
/// five nav icons and a pinned settings icon at the bottom.
struct NavRail: View {
    let destination: NavDestination
    let isLibrariesOpen: Bool
    let onSelect: (RailTarget) -> Void
    /// Overrides the rail's active-icon tint (`theme.accent`) — used by a
    /// meta-category screen with its own identity color (design 4b's magenta
    /// anime accent) so the Libraries icon reads in that category's color
    /// while browsing it, rather than the user's global theme accent.
    var accentOverride: Color? = nil

    @EnvironmentObject private var theme: Theme
    #if os(iOS)
    @EnvironmentObject private var appState: AppState
    #endif

    private var effectiveAccent: Color { accentOverride ?? theme.accent }

    #if os(iOS)
    /// The Libraries icon only appears when there is something to list —
    /// `libraryUIItems()` already drops the plain Movies/TV Shows libraries
    /// that the rail covers with their own icons.
    private var hasLibraries: Bool { !appState.libraryUIItems().isEmpty }
    #endif

    private var activeTarget: RailTarget {
        if isLibrariesOpen { return .libraries }
        switch destination {
        case .home: return .home
        case .settings: return .settings
        case .search: return .search
        case .movies: return .movies
        case .tv: return .tv
        // Reached via a Libraries submenu row, not its own rail icon — the
        // Libraries icon itself lights up instead (design 4b: "RAIL (libraries
        // active — Anime is a library)").
        case .animeLibrary, .lateNight, .videosLibrary: return .libraries
        }
    }

    var body: some View {
        #if os(iOS)
        if DeviceClass.current == .phone {
            // **No persistent rail on a phone.** A 104pt-wide leading column
            // is an iPad affordance — it assumes a wide landscape canvas and
            // a hand that isn't also holding the device. In a portrait
            // one-handed grip that column is just width taken from the
            // content before anything else fits, which is exactly what made
            // every screen read as "the iPad layout, clipped" on first boot.
            // `RootView` puts the same five destinations in a bottom
            // `PhoneTabBar` instead — see that file — so this returns
            // nothing and the `HStack(rail; content)` every screen already
            // builds collapses to just its content, full width, for free.
            EmptyView()
        } else {
            iPadRailBody
        }
        #else
        tvRailBody
        #endif
    }

    #if os(iOS)
    /// A narrower, touch-adapted sibling of the tvOS rail below — same
    /// idea (icon-only, translucent so the screen's own full-bleed
    /// backdrop shows through behind it, active icon accent-highlighted),
    /// reusing this same slot inside each screen's `HStack(rail; content)`
    /// so the backdrop-behind-the-rail effect just works the way it does
    /// on tvOS, with no separate padding math needed.
    ///
    /// **Libraries is a submenu here too, as on tvOS.** iPad used to put
    /// Anime and Late Night in the rail as direct icons, which meant the
    /// rail listed whichever few categories happened to have a dedicated
    /// screen and offered no route to any other library at all. One
    /// Libraries icon after TV Shows opens the same `LibrariesSubmenu`
    /// panel the Apple TV uses, listing every library the server has.
    private var iPadRailBody: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 36)
            // Same hand-drawn `NavIcons` set as the tvOS rail below, not a
            // separate iOS-only glyph language — the two rails are the same
            // control at two sizes, and reusing the shared, already-shared
            // code (`NavIcons` was never `#if os(tvOS)`-gated to begin with)
            // is what keeps that true rather than something to remember to
            // keep in sync by hand.
            iosRailButton(.home) { NavIcons.home(color: $0) }
            iosRailButton(.movies) { NavIcons.movies(color: $0) }
            iosRailButton(.tv) { NavIcons.tv(color: $0) }
            iosRailButton(.search) { NavIcons.search(color: $0) }
            if hasLibraries {
                iosRailButton(.libraries) { NavIcons.libraries(color: $0) }
            }
            Spacer(minLength: 36)
            // Pinned to the bottom, same placement as the tvOS rail's cog.
            // iPad had no route into Settings at all until now, which left
            // every per-device preference (accent, library classification,
            // the library backdrop effect) unreachable on this platform —
            // they're stored in local `UserDefaults`, so setting them on the
            // Apple TV doesn't carry over either.
            iosRailButton(.settings) { NavIcons.cog(color: $0) }
                .padding(.bottom, 20)
        }
        .padding(.vertical, 34)
        .frame(width: 104)
        .frame(maxHeight: .infinity)
        .background(Color(hex: "#06080E").opacity(0.4))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.text(0.1)).frame(width: 1)
        }
    }
    #endif

    #if os(tvOS)
    private var tvRailBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            VStack(spacing: 14) {
                railButton(.home) { NavIcons.home(color: $0) }
                railButton(.movies) { NavIcons.movies(color: $0) }
                railButton(.tv) { NavIcons.tv(color: $0) }
                railButton(.search) { NavIcons.search(color: $0) }
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
        // Without this, Left from an adjacent column (a Settings category
        // row, a library card, …) has no reliable on-axis candidate among
        // the rail's stacked icons and silently does nothing — the same
        // off-axis-rejection failure mode documented on the Settings detail
        // pane's own `.focusSection()`. Scoping the rail as its own section
        // lets the engine treat it as one entry point instead.
        .focusSection()
    }
    #endif

    private var railBackground: Color {
        Color(hex: "#06080E").opacity(isLibrariesOpen ? 0.85 : 0.2)
    }

    #if os(iOS)
    /// Same indirection as tvOS's `activeTarget`: a screen reached *through*
    /// the Libraries submenu lights up the Libraries icon, because that is
    /// the icon the user pressed to get there — there is no rail icon of its
    /// own to light.
    private var iosActiveTarget: RailTarget? {
        if isLibrariesOpen { return .libraries }
        switch destination {
        case .home: return .home
        case .movies: return .movies
        case .tv: return .tv
        case .animeLibrary, .lateNight, .videosLibrary: return .libraries
        case .settings: return .settings
        case .search: return .search
        }
    }

    @ViewBuilder
    private func iosRailButton<Icon: View>(_ target: RailTarget, @ViewBuilder icon: @escaping (Color) -> Icon) -> some View {
        let active = iosActiveTarget == target
        Button { onSelect(target) } label: {
            icon(active ? .white : Palette.text(0.55))
        }
        .buttonStyle(IOSRailIconButtonStyle(isActive: active, accent: effectiveAccent))
        .frame(width: 104, height: 56)
    }
    #endif

    @ViewBuilder
    private func railButton<Icon: View>(_ target: RailTarget, @ViewBuilder icon: @escaping (Color) -> Icon) -> some View {
        let active = activeTarget == target
        Button { onSelect(target) } label: {
            icon(active ? .white : Palette.text(0.5))
        }
        .buttonStyle(RailIconButtonStyle(isActive: active, accent: effectiveAccent))
        .frame(width: 118)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(effectiveAccent)
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
                    focused ? accent.opacity(0.28) : (isActive ? accent.opacity(0.15) : .clear),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .overlay {
                    if focused {
                        LEDRing(cornerRadius: 20, accent: accent)
                            .padding(-3)
                            .transition(.opacity)
                    } else {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(isActive ? accent.opacity(0.35) : Palette.text(0.08), lineWidth: 1)
                    }
                }
                .scaleEffect((focused ? 1.18 : 1.0) * (configuration.isPressed ? 0.94 : 1))
                .shadow(color: accent.opacity(focused ? 0.7 : 0), radius: focused ? 32 : 0)
                .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: focused ? 18 : 0, y: focused ? 10 : 0)
                .animation(.spring(response: 0.24, dampingFraction: 0.6), value: focused)
                .animation(.easeOut(duration: 0.18), value: isActive)
        }
    }
}

#if os(iOS)
/// iOS sibling of `RailIconButtonStyle` — same persistent active/inactive
/// accent tint, but a plain press-down dip instead of the tvOS focus
/// ring/glow (no resting "focused" state exists on touch).
private struct IOSRailIconButtonStyle: ButtonStyle {
    let isActive: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 56, height: 56)
            .background(
                isActive ? accent.opacity(0.2) : .clear,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isActive ? accent.opacity(0.4) : .clear, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
#endif
