import SwiftUI
import JellyTVKit

/// Focus targets on the Home screen that we drive explicitly.
enum HomeFocus: Hashable {
    case heroResume
    case continueFirst
    case recommendedFirst
    /// The "Couldn't load your library" empty/error state's Retry button —
    /// only ever mounted when `HomeView.homeLoadFailed` is true.
    case retry
}

/// A detail screen presented full-screen over Home from a Recommended poster.
private enum PresentedDetail: Equatable {
    case show(Show)
    case movie(Movie)
}

/// The Home screen: left rail, a hero backdrop behind the text, and
/// Continue Watching / Recommended rows. Data comes from `AppState`; while
/// the first `refresh()` is still in flight (`!appState.hasLoadedHome`) each
/// section shows a loading placeholder rather than sample-catalog data —
/// sample items look real but don't resolve against the actual server, so a
/// tap on one used to silently do nothing.
struct HomeView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void
    let onOpenSettings: () -> Void

    @FocusState private var focus: HomeFocus?
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState

    // Hero carousel state.
    // `displayHeroes` is what's actually on screen — it only ever changes
    // inside `revealNextSlide`, alongside the outgoing cover, or (once, on
    // first load) directly in the `.onChange` below. Starts empty rather than
    // seeded with `SampleCatalog.heroes`: showing sample data here used to
    // render a fully-tappable-looking Resume button that silently did
    // nothing (sample ids don't resolve against a real server) for as long
    // as `AppState.refresh()` took — see `AppState.hasLoadedHome`.
    @State private var displayHeroes: [HeroFeature] = []
    @State private var heroIndex = 0
    @State private var slideStartTime = Date()
    @State private var rotateTask: Task<Void, Never>?
    @State private var outgoingHero: HeroFeature?
    @State private var outgoingVisible = false
    @State private var departProgress: Double = 1
    @State private var presentedDetail: PresentedDetail?
    @State private var zoomOrigin: UnitPoint = .center
    @State private var focusBeforePresent: HomeFocus?
    @State private var transitionStartTime: Date?

    /// One-shot guard for the "stuck on the rail because there was nothing
    /// focusable yet" bug. `.defaultFocus` only resolves once per scope and
    /// does NOT re-fire when a `HomeFocus`-tagged view mounts moments later
    /// — without this, focus can sit on the rail forever even after real
    /// content arrives. Flips true the moment we intervene, or the moment
    /// `focus` becomes non-nil on its own (meaning the engine or the user
    /// already put it somewhere real) — after that, this view never assigns
    /// `focus` again, so a later background refresh or deliberate rail
    /// navigation can't get yanked back into content.
    @State private var hasEstablishedFocus = false
    @State private var isRetrying = false

    // tvOS has a 1080pt-tall canvas to spend on the hero before Continue
    // Watching/Recommended even enter the picture. An iPad landscape window
    // is much shorter — 880 alone eats nearly the whole screen, leaving the
    // rows below barely peeking in before you scroll. Shorter backdrop +
    // tighter text zone (see `HeroView`'s iOS constants) instead of iPad
    // just inheriting the tvOS proportions verbatim.
    #if os(iOS)
    private static let backdropHeight: CGFloat = 520
    #else
    private static let backdropHeight: CGFloat = 880
    #endif

    private var currentHero: HeroFeature? {
        guard !displayHeroes.isEmpty else { return nil }
        return displayHeroes[heroIndex % displayHeroes.count]
    }
    private var libraryItems: [Library] {
        let libs = appState.libraryUIItems()
        return libs.isEmpty ? SampleCatalog.libraries : libs
    }

    /// True once `AppState.refresh()` has finished (successfully or not)
    /// but every section still came back empty — indistinguishable from
    /// "this account genuinely has nothing yet," but Retry is the right
    /// call either way (harmless if there's really nothing to retry).
    private var homeLoadFailed: Bool {
        appState.hasLoadedHome
            && appState.heroes.isEmpty
            && appState.continueWatching.isEmpty
            && appState.recommended.isEmpty
    }

    /// Home's focus priority, recomputed from live data so it stays correct
    /// as content loads incrementally — never a single hardcoded case. The
    /// marquee action first, then "pick up where you left off," then
    /// discovery, then (only if nothing else exists) the failure
    /// affordance. `nil` only during the brief window before
    /// `hasLoadedHome` — nothing to resolve to yet.
    ///
    /// Reads `appState.heroes` directly rather than `currentHero`
    /// (`displayHeroes`'s crumble-presentation proxy): `AppState.refresh()`
    /// sets `continueWatching` well before `heroes` (there's a real network
    /// `await` — `fetchItemPool` — in between), so on every real cold
    /// launch Continue Watching's data lands, renders, and is briefly the
    /// only entry available before the hero ever exists. Resolving off
    /// `displayHeroes` here would let that intermediate frame win the
    /// one-shot assignment below and permanently outrank the hero once it
    /// *does* arrive. `appState.heroes` is the immediate source of truth —
    /// no such lag — and `displayHeroes` reliably catches up to it in the
    /// same update pass (see the `.onChange(of: appState.heroes.isEmpty)`
    /// handler above) before the next frame paints.
    private var resolvedFocusTarget: HomeFocus? {
        if !appState.heroes.isEmpty { return .heroResume }
        if !appState.continueWatching.isEmpty { return .continueFirst }
        if !appState.recommended.isEmpty { return .recommendedFirst }
        if homeLoadFailed { return .retry }
        return nil
    }

    private var initialFocus: HomeFocus {
        if ProcessInfo.processInfo.environment["JT_FOCUS"] == "continue" { return .continueFirst }
        return resolvedFocusTarget ?? .heroResume
    }

    /// Debug hook: `JT_SHOW_DEMO=movie|show|real-movie|real-show` opens a
    /// detail screen straight from launch, for design screenshots. Inert
    /// unless set, and applied only on the first appearance — see `.onAppear`.
    @State private var didApplyDemoHook = false

    private func applyDemoHookIfNeeded() {
        guard !didApplyDemoHook else { return }
        didApplyDemoHook = true
        switch ProcessInfo.processInfo.environment["JT_SHOW_DEMO"] {
        // The static samples carry full enrichment (cast/awards/ratings) for
        // previewing the rich layout; `movie(for:)`/`show(for:)` are bare.
        case "1", "movie": presentedDetail = .movie(SampleCatalog.movie)
        case "show": presentedDetail = .show(SampleCatalog.show)
        // Opens a REAL fetched item (e.g. against JT_MOCK_SERVER's TMDB/
        // AniList-sourced catalog) via the same bare-template + on-demand
        // enrichment path a tapped poster already uses — for verifying
        // detail-screen layout against real, busy artwork instead of
        // SampleCatalog's flat gradients.
        case "real-show":
            Task {
                // `refresh()`'s `/UserViews` fetch (which populates the
                // libraries `loadShows` filters against) races this same
                // `.onAppear` — retry until it's landed.
                for _ in 0..<25 {
                    let items = await appState.loadShows()
                    if let target = items.first(where: { $0.title.contains("House of the Dragon") }) ?? items.first {
                        presentedDetail = .show(SampleCatalog.show(for: target))
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        case "real-movie":
            Task {
                for _ in 0..<25 {
                    if let target = await appState.loadMovies().first {
                        presentedDetail = .movie(SampleCatalog.movie(for: target))
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        default: break
        }
    }

    var body: some View {
        ZStack {
            homeBackground
            // Neither the ring motif nor the full-bleed backdrop belongs on
            // phone: `HomeSonar` positions itself at x=1760 (nonsensical
            // outside a wide landscape canvas) and the backdrop is exactly
            // the full-bleed hero `Home.dc.html` replaces with a contained
            // featured-card carousel — see `content`'s phone branch.
            if DeviceClass.current != .phone {
                HomeSonar()
                heroBackdropLayer
            }
            HStack(spacing: 0) {
                NavRail(
                    destination: .home,
                    isLibrariesOpen: isLibrariesOpen,
                    onSelect: onSelectRail
                )
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: libraryItems,
                                        onDismiss: { onSelectRail(.libraries) }) {
                    content
                }
            }
            .railContentSafeArea()
            // `presentedDetail` (ShowView/MovieDetailView) is a same-ZStack
            // overlay, not a modal presentation — without this, the rail's
            // buttons stay in the tvOS focus engine's candidate pool even
            // though `detailView` visually covers them, so a Down/Up press
            // deep inside the detail view can silently escape all the way
            // out to the rail (confirmed on-device: repeated Down presses
            // from the Show view's cast row eventually focused-and-selected
            // the Settings rail icon underneath).
            .disabled(presentedDetail != nil)
            // The page zooms out of whatever was selected — a Recommended
            // poster or the hero's Details button — see `ZoomTransition`.
            .trackZoomOrigin($zoomOrigin)
            .zoomedBehind(presentedDetail != nil, origin: zoomOrigin)

            if let presentedDetail {
                detailView(presentedDetail)
                    .zoomPresented(from: zoomOrigin)
                    .zIndex(2)
            }
        }
        .animation(.zoomPresentation, value: presentedDetail)
        // Menu from a page puts the remote back on what opened it — the
        // poster or the hero's Details — instead of the first thing on screen.
        .onChange(of: presentedDetail) { old, new in
            if old == nil, new != nil { focusBeforePresent = focus }
            if new == nil, let saved = focusBeforePresent { focus = saved }
        }
        .onAppear {
            // Once per launch, not once per appearance: `.onAppear` fires
            // again every time Home comes back (dismissing a detail view,
            // switching rails), which made the hook re-open its demo dossier
            // and read as "the Home button goes to a dummy screen".
            applyDemoHookIfNeeded()

            // Data may already be loaded (e.g. returning to Home after the
            // first fetch completed elsewhere) — adopt it before the first
            // frame so there's nothing to reveal later.
            if !appState.heroes.isEmpty {
                displayHeroes = appState.heroes
            }

            // Warm return to Home (data already loaded elsewhere) —
            // `.defaultFocus` only gets one shot at resolution and that shot
            // may already have come and gone before this runs. Assert once,
            // directly; the guard makes this a no-op if `.defaultFocus`
            // already won on its own.
            if !hasEstablishedFocus, let target = resolvedFocusTarget {
                hasEstablishedFocus = true
                focus = target
            }
        }
        .onChange(of: focus) { _, newValue in
            if newValue != nil { hasEstablishedFocus = true }
        }
        .onChange(of: appState.hasLoadedHome) { _, loaded in
            // Cold start — `refresh()` has now fully settled (heroes,
            // Continue Watching, and Recommended are all in their final
            // state), a moment after first frame, after `.defaultFocus`
            // already had (and lost) its one shot at resolving to nothing.
            //
            // Deliberately keyed off `hasLoadedHome` rather than
            // `resolvedFocusTarget` itself: `refresh()` sets
            // `continueWatching` well before `heroes` (a real network
            // `await` sits between them), so watching `resolvedFocusTarget`
            // directly fires once Continue Watching alone lands, locks
            // `hasEstablishedFocus` in right there, and then permanently
            // outranks the hero once it arrives a moment later — sending
            // initial focus to a Continue Watching card even when a hero
            // exists. Waiting for the fully-settled signal means this fires
            // exactly once, using final data, so the priority order below
            // actually holds.
            //
            // Same one-shot guard as above — never fires again after the
            // first real hand-off, so a later background refresh can't
            // steal focus from wherever the user has since gone.
            guard loaded, !hasEstablishedFocus, let target = resolvedFocusTarget else { return }
            hasEstablishedFocus = true
            focus = target
        }
        // The whole rotation/crumble machinery below exists to animate the
        // full-bleed backdrop `heroBackdropLayer` draws — phone doesn't draw
        // that layer at all (see `body` above), so there's nothing for a
        // reveal to cover and no reason to run a background timer that would
        // just tick uselessly. `PhoneFeaturedCarousel` reads `appState.heroes`
        // directly instead.
        .task(id: theme.rotationInterval) {
            guard DeviceClass.current != .phone else { return }
            startHeroRotation()
        }
        .onChange(of: appState.heroes.isEmpty) { wasEmpty, isEmptyNow in
            guard DeviceClass.current != .phone else { return }
            guard wasEmpty, !isEmptyNow else { return }
            if displayHeroes.isEmpty {
                // First real data ever — there's no sample-catalog slide on
                // screen to crumble away (the loading placeholder isn't part
                // of this backdrop), so just adopt it directly and kick off
                // rotation now that there's more than a placeholder to rotate.
                displayHeroes = appState.heroes
                heroIndex = 0
                slideStartTime = Date()
                startHeroRotation()
            } else {
                // Real Jellyfin data just replaced an already-displayed
                // slide (e.g. a background re-refresh) — reveal it through
                // the same crumble/fade cover the rotation timer uses
                // instead of hard-cutting the backdrop.
                Task { await revealNextSlide(newList: appState.heroes) }
            }
        }
        .onDisappear { rotateTask?.cancel() }
        .tvBackCommand(
            closeOverlay: isLibrariesOpen,
            onCloseOverlay: { onSelectRail(.libraries) },
            isDetailPresented: presentedDetail != nil
            // goBack: nil (default) — Home is the true root; Menu here
            // correctly falls through to tvOS's own system default. Next
            // round: Search/Home Videos pass `goBack: { onSelectRail(.home) }`
            // here instead of hand-rolling their own `onExitCommand`.
        )
    }

    /// Presents a movie or show detail for the selected Recommended poster.
    private func present(_ item: MediaItem) {
        presentedDetail = item.kind == .movie
            ? .movie(SampleCatalog.movie(for: item))
            : .show(SampleCatalog.show(for: item))
    }

    /// The hero's Details button — the same detail screens a Recommended
    /// poster opens, built from what the hero already knows. An episode hero
    /// opens its *show* (there is no episode page; the show page is where the
    /// episode lives), under the show's name rather than the episode's. The
    /// detail screens fetch their own live data on appear, so the bare item
    /// here only has to carry an id and something to draw first.
    private func presentDetails(for hero: HeroFeature) {
        let isMovie = hero.itemType == "Movie"
        let isEpisode = hero.itemType == "Episode"
        let remoteImage = hero.image.hasPrefix("http") ? hero.image : nil
        let item = MediaItem(
            id: isEpisode ? (hero.seriesId ?? hero.id) : hero.id,
            title: isEpisode ? (hero.seriesTitle ?? hero.title) : hero.title,
            meta: isMovie ? "Movie" : "Series",
            image: remoteImage,
            artwork: hero.artwork,
            synopsis: isEpisode ? nil : hero.synopsis,
            backdropImage: remoteImage,
            isFavorite: hero.isFavorite
        )
        presentedDetail = isMovie ? .movie(SampleCatalog.movie(for: item)) : .show(SampleCatalog.show(for: item))
    }

    /// Resumes a Continue Watching card directly into the player — no
    /// intermediate detail screen. A no-op for sample-catalog fallback items
    /// (their ids don't resolve against a real server).
    private func resume(_ item: ContinueWatchingItem) {
        Task {
            guard let request = await appState.resumeRequest(for: item) else { return }
            appState.requestPlayback(request)
        }
    }

    /// **What tapping a `PhoneFeaturedCard` does.** iPad/tvOS's hero row has
    /// three actions (Resume/Details/♥); phone drops all three for a single
    /// tap on the card itself (`Home.dc.html`), and play is the one action a
    /// single tap on a featured card can mean, same as `HeroView.resume()`.
    #if os(iOS)
    private func resume(_ hero: HeroFeature) {
        Task {
            guard let request = await appState.resumeRequest(for: hero) else { return }
            appState.requestPlayback(request)
        }
    }
    #endif

    @ViewBuilder
    private func detailView(_ detail: PresentedDetail) -> some View {
        switch detail {
        case .show(let show):
            ShowView(show: show, onDismiss: { presentedDetail = nil })
        case .movie(let movie):
            MovieDetailView(movie: movie, onDismiss: { presentedDetail = nil }, onOpenItem: present)
                // A new identity per film: "More like this" and a person's
                // credits swap `presentedDetail` to another movie while this
                // view is up, and without this SwiftUI would keep the old
                // page's fetched detail as if it were the new film's.
                .id(movie.id)
        }
    }

    // MARK: - Content

    #if os(iOS)
    private static let contentSpacing: CGFloat = 14
    #else
    private static let contentSpacing: CGFloat = 26
    #endif

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if DeviceClass.current == .phone {
            phoneContent
        } else {
            padTVContent
        }
        #else
        padTVContent
        #endif
    }

    private var padTVContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Self.contentSpacing) {
                // Unconditional — this is Home's only always-present
                // interactive control (the remote-control switch on tvOS)
                // besides the rail itself. It used to be gated behind
                // `currentHero != nil`, which meant a failed/slow
                // `refresh()` left it unreachable along with everything
                // else in this column. `heroCount: 0` already renders
                // correctly with no rotation dots (`HeroDotsRow` no-ops for
                // `count <= 1`).
                TopBar(heroCount: displayHeroes.count, heroIndex: heroIndex,
                       slideStartTime: slideStartTime, rotationSeconds: theme.rotationInterval.seconds)

                if let hero = currentHero {
                    HeroView(hero: hero, resumeFocus: $focus, onDetails: { presentDetails(for: hero) })
                        .padding(.horizontal, 56)
                        .padding(.top, 4)
                } else if homeLoadFailed {
                    homeLoadErrorState
                } else {
                    heroLoadingPlaceholder
                }

                if !appState.continueWatching.isEmpty {
                    ContinueWatchingRow(items: appState.continueWatching,
                                        firstCardFocus: $focus, firstCardTag: .continueFirst,
                                        onSelect: resume)
                } else if !appState.hasLoadedHome {
                    rowLoadingPlaceholder(title: "Continue Watching")
                }

                if !appState.recommended.isEmpty {
                    RecommendedRow(items: appState.recommended,
                                   firstCardFocus: $focus, firstCardTag: .recommendedFirst,
                                   onSelect: present)
                        .padding(.bottom, 60)
                        .phoneTabBarClearance()
                } else if !appState.hasLoadedHome {
                    rowLoadingPlaceholder(title: "Recommended for You")
                        .padding(.bottom, 60)
                        .phoneTabBarClearance()
                }
            }
            .padding(.top, 8)
        }
        .defaultFocus($focus, initialFocus)
    }

    /// **No full-bleed hero — a title, not a banner.** Replaces
    /// `TopBar`/`HeroView`/`heroBackdropLayer` with a compact header, a row
    /// of library pills (every library one tap away, not buried in "More"),
    /// and a contained featured-card carousel — see `Home.dc.html` and
    /// `PhoneHomeComponents.swift`. Continue Watching/Recommended carry over
    /// unchanged in spirit, just re-margined for a phone column.
    #if os(iOS)
    private var phoneContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                PhoneHomeHeader(initial: SampleCatalog.profile.initial, onOpenSettings: onOpenSettings)
                PhoneLibraryPillsRow(libraries: libraryItems, onSelectRail: onSelectRail)

                if !appState.heroes.isEmpty {
                    PhoneFeaturedCarousel(heroes: appState.heroes, onSelect: resume)
                } else if !appState.hasLoadedHome {
                    phoneCarouselLoadingPlaceholder
                }

                if !appState.continueWatching.isEmpty {
                    ContinueWatchingRow(items: appState.continueWatching, onSelect: resume)
                } else if !appState.hasLoadedHome {
                    rowLoadingPlaceholder(title: "Continue Watching")
                }

                if !appState.recommended.isEmpty {
                    RecommendedRow(items: appState.recommended, onSelect: present)
                        .padding(.bottom, 60)
                        .phoneTabBarClearance()
                } else if !appState.hasLoadedHome {
                    rowLoadingPlaceholder(title: "Recommended for You")
                        .padding(.bottom, 60)
                        .phoneTabBarClearance()
                }
            }
            .padding(.top, 8)
        }
    }
    #endif

    // MARK: - Loading placeholders
    //
    // Shown only until `AppState.hasLoadedHome` flips true — never sample
    // data. A row that looks fully real and tappable but is secretly wired
    // to nothing (a sample-catalog id that can't resolve against the actual
    // server) is worse than an honest "still loading" state — see
    // CLAUDE.md's "Never show fake data as a placeholder".

    private var heroLoadingPlaceholder: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
            .padding(.horizontal, 56)
    }

    /// Home's own honest failure state. Replaces what used to be a bare,
    /// permanent `ProgressView()` once `hasLoadedHome` is true but every
    /// section came back empty — a real, focusable `Button`, not silence.
    /// Sized to roughly `heroLoadingPlaceholder`'s footprint so nothing
    /// jumps depending on which of the two renders.
    private var homeLoadErrorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Palette.text(0.4))
            Text("Couldn't load your library")
                .font(Typography.font(24, .heavy))
                .foregroundStyle(Palette.textPrimary)
            Text("Check that this device can still reach your Jellyfin server.")
                .font(Typography.font(16, .medium))
                .foregroundStyle(Palette.text(0.55))
            Button(action: retryLoad) {
                HStack(spacing: 10) {
                    if isRetrying {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .semibold))
                    }
                    Text(isRetrying ? "Retrying…" : "Retry")
                }
                .font(Typography.button)
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))
            .focused($focus, equals: .retry)
            .disabled(isRetrying)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
        .padding(.horizontal, 56)
    }

    private func retryLoad() {
        guard !isRetrying else { return }
        isRetrying = true
        Task {
            await appState.refresh()
            isRetrying = false
        }
    }

    #if os(iOS)
    private var phoneCarouselLoadingPlaceholder: some View {
        ProgressView()
            .tint(.white)
            .frame(maxWidth: .infinity, minHeight: PhoneFeaturedCarousel.cardSize.height, alignment: .center)
    }
    #endif

    private func rowLoadingPlaceholder(title: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: title)
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
        }
    }

    // MARK: - Hero backdrop

    /// Full-bleed hero image behind the text, with scrims for legibility
    /// and a bottom fade to blend into the page background.
    private var heroBackdropLayer: some View {
        GeometryReader { geo in
            // No slide yet (still loading) — nothing to draw behind the
            // placeholder; the ambient `homeBackground` gradient carries the
            // page on its own until real data arrives.
            if let hero = currentHero {
                let size = CGSize(width: geo.size.width, height: Self.backdropHeight)
                ZStack {
                    imageStack(hero: hero, size: size)
                        .opacity(0.9)
                    heroScrims
                }
                .frame(width: geo.size.width, height: Self.backdropHeight, alignment: .top)
                .mask(heroBottomFade)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// New slide as the base, the departing slide crumbling/fading on top.
    /// This is the RENDER side of the walkthrough in `revealNextSlide` below
    /// — re-run every time any of `currentHero`/`outgoingHero`/`outgoingVisible`
    /// change, plus every frame `departProgress` animates (via the
    /// Animatable fast path, which does NOT re-run this function's body —
    /// see the note on `isTransitioning` in STEP 5).
    private func imageStack(hero: HeroFeature, size: CGSize) -> some View {
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = transitionStartTime.map { now - $0.timeIntervalSinceReferenceDate } ?? 0

        // STEP 4/5 (render side) — this `let` is captured ONCE per body run.
        // It is NOT re-evaluated every animation frame (see the file header
        // comment above `outgoingVisible`'s declaration), so it only reflects
        // reality because `outgoingVisible` is a real, deliberately-toggled
        // @State — if this ever read a value that could go stale mid-animation,
        // that's exactly the shape of bug that causes a flash.
        let isTransitioning = outgoingVisible && outgoingHero != nil

        return ZStack {
            // BASE layer — always the current/new slide (STEP 6). Sits at the
            // default zIndex (0), so whatever's drawn in the OUTGOING branch
            // below it is what actually determines whether this is visible.
            baseHeroLayer(hero, size: size, elapsed: elapsed)
            // OUTGOING layer — STEP 4's snapshot, drawn ON TOP (zIndex 1).
            // `HeroDepartureModifier` is what actually shatters/fades this
            // away as `departProgress` animates 1 → 0 (STEP 7). While
            // `progress` is still ~1, this modifier draws the image
            // completely unmodified/opaque, fully hiding the BASE layer
            // beneath it — THIS is the thing that must stay true for there
            // to be no flash: as long as this branch renders at opacity 1
            // with progress ≈ 1, the base underneath is invisible no matter
            // what it already changed to in STEP 6.
            if let outgoing = outgoingHero {
                departingLayer(outgoing, size: size, elapsed: elapsed)
                    .opacity(isTransitioning ? 1 : 0)
                    .zIndex(1)
            }
        }
    }

    /// **tvOS renders the crumble at half size and scales it back up.**
    ///
    /// An Apple TV 4K draws this app at 3840×2160, and `layerEffect` runs the
    /// shader once per pixel of the departing layer — the 880pt backdrop
    /// *plus* the 600×560pt sample margin the flying tiles need, which more
    /// than doubles the layer's area. That is on the order of 25 million
    /// hex/noise/crack evaluations per frame, sixty times a second, on an
    /// A15 that is also compositing the rest of the screen; `lite` trimmed
    /// the instructions but never the pixels, and the real box still
    /// stuttered. Laying the layer out at half size cuts the fragments by
    /// four; flying the tiles 60% as far shrinks the margin with them, for
    /// another ~1.5×; one warp octave instead of two takes the largest term
    /// out of what's left. Roughly an order of magnitude less GPU work for a
    /// 1080p-equivalent render of a picture that is shattering — nothing a
    /// sofa can see. The shader works in screen points throughout
    /// (`unitScale`), so cells, cracks and glow are the size they were
    /// designed at. iPad keeps the full-resolution, full-flight effect.
    #if os(tvOS)
    private static let departureRenderScale: CGFloat = 0.5
    private static let departureFlightScale: Double = 0.6
    #else
    private static let departureRenderScale: CGFloat = 1
    private static let departureFlightScale: Double = 1
    #endif

    private func departingLayer(_ hero: HeroFeature, size: CGSize, elapsed: Double) -> some View {
        let scale = Self.departureRenderScale
        let layerSize = CGSize(width: size.width * scale, height: size.height * scale)
        return heroImage(hero, size: layerSize)
            .modifier(HeroDepartureModifier(
                style: theme.transitionStyle,
                progress: departProgress,
                canvasSize: size,
                accent: theme.accent,
                time: elapsed,
                // Drops the ember particles and the stretch motion-blur
                // resample (a second texture tap per pixel) as well — the
                // shatter/fly/crack skeleton survives, without the priciest
                // per-pixel extras.
                lite: DeviceClass.current == .tv,
                renderScale: scale,
                flightScale: Self.departureFlightScale
            ))
            .scaleEffect(1 / scale, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// The BASE hero layer (STEP 6's target). Heat haze is a subtle up-close
    /// wobble — worth it on an iPad held at arm's length, not worth its own
    /// full-canvas shader pass at a TV's 10-foot viewing distance, especially
    /// stacked on top of the (already-heavier, see `lite` above) crumble pass
    /// running at the same time.
    @ViewBuilder
    private func baseHeroLayer(_ hero: HeroFeature, size: CGSize, elapsed: Double) -> some View {
        let image = heroImage(hero, size: size)
        #if os(tvOS)
        image
        #else
        image.modifier(HeroHeatHazeModifier(progress: departProgress, canvasSize: size, time: elapsed))
        #endif
    }

    /// A hero backdrop image — remote (Jellyfin URL), bundled asset, or gradient.
    /// Remote images go through `HeroImageCache` rather than a plain
    /// `AsyncImage` — see that file's header for why (avoids a flash of a
    /// stale, two-cycles-old image when a slide becomes the outgoing layer).
    @ViewBuilder
    private func heroImage(_ hero: HeroFeature, size: CGSize) -> some View {
        Group {
            if hero.image.hasPrefix("http") {
                CachedHeroImage(urlString: hero.image, fallback: hero.artwork.gradient)
            } else if !hero.image.isEmpty {
                Image(hero.image).resizable().scaledToFill()
            } else {
                hero.artwork.gradient
            }
        }
        // Render the image into a 1.5× box then clip back to the frame — a 50%
        // zoom so the backdrop reads bigger/closer without changing its footprint.
        .frame(width: size.width * 1.5, height: size.height * 1.5)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - Ambient background

    /// Darkening scrims so the hero text stays readable over the backdrop.
    private var heroScrims: some View {
        Color.clear
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.55), location: 0.0),
                        .init(color: Color.black.opacity(0.35), location: 0.35),
                        .init(color: Color.black.opacity(0.10), location: 0.70),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.3), location: 0.0),
                        .init(color: .clear, location: 0.25),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            // Pre-darken the bottom of the backdrop toward black *before* the
            // alpha mask (`heroBottomFade`) starts cutting it away — without
            // this the image reads at full brightness right up until it gets
            // masked out, which looks like a hard cut into the dark page
            // background rather than a fade.
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.40),
                        .init(color: Color.black.opacity(0.5), location: 0.72),
                        .init(color: Color.black.opacity(0.92), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
    }

    /// Fades the backdrop to transparent at the bottom so it blends into
    /// content. Several stops (rather than one straight ramp) so the falloff
    /// eases out gently instead of reading as a hard edge — combined with
    /// the darkening in `heroScrims` above, the image is already dim by the
    /// time it's masked away, so it dissolves into the page background
    /// instead of visibly cutting off where the rows begin.
    private var heroBottomFade: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.32),
                .init(color: .white.opacity(0.7), location: 0.48),
                .init(color: .white.opacity(0.3), location: 0.62),
                .init(color: .white.opacity(0.08), location: 0.74),
                .init(color: .clear, location: 0.84),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Ambient background

    private var homeBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#080B12"), Color(hex: "#060810")],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(OKLCH(l: 0.34, c: 0.10, h: 235)).opacity(0.5), .clear],
                           center: UnitPoint(x: 0.82, y: 0.04), startRadius: 0, endRadius: 1100)
            RadialGradient(colors: [Color(OKLCH(l: 0.30, c: 0.09, h: 250)).opacity(0.32), .clear],
                           center: UnitPoint(x: -0.05, y: 1.1), startRadius: 0, endRadius: 900)
        }
        .ignoresSafeArea()
    }

    // MARK: - Rotation
    //
    // Step-by-step walkthrough of one full rotation cycle — read this top to
    // bottom alongside `imageStack(size:)` above, which is what's actually
    // on screen at each step.

    /// STEP 0 — kicks off the repeating timer loop. Called once on appear
    /// (via `.task(id: theme.rotationInterval)`) and again any time the
    /// rotation-speed setting changes.
    private func startHeroRotation() {
        rotateTask?.cancel()
        slideStartTime = Date()
        guard displayHeroes.count > 1 else { return }
        let seconds = theme.rotationInterval.seconds
        rotateTask = Task { @MainActor in
            while !Task.isCancelled {
                // STEP 1 — idle: just sit here for `seconds` (5/15/30s).
                // Nothing on screen changes during this wait.
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                // STEP 2 — wait's over, do one reveal.
                await revealNextSlide()
            }
        }
    }

    /// Crumbles/fades the current slide away to reveal the next one — either
    /// the next slide in `displayHeroes` (periodic rotation), or, once,
    /// `newList` when real Jellyfin data replaces the sample catalog. Reusing
    /// this same cover for both means the backdrop is *never* swapped without
    /// something opaque on top of it, so there's no hard-cut/flash either way.
    @MainActor
    private func revealNextSlide(newList: [HeroFeature]? = nil) async {
        // STEP 3 — bail if a reveal is already running (e.g. the periodic
        // timer fired while the one-time data-load reveal was still going).
        guard !outgoingVisible else { return }
        if let newList, newList.isEmpty { return }
        let style = theme.transitionStyle

        // STEP 4 — snapshot what's CURRENTLY on screen into `outgoingHero`.
        // At this instant `currentHero` still resolves to the OLD slide
        // (heroIndex hasn't moved yet), so this correctly captures "image 1".
        outgoingHero = currentHero
        departProgress = 1   // 1 = shader draws the outgoing image untouched/opaque.

        // STEP 5 — reveal the cover. This is a PLAIN (non-animated) state
        // flip, done before anything else changes, so `imageStack`'s
        // `isTransitioning` gate (STEP 4 of the render side, below) is
        // guaranteed true before the base swaps underneath it in STEP 6.
        outgoingVisible = true
        transitionStartTime = Date()

        // STEP 6 — flip the base to the next slide, underneath the now-opaque
        // cover from STEP 5. This is the moment `currentHero` (and therefore
        // the green "BASE:" debug label) changes to the new image/title.
        withAnimation(.easeInOut(duration: 0.2)) {
            if let newList {
                displayHeroes = newList
                heroIndex = 0
            } else {
                heroIndex = (heroIndex + 1) % displayHeroes.count
            }
        }
        slideStartTime = Date()

        // STEP 7 — animate departProgress 1 → 0 over the style's duration
        // (1.25s crumble / 0.7s fade, currently ×3.3 slower via
        // `debugSpeedFactor`). SwiftUI interpolates this frame-by-frame
        // through `HeroDepartureModifier.animatableData` — see
        // HeroTransitions.swift — which re-invokes the `hexCrumble`/opacity
        // shader on the OUTGOING image every frame with the new progress.
        // The outgoing image visually shatters/fades away, progressively
        // revealing the base (STEP 6) underneath through the gaps.
        withAnimation(style.animation) {
            departProgress = 0
        }

        // STEP 8 — wait out the full departure animation (+ a small buffer),
        // then reset to the "at rest" state: cover hidden, ready for the
        // next cycle. `outgoingHero` is deliberately left non-nil (see
        // STEP 4) so there's never a frame where it's missing from the tree.
        try? await Task.sleep(for: .seconds(style.duration + 0.05))
        departProgress = 1
        outgoingVisible = false
        transitionStartTime = nil
    }
}

/// The top-right concentric-ring sonar motif with a pulsing accent ring.
private struct HomeSonar: View {
    @EnvironmentObject private var theme: Theme
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().stroke(Color(hex: "#78B4DC").opacity(0.10), lineWidth: 1)
                .frame(width: 680, height: 680)
            Circle().stroke(Color(hex: "#78B4DC").opacity(0.14), lineWidth: 1)
                .frame(width: 480, height: 480)
            Circle().stroke(theme.accent.opacity(0.18), lineWidth: 1.5)
                .frame(width: 280, height: 280)
            Circle().stroke(theme.accent, lineWidth: 2)
                .frame(width: 280, height: 280)
                .scaleEffect(pulse ? 1.9 : 0.6)
                .opacity(pulse ? 0 : 0.7)
        }
        .position(x: 1760, y: 60)
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
