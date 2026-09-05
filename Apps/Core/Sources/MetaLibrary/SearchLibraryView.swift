import SwiftUI
import JellyTVKit

/// Search — a hero field, recent searches, TYPE/Unwatched/NSFW filters, and
/// results grouped into Movies/TV Shows/Anime/Home Videos shelves, over an
/// atmospheric backdrop of whatever's selected. Shared between iPad and
/// tvOS (design work, 2026-08-31/09-01) — the two differ only in the field's
/// input mechanism (a native `TextField` vs tvOS's hidden-`TVTextField`-
/// behind-a-focusable-button bridge) and a few sizing constants; the search
/// logic, filters, grouping, and backdrop are one shared implementation.
///
/// The query goes to the *server* (`AppState.searchGrouped`), not to an
/// already-fetched list. Every library loader in this app caps at 500 items,
/// so filtering locally would quietly only ever search the first 500 of
/// anything.
struct SearchLibraryView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedId: String?
    @FocusState private var searchFieldFocused: Bool?

    @State private var query = ""
    @State private var isSearching = false
    /// Distinguishes "nothing typed yet" from "searched and found nothing" —
    /// the difference between a prompt and a dead end.
    @State private var hasSearched = false
    @State private var presentedMovie: Movie?
    @State private var zoomOrigin: UnitPoint = .center
    @State private var focusBeforePresent: String?
    @State private var presentedShow: Show?
    @State private var groupedResults = AppState.SearchResults()
    /// TYPE/Unwatched/NSFW live on `AppState`, not local `@State` — Search
    /// rebuilds fresh every time it's selected (it's not kept alive
    /// off-screen like a tab), so local state would silently drop back to
    /// "All"/off on every single visit. `AppState` persists them to
    /// UserDefaults too, so they survive a relaunch, not just a revisit.
    private var activeFilter: SearchFilter {
        get { appState.searchTypeFilter }
        nonmutating set { appState.searchTypeFilter = newValue }
    }
    private var unwatchedOnly: Bool {
        get { appState.searchUnwatchedOnly }
        nonmutating set { appState.searchUnwatchedOnly = newValue }
    }
    /// Overrides the global "hide adult content" default for this one
    /// search — off by default regardless of the Settings toggle, since a
    /// screen this explicit about "search everything" shouldn't silently
    /// surface adult libraries without the user turning it on here too. Once
    /// turned on, though, it's remembered the same as the other two.
    private var includeNSFW: Bool {
        get { appState.searchIncludeNSFW }
        nonmutating set { appState.searchIncludeNSFW = newValue }
    }
    /// Separate state per button — sharing one would flash "Nothing to
    /// play" on the icon nobody pressed.
    @State private var playState: RandomPlayState = .idle
    @State private var randomState: RandomPlayState = .idle

    #if os(iOS)
    // Narrower margin and cards on phone — see `MoviesLibraryView`'s
    // identical reasoning on `gridColumns`/`libraryContentMargin()`. Search
    // otherwise needed no structural change for phone: its title, search
    // field, and filter chips already sit on three separate rows rather than
    // one wide `HStack`, so nothing was forcing content off the trailing
    // edge the way the other library screens' single-row header was.
    private static var horizontalPadding: CGFloat { DeviceClass.current == .phone ? 20 : 48 }
    private static let topPadding: CGFloat = 30
    private static let contentSpacing: CGFloat = 18
    private static var posterCardWidth: CGFloat { DeviceClass.current == .phone ? 148 : 160 }
    private static var videoCardWidth: CGFloat { DeviceClass.current == .phone ? 160 : 220 }
    #else
    private static let horizontalPadding: CGFloat = 56
    private static let topPadding: CGFloat = 40
    private static let contentSpacing: CGFloat = 22
    private static let posterCardWidth: CGFloat = 200
    private static let videoCardWidth: CGFloat = 280
    #endif

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            // The focused (or first) result's backdrop, atmospheric behind
            // the rail and content — same layer Movies/Shows use, so a
            // search result reads as part of the same cinematic app, not a
            // flat utility screen bolted on the side.
            if let selectedItem {
                SelectedBackdrop(item: selectedItem, blur: backdropBlur)
            }
            HStack(spacing: 0) {
                NavRail(destination: .search, isLibrariesOpen: isLibrariesOpen, onSelect: onSelectRail)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems(),
                                        onDismiss: { onSelectRail(.libraries) }) {
                    VStack(alignment: .leading, spacing: Self.contentSpacing) {
                        header.padding(.horizontal, Self.horizontalPadding)
                        // Phone moves the field to a floating bar over the
                        // tab bar instead (see `phoneFloatingSearchField`) —
                        // this hero row, with its own Play button, is
                        // iPad/tvOS only from here down.
                        #if os(iOS)
                        if DeviceClass.current != .phone {
                            searchRow.padding(.horizontal, Self.horizontalPadding)
                        }
                        #else
                        searchRow.padding(.horizontal, Self.horizontalPadding)
                        #endif
                        filterRow.padding(.horizontal, Self.horizontalPadding)
                        resultsArea
                    }
                    .padding(.top, Self.topPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .railContentSafeArea()
            // See `HomeView`'s matching `.disabled` for why: `presentedMovie`/
            // `presentedShow` are same-ZStack overlays, not modals, so without
            // this the rail stays focus-reachable underneath them.
            .disabled(presentedMovie != nil || presentedShow != nil)
            .trackZoomOrigin($zoomOrigin)
            .zoomedBehind(presentedMovie != nil || presentedShow != nil, origin: zoomOrigin)

            if let presentedMovie {
                MovieDetailView(movie: presentedMovie, onDismiss: { self.presentedMovie = nil },
                                onOpenItem: openFromDetail)
                    .id(presentedMovie.id)
                    .zoomPresented(from: zoomOrigin)
                    .zIndex(2)
            }
            if let presentedShow {
                ShowView(show: presentedShow, onDismiss: { self.presentedShow = nil })
                    .zoomPresented(from: zoomOrigin)
                    .zIndex(2)
            }

            #if os(iOS)
            // Floats above `PhoneTabBar` (an overlay `RootView` adds outside
            // this view entirely) rather than sitting up with the header —
            // this IS the field for the screen whose entire job is typing,
            // so it belongs where a thumb already rests, not at the top of a
            // reach. No z-index games needed: it's positioned clear of the
            // tab bar's own footprint, so the two never actually overlap.
            if DeviceClass.current == .phone {
                phoneFloatingSearchField
                    .padding(.horizontal, 20)
                    .padding(.bottom, 86)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            #endif
        }
        .animation(.zoomPresentation, value: presentedMovie)
        .animation(.zoomPresentation, value: presentedShow)
        // Menu from a page puts the remote back on the result it opened.
        .onChange(of: presentedMovie) { old, new in
            if old == nil, new != nil { focusBeforePresent = focusedId }
            if new == nil, presentedShow == nil { focusedId = focusBeforePresent }
        }
        .onChange(of: presentedShow) { old, new in
            if old == nil, new != nil { focusBeforePresent = focusedId }
            if new == nil, presentedMovie == nil { focusedId = focusBeforePresent }
        }
        #if os(tvOS)
        // Focus the field on appear, same reasoning as Movies' search field:
        // focusing a poster instead would auto-scroll it into view and push
        // the header/field off the top of the screen.
        .defaultFocus($searchFieldFocused, true)
        #endif
        // The tag vocabulary backs the tag-search phase below — loaded here
        // too (not just from the player's tag panel) since a session that
        // opens Search first would otherwise search with an empty
        // vocabulary. Idempotent: `loadTagVocabulary` no-ops if already
        // loaded or loading.
        .task { appState.loadTagVocabulary() }
        // Debounced rather than per-keystroke: a search is a round-trip, and
        // typing "matrix" would otherwise fire six of them, with the answer
        // to "m" free to land after the answer to "matrix". Keyed on
        // `includeNSFW` too — toggling it changes which libraries the
        // server-side fetch scopes to, so it needs a real re-search, not
        // just a client-side re-filter the way `unwatchedOnly` gets.
        .task(id: "\(query)#\(includeNSFW)") {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.count >= 2 else {
                groupedResults = AppState.SearchResults()
                hasSearched = false
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = await appState.searchGrouped(term, includeNSFW: includeNSFW)
            guard !Task.isCancelled else { return }
            groupedResults = found
            appState.noteRecentSearch(term)
            isSearching = false
            hasSearched = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            #if os(tvOS)
            Text("LIBRARY // SEARCH")
                .font(Mono.font(15, .bold))
                .tracking(2.6)
                .foregroundStyle(Palette.text(0.5))
            #endif
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Search")
                    .font(Typography.font(34, .black))
                    .foregroundStyle(Palette.textPrimary)
                if hasSearched && !isSearching {
                    Text("\(filteredCount)")
                        .font(Mono.font(17, .bold))
                        .foregroundStyle(Palette.text(0.45))
                }
            }
            // No trailing `Spacer` — a plain `HStack(Text, Text)` reports its
            // true intrinsic (hugging) width. A `Spacer` here was harmless on
            // iPad/tvOS (the row is already far short of the canvas width
            // either way) but on a phone-width `.padding()`+`.background()`
            // chain it made this view report a *greedy* width, which is what
            // caused the title text to render clipped past the leading
            // edge — see the git history for the debug session that found
            // this (`.border()`+colored `.background()` on each row until
            // the layout culprit was visible).
        }
    }

    private var searchField: some View {
        SearchHeroField(placeholder: "Search everything…", text: $query,
                        accent: theme.accent, field: true, focus: $searchFieldFocused)
        #if os(tvOS)
            .frame(maxWidth: 1020, alignment: .leading)
        #endif
    }

    /// The field plus its two field-height icon companions — Play (the top
    /// playable result) and Random (the same "reshuffle the whole scope"
    /// rule every other library screen's Random button follows, just
    /// applied to this screen's scope: whatever the current search plus
    /// TYPE filter turned up, not one fixed library).
    private var searchRow: some View {
        HStack(spacing: 14) {
            searchField
            RandomPlayButton(
                size: .icon(dimension: SearchHeroField<Bool>.height,
                            cornerRadius: SearchHeroField<Bool>.cornerRadius,
                            glyphSize: Self.actionGlyphSize),
                state: $playState, action: playTopResult,
                idleGlyph: "play.fill", idleLabel: "Play"
            )
            RandomPlayButton(
                size: .icon(dimension: SearchHeroField<Bool>.height,
                            cornerRadius: SearchHeroField<Bool>.cornerRadius,
                            glyphSize: Self.actionGlyphSize),
                state: $randomState, action: randomizeResults
            )
        }
    }

    #if os(iOS)
    /// Phone's own field: floating over the tab bar rather than pinned under
    /// the header, shorter and lighter-typed than the iPad/tvOS hero field
    /// (this one has to share a thumb's reach with the tab bar right below
    /// it, not command the whole top of the screen), and carrying Random as
    /// a small trailing circle *inside* the field — the same slot a clear
    /// button already occupies — rather than as its own separate square icon
    /// beside it. Play doesn't make the trip: on a screen this compact,
    /// "search, then tap a result" is a better default than a second
    /// same-row button for "play whatever's on top," and this field has no
    /// spare width for it once Random is already there.
    private var phoneFloatingSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.text(0.5))
            TextField("", text: $query,
                      prompt: Text("Search everything…").foregroundStyle(Palette.text(0.34)))
                .font(Typography.font(16, .semibold))
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFieldFocused, equals: true)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.text(0.4))
                }
                .buttonStyle(.plain)
            }
            // Same circle-in-the-field slot a clear button sits in, just
            // sized to actually be pressable (28pt, not a 16pt glyph) —
            // "same place the clear button appears, but a proper size."
            RandomPlayButton(
                size: .icon(dimension: 28, cornerRadius: 14, glyphSize: 13),
                state: $randomState, action: randomizeResults
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(Color(hex: "#06080E").opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(searchFieldFocused == true ? theme.accent : Palette.text(0.16),
                    lineWidth: searchFieldFocused == true ? 2 : 1.5))
        .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
        .animation(.easeOut(duration: 0.18), value: searchFieldFocused)
    }
    #endif

    #if os(iOS)
    private static let actionGlyphSize: CGFloat = 20
    #else
    private static let actionGlyphSize: CGFloat = 26
    #endif

    /// Items in the current (TYPE-filtered, Unwatched-filtered) results that
    /// can start playing on their own with no further fetch — a Movie, an
    /// anime film, or a home video. Fast path: everything here already sits
    /// in memory from the search itself.
    private var playableQueueItems: [PlayableItem] {
        var items: [PlayableItem] = []
        if activeFilter == .all || activeFilter == .movies {
            items += visibleItems(groupedResults.movies).map { $0.asPlayableItem() }
        }
        if activeFilter == .all || activeFilter == .anime {
            items += visibleItems(groupedResults.anime).filter { $0.kind == .movie }.map { $0.asPlayableItem() }
        }
        if activeFilter == .all || activeFilter == .videos {
            items += visibleItems(groupedResults.videos).map { $0.asPlayableItem(hidesTitle: true) }
        }
        return items
    }

    /// The Series hits in view — a TV Show, or an Anime hit that isn't
    /// itself a film. A Series has no video stream of its own to hand
    /// Jellyfin, so it can't join `playableQueueItems` directly; Play/Random
    /// fall back to shuffling one whole show's episodes instead, the same
    /// thing that show's own "Shuffle All" does. Without this fallback,
    /// searching an anime/TV-heavy library — this app's most common search,
    /// arguably — hits the empty state on every press: every result is a
    /// Series and `playableQueueItems` is always empty.
    private var seriesResults: [MediaItem] {
        var items: [MediaItem] = []
        if activeFilter == .all || activeFilter == .shows { items += visibleItems(groupedResults.shows) }
        if activeFilter == .all || activeFilter == .anime { items += visibleItems(groupedResults.anime).filter { $0.kind != .movie } }
        return items
    }

    /// Plays the current results in the order they're shown, starting from
    /// the top — the search-screen equivalent of "tap queues the list you
    /// tapped it from," just starting where the query already put the best
    /// match instead of wherever a finger landed. Falls back to the first
    /// Series result (whole-show shuffle) when nothing is directly playable.
    private func playTopResult() {
        let items = playableQueueItems
        guard !items.isEmpty else {
            playSeriesFallback(pick: { $0.first }, state: $playState)
            return
        }
        appState.requestPlayback(.queue(items, startIndex: 0))
    }

    /// Same rule as every other library screen's Random: reshuffle the
    /// whole scope this screen represents and play it, a fresh order every
    /// press. There's no larger library to reach past here — search results
    /// are already the whole scope — so the reshuffle happens client-side
    /// against what's already in hand rather than a fresh server fetch.
    /// Falls back to a random Series result (whole-show shuffle) when
    /// nothing is directly playable.
    private func randomizeResults() {
        let items = playableQueueItems.shuffled()
        guard !items.isEmpty else {
            playSeriesFallback(pick: { $0.randomElement() }, state: $randomState)
            return
        }
        appState.requestPlayback(.shuffled(items))
    }

    /// Shared by both buttons' series fallback — only the picker (first vs.
    /// random) and which state binding reports progress differ. This is the
    /// one path that needs a network round trip (a show's episode list),
    /// so it's the only place these buttons actually use `.loading`.
    private func playSeriesFallback(pick: ([MediaItem]) -> MediaItem?, state: Binding<RandomPlayState>) {
        guard let series = pick(seriesResults) else {
            state.wrappedValue = .empty
            return
        }
        state.wrappedValue = .loading
        Task {
            guard let request = await appState.shufflePlayRequest(seriesId: series.id, seriesTitle: series.title) else {
                state.wrappedValue = .empty
                return
            }
            state.wrappedValue = .idle
            appState.requestPlayback(request)
        }
    }

    // MARK: - Filter row

    @ViewBuilder
    private var filterRow: some View {
        #if os(iOS)
        if DeviceClass.current == .phone {
            phoneFilterRow
        } else {
            filterChipRow
        }
        #else
        filterChipRow
        #endif
    }

    #if os(iOS)
    /// TYPE becomes the same `Menu` dropdown the other library screens'
    /// Sort/Genre already use (`LibraryDropdownPill`) — it's a single-select
    /// out of a closed list, exactly the shape that pattern was built for.
    /// Unwatched/NSFW are a different shape (two independent booleans, not
    /// a list to pick one item from) and went through two looks before this
    /// one: text-label chips ran the row past a phone's content width
    /// (NSFW cut off at the trailing edge, everything scrollable), so they're
    /// `LibraryIconToggleChip`s instead — the glyph alone, at a fixed 42pt
    /// square, comfortably fits all three controls with room to spare.
    private var phoneFilterRow: some View {
        // Still a `ScrollView`, even though the current three controls fit
        // without it — cheap insurance against a future fourth filter
        // reopening the same overflow this row already hit once.
        // controls (this row was 7 before), and an over-constrained `HStack`
        // doesn't clip what doesn't fit, it *wraps* each chip's text into a
        // vertical column instead (see `filterChipRow`'s identical warning
        // above — this is the same failure mode with a shorter row).
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(SearchFilter.allCases) { filter in
                        Button {
                            activeFilter = filter
                        } label: {
                            if activeFilter == filter {
                                Label(filter.label, systemImage: "checkmark")
                            } else {
                                Text(filter.label)
                            }
                        }
                    }
                } label: {
                    LibraryDropdownPill(icon: "line.3.horizontal.decrease", text: activeFilter.label,
                                         active: true, accent: theme.accent)
                }
                LibraryIconToggleChip(systemImage: "eye.slash.fill", isOn: unwatchedOnly, accent: theme.accent,
                                      action: { unwatchedOnly.toggle() }, accessibilityLabel: "Unwatched only")
                LibraryIconToggleChip(systemImage: "lock.fill", isOn: includeNSFW, accent: Self.nsfwAccent,
                                      action: { includeNSFW.toggle() }, accessibilityLabel: "Include NSFW")
                Spacer(minLength: 0)
            }
        }
    }
    #endif

    // Horizontally scrollable, matching every other library screen's
    // `filterBar` — TYPE (5 chips) + Unwatched + NSFW is 7 chips plus a
    // label and a divider, which a plain non-scrolling `HStack` can't fit at
    // *any* width this app runs at (iPad included, just less obviously: it
    // was already the widest control row in the app before phone existed).
    // Without the `ScrollView`, an over-constrained `HStack` doesn't clip
    // its overflow — it hands each chip's `Text` a near-zero proposed
    // width, and text given less width than one character wraps instead of
    // truncating, which is what turned "Movies"/"Shows"/etc. into vertical
    // one-letter-per-line columns on phone. Phone itself no longer takes
    // this path — see `phoneFilterRow` — this stays the iPad/tvOS chip rail.
    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Text("TYPE")
                    .font(Mono.font(13, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.4))
                ForEach(SearchFilter.allCases) { filter in
                    LibraryFilterChip(label: filter.label, isOn: activeFilter == filter,
                                      action: { activeFilter = filter }, accent: theme.accent)
                }
                Rectangle().fill(Palette.text(0.14)).frame(width: 1, height: 24)
                LibraryFilterChip(label: "Unwatched", isOn: unwatchedOnly, action: { unwatchedOnly.toggle() },
                                  accent: theme.accent, systemImage: "eye.slash.fill")
                LibraryFilterChip(label: "NSFW", isOn: includeNSFW, action: { includeNSFW.toggle() },
                                  accent: Self.nsfwAccent, systemImage: "lock.fill")
            }
        }
    }

    /// A fixed warning-red, not `theme.accent` — this toggle changes what
    /// content is even fetched, and it should read as "you're opting into
    /// something" regardless of which color the user picked in Settings.
    private static let nsfwAccent = Color(hex: "#E8455C")

    /// Blur behind the backdrop, per Settings → Appearance — same rule
    /// `MoviesLibraryView.backdropBlur` uses. tvOS keeps the sharp backdrop
    /// it was designed with.
    private var backdropBlur: Double {
        #if os(iOS)
        theme.libraryBackdropEffect.blurRadius
        #else
        0
        #endif
    }

    /// `unwatchedOnly` is a pure client-side narrowing of whatever the
    /// server already returned — unlike the TYPE row or NSFW (which change
    /// what's fetched), ticking it never re-searches.
    private func visibleItems(_ items: [MediaItem]) -> [MediaItem] {
        unwatchedOnly ? items.filter { !$0.played } : items
    }

    private var filteredCount: Int {
        switch activeFilter {
        case .all: return allVisibleItems.count
        case .movies: return visibleItems(groupedResults.movies).count
        case .shows: return visibleItems(groupedResults.shows).count
        case .anime: return visibleItems(groupedResults.anime).count
        case .videos: return visibleItems(groupedResults.videos).count
        }
    }

    private func showsSection(_ filter: SearchFilter, count: Int) -> Bool {
        (activeFilter == .all || activeFilter == filter) && count > 0
    }

    /// Every item currently on screen across whichever sections the TYPE
    /// and Unwatched filters leave visible — what `selectedItem` (and so the
    /// atmospheric backdrop) is chosen from.
    private var allVisibleItems: [MediaItem] {
        var items: [MediaItem] = []
        if activeFilter == .all || activeFilter == .movies { items += visibleItems(groupedResults.movies) }
        if activeFilter == .all || activeFilter == .shows { items += visibleItems(groupedResults.shows) }
        if activeFilter == .all || activeFilter == .anime { items += visibleItems(groupedResults.anime) }
        if activeFilter == .all || activeFilter == .videos { items += visibleItems(groupedResults.videos) }
        return items
    }

    /// The item behind the atmospheric backdrop — the focused card wins on
    /// tvOS, same "follow the focus" rule `MoviesLibraryView.selectedItem`
    /// uses (a no-op check on iOS, where nothing sets `focusedId`);
    /// otherwise the first result with real art rather than whatever
    /// happened to sort first (an unidentified file with no backdrop would
    /// otherwise leave the screen looking broken).
    private var selectedItem: MediaItem? {
        allVisibleItems.first { $0.id == focusedId }
            ?? allVisibleItems.first { $0.rating != nil && $0.backdropImage != nil }
            ?? allVisibleItems.first { $0.backdropImage != nil }
            ?? allVisibleItems.first
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        if isSearching {
            centered {
                ProgressView().controlSize(.large).tint(theme.accent)
                Text("Searching…")
                    .font(Mono.font(15, .medium)).tracking(1)
                    .foregroundStyle(Palette.text(0.4))
            }
        } else if !hasSearched {
            idleState
        } else if groupedResults.isEmpty {
            centered {
                Text("Nothing matches “\(query)”.")
                    .font(Typography.font(22, .medium))
                    .foregroundStyle(Palette.text(0.45))
                // The single most common reason a real tag/title turns up
                // nothing: adult libraries are excluded until NSFW is on,
                // and that gate fails *silently* otherwise — a zero-result
                // screen that doesn't say why reads as "search is broken."
                if !includeNSFW {
                    Text("Adult libraries are excluded — turn on NSFW to include them.")
                        .font(Typography.font(15, .medium))
                        .foregroundStyle(Palette.text(0.32))
                }
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    if showsSection(.movies, count: visibleItems(groupedResults.movies).count) {
                        section(title: "MOVIES", dot: Self.movieDot, items: visibleItems(groupedResults.movies), bucket: .movies)
                    }
                    if showsSection(.shows, count: visibleItems(groupedResults.shows).count) {
                        section(title: "TV SHOWS", dot: Self.showDot, items: visibleItems(groupedResults.shows), bucket: .shows)
                    }
                    if showsSection(.anime, count: visibleItems(groupedResults.anime).count) {
                        section(title: "ANIME", dot: Self.animeDot, items: visibleItems(groupedResults.anime), bucket: .anime)
                    }
                    if showsSection(.videos, count: visibleItems(groupedResults.videos).count) {
                        videoSection
                    }
                    if activeFilter != .all && filteredCount == 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No matches in this filter.")
                                .font(Typography.font(20, .medium))
                                .foregroundStyle(Palette.text(0.45))
                            Text("Try “All” to see every result for “\(query)”.")
                                .font(Typography.font(15, .medium))
                                .foregroundStyle(Palette.text(0.32))
                        }
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, 6)
                .padding(.bottom, 60)
                // Phone needs more than the standard tab-bar clearance: the
                // floating search field sits *above* the tab bar (86pt up,
                // 48pt tall — see `phoneFloatingSearchField`'s own padding),
                // so the last grid row has to clear that too, or results
                // scroll in behind the field instead of stopping above it.
                #if os(iOS)
                .padding(.bottom, DeviceClass.current == .phone ? 150 : 0)
                #endif
                .phoneTabBarClearance()
            }
        }
    }

    private static let movieDot = Color(hex: "#F0525F")
    private static let showDot = Color(hex: "#4AA8E8")
    private static let animeDot = Color(hex: "#B77EF0")
    private static let videoDot = Color(hex: "#3FBF8F")

    /// Fixed-width columns, as many as fit — a real grid that wraps to new
    /// rows, not a single line you scroll sideways through. A tag search can
    /// come back with dozens of hits in one section; a shelf just hides most
    /// of them behind a horizontal scroll nobody thinks to try.
    ///
    /// Phone drops the fixed max entirely — same 100pt-minimum, flex-to-fill
    /// column `MoviesLibraryView.gridColumns` uses, so Search's own poster
    /// grid lands on the same three-per-row rhythm every other library
    /// screen already does, instead of Search's previously-wider fixed cards
    /// giving two. Video cards keep their own width even on phone: they're
    /// 16:9, and `VideosLibraryView` already made the call that two of those
    /// side by side reads as a grid while three would just be small.
    private static var posterGridColumns: [GridItem] {
        #if os(iOS)
        if DeviceClass.current == .phone {
            return [GridItem(.adaptive(minimum: 100), spacing: 22)]
        }
        #endif
        return [GridItem(.adaptive(minimum: posterCardWidth, maximum: posterCardWidth), spacing: 24)]
    }
    private static let videoGridColumns = [GridItem(.adaptive(minimum: videoCardWidth, maximum: videoCardWidth), spacing: 24)]

    @ViewBuilder
    private func section(title: String, dot: Color, items: [MediaItem], bucket: AppState.SearchGroupKind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHead(title: title, dot: dot, count: items.count)
            LazyVGrid(columns: Self.posterGridColumns, alignment: .leading, spacing: 24) {
                ForEach(items) { item in
                    LibraryPosterCard(item: item, onSelect: { open(item, in: bucket) })
                        .focused($focusedId, equals: item.id)
                }
            }
        }
    }

    @ViewBuilder
    private var videoSection: some View {
        let videos = visibleItems(groupedResults.videos)
        VStack(alignment: .leading, spacing: 14) {
            sectionHead(title: "HOME VIDEOS", dot: Self.videoDot, count: videos.count)
            LazyVGrid(columns: Self.videoGridColumns, alignment: .leading, spacing: 24) {
                ForEach(videos) { item in
                    HomeVideoCard(item: item, onSelect: { open(item, in: .videos) })
                        .focused($focusedId, equals: item.id)
                }
            }
        }
    }

    private func sectionHead(title: String, dot: Color, count: Int) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(title)
                .font(Mono.font(13, .bold)).tracking(2)
                .foregroundStyle(Palette.text(0.55))
            Text("\(count)")
                .font(Mono.font(13, .bold))
                .foregroundStyle(Palette.text(0.35))
        }
    }

    // MARK: - Idle state (recent searches)

    private var idleState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .opacity(0.16)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Palette.text(0.25))
            }
            Text("Search movies, shows, anime, and more")
                .font(Typography.font(22, .medium))
                .foregroundStyle(Palette.text(0.45))
            if !appState.recentSearches.isEmpty {
                VStack(spacing: 12) {
                    Text("RECENT")
                        .font(Mono.font(13, .bold)).tracking(2)
                        .foregroundStyle(Palette.text(0.4))
                    // A `ScrollView`, not a bare `HStack` — enough recent
                    // terms run past a phone's content width with nothing
                    // to scroll, which clipped chips clean off both edges
                    // (a leading "the" and a trailing "ho" that were
                    // actually "The Matrix" and "Robin Hood", just cut).
                    // Harmless on iPad/tvOS, where the row already fit.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(appState.recentSearches, id: \.self) { term in
                                Button { query = term } label: {
                                    Text(term)
                                        .font(Typography.font(15, .bold))
                                        .foregroundStyle(Palette.text(0.78))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 9)
                                        .background(Palette.text(0.06), in: Capsule())
                                        .overlay(Capsule().stroke(Palette.text(0.14), lineWidth: 1.5))
                                }
                                .buttonStyle(FocusScaleStyle(scale: 1.07, cornerRadius: 999))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Phone centers this block in the space below the filter row same as
        // any other platform, but that space now ends above a floating
        // search field instead of at the screen edge — without pulling the
        // centering axis up to match, "RECENT" and its chips land partly
        // behind the field on a short recent-searches list (the case that
        // actually happened: one row of terms, centered into a frame that
        // still assumed the full screen height was free).
        #if os(iOS)
        .padding(.bottom, DeviceClass.current == .phone ? 150 : 0)
        #endif
        // tvOS only: the recent-search row sits ~600pt below the TYPE chips,
        // centered under the idle illustration rather than left-aligned
        // under them — most starting columns (anything left of NSFW) are too
        // far off-axis for the plain nearest-neighbor heuristic to find it,
        // so Down did nothing at all. Wrapping just the row in its own
        // `.focusSection()` wasn't enough (its bounding box is still that
        // same narrow, off-center capsule); the section has to span this
        // whole centered block so its box overlaps the TYPE row above across
        // the full width. Same fix, same reasoning, as the Settings detail
        // pane's own `.focusSection()`: bundle the region into one entry
        // point instead of raycasting to a specific chip.
        #if os(tvOS)
        .focusSection()
        #endif
    }

    // MARK: - Opening a result

    /// A show hit is built the same bare-plus-real-fields way every other
    /// library screen builds one (`ShowsLibraryView.baseShow(for:)`) — no
    /// shared helper between them, same as the rest of this app's per-screen
    /// duplication for a ten-line adapter.
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

    /// A result opens the way it would from its own library screen: a series
    /// (including an anime series) opens its show screen — there's no single
    /// video stream to hand Jellyfin, so it needs the episode picker either
    /// way. A movie, an anime film, or a home video plays directly, queuing
    /// the rest of *this same bucket's* visible results behind it, same "tap
    /// queues the list you tapped it from" rule every other screen follows —
    /// NEXT in the player then walks the rest of the search results in the
    /// order they're shown here, not just within whichever library the movie
    /// happened to live in.
    ///
    /// **iPad/tvOS keep the movie dossier instead** (Anime's own film case
    /// too) — phone made this change specifically to give the tap the job
    /// its now-removed Play button used to do (see `MoviesLibraryView`'s
    /// phone header), but iPad/tvOS never lost that button, so a tap there
    /// still means "tell me about this" rather than "play it," same as it
    /// always has.
    /// From inside a movie page — "More like this" or a person's credits —
    /// where there is no search bucket to speak of: a film opens as a film, a
    /// show as a show, both from the bare item (the page fetches its own
    /// detail on appear).
    private func openFromDetail(_ item: MediaItem) {
        switch item.kind {
        case .movie: presentedMovie = SampleCatalog.movie(for: item)
        case .series: presentedShow = baseShow(for: item)
        }
    }

    private func open(_ item: MediaItem, in bucket: AppState.SearchGroupKind) {
        switch bucket {
        case .movies:
            #if os(iOS)
            if DeviceClass.current == .phone {
                playDirectly(item, from: visibleItems(groupedResults.movies))
                return
            }
            #endif
            Task {
                guard let movie = await appState.movieDetail(for: item.id) else { return }
                presentedMovie = movie
            }
        case .anime:
            if item.kind == .movie {
                #if os(iOS)
                if DeviceClass.current == .phone {
                    let films = visibleItems(groupedResults.anime).filter { $0.kind == .movie }
                    playDirectly(item, from: films)
                    return
                }
                #endif
                Task {
                    guard let movie = await appState.movieDetail(for: item.id) else { return }
                    presentedMovie = movie
                }
            } else {
                presentedShow = baseShow(for: item)
            }
        case .shows:
            presentedShow = baseShow(for: item)
        case .videos:
            playDirectly(item, from: visibleItems(groupedResults.videos), hidesTitle: true)
        }
    }

    /// Shared by every directly-playable bucket (Movies, Anime's film case,
    /// Home Videos): queue `items` in the order they're on screen and start
    /// at whichever one was tapped, so NEXT/PREV walk the rest of that same
    /// bucket's results — never a mix of buckets, since a movie and a home
    /// video queued together would put a random camcorder clip after a film.
    private func playDirectly(_ item: MediaItem, from items: [MediaItem], hidesTitle: Bool = false) {
        guard let request = appState.listQueueRequest(items, startingAt: item.id, hidesTitle: hidesTitle) else { return }
        appState.requestPlayback(request)
    }

    @ViewBuilder
    private func centered<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 14) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The four TYPE chips on the Search screen — `.all` plus one per group in
