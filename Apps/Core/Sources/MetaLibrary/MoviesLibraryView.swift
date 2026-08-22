import SwiftUI
import JellyTVKit

/// The Movies library screen (design 4a): rail + search/Play/Random header,
/// sort/genre filter chips, a "currently selected" band that tracks grid
/// focus, and a poster grid for the whole library. Shows a loading state
/// while the server's movies load — never sample data standing in for the
/// real grid.
struct MoviesLibraryView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    // tvOS has a 1080pt-tall canvas to spare above the poster grid. An iPad
    // landscape window doesn't, so the header/filters/selected-band block is
    // compacted for iOS rather than eating most of the screen before any
    // posters appear — matching the same treatment Home's hero zone got.
    #if os(iOS)
    private static let headerSpacing: CGFloat = 12
    private static let headerTopPadding: CGFloat = 12
    #else
    private static let headerSpacing: CGFloat = 22
    private static let headerTopPadding: CGFloat = 40
    #endif

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
    @State private var presentedMovie: Movie?
    /// Real detail (cast, ratings, tagline, awards) fetched for the selected
    /// item; shown in place of the sample fallback once it arrives.
    @State private var selectedDetail: Movie?
    @FocusState private var focusedId: String?
    @FocusState private var searchFocused: Bool?

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

    /// Closes the Libraries submenu first (if open), then the detail cover,
    /// then falls back to leaving the screen entirely.
    private var exitAction: (() -> Void)? {
        if isLibrariesOpen { return { onSelectRail(.libraries) } }
        if presentedMovie != nil { return nil }
        return { onSelectRail(.home) }
    }

    var body: some View {
        ZStack {
            background
            // The focused movie's backdrop: a full-screen layer pinned to the
            // top, behind the rail and the scrolling content, the same way
            // HomeView's hero backdrop covers the top of the screen and
            // dissolves into the page over the rows below.
            if let selectedItem {
                SelectedBackdrop(item: selectedItem)
            }
            HStack(spacing: 0) {
                NavRail(destination: .movies, isLibrariesOpen: isLibrariesOpen, onSelect: onSelectRail)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems()) {
                    // Header, filters and the selected-movie band stay pinned; only
                    // the poster catalog scrolls beneath them.
                    VStack(alignment: .leading, spacing: Self.headerSpacing) {
                        header.padding(.horizontal, 48)
                        filterBar.padding(.horizontal, 48)
                        if let dossierMovie {
                            SelectedMovieBand(movie: dossierMovie, isLoading: isDossierLoading)
                        }
                        if !hasLoadedMovies {
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
            // See `HomeView`'s matching `.disabled` for why: `presentedMovie`
            // is a same-ZStack overlay, not a modal, so without this the
            // rail stays focus-reachable underneath it.
            .disabled(presentedMovie != nil)

            if let presentedMovie {
                MovieDetailView(movie: presentedMovie, onDismiss: { self.presentedMovie = nil })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.25), value: presentedMovie)
        // Focus the search field on appear (a top control) rather than the
        // first poster — focusing a poster makes tvOS auto-scroll it into
        // place, which pushes the header/search off the top of the screen.
        // The band still shows the first movie (selectedItem falls back to
        // `filtered.first` when no poster is focused).
        .defaultFocus($searchFocused, true)
        // `appState.libraries.count` is part of the task id (not just `sort`)
        // so this re-fires once the server connection finishes configuring —
        // otherwise a view that appears before `AppState.refresh()` completes
        // (e.g. landing straight on Movies) would fetch once with no client
        // yet, get back `[]`, and never retry until the user touches a chip.
        .task(id: "\(sort.rawValue)-\(appState.libraries.count)") {
            let query = sort.query
            movies = await appState.loadMovies(sortBy: query.sortBy, sortOrder: query.sortOrder)
            hasLoadedMovies = true
        }
        // Fetch rich detail (cast/ratings/tagline/awards) for the selected item.
        .task(id: selectedItem?.id) { await loadSelectedDetail() }
        #if os(tvOS)
        .onExitCommand(perform: exitAction)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIBRARY // MOVIES")
                    .font(Mono.font(15, .bold))
                    .tracking(2.6)
                    .foregroundStyle(Palette.text(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Movies")
                        .font(Typography.font(34, .black))
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(allMovies.count) titles")
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
        TagSearchField(tags: $searchTags, liveText: $searchText, placeholder: "Search movies…",
                       accent: theme.secondaryAccent, trailing: "\(filtered.count)",
                       field: true, focus: $searchFocused)
    }

    private func randomize() {
        guard let item = filtered.randomElement() else { return }
        focusedId = item.id
    }

    // MARK: - Filters

    private var filterBar: some View {
        // A plain (non-scrolling) HStack here works fine on tvOS's 1920pt-wide
        // canvas but squeeze-wraps every chip's label to two lines on an
        // iPad's narrower width — scrolling instead of squeezing keeps every
        // chip a single line regardless of how many sort/genre options exist.
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
    /// never the sample catalog standing in for real movies.
    private var loadingGrid: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(theme.accent)
            Text("Loading movies…")
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
                Text("Showing \(filtered.count) of \(allMovies.count)")
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(Palette.text(0.4))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 210), spacing: 22)], spacing: 26) {
                ForEach(filtered) { item in
                    LibraryPosterCard(item: item, onSelect: { openMovie(item) })
                        .focused($focusedId, equals: item.id)
                }
            }
        }
    }

    private var sectionCaption: String {
        let genrePart = selectedGenre?.uppercased() ?? "ALL MOVIES"
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

/// The "currently selected" text band: the focused movie's title / meta /
/// synopsis on the left and a "Signal Dossier" info panel on the right
/// (design 4a), laid over the top of `SelectedBackdrop`. Rich fields (rating,
/// director, cast) come from `SampleCatalog.movie(for:)` — the same
/// demo-template seam Home's Recommended row uses to open a detail screen.
private struct SelectedMovieBand: View {
    let movie: Movie
    var isLoading: Bool = false

    @EnvironmentObject private var theme: Theme

    // Shorter, narrower-padded, and top-aligned on iOS: a single-line title
    // and a wider-but-shorter dossier panel (`StatsCastPanel`'s iOS size)
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
                StatsCastPanel(movie: movie, isLoading: isLoading, accent: theme.accent)
                #if os(tvOS)
                MetaPanel(movie: movie, isLoading: isLoading, accent: theme.accent)
                #endif
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height, alignment: Self.frameAlignment)
        .id(movie.id)
        .transition(.opacity)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Self.infoSpacing) {
            Text("SELECTED // NOW IN YOUR LIBRARY")
                .font(Mono.font(14, .bold))
                .tracking(3)
                .foregroundStyle(theme.accent)

            Text(movie.title)
                .font(Typography.font(Self.titleFontSize, .black))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(Self.titleLineLimit)
                .minimumScaleFactor(0.5)
                .lineSpacing(-6)

            HStack(spacing: 12) {
                Text("★ \(movie.rating)")
                    .fontWeight(.heavy)
                    .foregroundStyle(theme.accent)
                Text(movie.certification)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.text(0.3), lineWidth: 1.5))
                Text(movie.year)
                dot
                Text(genreTail)
                if !movie.runtime.isEmpty {
                    dot
                    Text(movie.runtime)
                }
            }
            .font(Typography.font(19, .semibold))
            .foregroundStyle(Palette.text(0.68))

            Text(movie.synopsis)
                .font(Typography.font(20, .medium))
                .foregroundStyle(Palette.text(0.7))
                .lineLimit(3)
                .lineSpacing(6)
                .frame(maxWidth: Self.synopsisMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: Self.infoMaxWidth, alignment: .leading)
    }

    private var genreTail: String {
        movie.genreLabel.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? movie.genreLabel
    }

    private var dot: some View { Text("·").foregroundStyle(Palette.text(0.4)) }
}
