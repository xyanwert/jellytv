import SwiftUI
import JellyTVKit

#if os(iOS)
/// The phone's primary navigation — a bottom tab bar, replacing `NavRail`'s
/// leading column on `DeviceClass.phone` (see that file's phone branch).
///
/// **Why a tab bar and not a shrunk rail.** A persistent leading-edge column
/// is a two-handed-or-stylus affordance: iPad and tvOS both assume a hand
/// free to reach a fixed screen edge, or a remote. Held one-handed in
/// portrait, the thumb's natural reach is the bottom of the screen — the
/// exact reason every major iPhone streaming app (Netflix, Disney+, Max)
/// puts primary navigation in a bottom bar and reserves a side rail for
/// iPad/tvOS. This ports that convention rather than reproducing the rail at
/// a smaller size, which would have put every icon at the *top* of a
/// one-handed reach instead of the bottom.
///
/// **Five destinations, not six.** `NavRail` has six rail icons (Home,
/// Movies, Search, TV, Libraries, Settings). A six-item bottom bar starts
/// working against "thumb-reachable" — narrower targets, more aiming, and
/// Apple's own tab bar guidance treats five as the practical ceiling before
/// items should collapse into a "More" row. Settings folds into the same
/// "More" sheet as the Libraries list (`PhoneMoreSheet`) rather than getting
/// its own tab — it's a once-in-a-while destination, not a browsing one.
struct PhoneTabBar: View {
    /// Mirrors `NavRail.activeTarget`'s indirection: a screen reached via the
    /// "More" sheet (Settings, Anime, Late Night, a Home Videos library)
    /// lights up the More tab, since that's the tab the user actually
    /// pressed to get there.
    let destination: NavDestination
    let onSelect: (RailTarget) -> Void
    let onMore: () -> Void
    var accentOverride: Color? = nil

    @EnvironmentObject private var theme: Theme

    private var effectiveAccent: Color { accentOverride ?? theme.accent }

    private enum Tab: CaseIterable {
        case home, search, movies, tv, more

        var label: String {
            switch self {
            case .home: return "Home"
            case .search: return "Search"
            case .movies: return "Movies"
            case .tv: return "Shows"
            case .more: return "More"
            }
        }

        var systemImage: String {
            switch self {
            case .home: return "house.fill"
            case .search: return "magnifyingglass"
            case .movies: return "film"
            case .tv: return "tv"
            case .more: return "square.stack.3d.up.fill"
            }
        }
    }

    private var activeTab: Tab {
        switch destination {
        case .home: return .home
        case .search: return .search
        case .movies: return .movies
        case .tv: return .tv
        case .settings, .animeLibrary, .lateNight, .videosLibrary: return .more
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.top, 10)
        // The home-indicator inset is handled by the safe area already;
        // a little extra breathing room above it keeps the label from
        // reading as glued to the edge.
        .padding(.bottom, 6)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color(hex: "#06080E").opacity(0.55))
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.text(0.1)).frame(height: 1)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func tabButton(_ tab: Tab) -> some View {
        let active = activeTab == tab
        return Button {
            if tab == .more { onMore() } else { onSelect(railTarget(for: tab)) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 21, weight: .semibold))
                Text(tab.label)
                    .font(Typography.font(11, .bold))
            }
            .foregroundStyle(active ? effectiveAccent : Palette.text(0.5))
            .frame(maxWidth: .infinity)
            // Full-height tap target, not just the icon+label's own footprint
            // — a thumb aiming at "roughly the third tab" should never miss.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PhoneTabButtonStyle())
    }

    private func railTarget(for tab: Tab) -> RailTarget {
        switch tab {
        case .home: return .home
        case .search: return .search
        case .movies: return .movies
        case .tv: return .tv
        case .more: return .libraries
        }
    }
}

/// A plain press-down dip — no resting focus state to draw, same reasoning
/// as `IOSRailIconButtonStyle`.
private struct PhoneTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The phone's "More" destination — presented as a sheet (native swipe-to-
/// dismiss, its own drag handle) rather than `LibrariesSubmenu`'s leading-
/// edge slide-out drawer. Two reasons that panel doesn't just carry over:
/// there's no rail for it to visually open "from" once `NavRail` is gone on
/// phone, and a drawer anchored to the screen's leading edge sits right where
/// iOS's own edge-swipe-back gesture lives — exactly the kind of
/// leading-edge custom gesture surface CLAUDE.md warns off. A sheet owns its
/// own dismiss gesture instead of competing with the system's.
///
/// Bundles Settings in with the library list — `NavRail` gives Settings its
/// own pinned icon because the rail has a whole edge to spend on it; a phone
/// tab bar doesn't have a sixth slot to spare (see `PhoneTabBar`'s doc
/// comment), so Settings becomes one more row here instead.
struct PhoneMoreSheet: View {
    let libraries: [Library]
    let onSelectSettings: () -> Void

    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(libraries) { library in
                        LibraryRow(library: library)
                    }
                    Button {
                        dismiss()
                        onSelectSettings()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(Palette.text(0.7))
                                .frame(width: 44, height: 44)
                                .background(Palette.text(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            Text("Settings")
                                .font(Typography.font(21, .bold))
                                .foregroundStyle(Palette.textPrimary)
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Palette.text(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.07), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Your Media")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
