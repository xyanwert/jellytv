import SwiftUI
import JellyTVKit

/// The Anime library screen (design 4b) — the anime meta-categories' own
/// dedicated browsing surface, reached from a Libraries submenu row rather
/// than a rail icon. Most real anime libraries are tvshows-collection
/// (episodic series, `.anime`) rather than movies-collection (`.animefilm`),
/// so this screen fetches and merges both into one poster grid, opening
/// `MovieDetailView` or `ShowView` per item depending on which kind it is —
/// from the user's perspective it's one "Anime" library, not two screens.
/// Reskinned with the design's magenta accent and a faint diagonal
/// "speed-line" energy texture. Ported ideas only where the design has no
/// real backing data (MAL score, seiyuu "legend" badges, tier ranks, opening
/// theme, a per-title Japanese name) — those slots are left out entirely
/// rather than inventing values, matching how the Movies/Shows dossiers
/// already degrade cleanly on sparse metadata.
struct AnimeLibraryView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    // See `MoviesLibraryView`'s identical constants.
    private static let headerSpacing: CGFloat = 16
    private static let headerTopPadding: CGFloat = 24

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme

    /// The category's own identity color (a fixed magenta/pink, not the
    /// user's customizable `theme.accent`) — matches design 4b's `accentAnime`
    /// token, seeded from the same hue (322) as its background radial glow.
    static let accent = Color(OKLCH(l: 0.62, c: 0.19, h: 322))

    @State private var items: [MediaItem] = []
    /// Same "loaded at least once" latch as `MoviesLibraryView` — never
    /// borrows sample data to fill the gap while the real fetch is in flight.
    @State private var hasLoaded = false
    @State private var sort: LibrarySort = .newest
    @State private var selectedGenre: String?
    @State private var searchText = ""
    @State private var searchTags: [String] = []
    /// Random's own state — it builds a queue over a whole library, which
    /// is a round trip long enough to need reporting.
    @State private var randomState: RandomPlayState = .idle
    @State private var presentedMovie: Movie?
    @State private var zoomOrigin: UnitPoint = .center
    @State private var presentedShow: Show?
    @State private var selectedMovieDetail: Movie?
    @State private var selectedShowDetail: Show?
    @FocusState private var focusedId: String?
    /// The last poster the remote sat on — see `MoviesLibraryView`.
    @State private var lastFocusedId: String?
    /// One-shot latch for `seedFocusIfNeeded`.
    @State private var hasSeededFocus = false
    @FocusState private var searchFocused: Bool?
    /// Which title's artwork is currently the page backdrop on iPad — see
    /// `LibraryBackdrop`. Chosen once per visit: `RootView` gives each screen
    /// `.id(selection)`, so navigating away and back rebuilds this view with
    /// fresh state and the load task picks again. Re-sorting inside the
    /// screen deliberately keeps the same image (the guard below), so tapping
    /// a filter chip doesn't reshuffle the wallpaper under you.
    @State private var backdropItemId: String?

    private var allItems: [MediaItem] { items }

    private var genres: [String] {
        let counts = Dictionary(grouping: allItems, by: \.genre).mapValues(\.count)
        return counts.keys
            .filter { !$0.isEmpty }
            .sorted { a, b in
                let (ca, cb) = (counts[a] ?? 0, counts[b] ?? 0)
                return ca != cb ? ca > cb : a < b
            }
            .prefix(8)
            .map { $0 }
    }

    private var filtered: [MediaItem] {
        var result = allItems
        if let selectedGenre { result = result.filter { $0.genre == selectedGenre } }
        if !searchTags.isEmpty { result = result.filter { $0.matches(allOf: searchTags) } }
        return result
    }

    /// The item whose artwork backs the page. tvOS follows the focused
    /// poster; iPad has no selection, so it uses the per-visit random pick
    /// and only falls back to `selectedItem` before the pick lands.
    private var backdropItem: MediaItem? {
        #if os(iOS)
        allItems.first { $0.id == backdropItemId } ?? selectedItem
        #else
        selectedItem
        #endif
    }

    /// Blur behind the library, per Settings → Appearance. tvOS keeps the
    /// sharp backdrop it was designed with.
    private var backdropBlur: Double {
        #if os(iOS)
        theme.libraryBackdropEffect.blurRadius
        #else
        0
        #endif
    }

    private var selectedItem: MediaItem? {
        filtered.first { $0.id == (focusedId ?? lastFocusedId) }
            ?? filtered.first { $0.rating != nil && $0.backdropImage != nil }
            ?? filtered.first { $0.backdropImage != nil }
            ?? filtered.first
    }

    private func baseMovie(for item: MediaItem) -> Movie {
        var movie = SampleCatalog.movie(for: item)
        if let rating = item.rating {
            movie.rating = String(format: "%.1f", rating)
            movie.communityRating = rating
        }
        if let year = item.year { movie.year = year }
        if let certification = item.certification, !certification.isEmpty { movie.certification = certification }
        if let synopsis = item.synopsis, !synopsis.isEmpty { movie.synopsis = synopsis }
        movie.runtime = ""
        return movie
    }

    private func baseShow(for item: MediaItem) -> Show {
        var show = SampleCatalog.show(for: item)
        if let rating = item.rating {
            show.rating = String(format: "%.1f", rating)
            show.communityRating = rating
        }
        if let year = item.year { show.years = year }
        if let certification = item.certification, !certification.isEmpty { show.certification = certification }
        if let synopsis = item.synopsis, !synopsis.isEmpty { show.synopsis = synopsis }
        return show
    }

    /// True while the full detail for the current selection hasn't arrived yet
    /// — the dossier shows "loading" rather than any placeholder/fake metadata.
    private var isDossierLoading: Bool {
        guard let item = selectedItem else { return false }
        switch item.kind {
        case .movie: return selectedMovieDetail?.id != item.id
        case .series: return selectedShowDetail?.id != item.id
        }
    }

    /// Fetches full detail for the selected item — a Jellyfin movie detail +
    /// OMDb, or a Jellyfin show detail + OMDb + TMDB network — depending on
    /// its kind. Debounced so scrolling the grid doesn't fetch per poster;
    /// `.task(id:)` cancels the prior run when the selection changes.
    private func loadSelectedDetail() async {
        guard let item = selectedItem else {
            selectedMovieDetail = nil
            selectedShowDetail = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
        switch item.kind {
        case .movie:
            guard var movie = await appState.movieDetail(for: item.id) else { return }
            selectedMovieDetail = movie
            if let enrichment = await appState.omdbEnrichment(imdbId: movie.imdbId), !Task.isCancelled {
                movie.externalRatings = enrichment.ratings
                movie.awards = enrichment.awards
                selectedMovieDetail = movie
            }
        case .series:
            guard var show = await appState.enrichedShow(baseShow(for: item)) else { return }
            selectedShowDetail = show
            let imdbId = show.imdbId
            async let omdbEnrichment = appState.omdbEnrichment(imdbId: imdbId)
            async let network = appState.tmdbNetwork(imdbId: imdbId)
            let enrichment = await omdbEnrichment
            let resolvedNetwork = await network
            guard !Task.isCancelled else { return }
            if let enrichment {
                show.externalRatings = enrichment.ratings
                show.awards = enrichment.awards
            }
            show.network = resolvedNetwork
            selectedShowDetail = show
        }
    }

    private func openItem(_ item: MediaItem) {
        switch item.kind {
        case .movie: presentedMovie = baseMovie(for: item)
        case .series: presentedShow = baseShow(for: item)
        }
    }

    private var exitAction: (() -> Void)? {
        if isLibrariesOpen { return { onSelectRail(.libraries) } }
        if presentedMovie != nil || presentedShow != nil { return nil }
        return { onSelectRail(.home) }
    }

    var body: some View {
        ZStack {
            background
            if let backdropItem {
                SelectedBackdrop(item: backdropItem, blur: backdropBlur)
            }
            HStack(spacing: 0) {
                NavRail(destination: .animeLibrary, isLibrariesOpen: isLibrariesOpen,
                        onSelect: onSelectRail, accentOverride: Self.accent)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems(),
                                        onDismiss: { onSelectRail(.libraries) }) {
                    VStack(alignment: .leading, spacing: Self.headerSpacing) {
                        controlBar.libraryContentMargin()
                        // tvOS only — see `MoviesLibraryView`'s identical gate.
                        #if os(tvOS)
                        selectedBand
                        #endif
                        if !hasLoaded {
                            loadingGrid
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                postersSection
                                    .libraryContentMargin()
                                    .padding(.top, 6)
                                    .padding(.bottom, 60)
                                    .phoneTabBarClearance()
                                    #if os(iOS)
                                    .fixesScrollTapDelay()
                                    #endif
                            }
                        }
                    }
                    .padding(.top, Self.headerTopPadding)
                }
            }
            .railContentSafeArea()
            // See `HomeView`'s matching `.disabled` for why: `presentedMovie`/
            // `presentedShow` are same-ZStack overlays, not modals, so
            // without this the rail stays focus-reachable underneath them.
            .disabled(presentedMovie != nil || presentedShow != nil)
            .trackZoomOrigin($zoomOrigin)
            .zoomedBehind(presentedMovie != nil || presentedShow != nil, origin: zoomOrigin)

            if let presentedMovie {
                MovieDetailView(movie: presentedMovie, onDismiss: { self.presentedMovie = nil },
                                onOpenItem: openItem)
                    .id(presentedMovie.id)
                    .zoomPresented(from: zoomOrigin)
                    .zIndex(2)
            }
            if let presentedShow {
                ShowView(show: presentedShow, onDismiss: { self.presentedShow = nil })
                    .zoomPresented(from: zoomOrigin)
                    .zIndex(2)
            }
        }
        .animation(.zoomPresentation, value: presentedMovie)
        .animation(.zoomPresentation, value: presentedShow)
        // Menu from a page puts the remote back on the poster it opened.
        .onChange(of: presentedMovie) { _, new in if new == nil { focusedId = lastFocusedId } }
        .onChange(of: presentedShow) { _, new in if new == nil { focusedId = lastFocusedId } }
        // Crossfades the backdrop and hero on a selection change — see
        // `MoviesLibraryView`.
        .animation(.easeInOut(duration: 0.35), value: selectedItem?.id)
        .onChange(of: focusedId) { _, id in
            if let id { lastFocusedId = id }
        }
        // tvOS seeds focus from the first poster instead — see
        // `MoviesLibraryView.seedFocusIfNeeded`.
        #if os(iOS)
        .defaultFocus($searchFocused, true)
        #endif
        // `appState.libraries.count` is part of the task id so this re-fires
        // once the server connection finishes configuring — see
        // `MoviesLibraryView`'s identical reasoning.
        .task(id: "\(sort.rawValue)-\(appState.libraries.count)") {
            let query = sort.query
            async let movies = appState.loadAnimeMovies(sortBy: query.sortBy, sortOrder: query.sortOrder)
            async let shows = appState.loadAnimeShows(sortBy: query.sortBy, sortOrder: query.sortOrder)
            items = await movies + shows
            hasLoaded = true
            #if os(iOS)
            // Only when unset: a re-sort re-runs this task, and reshuffling
            // the backdrop on every filter-chip tap would be noise.
            if backdropItemId == nil { backdropItemId = LibraryBackdrop.pick(from: items) }
            #endif
        }
        // tvOS only: this fetch exists purely to fill the selected-item
        // dossier, and iPad no longer renders one. Leaving it on would spend
        // a Jellyfin detail call plus OMDb/TMDB lookups per selection change
        // with nothing on screen to receive them.
        #if os(tvOS)
        .task(id: selectedItem?.id) { await loadSelectedDetail() }
        #endif
        #if os(tvOS)
        .onExitCommand(perform: exitAction)
        #endif
    }

    #if os(tvOS)
    /// One hero for both kinds — the same `LibraryHero` Movies and Shows use,
    /// in this screen's accent, with the cast labelled for what it is here.
    @ViewBuilder private var selectedBand: some View {
        if let item = selectedItem {
            switch item.kind {
            case .movie:
                let movie = (selectedMovieDetail?.id == item.id) ? selectedMovieDetail! : baseMovie(for: item)
                LibraryHero(content: .movie(movie, item: item, isLoading: isDossierLoading),
                            accent: Self.accent, castLabel: "Voice cast")
            case .series:
                let show = (selectedShowDetail?.id == item.id) ? selectedShowDetail! : baseShow(for: item)
                LibraryHero(content: .show(show, item: item, isLoading: isDossierLoading),
                            accent: Self.accent, castLabel: "Voice cast")
            }
        }
    }
    #endif

    // MARK: - Header / controls

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            header
            filterBar
        }
    }

    /// See `MoviesLibraryView.header` — no eyebrow on tvOS, no Play anywhere.
    /// The "アニメ" ornament went with them: decoration in the title row of a
    /// screen whose own identity is already the accent colour.
    ///
    /// iPad keeps the translucent backing behind this row (`SelectedBackdrop`'s
    /// top-darken scrim alone wasn't enough contrast for the search field's
    /// subtle fill there); on tvOS the field is compact and sits over the
    /// scrim's darkest band, and a boxed header over the art read as one more
    /// panel on a screen that had too many.
    private var header: some View {
        LibraryHeaderLayout {
            VStack(alignment: .leading, spacing: 4) {
                #if os(iOS)
                Text("LIBRARY // ANIME")
                    .font(Mono.font(15, .bold))
                    .tracking(2.6)
                    .foregroundStyle(Palette.text(0.5))
                #endif
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Anime")
                        .font(Typography.font(34, .black))
                        .foregroundStyle(Palette.textPrimary)
                    Text(LibraryChrome.countLabel(shown: filtered.count, total: allItems.count, noun: "titles"))
                        .font(Typography.font(20, .semibold))
                        .foregroundStyle(Palette.text(0.4))
                }
            }
            .libraryTitleBlockSizing()
        } search: {
            searchField
        } actions: {
            #if os(iOS)
            RandomPlayButton(size: .icon(dimension: 48, cornerRadius: 14, glyphSize: 18),
                              state: $randomState, action: randomize)
            #else
            RandomPlayButton(size: .header, state: $randomState, action: randomize)
            #endif
        }
        #if os(iOS)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: "#0B0E16").opacity(0.45))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.text(0.08), lineWidth: 1))
        #endif
    }

    private var searchField: some View {
        TagSearchField(tags: $searchTags, liveText: $searchText, placeholder: Self.searchPlaceholder,
                       accent: Self.accent,
                       trailing: LibraryChrome.searchTrailing(count: filtered.count),
                       field: true, focus: $searchFocused)
    }

    /// The evocative long form used to only fit the tvOS field — iPad's sat
    /// inline with the filter chips at a fixed 300pt, where it truncated to
    /// "Search anime, stud…". Now both platforms give the field the same
    /// header row width, so both get the full placeholder.
    private static let searchPlaceholder = "Search anime, studios, seiyuu…"

    /// **Random plays; it no longer just points at something.**
    ///
    /// It used to pick one card out of whatever the grid had loaded and open
    /// its detail page (or, on tvOS, merely move the focus to it) — a shuffle
    /// button that shuffled nothing and played nothing. Now it builds a queue
    /// over the every anime episode and film in the library, randomised server-side, and starts
    /// it: press Next and the next thing plays.
    ///
    /// The queue is deliberately the *whole scope*, not `filtered` — the
    /// visible grid is one sorted page of the library, and "random" that can
    /// only reach what happens to be on screen isn't random. A fresh queue is
    /// built per press, so pressing it again is a different order, never a
    /// re-entry into the last one.
    private func randomize() {
        guard randomState != .loading else { return }
        randomState = .loading
        Task {
            let request = await appState.randomQueue(for: .anime)
            guard let request else { randomState = .empty; return }
            randomState = .idle
            appState.requestPlayback(request)
        }
    }

    // MARK: - Filters

    @ViewBuilder
    private var filterBar: some View {
        #if os(iOS)
        if DeviceClass.current == .phone {
            LibrarySortGenreDropdownBar(sort: $sort, genres: genres, selectedGenre: $selectedGenre,
                                        accent: Self.accent, totalCount: allItems.count)
        } else {
            filterChipRail
        }
        #else
        filterChipRail
        #endif
    }

    private var filterChipRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                #if os(iOS)
                Text("FILTER")
                    .font(Mono.font(13, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.4))
                #endif
                ForEach(LibrarySort.allCases) { option in
                    LibraryFilterChip(label: option.rawValue, isOn: sort == option, action: { sort = option }, accent: Self.accent)
                }
                Rectangle().fill(Palette.text(0.14)).frame(width: 1, height: 26)
                ForEach(genres, id: \.self) { genre in
                    LibraryFilterChip(
                        label: genre, isOn: selectedGenre == genre,
                        action: { selectedGenre = (selectedGenre == genre) ? nil : genre },
                        accent: Self.accent
                    )
                }
            }
        }
    }

    // MARK: - Poster grid

    /// iPad drops the `maximum:` so the columns share the full content width
    /// (with `LibraryPosterCard` filling its cell) instead of capping at
    /// 210pt and leaving the remainder as a gap on the right. tvOS keeps the
    /// cap — its cards are a fixed 200pt and its canvas is wide enough that
    /// uncapped columns would stretch the cells well past the artwork.
    #if os(iOS)
    // See `MoviesLibraryView`'s identical comment on the phone minimum.
    private static var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: DeviceClass.current == .phone ? 100 : 180), spacing: 22)]
    }
    #else
    private static let gridColumns = [GridItem(.adaptive(minimum: 150, maximum: 175), spacing: 18)]
    #endif

    private var loadingGrid: some View {
        LibraryLoadingState(message: "Loading anime…", accent: Self.accent)
    }

    private var postersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // iPad only — see `MoviesLibraryView.postersSection`.
            #if os(iOS)
            HStack(alignment: .firstTextBaseline) {
                Text(sectionCaption)
                    .font(Mono.font(15, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.5))
                Spacer()
                Text("Showing \(filtered.count) of \(allItems.count)")
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(Palette.text(0.4))
            }
            #endif
            if filtered.isEmpty {
                if allItems.isEmpty {
                    LibraryEmptyState(message: "No anime here yet.",
                                      hint: "Mark a library as Anime in Settings → Libraries and it will show up here.")
                } else {
                    LibraryEmptyState(message: "Nothing matches these filters.")
                }
            }
            LazyVGrid(columns: Self.gridColumns, spacing: 20) {
                ForEach(filtered) { item in
                    LibraryPosterCard(item: item, onSelect: { openItem(item) })
                        .focused($focusedId, equals: item.id)
                        .onAppear { seedFocusIfNeeded(item) }
                }
            }
        }
    }

    /// See `MoviesLibraryView.seedFocusIfNeeded`.
    private func seedFocusIfNeeded(_ item: MediaItem) {
        #if os(tvOS)
        guard !hasSeededFocus, item.id == filtered.first?.id else { return }
        hasSeededFocus = true
        if focusedId == nil, searchFocused != true { focusedId = item.id }
        #endif
    }

    #if os(iOS)
    private var sectionCaption: String {
        let genrePart = selectedGenre?.uppercased() ?? "ALL ANIME"
        return "\(genrePart) · \(sort.rawValue.uppercased())"
    }
    #endif

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(hex: "#0A0714")
            RadialGradient(colors: [Color(OKLCH(l: 0.34, c: 0.15, h: 322)).opacity(0.5), .clear],
                           center: UnitPoint(x: 0.82, y: 0.04), startRadius: 0, endRadius: 1300)
            SpeedLines()
        }
        .ignoresSafeArea()
    }
}

/// A faint diagonal "speed-line" energy texture (design 4b) — thin parallel
/// lines at a shallow angle, screen-blended at very low opacity so it reads as
/// motion/energy behind the content rather than a visible pattern.
private struct SpeedLines: View {
    private let spacing: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let diagonal = (pow(geo.size.width, 2) + pow(geo.size.height, 2)).squareRoot()
            let count = Int(diagonal / spacing) + 4
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 1, height: diagonal)
                        .offset(x: CGFloat(i) * spacing - diagonal / 2)
                }
            }
            .frame(width: diagonal, height: diagonal)
            .rotationEffect(.degrees(25))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .opacity(0.05)
        .blendMode(.screen)
        .allowsHitTesting(false)
        .clipped()
    }
}
