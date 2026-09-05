import SwiftUI
import JellyTVKit

/// The TV Shows library screen: rail, controls (a full header + filter row,
/// shared by both platforms — see `MoviesLibraryView`'s header comment for
/// why iPad no longer gets a separate compacted line), a hero that tracks
/// grid focus (tvOS), and a poster grid for the whole library. A structural
/// sibling of `MoviesLibraryView` (shared chrome lives in
/// `LibraryComponents.swift`, the hero in `LibraryHero.swift`); the hero's
/// facts line carries season count and the network where a film's carries
/// runtime and director. Shows a loading state while the server's shows load
/// — never sample data standing in for the real grid.
struct ShowsLibraryView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    // See `MoviesLibraryView`'s identical constants.
    private static let headerSpacing: CGFloat = 16
    private static let headerTopPadding: CGFloat = 24

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme

    @State private var shows: [MediaItem] = []
    /// True once `shows` has been populated at least once (even if the
    /// result was empty) — distinguishes "still loading" from "genuinely no
    /// shows" so the grid never has to borrow the sample catalog to fill
    /// the gap. Deliberately never reset to `false` again: a re-sort keeps
    /// showing the previous real results until the new ones land, rather
    /// than blanking the screen on every filter chip tap.
    @State private var hasLoadedShows = false
    @State private var sort: LibrarySort = .newest
    @State private var selectedGenre: String?
    @State private var searchText = ""
    @State private var searchTags: [String] = []
    /// Random's own state — it builds a queue over a whole library, which
    /// is a round trip long enough to need reporting.
    @State private var randomState: RandomPlayState = .idle
    @State private var presentedShow: Show?
    @State private var zoomOrigin: UnitPoint = .center
    /// Real detail (cast, ratings, season count, network) fetched for the
    /// selected item; shown in place of the sample fallback once it arrives.
    @State private var selectedDetail: Show?
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

    private var allShows: [MediaItem] { shows }

    /// Distinct genres present in the current catalog, most common first.
    private var genres: [String] {
        let counts = Dictionary(grouping: allShows, by: \.genre).mapValues(\.count)
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
        var items = allShows
        if let selectedGenre { items = items.filter { $0.genre == selectedGenre } }
        if !searchTags.isEmpty { items = items.filter { $0.matches(allOf: searchTags) } }
        return items
    }

    /// The item whose artwork backs the page. tvOS follows the focused
    /// poster; iPad has no selection, so it uses the per-visit random pick
    /// and only falls back to `selectedItem` before the pick lands.
    private var backdropItem: MediaItem? {
        #if os(iOS)
        allShows.first { $0.id == backdropItemId } ?? selectedItem
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

    /// The show shown in the dossier: real fetched detail once it's in and
    /// matches the current selection, otherwise a bare base (real list fields,
    /// no cast/season count/network) that the dossier renders as a loading state.
    private var dossierShow: Show? {
        guard let item = selectedItem else { return nil }
        if let detail = selectedDetail, detail.id == item.id { return detail }
        return baseShow(for: item)
    }

    /// True while the full detail for the current selection hasn't arrived yet
    /// — the dossier shows "loading" rather than any placeholder/fake metadata.
    private var isDossierLoading: Bool {
        guard let item = selectedItem else { return false }
        return selectedDetail?.id != item.id
    }

    /// A bare `Show` carrying only an item's real list-level fields (title,
    /// rating, year, certification, synopsis). Cast/season-count/network stay
    /// empty until the live detail fetch fills them in — never demo data.
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

    /// Fetches full Jellyfin detail for the selected item, then concurrently
    /// merges OMDb ratings/awards and TMDB network branding. Debounced so
    /// scrolling the grid doesn't fetch per poster; `.task(id:)` cancels the
    /// prior run when the selection changes.
    private func loadSelectedDetail() async {
        guard let item = selectedItem else { selectedDetail = nil; return }
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
        guard var show = await appState.enrichedShow(baseShow(for: item)) else { return }
        selectedDetail = show
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
        selectedDetail = show
    }

    /// Opens the Show detail screen with a bare base; `ShowView` fetches its
    /// own live detail (cast, ratings, tagline) on appear.
    private func openShow(_ item: MediaItem) {
        presentedShow = baseShow(for: item)
    }

    /// Closes the Libraries submenu first (if open), then the detail cover,
    /// then falls back to leaving the screen entirely.
    private var exitAction: (() -> Void)? {
        if isLibrariesOpen { return { onSelectRail(.libraries) } }
        if presentedShow != nil { return nil }
        return { onSelectRail(.home) }
    }

    var body: some View {
        ZStack {
            background
            // The focused show's backdrop: a full-screen layer pinned to the
            // top, behind the rail and the scrolling content — the same
            // treatment Movies uses.
            if let backdropItem {
                SelectedBackdrop(item: backdropItem, blur: backdropBlur)
            }
            HStack(spacing: 0) {
                NavRail(destination: .tv, isLibrariesOpen: isLibrariesOpen, onSelect: onSelectRail)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems(),
                                        onDismiss: { onSelectRail(.libraries) }) {
                    // Header, filters and the selected-show band stay pinned; only
                    // the poster catalog scrolls beneath them.
                    VStack(alignment: .leading, spacing: Self.headerSpacing) {
                        controlBar.libraryContentMargin()
                        // tvOS only — see `MoviesLibraryView`'s identical gate.
                        #if os(tvOS)
                        if let selectedItem, let dossierShow {
                            LibraryHero(content: .show(dossierShow, item: selectedItem, isLoading: isDossierLoading),
                                        accent: theme.accent)
                        }
                        #endif
                        if !hasLoadedShows {
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
            // See `HomeView`'s matching `.disabled` for why: `presentedShow`
            // is a same-ZStack overlay, not a modal, so without this the
            // rail stays focus-reachable underneath it.
            .disabled(presentedShow != nil)
            .trackZoomOrigin($zoomOrigin)
            .zoomedBehind(presentedShow != nil, origin: zoomOrigin)

            if let presentedShow {
                ShowView(show: presentedShow, onDismiss: { self.presentedShow = nil })
                    .zoomPresented(from: zoomOrigin)
                    .zIndex(2)
            }
        }
        .animation(.zoomPresentation, value: presentedShow)
        // Menu from a page puts the remote back on the poster it opened.
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
        // `appState.libraries.count` is part of the task id (not just `sort`)
        // so this re-fires once the server connection finishes configuring —
        // otherwise a view that appears before `AppState.refresh()` completes
        // would fetch once with no client yet, get back `[]`, and never retry
        // until the user touches a chip.
        .task(id: "\(sort.rawValue)-\(appState.libraries.count)") {
            let query = sort.query
            shows = await appState.loadShows(sortBy: query.sortBy, sortOrder: query.sortOrder)
            hasLoadedShows = true
            #if os(iOS)
            // Only when unset: a re-sort re-runs this task, and reshuffling
            // the backdrop on every filter-chip tap would be noise.
            if backdropItemId == nil { backdropItemId = LibraryBackdrop.pick(from: shows) }
            #endif
        }
        // Fetch rich detail (cast/season count/network) for the selected item.
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

    /// See `MoviesLibraryView.header` — no eyebrow on tvOS, no Play anywhere.
    private var header: some View {
        LibraryHeaderLayout {
            VStack(alignment: .leading, spacing: 4) {
                #if os(iOS)
                Text("LIBRARY // TV SHOWS")
                    .font(Mono.font(15, .bold))
                    .tracking(2.6)
                    .foregroundStyle(Palette.text(0.5))
                #endif
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("TV Shows")
                        .font(Typography.font(34, .black))
                        .foregroundStyle(Palette.textPrimary)
                    Text(LibraryChrome.countLabel(shown: filtered.count, total: allShows.count, noun: "titles"))
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
        TagSearchField(tags: $searchTags, liveText: $searchText, placeholder: "Search TV shows…",
                       accent: theme.secondaryAccent,
                       trailing: LibraryChrome.searchTrailing(count: filtered.count),
                       field: true, focus: $searchFocused)
    }

    /// **Random plays; it no longer just points at something.**
    ///
    /// It used to pick one card out of whatever the grid had loaded and open
    /// its detail page (or, on tvOS, merely move the focus to it) — a shuffle
    /// button that shuffled nothing and played nothing. Now it builds a queue
    /// over the every episode of every season of every show, randomised server-side, and starts
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
            let request = await appState.randomQueue(for: .shows)
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
                                        totalCount: allShows.count)
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
    // See `MoviesLibraryView`'s identical comment on the phone minimum.
    private static var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: DeviceClass.current == .phone ? 100 : 180), spacing: 22)]
    }
    #else
    private static let gridColumns = [GridItem(.adaptive(minimum: 150, maximum: 175), spacing: 18)]
    #endif

    /// Shown in place of the grid until the first real fetch resolves —
    /// never the sample catalog standing in for real shows.
    private var loadingGrid: some View {
        LibraryLoadingState(message: "Loading TV shows…", accent: theme.accent)
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
                Text("Showing \(filtered.count) of \(allShows.count)")
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(Palette.text(0.4))
            }
            #endif
            if filtered.isEmpty {
                if allShows.isEmpty {
                    LibraryEmptyState(message: "No TV shows in this library.")
                } else {
                    LibraryEmptyState(message: "Nothing matches these filters.")
                }
            }
            LazyVGrid(columns: Self.gridColumns, spacing: 20) {
                ForEach(filtered) { item in
                    LibraryPosterCard(item: item, onSelect: { openShow(item) })
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
        let genrePart = selectedGenre?.uppercased() ?? "ALL TV SHOWS"
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
