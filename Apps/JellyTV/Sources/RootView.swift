import SwiftUI
import JellyTVKit

struct RootView: View {
    @StateObject private var theme = Theme()
    @StateObject private var server = ServerConnection()
    @StateObject private var appState = AppState()
    /// A plain box rather than `@StateObject`: the store cannot be built until a server
    /// is connected, and `@StateObject` has to be initialised at view-init time.
    @StateObject private var discoverStoreBox = DiscoverStoreBox()
    /// "Play On" from other Jellyfin apps — attached to `appState` once the
    /// server connection is up; its own object so the Home top bar can
    /// observe just it.
    @StateObject private var remote = RemoteControl()
    /// *Pair a remote*: the TV's side of pairing a phone, and the panel over Home the
    /// top bar's remote button opens.
    @StateObject private var pairingHost = RemotePairingHost()
    @State private var destination: NavDestination = {
        let env = ProcessInfo.processInfo.environment
        if env["JT_SHOW_SETTINGS"] == "1" { return .settings }
        if env["JT_SHOW_MOVIES"] == "1" { return .movies }
        if env["JT_SHOW_TV"] == "1" { return .tv }
        if env["JT_SHOW_ANIME"] == "1" { return .animeLibrary }
        if env["JT_SHOW_LATE_NIGHT"] == "1" { return .lateNight }
        if env["JT_SHOW_SEARCH"] == "1" { return .search }
        // Discover and the download centre need a YSOJ-server; `=demo` seeds fixture
        // rows and `JT_SHOW_DISCOVER=detail` opens on a title mid-download — see
        // `DiscoverStore.demo()`. The same hooks as `Remote`'s `RootView`.
        if env["JT_SHOW_DISCOVER"] != nil { return .discover }
        if env["JT_SHOW_DOWNLOADS"] != nil { return .downloads }
        // `1` for Home Videos, `nsfw` for After Hours — the two libraries a
        // `homevideos` collection resolves to. See `Remote`'s `RootView` for
        // the same hook on iPad.
        if let videos = env["JT_SHOW_VIDEOS"] {
            return .videosLibrary(videos == "nsfw" ? .porn : .videos)
        }
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
                ZStack {
                    // `.disabled`, not just covered: the screen's controls have to leave
                    // the focus pool while the panel is up, or Menu and the arrows keep
                    // reaching them through it.
                    mainContent
                        .disabled(pairingHost.isPanelOpen)
                    if pairingHost.isPanelOpen {
                        RemotePanel()
                            .zIndex(5)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: pairingHost.isPanelOpen)
            } else if case .connecting = server.status {
                SetupView(server: server)
            } else {
                SetupView(server: server)
            }
        }
        .environmentObject(theme)
        .environmentObject(server)
        .environmentObject(appState)
        .environmentObject(remote)
        .environmentObject(pairingHost)
        // An overlay attached *outside* the `.environmentObject` modifiers does not see
        // them — SwiftUI crashes on the first missing object at launch (verified). Inject
        // what the toast reads by hand.
        .overlay(alignment: .top) {
            RemoteNoticeToast().environmentObject(remote).environmentObject(theme)
        }
        .preferredColorScheme(.dark)
        .onChange(of: appState.activePlaybackRequest) { _, request in
            if let request {
                playerPresentation = .request(request)
            } else if case .request = playerPresentation {
                // Cleared from outside the player — a remote Stop/GoHome
                // (`RemoteControl`). The cover's own dismiss already nils the
                // request (below), so this is a no-op in that direction.
                playerPresentation = nil
            }
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
            // The cover is its own window layer, so the toast has to be drawn here too
            // for a "which TV is this?" to reach someone mid-film.
            .overlay(alignment: .top) {
                RemoteNoticeToast().environmentObject(remote).environmentObject(theme)
            }
            // **tvOS dismisses this cover on Menu before any SwiftUI code
            // runs — `.interactiveDismissDisabled()` does not stop it.**
            // Verified three ways, all producing an unconditional exit back
            // to whatever presented the cover, with zero log line from
            // `PlayerChrome.handleMenuPress`/`interact` — meaning the press
            // never reaches the view at all: raw HID keycode 41, a real
            // `System Events key code 53` (routed through Simulator.app's
            // own remote translation, not a bypass), and with
            // `.interactiveDismissDisabled()` attached here (tried and
            // removed — no effect on tvOS's cover-dismiss gesture, whatever
            // it does on iOS/iPadOS sheets). See `PlayerChrome`'s own doc
            // comment for what this means for Menu inside the player.
        }
        .onChange(of: playerPresentation) { _, presentation in
            // The cover's own dismiss (back button / exit command) only
            // clears local state — mirror it back so `AppState` doesn't
            // think a request is still active.
            if presentation == nil { appState.activePlaybackRequest = nil }
        }
        .onChange(of: appState.pendingLibraryNavigation) { _, category in
            // Fire-once: always reset after handling (or ignoring) so a
            // repeat tap on the same category still triggers this again.
            defer { appState.pendingLibraryNavigation = nil }
            guard let category else { return }
            switch category {
            case .animefilm, .anime:
                destination = .animeLibrary
                isLibrariesOpen = false
            case .hentai:
                destination = .lateNight
                isLibrariesOpen = false
            case .videos, .porn:
                destination = .videosLibrary(category)
                isLibrariesOpen = false
            case .movies, .moviesxxx:
                destination = .movies
                isLibrariesOpen = false
            case .shows:
                destination = .tv
                isLibrariesOpen = false
            }
        }
        .onChange(of: server.isConnected) { _, connected in
            if connected, let info = server.serverInfo {
                appState.configure(
                    baseURL: info.baseURL,
                    apiKey: info.apiKey,
                    deviceId: server.deviceId,
                    userId: info.userId,
                    kind: info.kind
                )
                Task { await appState.refresh() }
                appState.startRefreshTimer()
                remote.attach(appState)
                pairingHost.attach(appState, remote: remote, deviceId: server.deviceId)
                // `JT_SHOW_REMOTE_PANEL=1` lands on the pairing panel for screenshots.
                // Inert unless set, like every other hook here.
                if ProcessInfo.processInfo.environment["JT_SHOW_REMOTE_PANEL"] == "1" {
                    pairingHost.isPanelOpen = true
                }
            } else {
                appState.stopRefreshTimer()
                remote.detach()
                pairingHost.detach()
                // The store was built around the *previous* server's client — its shelves,
                // jobs and token. Nothing of it may outlive the connection.
                discoverStoreBox.store?.stopPolling()
                discoverStoreBox.store = nil
                appState.activeDownloadCount = 0
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
            SettingsView(isLibrariesOpen: isLibrariesOpen, onSelectRail: handleRailSelection)
        case .search:
            SearchLibraryView(isLibrariesOpen: isLibrariesOpen, onSelectRail: handleRailSelection)
        case .movies:
            MoviesLibraryView(isLibrariesOpen: isLibrariesOpen, onSelectRail: handleRailSelection)
        case .tv:
            ShowsLibraryView(isLibrariesOpen: isLibrariesOpen, onSelectRail: handleRailSelection)
        case .animeLibrary:
            AnimeLibraryView(isLibrariesOpen: isLibrariesOpen, onSelectRail: handleRailSelection)
        case .lateNight:
            LateNightLibraryView(isLibrariesOpen: isLibrariesOpen, onSelectRail: handleRailSelection)
        case .videosLibrary(let category):
            VideosLibraryView(category: category, isLibrariesOpen: isLibrariesOpen,
                              onSelectRail: handleRailSelection)
        case .discover:
            if let store = discoverStore() {
                DiscoverView(isLibrariesOpen: isLibrariesOpen,
                             onSelectRail: handleRailSelection, store: store)
            } else {
                // Unreachable in practice: the rail icon that routes here only exists
                // when the server offers Discover.
                LibraryEmptyState(message: "Discover isn't available on this server.")
            }
        case .downloads:
            if let store = discoverStore() {
                DownloadCenterView(store: store, isLibrariesOpen: isLibrariesOpen,
                                   onSelectRail: handleRailSelection)
            } else {
                LibraryEmptyState(message: "Discover isn't available on this server.")
            }
        }
    }

