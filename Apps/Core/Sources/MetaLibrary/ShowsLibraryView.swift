import SwiftUI
import JellyTVKit

/// The TV Shows library screen: rail + search/Play/Random header, sort/genre
/// filter chips, a "currently selected" band that tracks grid focus, and a
/// poster grid for the whole library. A structural sibling of
/// `MoviesLibraryView` (shared chrome lives in `LibraryComponents.swift`);
/// its own dossier panels (`ShowStatsCastPanel`/`ShowMetaPanel`) swap in
/// network branding and season/year/critics in place of the movie dossier's
/// stat boxes and director/studio/runtime rows. Shows a loading state while
/// the server's shows load — never sample data standing in for the real grid.
struct ShowsLibraryView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    // See `MoviesLibraryView`'s identical constants/comment.
    #if os(iOS)
    private static let headerSpacing: CGFloat = 12
    private static let headerTopPadding: CGFloat = 12
    #else
    private static let headerSpacing: CGFloat = 22
    private static let headerTopPadding: CGFloat = 40
    #endif

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
    @State private var presentedShow: Show?
    /// Real detail (cast, ratings, season count, network) fetched for the
    /// selected item; shown in place of the sample fallback once it arrives.
    @State private var selectedDetail: Show?
    @FocusState private var focusedId: String?
    @FocusState private var searchFocused: Bool?

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

    private var selectedItem: MediaItem? {
        // A focused poster wins. Otherwise (initial state, nothing focused)
        // feature the first item that actually has backdrop art rather than
        // `filtered.first` — the newest item is often an unidentified file
        // with no artwork, which would leave the big backdrop blank.
        filtered.first { $0.id == focusedId }
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
            if let selectedItem {
                SelectedBackdrop(item: selectedItem)
            }
            HStack(spacing: 0) {
                NavRail(destination: .tv, isLibrariesOpen: isLibrariesOpen, onSelect: onSelectRail)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems()) {
                    // Header, filters and the selected-show band stay pinned; only
                    // the poster catalog scrolls beneath them.
                    VStack(alignment: .leading, spacing: Self.headerSpacing) {
                        header.padding(.horizontal, 48)
                        filterBar.padding(.horizontal, 48)
                        if let dossierShow {
                            SelectedShowBand(show: dossierShow, isLoading: isDossierLoading)
                        }
                        if !hasLoadedShows {
                            loadingGrid
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                postersSection
                                    .padding(.horizontal, 48)
                                    .padding(.top, 6)   // room for the top row's focus glow
                                    .padding(.bottom, 60)
                            }
                        }
                    }
                    .padding(.top, Self.headerTopPadding)
                }
            }
            .ignoresSafeArea()
            // See `HomeView`'s matching `.disabled` for why: `presentedShow`
            // is a same-ZStack overlay, not a modal, so without this the
            // rail stays focus-reachable underneath it.
            .disabled(presentedShow != nil)

            if let presentedShow {
                ShowView(show: presentedShow, onDismiss: { self.presentedShow = nil })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.25), value: presentedShow)
        // Focus the search field on appear (a top control) rather than the
        // first poster — focusing a poster makes tvOS auto-scroll it into
        // place, which pushes the header/search off the top of the screen.
        .defaultFocus($searchFocused, true)
        // `appState.libraries.count` is part of the task id (not just `sort`)
        // so this re-fires once the server connection finishes configuring —
        // otherwise a view that appears before `AppState.refresh()` completes
        // would fetch once with no client yet, get back `[]`, and never retry
        // until the user touches a chip.
        .task(id: "\(sort.rawValue)-\(appState.libraries.count)") {
            let query = sort.query
            shows = await appState.loadShows(sortBy: query.sortBy, sortOrder: query.sortOrder)
            hasLoadedShows = true
        }
        // Fetch rich detail (cast/season count/network) for the selected item.
        .task(id: selectedItem?.id) { await loadSelectedDetail() }
        #if os(tvOS)
        .onExitCommand(perform: exitAction)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIBRARY // TV SHOWS")
                    .font(Mono.font(15, .bold))
                    .tracking(2.6)
                    .foregroundStyle(Palette.text(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("TV Shows")
                        .font(Typography.font(34, .black))
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(allShows.count) titles")
                        .font(Typography.font(20, .semibold))
                        .foregroundStyle(Palette.text(0.4))
                }
            }
            .fixedSize()

            searchField

            Button {} label: {
                HStack(spacing: 11) {
                    Image(systemName: "play.fill").font(.system(size: 18))
                    Text("Play")
                }
                .font(Typography.button)
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 15)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: theme.accent.opacity(0.4), radius: 16, y: 4)
            }
            .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 14))

            Button(action: randomize) {
                HStack(spacing: 10) {
                    Image(systemName: "shuffle").font(.system(size: 18, weight: .semibold))
                    Text("Random")
                }
                .font(Typography.button)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 15)
                .background(Palette.text(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.2), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 14))
        }
    }

    private var searchField: some View {
        TagSearchField(tags: $searchTags, liveText: $searchText, placeholder: "Search TV shows…",
                       accent: theme.secondaryAccent, trailing: "\(filtered.count)",
                       field: true, focus: $searchFocused)
    }

    private func randomize() {
        guard let item = filtered.randomElement() else { return }
        focusedId = item.id
    }

    // MARK: - Filters

    private var filterBar: some View {
        // Scrolling instead of a plain (non-scrolling) HStack keeps every
        // chip a single line on an iPad's narrower width instead of
        // squeeze-wrapping — see `MoviesLibraryView`'s identical comment.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Text("FILTER")
                    .font(Mono.font(13, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.4))
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

    /// Shown in place of the grid until the first real fetch resolves —
    /// never the sample catalog standing in for real shows.
    private var loadingGrid: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(theme.accent)
            Text("Loading TV shows…")
                .font(Mono.font(15, .medium)).tracking(1)
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 140)
    }

    private var postersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 210), spacing: 22)], spacing: 26) {
                ForEach(filtered) { item in
                    LibraryPosterCard(item: item, onSelect: { openShow(item) })
                        .focused($focusedId, equals: item.id)
                }
            }
        }
    }

    private var sectionCaption: String {
        let genrePart = selectedGenre?.uppercased() ?? "ALL TV SHOWS"
        return "\(genrePart) · \(sort.rawValue.uppercased())"
    }

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

