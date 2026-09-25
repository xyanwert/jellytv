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
        // `=1`, or a category name (`=libraries`) — see `SettingsView`.
        if env["JT_SHOW_SETTINGS"] != nil { return .settings }
        // Settings → Home, on the adult-content row; `=1` with the keypad up.
        if env["JT_SHOW_ADULT_UNLOCK"] != nil { return .settings }
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

    /// Set when the launch splash has finished; it never comes back this launch.
    @State private var splashDone = false

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

    // MARK: - Launch splash

    /// `JT_SHOW_SPLASH=1` holds the splash up for screenshots — even with no
    /// saved session — and never lets it finish. Inert unless set.
    private static let holdsSplash = ProcessInfo.processInfo.environment["JT_SHOW_SPLASH"] == "1"

    /// The animated mark covers the launch while a saved session is restored and
    /// Home loads — once per launch, never again for a later reconnect.
    private var showsSplash: Bool {
        !splashDone && (server.launchedWithStoredSession || Self.holdsSplash)
    }

    /// Something to show: Home has loaded, or the reconnect gave up and the form
    /// has a sentence to say.
    private var splashReady: Bool {
        if Self.holdsSplash { return false }
        if server.isConnected { return appState.hasLoadedHome }
        if case .connecting = server.status { return false }
        return true
    }

    private var splashStatus: String {
        server.isConnected ? "Loading your library" : "Reaching \(server.hostReadout)"
    }

    var body: some View {
        ZStack {
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
            // The screen under the player: out of the focus pool, invisible, and told
            // so (`isObscured`) so its clocks stop — but alive, with its state, so Menu
            // lands back on the movie page or the episode drawer playback started from.
            // The opacity flips without animation on purpose: the player fades in over
            // it (its own `.transition`), and on the way out the screen has to be at
            // full alpha on the first frame or the focus engine refuses to land there.
            .disabled(playerPresentation != nil)
            .opacity(playerPresentation == nil ? 1 : 0)
            .animation(nil, value: playerPresentation == nil)
            .accessibilityHidden(playerPresentation != nil)
            // The splash counts too: Home's hero rotation (the crumble shader) and its
            // clocks have no business running under a screen nobody can see through.
            .environment(\.isObscured, playerPresentation != nil || showsSplash)

            // **A same-`ZStack` overlay, not a `.fullScreenCover` — so Menu is ours.**
            // tvOS dismisses a SwiftUI cover on Menu at the system level, before any
            // `.onExitCommand` inside it runs — verified again with the chrome showing
            // and focus on the play circle: the press produced no log line and dropped
            // the user on Home (raw HID keycode 41 and a real `System Events` keystroke
            // both; `.interactiveDismissDisabled()` changes nothing). The player needs
            // Menu for something else: with the chrome showing it hides the chrome, and
            // only with the chrome hidden does it leave — the same split every detail
            // page presented this way already gets (`MovieDetailView` over Home). An
            // overlay in the ZStack is what those pages do, and Menu reaches it as long
            // as something in it is focused, which the player guarantees (the invisible
            // catcher, the play circle, the night badge, or the loading placeholder).
            if let presentation = playerPresentation {
                playerLayer(presentation)
                    .zIndex(10)
                    .transition(.opacity)
            }

            // Over everything, including a player an autoplay hook raised under it.
            // Removed in one frame when it finishes (it fades its own mark first) —
            // a full-screen fade is exactly what this hardware does badly.
            if showsSplash {
                LaunchSplash(isReady: splashReady, status: splashStatus) { splashDone = true }
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playerPresentation == nil)
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
        .onChange(of: playerPresentation) { _, presentation in
            // The player's own close (BACK, Menu with the chrome hidden) only
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
        // **The door shutting takes the screen with it.** Twelve hours after
        // somebody typed the code — or the moment they press Hide now — a
        // Late Night or After Hours screen is still on the television unless
        // this puts it back on Home. An adult item already *playing* is left
        // alone: stopping an episode mid-scene is a worse surprise than
        // finishing it, and the player is a cover over all of this anyway.
        .onChange(of: appState.adultUnlockedUntil) { _, _ in
            guard !appState.showsAdultContent, destination.isAdultOnly else { return }
            destination = .home
            isLibrariesOpen = false
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

    /// The player, over everything. Sits inside the same `ZStack` as the screens, so
    /// the `.environmentObject`s applied to that stack reach it without the by-hand
    /// injection a `.fullScreenCover` needed; the toast is drawn once, over the stack.
    @ViewBuilder
    private func playerLayer(_ presentation: PlayerPresentation) -> some View {
        switch presentation {
        case .fixture:
            PlayerPreviewFixture(onClose: { playerPresentation = nil })
        case .request(let request):
            if let client = appState.jellyfinClient {
                PlayerView(request: request, client: client, userId: appState.currentUserId,
                           onClose: { playerPresentation = nil })
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
        if DiscoverFixture.uses(env["JT_SHOW_DISCOVER"]) || DiscoverFixture.uses(env["JT_SHOW_DOWNLOADS"]) {
            let demo = DiscoverStore.demo(
                landed: env["JT_SHOW_DISCOVER"] == DiscoverFixture.landed
                    || env["JT_SHOW_DOWNLOADS"] == DiscoverFixture.landed,
                owned: env["JT_SHOW_DISCOVER"] == DiscoverFixture.owned,
                idle: [DiscoverFixture.filmOnly, DiscoverFixture.download]
                    .contains(env["JT_SHOW_DISCOVER"] ?? ""),
                failed: env["JT_SHOW_DISCOVER"] == DiscoverFixture.failed)
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
