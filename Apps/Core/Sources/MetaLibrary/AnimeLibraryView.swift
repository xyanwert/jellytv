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

    // See `MoviesLibraryView`'s identical constants/comment.
    #if os(iOS)
    private static let headerSpacing: CGFloat = 12
    private static let headerTopPadding: CGFloat = 12
    #else
    private static let headerSpacing: CGFloat = 22
    private static let headerTopPadding: CGFloat = 40
    #endif

    @EnvironmentObject private var appState: AppState

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
    @State private var presentedMovie: Movie?
    @State private var presentedShow: Show?
    @State private var selectedMovieDetail: Movie?
    @State private var selectedShowDetail: Show?
    @FocusState private var focusedId: String?
    @FocusState private var searchFocused: Bool?

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

    private var selectedItem: MediaItem? {
        filtered.first { $0.id == focusedId }
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
            if let selectedItem {
                SelectedBackdrop(item: selectedItem)
            }
            HStack(spacing: 0) {
                NavRail(destination: .animeLibrary, isLibrariesOpen: isLibrariesOpen,
                        onSelect: onSelectRail, accentOverride: Self.accent)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems()) {
                    VStack(alignment: .leading, spacing: Self.headerSpacing) {
                        header.padding(.horizontal, 48)
                        filterBar.padding(.horizontal, 48)
                        selectedBand
                        if !hasLoaded {
                            loadingGrid
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                postersSection
                                    .padding(.horizontal, 48)
                                    .padding(.top, 6)
                                    .padding(.bottom, 60)
                            }
                        }
                    }
                    .padding(.top, Self.headerTopPadding)
                }
            }
            .ignoresSafeArea()
            // See `HomeView`'s matching `.disabled` for why: `presentedMovie`/
            // `presentedShow` are same-ZStack overlays, not modals, so
            // without this the rail stays focus-reachable underneath them.
            .disabled(presentedMovie != nil || presentedShow != nil)

            if let presentedMovie {
                MovieDetailView(movie: presentedMovie, onDismiss: { self.presentedMovie = nil })
                    .transition(.opacity)
                    .zIndex(2)
            }
            if let presentedShow {
                ShowView(show: presentedShow, onDismiss: { self.presentedShow = nil })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.25), value: presentedMovie)
        .animation(.easeOut(duration: 0.25), value: presentedShow)
        .defaultFocus($searchFocused, true)
        // `appState.libraries.count` is part of the task id so this re-fires
        // once the server connection finishes configuring — see
        // `MoviesLibraryView`'s identical reasoning.
        .task(id: "\(sort.rawValue)-\(appState.libraries.count)") {
            let query = sort.query
            async let movies = appState.loadAnimeMovies(sortBy: query.sortBy, sortOrder: query.sortOrder)
            async let shows = appState.loadAnimeShows(sortBy: query.sortBy, sortOrder: query.sortOrder)
            items = await movies + shows
            hasLoaded = true
        }
        .task(id: selectedItem?.id) { await loadSelectedDetail() }
        #if os(tvOS)
        .onExitCommand(perform: exitAction)
        #endif
    }

    @ViewBuilder private var selectedBand: some View {
        if let item = selectedItem {
            switch item.kind {
            case .movie:
                let movie = (selectedMovieDetail?.id == item.id) ? selectedMovieDetail! : baseMovie(for: item)
                AnimeMovieBand(movie: movie, isLoading: isDossierLoading)
            case .series:
                let show = (selectedShowDetail?.id == item.id) ? selectedShowDetail! : baseShow(for: item)
                AnimeShowBand(show: show, isLoading: isDossierLoading)
            }
        }
    }

    // MARK: - Header

    /// The busy backdrop art behind this row (`SelectedBackdrop`'s top-darken
    /// scrim alone isn't enough contrast for the search field's subtle fill)
    /// gets its own translucent-blur backing here, same idiom as the rail's
    /// `LibrariesSubmenu` panel — material + a dark tint, not material alone.
    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIBRARY // ANIME")
                    .font(Mono.font(15, .bold))
                    .tracking(2.6)
                    .foregroundStyle(Palette.text(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Anime")
                        .font(Typography.font(34, .black))
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(allItems.count) titles")
                        .font(Typography.font(20, .semibold))
                        .foregroundStyle(Palette.text(0.4))
                    Text("アニメ")
                        .font(Mono.font(16, .bold))
                        .tracking(1.5)
                        .foregroundStyle(Self.accent)
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
                .background(Self.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Self.accent.opacity(0.4), radius: 16, y: 4)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: "#0B0E16").opacity(0.45))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.text(0.08), lineWidth: 1))
    }

    private var searchField: some View {
        TagSearchField(tags: $searchTags, liveText: $searchText, placeholder: "Search anime, studios, seiyuu…",
                       accent: Self.accent, trailing: "\(filtered.count)",
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

    private var loadingGrid: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Self.accent)
            Text("Loading anime…")
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
                Text("Showing \(filtered.count) of \(allItems.count)")
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(Palette.text(0.4))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 210), spacing: 22)], spacing: 26) {
                ForEach(filtered) { item in
                    LibraryPosterCard(item: item, onSelect: { openItem(item) })
                        .focused($focusedId, equals: item.id)
                }
            }
        }
    }

    private var sectionCaption: String {
        let genrePart = selectedGenre?.uppercased() ?? "ALL ANIME"
        return "\(genrePart) · \(sort.rawValue.uppercased())"
    }

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

