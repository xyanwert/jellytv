import SwiftUI
import JellyTVKit

/// The Movies library screen (design 4a): rail, controls, a "currently
/// selected" band that tracks grid focus, and a poster grid for the whole
/// library. Shows a loading state while the server's movies load — never
/// sample data standing in for the real grid.
///
/// The full header (eyebrow, big title, count, Play, Random) over its own
/// filter row — one shared layout for both platforms. iPad used to collapse
/// this into a single compact `LibraryControlBar` line to save vertical
/// space; on a real device that line had a search field plus three sort
/// chips plus a genre row plus a Random button fighting for one 48pt-tall
/// strip, and everything past the first couple of chips just truncated
/// ("Lates…", "Ran…"). tvOS's roomier two-row layout was never actually
/// short on space on an iPad in landscape — it just hadn't been tried there.
struct MoviesLibraryView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    private static let headerSpacing: CGFloat = 16
    private static let headerTopPadding: CGFloat = 24

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme

    @State private var movies: [MediaItem] = []
    /// True once `movies` has been populated at least once (even if the
    /// result was empty) — distinguishes "still loading" from "genuinely no
    /// movies" so the grid never has to borrow the sample catalog to fill
    /// the gap. Deliberately never reset to `false` again: a re-sort keeps
    /// showing the previous real results until the new ones land, rather
    /// than blanking the screen on every filter chip tap.
    @State private var hasLoadedMovies = false
    @State private var sort: LibrarySort = .newest
    @State private var selectedGenre: String?
    @State private var searchText = ""
    @State private var searchTags: [String] = []
    /// Random's own state — it builds a queue over a whole library, which
    /// is a round trip long enough to need reporting.
    @State private var randomState: RandomPlayState = .idle
    @State private var presentedMovie: Movie?
    /// Where a presented page zooms from: the focused poster.
    @State private var zoomOrigin: UnitPoint = .center
    /// A show reached *from* a movie page — one of an actor's other credits
    /// in the person sheet. This screen never lists shows itself.
    @State private var presentedShow: Show?
    /// Real detail (cast, ratings, tagline, awards) fetched for the selected
    /// item; shown in place of the sample fallback once it arrives.
    @State private var selectedDetail: Movie?
    @FocusState private var focusedId: String?
    /// The last poster the remote sat on. The hero keeps showing it while
    /// focus is up on the chips or the search field — moving to a filter
    /// used to snap the hero back to the first title, as if the selection
    /// had been lost.
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

    private var allMovies: [MediaItem] { movies }

    /// Distinct genres present in the current catalog, most common first.
    private var genres: [String] {
        let counts = Dictionary(grouping: allMovies, by: \.genre).mapValues(\.count)
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
        var items = allMovies
        if let selectedGenre { items = items.filter { $0.genre == selectedGenre } }
        if !searchTags.isEmpty { items = items.filter { $0.matches(allOf: searchTags) } }
        return items
    }

    /// The item whose artwork backs the page. tvOS follows the focused
    /// poster; iPad has no selection, so it uses the per-visit random pick
    /// and only falls back to `selectedItem` before the pick lands.
    private var backdropItem: MediaItem? {
        #if os(iOS)
        allMovies.first { $0.id == backdropItemId } ?? selectedItem
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
        // A focused poster wins. Otherwise (initial state, nothing focused)
        // feature the first item that actually has backdrop art rather than
        // `filtered.first` — the newest item is often an unidentified file
        // with no artwork, which would leave the big backdrop blank.
        filtered.first { $0.id == (focusedId ?? lastFocusedId) }
            ?? filtered.first { $0.rating != nil && $0.backdropImage != nil }
            ?? filtered.first { $0.backdropImage != nil }
            ?? filtered.first
    }

    /// The movie shown in the dossier: real fetched detail once it's in and
    /// matches the current selection, otherwise a bare base (real list fields,
    /// no cast/ratings/awards) that the dossier renders as a loading state.
    private var dossierMovie: Movie? {
        guard let item = selectedItem else { return nil }
        if let detail = selectedDetail, detail.id == item.id { return detail }
        return baseMovie(for: item)
    }

    /// True while the full detail for the current selection hasn't arrived yet
    /// — the dossier shows "loading" rather than any placeholder/fake metadata.
    private var isDossierLoading: Bool {
        guard let item = selectedItem else { return false }
        return selectedDetail?.id != item.id
    }

    /// A bare `Movie` carrying only an item's real list-level fields (title,
    /// rating, year, certification, synopsis). Cast/ratings/tagline/awards stay
    /// empty until the live detail fetch fills them in — never demo data.
    private func baseMovie(for item: MediaItem) -> Movie {
        var movie = SampleCatalog.movie(for: item)
        if let rating = item.rating {
            movie.rating = String(format: "%.1f", rating)
            movie.communityRating = rating
        }
        if let year = item.year { movie.year = year }
        if let certification = item.certification, !certification.isEmpty { movie.certification = certification }
        if let synopsis = item.synopsis, !synopsis.isEmpty { movie.synopsis = synopsis }
        movie.runtime = ""   // unknown until detail loads
        return movie
    }

    /// Fetches full Jellyfin detail for the selected item, then merges OMDb
    /// enrichment. Debounced so scrolling the grid doesn't fetch per poster;
    /// `.task(id:)` cancels the prior run when the selection changes.
    private func loadSelectedDetail() async {
        guard let item = selectedItem else { selectedDetail = nil; return }
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
        guard var movie = await appState.movieDetail(for: item.id) else { return }
        selectedDetail = movie
        if let enrichment = await appState.omdbEnrichment(imdbId: movie.imdbId), !Task.isCancelled {
            movie.externalRatings = enrichment.ratings
            movie.awards = enrichment.awards
            selectedDetail = movie
        }
    }

    /// Opens the Movie detail screen with a bare base; `MovieDetailView`
    /// fetches its own live detail (cast, ratings, awards) on appear.
    private func openMovie(_ item: MediaItem) {
        presentedMovie = baseMovie(for: item)
    }

    /// From inside a movie page: another film from "More like this", or any
    /// item from a person's credits (which can be a show).
    private func openItem(_ item: MediaItem) {
        switch item.kind {
        case .movie: presentedMovie = baseMovie(for: item)
        case .series: presentedShow = SampleCatalog.show(for: item)
        }
    }

    /// Closes the Libraries submenu first (if open), then the detail cover,
    /// then falls back to leaving the screen entirely.
    private var exitAction: (() -> Void)? {
        if isLibrariesOpen { return { onSelectRail(.libraries) } }
        if presentedMovie != nil || presentedShow != nil { return nil }
        return { onSelectRail(.home) }
    }

    var body: some View {
        ZStack {
            background
            // The focused movie's backdrop: a full-screen layer pinned to the
            // top, behind the rail and the scrolling content, the same way
            // HomeView's hero backdrop covers the top of the screen and
            // dissolves into the page over the rows below.
            if let backdropItem {
                SelectedBackdrop(item: backdropItem, blur: backdropBlur)
            }
            HStack(spacing: 0) {
                NavRail(destination: .movies, isLibrariesOpen: isLibrariesOpen, onSelect: onSelectRail)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems(),
                                        onDismiss: { onSelectRail(.libraries) }) {
                    // Header, filters and the selected-movie band stay pinned; only
                    // the poster catalog scrolls beneath them.
                    VStack(alignment: .leading, spacing: Self.headerSpacing) {
                        controlBar.libraryContentMargin()
                        // tvOS only. On iPad the band (plus its dossier
                        // panel) ran ~300pt between the controls and the
                        // first poster row — the single biggest thing
                        // standing between the user and the catalog. The
                        // grid takes that space back; the backdrop still
                        // carries the screen's atmosphere behind it.
                        #if os(tvOS)
                        if let selectedItem, let dossierMovie {
                            LibraryHero(content: .movie(dossierMovie, item: selectedItem, isLoading: isDossierLoading),
                                        accent: theme.accent)
                        }
                        #endif
                        if !hasLoadedMovies {
                            loadingGrid
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                postersSection
                                    .libraryContentMargin()
                                    .padding(.top, 6)   // room for the top row's focus glow
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
            // See `HomeView`'s matching `.disabled` for why: `presentedMovie`
            // is a same-ZStack overlay, not a modal, so without this the
            // rail stays focus-reachable underneath it.
            .disabled(presentedMovie != nil || presentedShow != nil)
            // The page zooms out of the focused poster and the shelf pushes
            // in behind it — see `ZoomTransition`.
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
                    .zIndex(3)
            }
        }
        .animation(.zoomPresentation, value: presentedMovie)
        .animation(.zoomPresentation, value: presentedShow)
        // Menu from a page puts the remote back on the poster it opened —
        // left alone, focus came back on the first filter chip.
        .onChange(of: presentedMovie) { _, new in if new == nil { focusedId = lastFocusedId } }
        .onChange(of: presentedShow) { _, new in if new == nil { focusedId = lastFocusedId } }
        // The backdrop and hero carry `.id(item)` + `.transition(.opacity)`;
        // this is what turns a selection change into a crossfade instead of
        // a cut.
        .animation(.easeInOut(duration: 0.35), value: selectedItem?.id)
        .onChange(of: focusedId) { _, id in
            if let id { lastFocusedId = id }
        }
        // tvOS seeds focus from the first poster instead — see
        // `seedFocusIfNeeded`.
        #if os(iOS)
        .defaultFocus($searchFocused, true)
        #endif
        // `appState.libraries.count` is part of the task id (not just `sort`)
        // so this re-fires once the server connection finishes configuring —
        // otherwise a view that appears before `AppState.refresh()` completes
        // (e.g. landing straight on Movies) would fetch once with no client
        // yet, get back `[]`, and never retry until the user touches a chip.
        .task(id: "\(sort.rawValue)-\(appState.libraries.count)") {
            let query = sort.query
            movies = await appState.loadMovies(sortBy: query.sortBy, sortOrder: query.sortOrder)
            hasLoadedMovies = true
            #if os(iOS)
            // Only when unset: a re-sort re-runs this task, and reshuffling
            // the backdrop on every filter-chip tap would be noise.
            if backdropItemId == nil { backdropItemId = LibraryBackdrop.pick(from: movies) }
            #endif
        }
        // Fetch rich detail (cast/ratings/tagline/awards) for the selected item.
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

    // MARK: - Header / controls

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            header
            filterBar
        }
    }

    /// Title and count, then search and Random. No eyebrow on tvOS (the rail
    /// already says where you are), and **no Play button anywhere** — it was
    /// an empty `Button {}` in the accent colour, the most prominent control
    /// on the screen and the only one that did nothing.
    private var header: some View {
        LibraryHeaderLayout {
            VStack(alignment: .leading, spacing: 4) {
                #if os(iOS)
                Text("LIBRARY // MOVIES")
                    .font(Mono.font(15, .bold))
                    .tracking(2.6)
                    .foregroundStyle(Palette.text(0.5))
                #endif
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Movies")
                        .font(Typography.font(34, .black))
                        .foregroundStyle(Palette.textPrimary)
                    Text(LibraryChrome.countLabel(shown: filtered.count, total: allMovies.count, noun: "titles"))
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
    }

    private var searchField: some View {
        TagSearchField(tags: $searchTags, liveText: $searchText, placeholder: "Search movies…",
                       accent: theme.secondaryAccent,
                       trailing: LibraryChrome.searchTrailing(count: filtered.count),
                       field: true, focus: $searchFocused)
    }

    /// **Random plays; it no longer just points at something.**
    ///
    /// It used to pick one card out of whatever the grid had loaded and open
    /// its detail page (or, on tvOS, merely move the focus to it) — a shuffle
    /// button that shuffled nothing and played nothing. Now it builds a queue
    /// over the whole movie library, randomised server-side, and starts
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
            let request = await appState.randomQueue(for: .movies)
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
                                        totalCount: allMovies.count)
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
                    LibraryFilterChip(label: option.rawValue, isOn: sort == option) { sort = option }
                }
                Rectangle().fill(Palette.text(0.14)).frame(width: 1, height: 26)
                ForEach(genres, id: \.self) { genre in
                    LibraryFilterChip(label: genre, isOn: selectedGenre == genre) {
                        selectedGenre = (selectedGenre == genre) ? nil : genre
                    }
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
    // A 180pt minimum (right for iPad's wide landscape column) leaves a
    // phone portrait column room for only two, oversized columns — a
    // 100pt minimum instead fills the same 362pt content width with three
    // smaller posters per row, which reads more like the genre's own
    // library grids (Netflix/Disney+ both run 3 across in portrait).
    private static var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: DeviceClass.current == .phone ? 100 : 180), spacing: 22)]
    }
    #else
    private static let gridColumns = [GridItem(.adaptive(minimum: 150, maximum: 175), spacing: 18)]
    #endif

    /// Shown in place of the grid until the first real fetch resolves —
    /// never the sample catalog standing in for real movies.
    private var loadingGrid: some View {
        LibraryLoadingState(message: "Loading movies…", accent: theme.accent)
    }

    private var postersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // iPad only. On tvOS the header's count already says how many
            // are showing, the chips already say which sort and genre, and
            // this row was one more line of mono-tracked labels between the
            // hero and the posters.
            #if os(iOS)
            HStack(alignment: .firstTextBaseline) {
                Text(sectionCaption)
                    .font(Mono.font(15, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.5))
                Spacer()
                Text("Showing \(filtered.count) of \(allMovies.count)")
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(Palette.text(0.4))
            }
            #endif
            // The grid draws nothing at all when empty; without this the
            // screen would be blank below the control bar — on tvOS the hero
            // has nothing to show either, so it is blank there too.
            if filtered.isEmpty {
                if allMovies.isEmpty {
                    LibraryEmptyState(message: "No movies in this library.")
                } else {
                    LibraryEmptyState(message: "Nothing matches these filters.")
                }
            }
            LazyVGrid(columns: Self.gridColumns, spacing: 20) {
                ForEach(filtered) { item in
                    LibraryPosterCard(item: item, onSelect: { openMovie(item) })
                        .focused($focusedId, equals: item.id)
                        .onAppear { seedFocusIfNeeded(item) }
                }
            }
        }
    }

    /// Focus lands on the first poster the moment it exists — content first,
    /// the way every commercial TV app opens a library. The grid scrolls
    /// inside its own `ScrollView` below the pinned header and hero, so
    /// focusing a poster no longer drags the header off the top (which is why
    /// the search field used to take default focus). Seeded from the first
    /// card's own `onAppear`, once: `.defaultFocus` can't target a poster that
    /// hasn't been fetched yet, and an `onChange` on the loaded flag runs a
    /// pass *before* the lazy grid has mounted the card — that assignment
    /// landed on nothing and focus stayed on the first filter chip.
    private func seedFocusIfNeeded(_ item: MediaItem) {
        #if os(tvOS)
        guard !hasSeededFocus, item.id == filtered.first?.id else { return }
        hasSeededFocus = true
        if focusedId == nil, searchFocused != true { focusedId = item.id }
        #endif
    }

    #if os(iOS)
    private var sectionCaption: String {
        let genrePart = selectedGenre?.uppercased() ?? "ALL MOVIES"
        return "\(genrePart) · \(sort.rawValue.uppercased())"
    }
    #endif

    // MARK: - Background

    private var background: some View {
        ZStack {
            Palette.background
            RadialGradient(colors: [Color(OKLCH(l: 0.34, c: 0.10, h: 235)).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.82, y: 0.04), startRadius: 0, endRadius: 1100)
        }
        .ignoresSafeArea()
    }
}
