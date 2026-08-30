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

    @State private var selection: NavDestination? = {
        let env = ProcessInfo.processInfo.environment
        if env["RT_SHOW_MOVIES"] == "1" { return .movies }
        if env["RT_SHOW_TV"] == "1" { return .tv }
        if env["RT_SHOW_ANIME"] == "1" { return .animeLibrary }
        if env["RT_SHOW_LATE_NIGHT"] == "1" { return .lateNight }
        return .home
    }()

    /// `.fullScreenCover(item:)` doesn't reliably stack — fold the debug
    /// fixture and real playback into one cover driven by a single optional,
    /// same as tvOS's `RootView`.
    @State private var playerPresentation: PlayerPresentation?
    /// One-shot: the screenshot fixture is raised once, on first appear, and
    /// never re-raised after it is dismissed.
    @State private var didSeedFixture = false

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
        .preferredColorScheme(.dark)
        .onAppear {
            // Nudges an already-connected scene to re-evaluate orientation
            // immediately (belt-and-suspenders alongside the static
            // Info.plist restriction and the AppDelegate override).
            OrientationLock.shared.applyToCurrentScene()
            raiseScreenshotFixtureIfRequested()
        }
        .onChange(of: appState.activePlaybackRequest) { _, request in
            guard let request else { return }
            playerPresentation = .request(request)
        }
        .onChange(of: playerPresentation) { _, presentation in
            PlayerDiagnostics.log("root: playerPresentation -> \(presentation?.id ?? "nil")")
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
                Task {
                    await appState.refresh()
                    await autoplayHook()
                }
                appState.startRefreshTimer()
            } else {
                appState.stopRefreshTimer()
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

    /// Maps a rail tap back onto `selection`. `.search` and `.libraries`
    /// remain tvOS-only concepts (no submenu, no dedicated search screen on
    /// iOS) — no-ops here.
    private func handleRailSelection(_ target: RailTarget) {
        switch target {
        case .home: selection = .home
        case .movies: selection = .movies
        case .tv: selection = .tv
        case .animeLibrary: selection = .animeLibrary
        case .lateNight: selection = .lateNight
        case .settings: selection = .settings
        case .search, .libraries: break
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selection ?? .home {
        case .home:
            HomeView(isLibrariesOpen: false, onSelectRail: handleRailSelection, onOpenSettings: {})
        case .movies:
            MoviesLibraryView(isLibrariesOpen: false, onSelectRail: handleRailSelection)
        case .tv:
            ShowsLibraryView(isLibrariesOpen: false, onSelectRail: handleRailSelection)
        case .animeLibrary:
            AnimeLibraryView(isLibrariesOpen: false, onSelectRail: handleRailSelection)
        case .lateNight:
            LateNightLibraryView(isLibrariesOpen: false, onSelectRail: handleRailSelection)
        case .settings:
            SettingsView(isLibrariesOpen: false, onSelectRail: handleRailSelection)
        case .search:
            HomeView(isLibrariesOpen: false, onSelectRail: handleRailSelection, onOpenSettings: {})
        }
    }
}

#Preview {
    RootView()
}
