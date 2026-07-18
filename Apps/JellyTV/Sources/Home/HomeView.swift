import SwiftUI
import JellyTVKit

/// Focus targets on the Home screen that we drive explicitly.
enum HomeFocus: Hashable {
    case heroResume
    case continueFirst
}

/// A detail screen presented full-screen over Home from a Recommended poster.
private enum PresentedDetail: Equatable {
    case show(Show)
    case movie(Movie)
}

/// The Home screen: left rail, a hero backdrop behind the text, and
/// Continue Watching / Recommended rows. Data comes from `AppState` with a
/// sample-catalog fallback while the server is still loading.
struct HomeView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void
    let onOpenSettings: () -> Void

    @FocusState private var focus: HomeFocus?
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState

    // Hero carousel state.
    // `displayHeroes` is what's actually on screen — it only ever changes
    // inside `revealNextSlide`, alongside the outgoing cover. `liveHeroes`
    // (below) is the live truth from AppState; reading it directly for
    // display would let the hero hard-cut the instant real data replaces the
    // sample catalog, bypassing the crumble entirely (that was the flash).
    @State private var displayHeroes: [HeroFeature] = SampleCatalog.heroes
    @State private var heroIndex = 0
    @State private var slideStartTime = Date()
    @State private var rotateTask: Task<Void, Never>?
    @State private var outgoingHero: HeroFeature?
    @State private var outgoingVisible = false
    @State private var departProgress: Double = 1
    @State private var presentedDetail: PresentedDetail?
    @State private var transitionStartTime: Date?

    private static let backdropHeight: CGFloat = 880

    private var liveHeroes: [HeroFeature] {
        let h = appState.heroes.isEmpty ? SampleCatalog.heroes : appState.heroes
        return h.isEmpty ? SampleCatalog.heroes : h
    }
    private var currentHero: HeroFeature { displayHeroes[heroIndex % displayHeroes.count] }

    private var initialFocus: HomeFocus {
        ProcessInfo.processInfo.environment["JT_FOCUS"] == "continue" ? .continueFirst : .heroResume
    }

    var body: some View {
        ZStack {
            homeBackground
            HomeSonar()
            heroBackdropLayer
            HStack(spacing: 0) {
                NavRail(
                    destination: .home,
                    isLibrariesOpen: isLibrariesOpen,
                    onSelect: onSelectRail
                )
                ZStack(alignment: .leading) {
                    content
                        .opacity(isLibrariesOpen ? 0.5 : 1)
                        .allowsHitTesting(!isLibrariesOpen)
                    if isLibrariesOpen {
                        let libs = appState.libraryUIItems()
                        LibrariesSubmenu(libraries: libs.isEmpty ? SampleCatalog.libraries : libs)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.2), value: isLibrariesOpen)

            if let presentedDetail {
                detailView(presentedDetail)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.25), value: presentedDetail)
        .onAppear {
            switch ProcessInfo.processInfo.environment["JT_SHOW_DEMO"] {
            // The static samples carry full enrichment (cast/awards/ratings) for
            // previewing the rich layout; `movie(for:)`/`show(for:)` are bare.
            case "1", "movie": presentedDetail = .movie(SampleCatalog.movie)
            case "show": presentedDetail = .show(SampleCatalog.show)
            default: break
            }
            // Data may already be loaded (e.g. returning to Home after the
            // first fetch completed elsewhere) — adopt it before the first
            // frame so there's nothing to reveal later.
            if !appState.heroes.isEmpty {
                displayHeroes = appState.heroes
            }
        }
        .task(id: theme.rotationInterval) { startHeroRotation() }
        .onChange(of: appState.heroes.isEmpty) { wasEmpty, isEmptyNow in
            // Real Jellyfin data just replaced the sample-catalog fallback —
            // reveal it through the same crumble/fade cover the rotation
            // timer uses instead of hard-cutting the backdrop.
            guard wasEmpty, !isEmptyNow else { return }
            Task { await revealNextSlide(newList: appState.heroes) }
        }
        .onDisappear { rotateTask?.cancel() }
        .onExitCommand(perform: isLibrariesOpen ? { onSelectRail(.home) } : nil)
    }

    /// Presents a movie or show detail for the selected Recommended poster.
    private func present(_ item: MediaItem) {
        presentedDetail = item.kind == .movie
            ? .movie(SampleCatalog.movie(for: item))
            : .show(SampleCatalog.show(for: item))
    }

    @ViewBuilder
    private func detailView(_ detail: PresentedDetail) -> some View {
        switch detail {
        case .show(let show):
            ShowView(show: show, onDismiss: { presentedDetail = nil })
        case .movie(let movie):
            MovieDetailView(movie: movie, onDismiss: { presentedDetail = nil })
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                TopBar(profile: SampleCatalog.profile, onOpenSettings: onOpenSettings,
                       heroCount: displayHeroes.count, heroIndex: heroIndex,
                       slideStartTime: slideStartTime, rotationSeconds: theme.rotationInterval.seconds)

                HeroView(hero: currentHero, resumeFocus: $focus)
                    .padding(.horizontal, 56)
                    .padding(.top, 4)

                let cwItems = appState.continueWatching.isEmpty
                    ? SampleCatalog.continueWatching : appState.continueWatching
                if !cwItems.isEmpty {
                    ContinueWatchingRow(items: cwItems,
                                        firstCardFocus: $focus, firstCardTag: .continueFirst)
                }

                let recItems = appState.recommended.isEmpty
                    ? SampleCatalog.recommended : appState.recommended
                RecommendedRow(items: recItems, onSelect: present)
                    .padding(.bottom, 60)
            }
            .padding(.top, 8)
        }
        .defaultFocus($focus, initialFocus)
    }

    // MARK: - Hero backdrop

    /// Full-bleed hero image behind the text, with scrims for legibility
    /// and a bottom fade to blend into the page background.
    private var heroBackdropLayer: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: Self.backdropHeight)
            ZStack {
                imageStack(size: size)
                    .opacity(0.9)
                heroScrims
            }
            .frame(width: geo.size.width, height: Self.backdropHeight, alignment: .top)
            .mask(heroBottomFade)
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
    private func imageStack(size: CGSize) -> some View {
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
            heroImage(currentHero, size: size)
                .modifier(HeroHeatHazeModifier(progress: departProgress, canvasSize: size, time: elapsed))
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
                heroImage(outgoing, size: size)
                    .modifier(HeroDepartureModifier(
                        style: theme.transitionStyle,
                        progress: departProgress,
                        canvasSize: size,
                        accent: theme.accent,
                        time: elapsed
                    ))
                    .opacity(isTransitioning ? 1 : 0)
                    .zIndex(1)
            }
        }
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
