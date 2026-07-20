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
        if env["JT_SHOW_TV"] == "1" { return .tv }
        return .home
    }()
    @State private var isLibrariesOpen = ProcessInfo.processInfo.environment["JT_SHOW_LIBRARIES"] == "1"
    /// `.fullScreenCover(item:)` doesn't reliably stack — a second cover
    /// modifier on the same view can silently lose to the first. Fold the
    /// debug fixture and real playback into one cover driven by a single
    /// optional so there's only ever one presentation point.
    @State private var playerPresentation: PlayerPresentation? = {
        ProcessInfo.processInfo.environment["JT_SHOW_PLAYER"] != nil ? .fixture : nil
    }()

    private enum PlayerPresentation: Identifiable, Equatable {
        case fixture
        case request(PlaybackRequest)

        var id: String {
            switch self {
            case .fixture: return "fixture"
            case .request(let request): return request.id
            }
        }
    }

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
        .onChange(of: appState.activePlaybackRequest) { _, request in
            guard let request else { return }
            playerPresentation = .request(request)
        }
        .fullScreenCover(item: $playerPresentation) { presentation in
            Group {
                switch presentation {
                case .fixture:
                    PlayerPreviewFixture()
                case .request(let request):
                    if let client = appState.jellyfinClient {
                        PlayerView(request: request, client: client, userId: appState.currentUserId)
                    }
                }
            }
            // `.fullScreenCover` content doesn't reliably inherit
            // `@EnvironmentObject`s from the presenting view — inject them
            // explicitly (`PlayerChrome` reads `theme` directly).
            .environmentObject(theme)
            .environmentObject(appState)
        }
        .onChange(of: playerPresentation) { _, presentation in
            // The cover's own dismiss (back button / exit command) only
            // clears local state — mirror it back so `AppState` doesn't
            // think a request is still active.
            if presentation == nil { appState.activePlaybackRequest = nil }
        }
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
            ShowsLibraryView(onSelectRail: handleRailSelection)
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
