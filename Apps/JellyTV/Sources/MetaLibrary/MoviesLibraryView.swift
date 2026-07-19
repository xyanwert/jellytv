import SwiftUI
import JellyTVKit

/// Sort chips for the Movies library (design 4a). Each maps to a real
/// Jellyfin `sortBy`/`sortOrder` pair — picking a chip re-fetches the
/// library in that order rather than just re-arranging local state.
private enum MoviesSort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case az = "A–Z"
    case topRated = "Top Rated"

    var id: String { rawValue }

    var query: (sortBy: String, sortOrder: String) {
        switch self {
        case .newest: return ("DateCreated", "Descending")
        case .az: return ("SortName", "Ascending")
        case .topRated: return ("CommunityRating", "Descending")
        }
    }
}

/// The genre tail of a `MediaItem.meta` line ("Movie · Thriller" → "Thriller").
private extension MediaItem {
    var genre: String {
        guard meta.contains("·") else { return "" }
        return meta.split(separator: "·").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}

/// The Movies library screen (design 4a): rail + search/Play/Random header,
/// sort/genre filter chips, a "currently selected" band that tracks grid
/// focus, and a poster grid for the whole library. Falls back to the sample
/// catalog while the server's movies haven't loaded (or there's no server).
struct MoviesLibraryView: View {
    let onSelectRail: (RailTarget) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme

    @State private var movies: [MediaItem] = []
    @State private var sort: MoviesSort = .newest
    @State private var selectedGenre: String?
    @State private var searchText = ""
    @State private var presentedMovie: Movie?
    /// Real detail (cast, ratings, tagline, awards) fetched for the selected
    /// item; shown in place of the sample fallback once it arrives.
    @State private var selectedDetail: Movie?
    @FocusState private var focusedId: String?
    @FocusState private var searchFocused: Bool?

    private static let sampleMovies = SampleCatalog.recommended.filter { $0.kind == .movie }

    private var allMovies: [MediaItem] { movies.isEmpty ? Self.sampleMovies : movies }

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
        if !searchText.isEmpty {
            items = items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
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
                NavRail(destination: .movies, isLibrariesOpen: false, onSelect: onSelectRail)
                // Header, filters and the selected-movie band stay pinned; only
                // the poster catalog scrolls beneath them.
                VStack(alignment: .leading, spacing: 22) {
                    header.padding(.horizontal, 48)
                    filterBar.padding(.horizontal, 48)
                    if let dossierMovie {
                        SelectedMovieBand(movie: dossierMovie, isLoading: isDossierLoading)
                    }
                    ScrollView(.vertical, showsIndicators: false) {
                        postersSection
                            .padding(.horizontal, 48)
                            .padding(.top, 6)   // room for the top row's focus glow
                            .padding(.bottom, 60)
                    }
                }
                .padding(.top, 40)
            }
            .ignoresSafeArea()

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
        }
        // Fetch rich detail (cast/ratings/tagline/awards) for the selected item.
        .task(id: selectedItem?.id) { await loadSelectedDetail() }
        .onExitCommand(perform: presentedMovie == nil ? { onSelectRail(.home) } : nil)
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
        AppTextField(placeholder: "Search movies…", text: $searchText,
                     systemImage: "magnifyingglass", trailing: "\(filtered.count)",
                     accent: theme.secondaryAccent, field: true, focus: $searchFocused)
    }

    private func randomize() {
        guard let item = filtered.randomElement() else { return }
        focusedId = item.id
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: 12) {
            Text("FILTER")
                .font(Mono.font(13, .bold))
                .tracking(2)
                .foregroundStyle(Palette.text(0.4))
            ForEach(MoviesSort.allCases) { option in
                chip(option.rawValue, isOn: sort == option) { sort = option }
            }
            Rectangle().fill(Palette.text(0.14)).frame(width: 1, height: 26)
            ForEach(genres, id: \.self) { genre in
                chip(genre, isOn: selectedGenre == genre) {
                    selectedGenre = (selectedGenre == genre) ? nil : genre
                }
            }
        }
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typography.font(17, .bold))
                .foregroundStyle(isOn ? .white : Palette.text(0.7))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(isOn ? theme.accent : Palette.text(0.06), in: Capsule())
                .overlay(Capsule().stroke(isOn ? .clear : Palette.text(0.14), lineWidth: 1.5))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 999))
    }

    // MARK: - Poster grid

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
                    MoviePosterCard(item: item, onSelect: { openMovie(item) })
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