    /// One store for both Discover and the download centre — a job started in one keeps
    /// running while the user is in the other, and the rail badge reads its count.
    @MainActor
    private func discoverStore() -> DiscoverStore? {
        if let existing = discoverStoreBox.store { return existing }
        let env = ProcessInfo.processInfo.environment
        if ["demo", "detail"].contains(env["JT_SHOW_DISCOVER"] ?? "") || env["JT_SHOW_DOWNLOADS"] == "demo" {
            let demo = DiscoverStore.demo()
            discoverStoreBox.store = demo
            return demo
        }
        guard let client = appState.ysojClient else { return nil }
        let created = DiscoverStore(client: client)
        created.onActiveJobCountChange = { [weak appState] in appState?.activeDownloadCount = $0 }
        discoverStoreBox.store = created
        return created
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
            // Opens the submenu over whatever screen is already showing —
            // never forces a navigation to Home first.
            isLibrariesOpen.toggle()
        case .discover:
            isLibrariesOpen = false
            destination = .discover
        case .downloads:
            isLibrariesOpen = false
            destination = .downloads
        case .animeLibrary, .lateNight:
            // Unreachable here — tvOS only reaches these via a Libraries
            // submenu row (`LibrariesSubmenu`), never this rail directly.
            // Only iOS's rail body (no submenu) reports these.
            break
        }
    }
}

#Preview {
    RootView()
}
