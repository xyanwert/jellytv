import SwiftUI
import JellyTVKit

struct RootView: View {
    @StateObject private var theme = Theme()
    @StateObject private var server = ServerConnection()
    @StateObject private var appState = AppState()
    @State private var destination: NavDestination = {
        let env = ProcessInfo.processInfo.environment
        if env["JT_SHOW_SETTINGS"] == "1" { return .settings }
        if env["JT_SHOW_MOVIES"] == "1" { return .movies }
        return .home
    }()
    @State private var isLibrariesOpen = ProcessInfo.processInfo.environment["JT_SHOW_LIBRARIES"] == "1"

    var body: some View {
        Group {
            if server.isConnected {
                mainContent
            } else if case .connecting = server.status {
                SetupView(server: server)
            } else {
                SetupView(server: server)
            }
        }
        .environmentObject(theme)
        .environmentObject(server)
        .environmentObject(appState)
        .preferredColorScheme(.dark)
        .onChange(of: server.isConnected) { _, connected in
            if connected, let info = server.serverInfo {
                appState.configure(
                    baseURL: info.baseURL,
                    apiKey: info.apiKey,
                    deviceId: server.deviceId,
                    userId: info.userId
                )
                Task { await appState.refresh() }
                appState.startRefreshTimer()
            } else {
                appState.stopRefreshTimer()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch destination {
        case .home:
            HomeView(
                isLibrariesOpen: isLibrariesOpen,
                onSelectRail: handleRailSelection,
                onOpenSettings: { destination = .settings }
            )
        case .settings:
            SettingsView(onSelectRail: handleRailSelection)
        case .search:
            placeholder
        case .movies:
            MoviesLibraryView(onSelectRail: handleRailSelection)
        case .tv:
            MetaLibraryView(collectionType: "tvshows", onSelectRail: handleRailSelection)
        }
    }

    private var placeholder: some View {
        HStack(spacing: 0) {
            NavRail(
                destination: destination,
                isLibrariesOpen: false,
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