/// The focused movie's full-screen backdrop — the same layer treatment as
/// `HomeView.heroBackdropLayer`: a full-width image pinned to the top of the
/// screen (behind the rail and the scrolling content), scrimmed for
/// legibility and alpha-masked at the bottom so it dissolves into the page
/// background over the first poster row. Sits behind the header, filters, and
/// the `SelectedMovieBand` text so the image reads across the whole top of
/// the screen, not just a mid-page strip.
private struct SelectedBackdrop: View {
    let item: MediaItem

    /// How far down the screen the backdrop reaches before it has fully faded
    /// out — tall enough to cover the header, filters, the text band, and the
    /// top of the first poster row.
    private static let height: CGFloat = 900
    /// Shift the image content up so it sits a little higher than dead-center —
    /// the top of the art rides above the screen edge (roughly y = -100).
    private static let imageShift: CGFloat = -100

    /// The high-resolution wide image (real Backdrop when present), falling
    /// back to the poster if that's all the item has.
    private var imageURL: String? { item.backdropImage ?? item.image }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                heroImage(width: geo.size.width)
                    .opacity(0.9)
                // A softly-blurred copy of the image, shown only across the
                // top (behind the header/filters) and fading to the sharp
                // image below — takes the visual busyness out from under the
                // header without blurring the whole backdrop.
                heroImage(width: geo.size.width, blur: 18)
                    .opacity(0.9)
                    .mask(topBlur)
                scrims
            }
            .frame(width: geo.size.width, height: Self.height, alignment: .top)
            .mask(bottomFade)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .id(item.id)
        .transition(.opacity)
    }

    /// The backdrop rendered into a 1.5× box then clipped back to the frame —
    /// the same 50% zoom `HomeView.heroImage` applies, so the backdrop reads
    /// bigger/closer without changing its footprint. The image content is
    /// shifted up by `imageShift`; the blur (when set) is applied on the
    /// oversized box before clipping so it doesn't bleed transparent edges.
    private func heroImage(width: CGFloat, blur: CGFloat = 0) -> some View {
        backdrop
            .frame(width: width * 1.5, height: Self.height * 1.5)
            .blur(radius: blur)
            .offset(y: Self.imageShift)
            .frame(width: width, height: Self.height)
            .clipped()
    }

    @ViewBuilder private var backdrop: some View {
        if let art = imageURL, art.hasPrefix("http"), let url = URL(string: art) {
            JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
        } else if let art = imageURL {
            Image(art).resizable().scaledToFill()
        } else {
            item.artwork.gradient
        }
    }

    /// Mask for the blurred copy: opaque across the top (behind the header and
    /// filters), fading to clear so the sharp image shows below.
    private var topBlur: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.10),
                .init(color: .clear, location: 0.24),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// The darkening scrims from `HomeView.heroScrims`: a left→right scrim so
    /// the title/synopsis stay legible over the art, a top darkening so the
    /// header controls read over it, and a pre-darkening toward black at the
    /// bottom *before* the alpha mask cuts it away — that pre-darkening is what
    /// makes the image dissolve into the page rather than read as a hard cut.
    private var scrims: some View {
        Color.clear
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0.0),
                        .init(color: .black.opacity(0.35), location: 0.35),
                        .init(color: .black.opacity(0.10), location: 0.70),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.5), location: 0.0),
                        .init(color: .black.opacity(0.28), location: 0.07),
                        .init(color: .clear, location: 0.18),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.62),
                        .init(color: .black.opacity(0.5), location: 0.85),
                        .init(color: .black.opacity(0.9), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
    }

    /// Fades the bottom of the backdrop to transparent so it blends into the
    /// content below — several stops (rather than one straight ramp) so the
    /// falloff eases out gently, the same treatment as `HomeView.heroBottomFade`.
    /// The top stays fully opaque (it's at the screen edge, behind the header).
    private var bottomFade: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.68),
                .init(color: .white.opacity(0.7), location: 0.78),
                .init(color: .white.opacity(0.3), location: 0.87),
                .init(color: .white.opacity(0.08), location: 0.94),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
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

    private static let height: CGFloat = 536

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            info
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 16) {
                StatsCastPanel(movie: movie, isLoading: isLoading)
                MetaPanel(movie: movie, isLoading: isLoading)
            }
        }
        .padding(.horizontal, 100)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .id(movie.id)
        .transition(.opacity)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SELECTED // NOW IN YOUR LIBRARY")
                .font(Mono.font(14, .bold))
                .tracking(3)
                .foregroundStyle(theme.accent)

            Text(movie.title)
                .font(Typography.font(72, .black))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
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
                .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var genreTail: String {
        movie.genreLabel.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? movie.genreLabel
    }

    private var dot: some View { Text("·").foregroundStyle(Palette.text(0.4)) }
}