/// `AppState.SearchGroupKind`. A separate, UI-only enum: the fetch layer has
/// no "all" bucket of its own, only real content groups. Not `private`:
/// `AppState` persists a user's choice of this alongside the Unwatched/NSFW
/// toggles, so it needs to be nameable from outside this file.
enum SearchFilter: String, CaseIterable, Identifiable {
    case all, movies, shows, anime, videos

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .shows: return "Shows"
        case .anime: return "Anime"
        case .videos: return "Home Videos"
        }
    }
}

/// The Search screen's own hero field — deliberately not `AppTextField` at
/// its usual size: this field IS the screen ("wire it, make it bigger and
/// bolder — it's the center of the feature"), so it gets a wider dark
/// rounded-rect and heavier type on both platforms, plus tvOS's full
/// `LEDRing` focus treatment.
///
/// **No resting glow on tvOS** — this app's own house rule (`FocusScaleStyle`,
/// `LEDRing`) is that a glow at rest has nothing left to say once focus
/// arrives. Boldness at rest comes from size and weight alone; the `LEDRing`
/// every other tvOS focal control uses is what lights up, only on focus.
/// iOS has no such "resting" state to protect — a real `TextField` there
/// gets a plain accent-stroke-plus-soft-bloom on `.focused`, only while
/// actually being edited.
///
/// iOS uses a native `TextField` directly; tvOS reuses `TVTextField` — the
/// same invisible-UIKit-field-behind-a-focusable-button bridge
/// `AppTextField`/`TagSearchField` use, because that part is worth not
/// re-deriving: a directly-focused tvOS `TextField` paints an unremovable
/// white pill and won't reliably raise the keyboard for an off-screen field.
private struct SearchHeroField<F: Hashable>: View {
    let placeholder: String
    @Binding var text: String
    let accent: Color
    let field: F
    var focus: FocusState<F?>.Binding
    var onSubmit: () -> Void = {}