/// The "currently selected" text band: the focused show's title / meta /
/// synopsis on the left and the TV "Signal Dossier" info panel on the right,
/// laid over the top of `SelectedBackdrop`. Rich fields (rating, cast, network)
/// come from `SampleCatalog.show(for:)` — the same demo-template seam the
/// Movies band uses.
private struct SelectedShowBand: View {
    let show: Show
    var isLoading: Bool = false

    @EnvironmentObject private var theme: Theme

    // Shorter, narrower-padded, and top-aligned on iOS: a single-line title
    // and a wider-but-shorter dossier panel (`ShowStatsCastPanel`'s iOS size)
    // need much less vertical room than tvOS's centered, two-line-title
    // layout — pulling everything to the top of a shorter band (rather than
    // centering it in a still-tall one) removes the dead space that used to
    // sit between the synopsis and the poster grid below.
    #if os(iOS)
    private static let height: CGFloat = 300
    private static let horizontalPadding: CGFloat = 64
    private static let bandAlignment: VerticalAlignment = .top
    private static let frameAlignment: Alignment = .top
    private static let infoSpacing: CGFloat = 10
    private static let titleFontSize: CGFloat = 44
    private static let titleLineLimit = 1
    private static let infoMaxWidth: CGFloat = 560
    private static let synopsisMaxWidth: CGFloat = 560
    #else
    private static let height: CGFloat = 536
    private static let horizontalPadding: CGFloat = 100
    private static let bandAlignment: VerticalAlignment = .center
    private static let frameAlignment: Alignment = .center
    private static let infoSpacing: CGFloat = 16
    private static let titleFontSize: CGFloat = 72
    private static let titleLineLimit = 2
    private static let infoMaxWidth: CGFloat = 720
    private static let synopsisMaxWidth: CGFloat = 620
    #endif

    var body: some View {
        HStack(alignment: Self.bandAlignment, spacing: 40) {
            info
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 16) {
                ShowStatsCastPanel(show: show, isLoading: isLoading, accent: theme.accent)
                #if os(tvOS)
                ShowMetaPanel(show: show, isLoading: isLoading, accent: theme.accent)
                #endif
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height, alignment: Self.frameAlignment)
        .id(show.id)
        .transition(.opacity)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Self.infoSpacing) {
            Text("SELECTED // NOW IN YOUR LIBRARY")
                .font(Mono.font(14, .bold))
                .tracking(3)
                .foregroundStyle(theme.accent)

            Text(show.title)
                .font(Typography.font(Self.titleFontSize, .black))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(Self.titleLineLimit)
                .minimumScaleFactor(0.5)
                .lineSpacing(-6)

            HStack(spacing: 12) {
                Text("★ \(show.rating)")
                    .fontWeight(.heavy)
                    .foregroundStyle(theme.accent)
                Text(show.certification)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.text(0.3), lineWidth: 1.5))
                Text(show.years)
                dot
                Text(genreTail)
            }
            .font(Typography.font(19, .semibold))
            .foregroundStyle(Palette.text(0.68))

            Text(show.synopsis)
                .font(Typography.font(20, .medium))
                .foregroundStyle(Palette.text(0.7))
                .lineLimit(3)
                .lineSpacing(6)
                .frame(maxWidth: Self.synopsisMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: Self.infoMaxWidth, alignment: .leading)
    }

    private var genreTail: String {
        show.genreLabel.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? show.genreLabel
    }

    private var dot: some View { Text("·").foregroundStyle(Palette.text(0.4)) }
}