/// The dossier's top panel (design 4a): the "SIGNAL DOSSIER / DECODED" header,
/// two big rating stat boxes (critics / audience), and a two-column cast grid
/// with Oscar-winner medals. Rich data is fetched per selection (Jellyfin
/// detail + optional OMDb); anything absent simply doesn't render, so the
/// panel degrades cleanly on sparse metadata.
private struct StatsCastPanel: View {
    let movie: Movie
    var isLoading: Bool = false

    @EnvironmentObject private var theme: Theme

    /// Fixed footprint — independent of `MetaPanel`'s — so this panel never
    /// resizes/jumps as content changes (loading → loaded, rich → sparse);
    /// content is top-aligned inside it.
    static let size = CGSize(width: 440, height: 380)

    /// Audience score (IMDb / community), 0–10.
    private var audience: Double? { movie.externalRatings?.imdbRating ?? movie.communityRating }
    /// Critics score (Rotten Tomatoes / Jellyfin critic), a percentage.
    private var critics: Int? { movie.externalRatings?.rottenTomatoes ?? movie.criticRating.map { Int($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isLoading {
                loadingBody
            } else {
                statBoxes
                castSection
            }
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(Color(hex: "#0E121A").opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
    }

    private var header: some View {
        HStack {
            Text("SIGNAL DOSSIER")
                .font(Mono.font(12, .bold))
                .tracking(2.4)
                .foregroundStyle(Palette.text(0.42))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(isLoading ? Palette.text(0.35) : theme.accent).frame(width: 7, height: 7)
                    .shadow(color: isLoading ? .clear : theme.accent, radius: 6)
                Text(isLoading ? "SCANNING" : "DECODED")
                    .font(Mono.font(11, .bold))
                    .tracking(1)
                    .foregroundStyle(isLoading ? Palette.text(0.4) : theme.accent)
            }
        }
    }

    /// Shown until the live detail arrives — a quiet indicator, never fake data.
    private var loadingBody: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(theme.accent)
            Text("Decoding signal…")
                .font(Mono.font(14, .medium)).tracking(1)
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ratings

    @ViewBuilder private var statBoxes: some View {
        if critics != nil || audience != nil {
            HStack(spacing: 12) {
                if let critics { statBox(value: "\(critics)%", label: "CRITICS", accent: true) }
                if let audience { statBox(value: String(format: "%.1f", audience), label: "AUDIENCE", accent: false) }
            }
        }
    }

    private func statBox(value: String, label: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Typography.font(34, .black))
                .foregroundStyle(accent ? theme.accent : Palette.textPrimary)
            Text(label)
                .font(Mono.font(11, .bold)).tracking(1.5)
                .foregroundStyle(Palette.text(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13).padding(.horizontal, 16)
        .background(Palette.text(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
    }

    // MARK: - Cast (two-column grid)

    @ViewBuilder private var castSection: some View {
        if !movie.cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("CAST")
                    .font(Mono.font(12, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.42))
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    alignment: .leading, spacing: 14
                ) {
                    ForEach(movie.cast.prefix(6)) { member in
                        CastListItem(member: member, portrait: 42)
                    }
                }
            }
        }
    }
}

/// The dossier's bottom panel (design 4a): director / studio / runtime crew
/// rows, in its own fixed-size card below `StatsCastPanel`. The director's
/// name renders upper-case. When the film has actually *won* an Oscar (other
/// awards are ignored per the product decision — see `MovieAwards.academyAwardsLabel`),
/// the panel gets a quiet trophy-art background at 40% opacity instead of the
/// flat panel color, as a subtle Oscar signal rather than another text badge.
private struct MetaPanel: View {
    let movie: Movie
    var isLoading: Bool = false

