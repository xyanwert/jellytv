import SwiftUI
import JellyTVKit

/// iPad's primary navigation shell. Each screen (`HomeView`,
/// `MoviesLibraryView`, …) already embeds `NavRail` internally, next to its
/// own full-bleed backdrop, exactly like tvOS — `NavRail` now has a real iOS
/// body (icon-only, translucent, backdrop-visible-through-it) alongside the
/// tvOS one, so this shell just needs to own `selection` and hand each screen
/// a real `onSelectRail` that updates it. That's what makes the backdrop show
/// through behind the rail for free: the rail and the backdrop are siblings
/// in the *same* screen's `ZStack`, not a separate column bolted on here.
///
/// Settings is reachable from the rail's bottom cog. Search still isn't —
/// there's no dedicated search screen on iOS yet, and the library screens
/// carry their own search field.
struct RootView: View {
    @StateObject private var theme = Theme()
    @StateObject private var server = ServerConnection()
    @StateObject private var appState = AppState()
    /// A plain box rather than `@StateObject`: the store cannot be built until a server
    /// is connected, and `@StateObject` has to be initialised at view-init time.
    @StateObject private var discoverStoreBox = DiscoverStoreBox()
    /// The paired Apple TV — the phone's side of remote control. Attached on connect;
    /// installed as `AppState.playbackRouter` so every play in the app can go there.
    @StateObject private var tvLink = TVLink()
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: NavDestination? = {
        let env = ProcessInfo.processInfo.environment
        if env["RT_SHOW_MOVIES"] == "1" { return .movies }
        if env["RT_SHOW_TV"] == "1" { return .tv }
        if env["RT_SHOW_ANIME"] == "1" { return .animeLibrary }
        if env["RT_SHOW_LATE_NIGHT"] == "1" { return .lateNight }
        if env["RT_SHOW_SEARCH"] == "1" { return .search }
        // Discover and its download centre. Both only render against a YSOJ-server, so
        // these land on an explanatory empty state rather than a screen when pointed at
        // a plain Jellyfin — which is itself the thing worth screenshotting.
        if env["RT_SHOW_DISCOVER"] != nil { return .discover }
        if env["RT_SHOW_DOWNLOADS"] != nil { return .downloads }
        // `1` for Home Videos, `nsfw` for After Hours — the two libraries a
        // `homevideos` collection resolves to.
        if let videos = env["RT_SHOW_VIDEOS"] {
            return .videosLibrary(videos == "nsfw" ? .porn : .videos)
        }
        return .home
    }()

