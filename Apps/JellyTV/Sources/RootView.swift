import SwiftUI
import JellyTVKit

/// App shell: routes the rail's selections between Home, Settings, and the
/// placeholder destinations, and owns the Libraries submenu's open/closed
/// state (always paired with `.home`, never with Settings/placeholders — see
/// design.md). Owns and injects the shared `Theme`.
struct RootView: View {
    @StateObject private var theme = Theme()
    // Opens Settings at launch only when JT_SHOW_SETTINGS=1 (screenshot/testing hook).
    @State private var destination: NavDestination =
        ProcessInfo.processInfo.environment["JT_SHOW_SETTINGS"] == "1" ? .settings : .home
    // Opens the Libraries submenu at launch only when JT_SHOW_LIBRARIES=1 (screenshot/testing hook).
    @State private var isLibrariesOpen = ProcessInfo.processInfo.environment["JT_SHOW_LIBRARIES"] == "1"

    var body: some View {
        Group {
            switch destination {
            case .home:
                HomeView(
                    isLibrariesOpen: isLibrariesOpen,
                    onSelectRail: handleRailSelection,
                    onOpenSettings: { destination = .settings }
                )
            case .settings:
                SettingsView(onSelectRail: handleRailSelection)
            case .search, .movies, .tv:
                placeholder
            }
        }
        .environmentObject(theme)
        .preferredColorScheme(.dark)
    }

    private var placeholder: some View {
        HStack(spacing: 0) {
            NavRail(
                destination: destination,
                isLibrariesOpen: false,
                isServerConnected: SampleCatalog.server.isConnected,
                onSelect: handleRailSelection
            )
            ComingSoon(title: placeholderTitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .ignoresSafeArea()
        .onExitCommand { handleRailSelection(.home) }
    }

    private var placeholderTitle: String {
        switch destination {
        case .search: return "Search"
        case .movies: return "Movies"
        case .tv: return "TV Shows"
        case .home, .settings: return ""
        }
    }

    private func handleRailSelection(_ target: RailTarget) {
        switch target {
        case .home:
            isLibrariesOpen = false
            destination = .home
        case .search:
            isLibrariesOpen = false
            destination = .search
        case .movies:
            isLibrariesOpen = false
            destination = .movies
        case .tv:
            isLibrariesOpen = false
            destination = .tv
        case .settings:
            isLibrariesOpen = false
            destination = .settings
        case .libraries:
            if destination == .home {
                isLibrariesOpen.toggle()
            } else {
                destination = .home
                isLibrariesOpen = true
            }
        }
    }
}

#Preview {
    RootView()
}