/// The vertical Japanese watermark between the info block and the dossier
/// panel (design 4b's "サクラ鎮魂歌 · 劇場版" signature). The design's version
/// is a per-film Japanese title — no real source for that exists (Jellyfin
/// doesn't carry a per-title Japanese name here), so this stays the fixed
/// category label ("アニメ") already used elsewhere on this screen, stacked
/// character-by-character to read top-to-bottom like the design's vertical
/// type, rather than inventing a translation of whatever's selected.
private struct KatakanaSignature: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array("アニメ".enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(Mono.font(22, .bold))
            }
        }
        .tracking(2)
        .foregroundStyle(AnimeLibraryView.accent.opacity(0.7))
        // A plain low-opacity glyph over arbitrary backdrop art is only
        // legible by luck (it read fine over a dark region, vanished over a
        // light one) — the same lesson as the header row: give it its own
        // fixed contrast (shadow + a soft dark backing) instead of
        // depending on whatever happens to be behind it.
        .shadow(color: .black.opacity(0.8), radius: 5)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize()
    }
}

/// The "currently selected" band for an anime film (design 4b): the same
/// composition as `MoviesLibraryView`'s `SelectedMovieBand`, recolored to the
/// anime accent with the cast panel relabeled "SEIYUU" (the same real
/// Jellyfin cast data — an accurate label for voice-acted content, not a
/// different data source).
private struct AnimeMovieBand: View {
    let movie: Movie
    var isLoading: Bool = false

    // See `MoviesLibraryView.SelectedMovieBand`'s identical comment. Slightly
    // tighter numbers than that band's (narrower padding, smaller inter-item
    // spacing, narrower info column) since this band also carries the
    // `KatakanaSignature` between info and the dossier panel.
    #if os(iOS)
    private static let height: CGFloat = 300
    private static let horizontalPadding: CGFloat = 56
    private static let itemSpacing: CGFloat = 24
    private static let bandAlignment: VerticalAlignment = .top
    private static let frameAlignment: Alignment = .top
    private static let infoSpacing: CGFloat = 10
    private static let titleFontSize: CGFloat = 44
    private static let titleLineLimit = 1
    private static let infoMaxWidth: CGFloat = 520
    private static let synopsisMaxWidth: CGFloat = 520
    #else
    private static let height: CGFloat = 536
    private static let horizontalPadding: CGFloat = 100
    private static let itemSpacing: CGFloat = 32
    private static let bandAlignment: VerticalAlignment = .center
    private static let frameAlignment: Alignment = .center
    private static let infoSpacing: CGFloat = 16
    private static let titleFontSize: CGFloat = 72
    private static let titleLineLimit = 2
    private static let infoMaxWidth: CGFloat = 720
    private static let synopsisMaxWidth: CGFloat = 620
    #endif

    var body: some View {
        HStack(alignment: Self.bandAlignment, spacing: Self.itemSpacing) {
            info
            Spacer(minLength: 8)
            KatakanaSignature()
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 16) {
                StatsCastPanel(movie: movie, isLoading: isLoading, accent: AnimeLibraryView.accent,
                               dossierLabel: "STUDIO DOSSIER", castLabel: "SEIYUU")
                #if os(tvOS)
                MetaPanel(movie: movie, isLoading: isLoading, accent: AnimeLibraryView.accent)
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
                .foregroundStyle(AnimeLibraryView.accent)

            Text(movie.title)
                .font(Typography.font(Self.titleFontSize, .black))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(Self.titleLineLimit)
                .minimumScaleFactor(0.5)
                .lineSpacing(-6)

            HStack(spacing: 12) {
                Text("★ \(movie.rating)")
                    .fontWeight(.heavy)
                    .foregroundStyle(AnimeLibraryView.accent)
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

/// The "currently selected" band for an anime series (design 4b): the same
/// composition as `ShowsLibraryView`'s `SelectedShowBand`, recolored to the
/// anime accent with the cast panel relabeled "SEIYUU".
private struct AnimeShowBand: View {
    let show: Show
    var isLoading: Bool = false

    // See `AnimeMovieBand`'s identical comment.
    #if os(iOS)
    private static let height: CGFloat = 300
    private static let horizontalPadding: CGFloat = 56
    private static let itemSpacing: CGFloat = 24
    private static let bandAlignment: VerticalAlignment = .top
    private static let frameAlignment: Alignment = .top
    private static let infoSpacing: CGFloat = 10
    private static let titleFontSize: CGFloat = 44
    private static let titleLineLimit = 1
    private static let infoMaxWidth: CGFloat = 520
    private static let synopsisMaxWidth: CGFloat = 520
    #else
    private static let height: CGFloat = 536
    private static let horizontalPadding: CGFloat = 100
    private static let itemSpacing: CGFloat = 32
    private static let bandAlignment: VerticalAlignment = .center
    private static let frameAlignment: Alignment = .center
    private static let infoSpacing: CGFloat = 16
    private static let titleFontSize: CGFloat = 72
    private static let titleLineLimit = 2
    private static let infoMaxWidth: CGFloat = 720
    private static let synopsisMaxWidth: CGFloat = 620
    #endif

    var body: some View {
        HStack(alignment: Self.bandAlignment, spacing: Self.itemSpacing) {
            info
            Spacer(minLength: 8)
            KatakanaSignature()
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 16) {
                ShowStatsCastPanel(show: show, isLoading: isLoading, accent: AnimeLibraryView.accent, castLabel: "SEIYUU")
                #if os(tvOS)
                ShowMetaPanel(show: show, isLoading: isLoading, accent: AnimeLibraryView.accent)
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
                .foregroundStyle(AnimeLibraryView.accent)

            Text(show.title)
                .font(Typography.font(Self.titleFontSize, .black))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(Self.titleLineLimit)
                .minimumScaleFactor(0.5)
                .lineSpacing(-6)

            HStack(spacing: 12) {
                Text("★ \(show.rating)")
                    .fontWeight(.heavy)
                    .foregroundStyle(AnimeLibraryView.accent)
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
