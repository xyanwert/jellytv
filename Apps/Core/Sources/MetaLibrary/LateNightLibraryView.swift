import SwiftUI
import JellyTVKit

/// The Late Night library screen (design 4c) — the `.hentai` meta-category
/// (tvshows + anime + NSFW), reached from a Libraries submenu row. Shows-only
/// (movies has no combined NSFW+anime category, so there's no equivalent
/// movies pool to merge in here the way `AnimeLibraryView` does). Named for
/// the design's own tasteful in-product label ("Late Night") rather than the
/// internal `MetaCategory.hentai` case name — the screen never uses that word
/// itself, matching the same discretion the design applies.
///
/// Reskinned with a muted red/crimson identity color and a darker, grittier
/// backdrop treatment (vignette) than the Anime screen's magenta/energetic
/// one. A fixed "18+" badge beside the title is legitimate here (every item
/// in this category is NSFW by definition, so it's a category-wide fact, not
/// invented per-item data) — but the design's MAL score, content-advisory
/// tags, and "director's cut" callout have no real backing source and are
/// left out, same reasoning as `AnimeLibraryView`. The per-item "VIEWER
/// DISCRETION" / "EXPLICIT CONTENT" chips went with the rest of the dossier
/// chrome (see `LibraryHero`): they said the same thing as the 18+ badge,
/// twice more, in a smaller font.
struct LateNightLibraryView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    // See `MoviesLibraryView`'s identical constants.
    private static let headerSpacing: CGFloat = 16
    private static let headerTopPadding: CGFloat = 24

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme

    /// The category's own identity color — matches design 4c's `accentLate`
    /// token, seeded from the same hue (20, red) as its background radial glow.
    static let accent = Color(OKLCH(l: 0.56, c: 0.18, h: 20))

    @State private var items: [MediaItem] = []
    @State private var hasLoaded = false
    @State private var sort: LibrarySort = .newest
    @State private var selectedGenre: String?
    @State private var searchText = ""
    @State private var searchTags: [String] = []
    /// Random's own state — it builds a queue over a whole library, which
    /// is a round trip long enough to need reporting.
    @State private var randomState: RandomPlayState = .idle
    @State private var presentedShow: Show?
    @State private var zoomOrigin: UnitPoint = .center
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

    private var isDossierLoading: Bool {
        guard let item = selectedItem else { return false }
        return selectedDetail?.id != item.id
    }

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

    private func openShow(_ item: MediaItem) {
        presentedShow = baseShow(for: item)
    }

    private var exitAction: (() -> Void)? {
        if isLibrariesOpen { return { onSelectRail(.libraries) } }
        if presentedShow != nil { return nil }
        return { onSelectRail(.home) }
    }

    var body: some View {
        ZStack {
            background
            if let backdropItem {
                SelectedBackdrop(item: backdropItem, blur: backdropBlur)
            }
            HStack(spacing: 0) {
                NavRail(destination: .lateNight, isLibrariesOpen: isLibrariesOpen,
                        onSelect: onSelectRail, accentOverride: Self.accent)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems(),
                                        onDismiss: { onSelectRail(.libraries) }) {
                    VStack(alignment: .leading, spacing: Self.headerSpacing) {
                        controlBar.libraryContentMargin()
                        // tvOS only — see `MoviesLibraryView`'s identical gate.
                        #if os(tvOS)
                        if let selectedItem, let dossierShow {
                            LibraryHero(content: .show(dossierShow, item: selectedItem, isLoading: isDossierLoading),
                                        accent: Self.accent, castLabel: "Voice cast")
                        }
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
        .task(id: "\(sort.rawValue)-\(appState.libraries.count)") {
            let query = sort.query
            items = await appState.loadLateNightShows(sortBy: query.sortBy, sortOrder: query.sortOrder)
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

    private var dossierShow: Show? {
        guard let item = selectedItem else { return nil }
        if let selectedDetail, selectedDetail.id == item.id { return selectedDetail }
        return baseShow(for: item)
    }

    // MARK: - Header / controls

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            header
            filterBar
        }
    }

    /// See `AnimeLibraryView.header` for what left this row and why. The one
    /// thing that stays on tvOS is the 18+ badge, moved up beside the title:
    /// it is the single category-wide fact worth stating, and the eyebrow it
    /// used to hang off is gone.
    private var header: some View {
        LibraryHeaderLayout {
            VStack(alignment: .leading, spacing: 4) {
                #if os(iOS)
                HStack(spacing: 10) {
                    Text("LIBRARY // LATE NIGHT")
                        .font(Mono.font(15, .bold))
                        .tracking(2.6)
                        .foregroundStyle(Palette.text(0.5))
                    AdultBadge(accent: Self.accent)
                }
                #endif
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    #if os(tvOS)
                    AdultBadge(accent: Self.accent)
                    #endif
                    Text("Late Night")
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
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: "#0B0808").opacity(0.5))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.text(0.07), lineWidth: 1))
        #endif
    }

    private var searchField: some View {
        TagSearchField(tags: $searchTags, liveText: $searchText, placeholder: Self.searchPlaceholder,
                       accent: Self.accent,
                       trailing: LibraryChrome.searchTrailing(count: filtered.count),
                       field: true, focus: $searchFocused)
    }

    /// See `AnimeLibraryView.searchPlaceholder` — used to truncate to "Search
    /// seinen, p…" in iPad's old inline field; both platforms now give the
    /// field the same header row width.
    private static let searchPlaceholder = "Search seinen, psychological, uncut cuts…"

    /// **Random plays; it no longer just points at something.**
    ///
    /// It used to pick one card out of whatever the grid had loaded and open
    /// its detail page (or, on tvOS, merely move the focus to it) — a shuffle
    /// button that shuffled nothing and played nothing. Now it builds a queue
    /// over every episode of every season of every show, randomised
    /// server-side, and starts it: press Next and the next thing plays.
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
            let request = await appState.randomQueue(for: .lateNight)
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
        LibraryLoadingState(message: "Loading late night…", accent: Self.accent)
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
                    LibraryEmptyState(message: "No late night titles here yet.",
                                      hint: "Mark a library as both Anime and Adult in Settings → Libraries and it will show up here.")
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
        let genrePart = selectedGenre?.uppercased() ?? "ALL LATE NIGHT"
        return "\(genrePart) · \(sort.rawValue.uppercased())"
    }
    #endif

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(hex: "#0A0808")
            RadialGradient(colors: [Color(OKLCH(l: 0.24, c: 0.09, h: 20)).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.82, y: 0.0), startRadius: 0, endRadius: 1300)
            Vignette()
        }
        .ignoresSafeArea()
    }
}

/// A soft edge-darkening overlay (design 4c's inset vignette) — the grittier,
/// more claustrophobic counterpart to the Anime screen's diagonal speed-lines.
private struct Vignette: View {
    var body: some View {
        RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 420, endRadius: 1000)
            .allowsHitTesting(false)
    }
}