    /// `.fullScreenCover(item:)` doesn't reliably stack — fold the debug
    /// fixture and real playback into one cover driven by a single optional,
    /// same as tvOS's `RootView`.
    @State private var playerPresentation: PlayerPresentation?
    /// One-shot: the screenshot fixture is raised once, on first appear, and
    /// never re-raised after it is dismissed.
    @State private var didSeedFixture = false
    /// The rail's Libraries flyout. Same model as tvOS: not a destination, a
    /// panel that opens over whatever screen is already showing. iPad/tvOS
    /// only — see `isMorePresented` for the phone equivalent.
    @State private var isLibrariesOpen = false
    /// The phone `PhoneTabBar`'s "More" sheet (Libraries + Settings). A
    /// separate flag from `isLibrariesOpen` rather than the same one wearing
    /// two presentations: `isLibrariesOpen` drives a same-screen slide-out
    /// drawer next to a rail that no longer exists on phone, while this
    /// drives a native `.sheet` — see `PhoneTabBar.swift` for why a phone
    /// gets a sheet instead of the drawer.
    @State private var isMorePresented = false

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
        // **A `ZStack`, not a `Group`.** The `.fullScreenCover` below hangs off
        // this container, and a `Group` whose branch switches (setup ↔ split
        // view) changes identity when `server.isConnected` flips — taking any
        // presented cover down with it. That is what made `RT_SHOW_PLAYER`
        // land on the setup screen instead of the player: stored credentials
        // are tried, fail, and the resulting flip drops the cover. A stable
        // container keeps the presentation across the swap.
        ZStack {
            if server.isConnected {
                splitView
            } else {
                SetupView(server: server)
            }

            // The TV's pairing prompt and the remote sheet: same-ZStack overlays, above
            // the screen and below the player cover.
            if server.isConnected, let beacon = tvLink.pendingBeacon {
                PairingPrompt(beacon: beacon).zIndex(30)
            }
            if server.isConnected, tvLink.isSheetPresented {
                TVRemoteSheet(onClose: { tvLink.isSheetPresented = false }).zIndex(31)
            }

            // **The player cover hangs off this, not off the branch above.**
            // `server.isConnected` flips whenever stored credentials are
            // tried, fail, or later succeed, and each flip changes the
            // identity of whichever branch is showing — which tears down any
            // cover presented from it. A `Color.clear` sibling never changes
            // identity, so a player presented from here survives the swap.
            // That matters beyond the screenshot hook: a server blip during
            // playback used to drop the user out of the film.
            Color.clear
                .allowsHitTesting(false)
                .fullScreenCover(item: $playerPresentation) { presentation in
                    Group {
                        switch presentation {
                        case .fixture:
                            PlayerPreviewFixture()
                        case .request(let request):
                            if let client = appState.jellyfinClient {
                                PlayerView(request: request, client: client,
                                           userId: appState.currentUserId)
                            }
                        }
                    }
                    // `.fullScreenCover` content doesn't reliably inherit
                    // `@EnvironmentObject`s from the presenting view.
                    .environmentObject(theme)
                    .environmentObject(appState)
                }
        }
        .environmentObject(theme)
        .environmentObject(server)
        .environmentObject(appState)
        .environmentObject(tvLink)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.25), value: tvLink.isSheetPresented)
        .animation(.easeOut(duration: 0.25), value: tvLink.pendingBeacon)
        .onChange(of: scenePhase) { _, phase in
            tvLink.setForeground(phase == .active)
        }
        .onAppear {
            // Nudges an already-connected scene to re-evaluate orientation
            // immediately (belt-and-suspenders alongside the static
            // Info.plist restriction and the AppDelegate override).
            OrientationLock.shared.applyToCurrentScene()
            raiseScreenshotFixtureIfRequested()
            // Every play in the app asks the TV link first; with no TV up it says no
            // and the play stays here.
            appState.playbackRouter = { [weak tvLink] request in
                tvLink?.route(request) ?? false
            }
            // Covers the signed-out case; `AppState.loadYsojCapabilities` re-seeds on
            // every connect, since `configure()` clears the capabilities each time.
            let env = ProcessInfo.processInfo.environment
            if DiscoverFixture.uses(env["RT_SHOW_DISCOVER"]) || DiscoverFixture.uses(env["RT_SHOW_DOWNLOADS"]) {
                appState.seedDemoCapabilities()
            }
        }
        .onChange(of: appState.activePlaybackRequest) { _, request in
            guard let request else { return }
            playerPresentation = .request(request)
        }
        .onChange(of: playerPresentation) { _, presentation in
            PlayerDiagnostics.log("root: playerPresentation -> \(presentation?.id ?? "nil")")
            if presentation == nil { appState.activePlaybackRequest = nil }
        }
        .onChange(of: appState.pendingLibraryNavigation) { _, category in
            // Fire-once: always reset after handling (or ignoring) so a repeat
            // tap on the same category still triggers this again.
            defer { appState.pendingLibraryNavigation = nil }
            guard let category else { return }
            // Closes whichever "browse the rest of the libraries" surface is
            // currently open — the pad/tv slide-out drawer, or the phone
            // `PhoneMoreSheet` — since a row tap inside either means to
            // navigate, not to keep browsing the list it came from.
            isLibrariesOpen = false
            isMorePresented = false
            switch category {
            case .animefilm, .anime:
                selection = .animeLibrary
            case .hentai:
                selection = .lateNight
            case .videos, .porn:
                selection = .videosLibrary(category)
            case .movies, .moviesxxx:
                selection = .movies
            case .shows:
                selection = .tv
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
                Task {
                    await appState.refresh()
                    await autoplayHook()
                }
                appState.startRefreshTimer()
                tvLink.attach(appState, deviceId: server.deviceId)
                // `RT_SHOW_REMOTE=bar|sheet|prompt` seeds the TV link from fixtures so the
                // chrome can be iterated on without a paired Apple TV in the room.
                if let mode = ProcessInfo.processInfo.environment["RT_SHOW_REMOTE"] {
                    tvLink.seedDemo(mode)
                }
            } else {
                appState.stopRefreshTimer()
                tvLink.detach()
                // The store was built around the *previous* server's client — its shelves,
                // jobs and token. Nothing of it may outlive the connection.
                discoverStoreBox.store?.stopPolling()
                discoverStoreBox.store = nil
                appState.activeDownloadCount = 0
            }
        }
    }

    /// `RT_SHOW_PLAYER` — the player-chrome screenshot hook, inert unless set.
    ///
    /// Raised here rather than as `playerPresentation`'s initial value:
    /// SwiftUI drops a `.fullScreenCover` whose item is already non-nil on the
    /// very first render pass often enough to be useless, and this one races
    /// the setup screen's own connect attempt on top of that. Setting it after
    /// the first frame has committed presents every time.
    private func raiseScreenshotFixtureIfRequested() {
        guard !didSeedFixture,
              ProcessInfo.processInfo.environment["RT_SHOW_PLAYER"] != nil else { return }
        didSeedFixture = true
        playerPresentation = .fixture
        PlayerDiagnostics.log("root: raised screenshot fixture")
    }

    private var splitView: some View {
        detailPane
            .id(selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(theme.accent)
            // The TV bar stacks above the tab bar; the screens' bottom clearance grows
            // by its height through the environment rather than thirteen edits.
            .environment(\.phoneBottomBarInset,
                         DeviceClass.current == .phone && tvLink.showsBar ? TVBar.phoneHeight : 0)
            // A plain `.overlay`, not a `.safeAreaInset` — every screen's own
            // content already calls `.ignoresSafeArea()` for its full-bleed
            // backdrop, which would swallow a safe-area inset added here the
            // same way (see `View.phoneTabBarClearance()`). Each screen's
            // scrollable content carries its own bottom clearance instead.
            .overlay(alignment: .bottom) {
                if DeviceClass.current == .phone {
                    VStack(spacing: 0) {
                        if let notice = tvLink.notice {
                            TVNotice(text: notice).padding(.bottom, 10)
                        }
                        if tvLink.showsBar {
                            TVBar(onOpen: { tvLink.isSheetPresented = true })
                        }
                        PhoneTabBar(
                            destination: selection ?? .home,
                            onSelect: handleRailSelection,
                            onMore: { isMorePresented = true }
                        )
                    }
                    .animation(.easeOut(duration: 0.25), value: tvLink.showsBar)
                    .animation(.easeOut(duration: 0.25), value: tvLink.notice)
                }
            }
            // The iPad has no tab bar to stack on: the TV bar floats as a card instead.
            .overlay(alignment: .bottomTrailing) {
                if DeviceClass.current != .phone {
                    VStack(alignment: .trailing, spacing: 10) {
                        if let notice = tvLink.notice {
                            TVNotice(text: notice)
                        }
                        if tvLink.showsBar {
                            TVBar(onOpen: { tvLink.isSheetPresented = true })
                                .frame(width: 400)
                        }
                    }
                    .padding(24)
                    .animation(.easeOut(duration: 0.25), value: tvLink.showsBar)
                    .animation(.easeOut(duration: 0.25), value: tvLink.notice)
                }
            }
            .sheet(isPresented: $isMorePresented) {
                PhoneMoreSheet(
                    libraries: appState.libraryUIItems(),
                    onSelectSettings: { selection = .settings },
                    onSelectDiscover: { selection = .discover },
                    onSelectDownloads: { selection = .downloads }
                )
                .environmentObject(theme)
                .environmentObject(appState)
            }
    }

    /// Debug hook: `RT_AUTOPLAY=<title substring>` resumes the first matching
    /// Continue Watching entry as soon as the library loads, so a playback
    /// bug can be reproduced on a simulator with no tap automation available.
    /// Inert unless set, same convention as `RT_SHOW_MOVIES`.
    private func autoplayHook() async {
        let env = ProcessInfo.processInfo.environment
        guard let needle = env["RT_AUTOPLAY"], !needle.isEmpty else { return }
        let match = appState.continueWatching.first {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.episodeLabel.localizedCaseInsensitiveContains(needle)
        } ?? appState.continueWatching.first
        guard let match, let request = await appState.resumeRequest(for: match) else { return }
        appState.requestPlayback(request)
    }

    /// Maps a rail tap back onto `selection`. `.search` stays a tvOS-only
    /// concept — no dedicated search screen on iOS.
    private func handleRailSelection(_ target: RailTarget) {
        switch target {
        case .home: selection = .home; isLibrariesOpen = false
        case .movies: selection = .movies; isLibrariesOpen = false
        case .tv: selection = .tv; isLibrariesOpen = false
        case .animeLibrary: selection = .animeLibrary; isLibrariesOpen = false
        case .lateNight: selection = .lateNight; isLibrariesOpen = false
        case .libraries:
            // Opens over whatever is showing — never navigates first.
            isLibrariesOpen.toggle()
        case .settings: selection = .settings; isLibrariesOpen = false
        case .search: selection = .search; isLibrariesOpen = false
        case .discover: selection = .discover; isLibrariesOpen = false
        case .downloads: selection = .downloads; isLibrariesOpen = false
        }
    }

    /// One store for both Discover and the download centre, built the first time a
    /// YSOJ-server is connected. It has to outlive the Discover screen: a job started
    /// there keeps running after the user navigates away, and the rail's badge reads
    /// its count.
    @MainActor
    private func discoverStore() -> DiscoverStore? {
        if let existing = discoverStoreBox.store { return existing }
        // `=demo` seeds fixture rows so Discover can be iterated on without a live
        // YSOJ-server — see `DiscoverStore.demo()`. Inert unless the var is set.
        let env = ProcessInfo.processInfo.environment
        if DiscoverFixture.uses(env["RT_SHOW_DISCOVER"]) || DiscoverFixture.uses(env["RT_SHOW_DOWNLOADS"]) {
            let demo = DiscoverStore.demo(
                landed: env["RT_SHOW_DISCOVER"] == DiscoverFixture.landed
                    || env["RT_SHOW_DOWNLOADS"] == DiscoverFixture.landed,
                owned: env["RT_SHOW_DISCOVER"] == DiscoverFixture.owned,
                filmOnly: env["RT_SHOW_DISCOVER"] == DiscoverFixture.filmOnly,
                failed: env["RT_SHOW_DISCOVER"] == DiscoverFixture.failed)
            discoverStoreBox.store = demo
            return demo
        }
        guard let client = appState.ysojClient else { return nil }
        let created = DiscoverStore(client: client)
        created.onActiveJobCountChange = { [weak appState] in appState?.activeDownloadCount = $0 }
        discoverStoreBox.store = created
        return created
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selection ?? .home {
        case .home:
            HomeView(isLibrariesOpen: isLibrariesOpen, onSelectRail: handleRailSelection,
                     onOpenSettings: { selection = .settings })
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
        case .settings:
            SettingsView(isLibrariesOpen: isLibrariesOpen, onSelectRail: handleRailSelection)
        case .search:
            SearchLibraryView(isLibrariesOpen: isLibrariesOpen, onSelectRail: handleRailSelection)
        case .discover:
            if let store = discoverStore() {
                DiscoverView(isLibrariesOpen: isLibrariesOpen,
                             onSelectRail: handleRailSelection, store: store)
            } else {
                // Unreachable in practice — the rail icon that routes here only exists
                // when the server offers Discover — but a destination with no store must
                // still render something rather than trapping.
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
}

#Preview {
    RootView()
}