    @State private var editing = false

    // `fileprivate`, not `private`: `SearchLibraryView`'s Play/Random icon
    // buttons size themselves to match this field's height/corner radius
    // exactly, so the row reads as one control cluster.
    #if os(iOS)
    fileprivate static var height: CGFloat { 64 }
    fileprivate static var cornerRadius: CGFloat { 18 }
    #else
    fileprivate static var height: CGFloat { 92 }
    fileprivate static var cornerRadius: CGFloat { 22 }
    #endif

    private var isFocused: Bool { focus.wrappedValue == field }
    #if os(tvOS)
    private var active: Bool { isFocused || editing }
    #else
    private var active: Bool { isFocused }
    #endif
    private var isEmpty: Bool { text.isEmpty }
    private var displayText: String { isEmpty ? placeholder : text }
    private var fill: Color { .white.opacity(active ? 0.09 : 0.05) }

    var body: some View {
        #if os(iOS)
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.text(0.5))
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.text(0.34)))
                .font(Typography.font(24, .heavy))
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focus, equals: field)
                .onSubmit(onSubmit)
            if !isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.text(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .stroke(active ? accent : Palette.text(0.14), lineWidth: active ? 2 : 1.5))
        .shadow(color: accent.opacity(active ? 0.30 : 0), radius: active ? 16 : 0)
        .animation(.easeOut(duration: 0.18), value: active)
        #else
        ZStack {
            if active {
                TVTextField(text: $text, isSecure: false, isEditing: $editing, onSubmit: onSubmit)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.height)
                    .opacity(0.02)
            }

            Button { editing = true } label: {
                HStack(spacing: 18) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Palette.text(0.5))
                    Text(displayText)
                        .font(Typography.font(32, .heavy))
                        .foregroundStyle(isEmpty ? Palette.text(0.34) : Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 30)
                .frame(height: Self.height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .stroke(active ? .clear : .white.opacity(0.16), lineWidth: 1.5))
                .overlay {
                    if active {
                        LEDRing(cornerRadius: Self.cornerRadius + 4, accent: accent)
                            .padding(-4)
                            .transition(.opacity)
                    }
                }
                .shadow(color: accent.opacity(active ? 0.7 : 0), radius: active ? 42 : 0)
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .animation(.spring(response: 0.26, dampingFraction: 0.6), value: active)
            }
            .buttonStyle(AppTextFieldButtonStyle())
            .focused(focus, equals: field)
        }
        .onChange(of: editing) {
            if !editing { focus.wrappedValue = field }
        }
        .frame(height: Self.height)
        #endif
    }
}