    @EnvironmentObject private var theme: Theme

    /// Fixed footprint — independent of `StatsCastPanel`'s — so this panel
    /// never resizes/jumps as content changes.
    static let size = CGSize(width: 440, height: 140)

    private static let oscarArtURL = URL(string: "https://w.wallhaven.cc/full/4y/wallhaven-4yzo3d.jpg")
    private var wonOscar: Bool { (movie.awards?.oscarsWon ?? 0) > 0 }

    var body: some View {
        Group {
            if isLoading { loadingBody } else { metaRows }
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
    }

    /// This panel's own decode indicator — smaller than `StatsCastPanel`'s
    /// (there's less vertical room here), but the same visual language, so
    /// both dossier windows read as "still decoding" rather than one loading
    /// and the other going blank.
    private var loadingBody: some View {
        HStack(spacing: 10) {
            ProgressView().tint(theme.accent)
            Text("Decoding…")
                .font(Mono.font(13, .medium)).tracking(1)
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metaRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !movie.director.isEmpty { crewRow(label: "Director", value: movie.director.uppercased()) }
            if !movie.studios.isEmpty { crewRow(label: "Studio", value: movie.studios.prefix(2).joined(separator: ", ")) }
            if !movie.runtime.isEmpty { crewRow(label: "Runtime", value: movie.runtime) }
        }
    }

    private func crewRow(label: String, value: String) -> some View {
        HStack {
            Text(label.uppercased()).font(Mono.font(13, .semibold)).tracking(1).foregroundStyle(Palette.text(0.42))
            Spacer(minLength: 12)
            Text(value).font(Typography.font(15, .bold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
        }
    }

    @ViewBuilder private var background: some View {
        ZStack {
            Color(hex: "#0E121A").opacity(0.7)
            if wonOscar, let oscarArtURL = Self.oscarArtURL {
                AsyncImage(url: oscarArtURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: Self.size.width, height: Self.size.height)
                            .opacity(0.4)
                    }
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
            }
        }
    }
}

/// A single poster in the Movies grid (design 4a): artwork, a real ★ rating
/// badge when the server has one, and a title/year/genre caption.
private struct MoviePosterCard: View {
    let item: MediaItem
    var onSelect: () -> Void = {}

    private var isRemote: Bool { item.image?.hasPrefix("http") == true }
    private var dominant: Color {
        if let name = item.image, !isRemote { return DominantColor.of(name, fallback: Color(item.artwork.top)) }
        return Color(item.artwork.top)
    }

    private var caption: String {
        [item.year, item.genre].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                artwork
                LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.82)],
                               startPoint: .center, endPoint: .bottom)

                if let rating = item.rating {
                    Text("★ " + String(format: "%.1f", rating))
                        .font(Typography.font(13, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(12)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(Typography.font(19, .heavy))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.6), radius: 10, y: 2)
                    if !caption.isEmpty {
                        Text(caption)
                            .font(Mono.font(13, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.text(0.72))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.1))
    }

    @ViewBuilder private var artwork: some View {
        if let image = item.image, isRemote, let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
        } else if let name = item.image {
            Image(name).resizable().scaledToFill()
        } else {
            item.artwork.gradient
        }
    }
}
