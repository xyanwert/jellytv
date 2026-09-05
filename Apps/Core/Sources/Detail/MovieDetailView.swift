import SwiftUI
import JellyTVKit

/// Focusable fields on the Movie detail. Not private: the tvOS section views
/// (`CastLineup`, `ScenesStrip`, `SimilarRow`) share the page's one
/// `@FocusState`, which is what lets Down from the Play bar walk the folds.
enum MovieField: Hashable {
    case play, favorite
    case cast(String)
    case scene(Int)
    case similar(String)
}

/// The Movie detail as a **one-sheet** (design 1b-onesheet): the poster as a
/// physical object on the left; the text column beside it — eyebrow, tagline,
/// title, rating chips, a hairline metadata rail, synopsis, and the lit Play
/// bar landing on the poster's bottom edge; a cast band across the foot; all
/// of it over `PosterBloom`, the poster's own colour thrown across the screen.
///
/// iPad drew it first. tvOS is the same screen at ten feet — a taller poster,
/// larger type, and only the controls that do something (`tvBody`). Phone has
/// its own one-column shape (`phoneBody`). The "signal dossier" tvOS used to
/// carry — a boxed key-art panel with a floating resume card, a 2×2 spec
/// sheet, a MORE LIKE THIS row of `SampleCatalog` posters on a real film's
/// page, and Trailer / EN·5.1 / CC·OFF pills that were focusable buttons doing
/// nothing — is gone.
struct MovieDetailView: View {
    let initialMovie: Movie
    let onDismiss: () -> Void
    /// Opens another item's own page — a film from "More like this", or one
    /// of a person's other credits. The parent owns presentation, so it swaps
    /// what it is showing; this page just says which.
    var onOpenItem: (MediaItem) -> Void = { _ in }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: MovieField?
    /// Live Jellyfin + OMDb detail; replaces the initial (often sample-derived)
    /// movie once it resolves. All `movie.*` reads below go through `movie`.
    @State private var detail: Movie?
    /// Optimistic favorite override, same idiom as `ShowView.favoriteOverride`
    /// — `movie.isFavorite` only updates once `loadDetail()` re-fetches, which
    /// this doesn't wait for. `nil` defers to the real value; reverted on a
    /// failed write. Shared by iPhone's FAVOURITE quick action and the tvOS
    /// control bar's heart.
    @State private var favoriteOverride: Bool?
    /// The poster's dominant colour, extracted once the art is in hand — the
    /// one-sheet layout takes every accent on the screen from it.
    @State private var posterTint: Color?
    #if os(tvOS)
    // The movie-night extras — each fetched once the detail lands, each
    // optional, each drawn only when it exists (`loadMovieNight`).
    @State private var extras: TMDBMovieExtras?
    @State private var similar: [MediaItem] = []
    @State private var topPercent: Int?
    @State private var directorCredits: Int?
    @State private var collection: (position: Int?, total: Int, seen: Int)?
    @State private var presentedPerson: CastMember?
    @State private var zoomOrigin: UnitPoint = .center
    /// Flips on appear; the folds enter in order off it — see `contentTV`.
    @State private var entered = false
    #endif
    #if os(iOS)
    /// Phone only — which of the DETAILS/CAST tabs is showing.
    @State private var phoneTab: PhoneMovieTab = .details
    #endif

    init(movie: Movie, onDismiss: @escaping () -> Void, onOpenItem: @escaping (MediaItem) -> Void = { _ in }) {
        self.initialMovie = movie
        self.onDismiss = onDismiss
        self.onOpenItem = onOpenItem
    }

    private var movie: Movie { detail ?? initialMovie }

    var body: some View {
        Group {
            #if os(iOS)
            if DeviceClass.current == .phone {
                phoneBody
            } else {
                iPadBody
            }
            #else
            tvBody
            #endif
        }
        .background(Color(hex: "#070A10").ignoresSafeArea())
        .defaultFocus($focus, .play)
        .task { await loadDetail() }
        .task(id: posterImage) { await loadPosterTint() }
        #if os(tvOS)
        .onExitCommand(perform: onDismiss)
        // `.defaultFocus` alone left this screen with *no* focus when it was
        // presented over Home as a same-ZStack overlay — verified from both
        // the hero's Details button and a Recommended poster: the primary
        // control sat unlit, and Menu, with no focused view for
        // `onExitCommand` to hang off, fell through to tvOS and backgrounded
        // the whole app. Seeding directly on appear is what the failure
        // overlay and the library grids do for the same reason.
        .onAppear { if focus == nil { focus = .play } }
        #endif
    }

    #if os(iOS)
    /// iPad: the one-sheet layout — poster panel, title/spec column, cast
    /// band, over a `PosterBloom` colour wash taken from the poster itself.
    private var iPadBody: some View {
        ZStack {
            PosterBloom(image: posterImage, artwork: movie.artwork, tint: tint)
            HStack(spacing: 0) {
                DetailSpine(genreLabel: movie.genreLabel, markerTop: "FILM",
                            markerBottom: "001", onBack: onDismiss, accent: tint)
                contentIOS
            }
            .ignoresSafeArea()
        }
    }
    #else
    /// tvOS: the one-sheet as a pitch, then the folds that sell it — see
    /// `contentTV`.
    private var tvBody: some View {
        ZStack {
            // The two heavy layers — a 90pt blur of the poster at 1.3× the
            // screen, and a full-bleed backdrop on a drift — wait out the
            // zoom and fade in over the settled page. Rendered during the
            // transition they were the frames it dropped; and the colour
            // arriving a beat after the page reads as the room lighting up.
            ZStack {
                PosterBloom(image: posterImage, artwork: movie.artwork, tint: tint)
                AmbientBackdrop(urls: backdropURLs, fallback: movie.artwork.gradient)
            }
            .opacity(entered ? 1 : 0)
            .animation(.easeIn(duration: 0.9).delay(0.4), value: entered)
            HStack(spacing: 0) {
                DetailSpine(genreLabel: movie.genreLabel, markerTop: "FILM",
                            markerBottom: "001", onBack: onDismiss, accent: tint)
                contentTV
            }
            .ignoresSafeArea()
            // Same-ZStack overlay, not a modal: without this the page's
            // controls stay in the focus engine's pool under the sheet.
            .disabled(presentedPerson != nil)
            // The sheet zooms out of the coin — see `ZoomTransition`.
            .trackZoomOrigin($zoomOrigin)
            .zoomedBehind(presentedPerson != nil, origin: zoomOrigin)

            if presentedPerson != nil {
                // Near-opaque: at 0.74 the page's Play bar and fact card
                // stayed legible under the biography and read as part of the
                // sheet. Fades in place while the sheet itself zooms.
                Color.black.opacity(0.92).ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(1)
            }
            if let presentedPerson {
                PersonSheet(member: presentedPerson, releaseYear: Int(movie.year),
                            currentItemId: movie.id, tint: tint,
                            onOpen: { item in self.presentedPerson = nil; onOpenItem(item) },
                            onDismiss: { self.presentedPerson = nil })
                    .zoomPresented(from: zoomOrigin)
                    .zIndex(2)
            }
        }
        .animation(.zoomPresentation, value: presentedPerson)
        // The poster's colour lands a beat after the page; every surface that
        // wears it glides there rather than snapping.
        .animation(.easeInOut(duration: 0.7), value: posterTint)
        // Closing the sheet puts the remote back on the person it was opened
        // from; otherwise the re-enabled page picks its own geometric
        // nearest, which scrolled the lineup back to its first figure.
        .onChange(of: presentedPerson) { old, new in
            if new == nil, let old { focus = .cast(old.id) }
        }
    }
    #endif

    /// Fetches full detail (cast, ratings, tagline, director) then merges OMDb
    /// awards/RT. No-ops gracefully before the server is up (keeps the initial).
    private func loadDetail() async {
        #if os(tvOS)
        // Fetch at once, apply after the zoom has settled: the detail lands
        // in ~300ms, squarely inside a 450ms transition, and re-laying out
        // the whole page (logo, chips, cast, scenes) mid-animation was a
        // visible hitch. Waiting costs at most the remainder of the zoom.
        async let fetched = appState.movieDetail(for: initialMovie.id)
        try? await Task.sleep(for: .milliseconds(500))
        guard var m = await fetched else { return }
        #else
        guard var m = await appState.movieDetail(for: initialMovie.id) else { return }
        #endif
        m.moreLikeThis = initialMovie.moreLikeThis   // keep the row we were opened with
        detail = m
        #if os(tvOS)
        let landed = m
        Task { await loadMovieNight(for: landed) }
        #endif
        if let enrichment = await appState.omdbEnrichment(imdbId: m.imdbId) {
            m.externalRatings = enrichment.ratings
            m.awards = enrichment.awards
            detail = m
        }
    }

    private func play() {
        appState.requestPlayback(.single(movie.asPlayableItem()))
    }

    // MARK: - One-sheet data (both platforms)

    private var imdbRating: Double? { movie.externalRatings?.imdbRating ?? movie.communityRating }
    private var rottenTomatoes: Int? { movie.externalRatings?.rottenTomatoes ?? movie.criticRating.map { Int($0) } }
    private var metacritic: Int? { movie.externalRatings?.metacritic }

    /// The poster (Jellyfin `Primary`), falling back to the landscape backdrop
    /// on an item that has no poster — cropped to 2:3 rather than left blank.
    private var posterImage: String? { movie.posterArt ?? movie.keyArt }

    /// Every accent on this screen: the poster's dominant colour, or the app
    /// accent until (or unless) the extraction lands.
    private var tint: Color { posterTint ?? theme.accent }

    private func loadPosterTint() async {
        guard let image = posterImage else { return }
        if image.hasPrefix("http"), let url = URL(string: image) {
            posterTint = await DominantColor.of(url: url, fallback: theme.accent)
        } else {
            posterTint = DominantColor.of(image, fallback: theme.accent)
        }
    }

    /// The poster is the tallest thing on the screen, so it — not the text —
    /// is what has to give when the device is shorter. Everything else on the
    /// screen has a fixed height, so subtracting that from what we're given
    /// leaves the poster's; the 2:3 width follows from it.
    private func posterHeight(in size: CGSize) -> CGFloat {
        let chrome: CGFloat = movie.cast.isEmpty ? Self.chromeWithoutCast : Self.chromeWithCast
        return max(Self.posterMinHeight, min(Self.posterMaxHeight, size.height - chrome))
    }

    #if os(iOS)
    private static let chromeWithoutCast: CGFloat = 174
    private static let chromeWithCast: CGFloat = 336
    private static let posterMinHeight: CGFloat = 300
    private static let posterMaxHeight: CGFloat = 645
    private static let railValueSize: CGFloat = 20
    private static let certificationSize: CGFloat = 15
    #else
    // The paddings above and below, plus the cast band (rule, header, strip
    // and its gaps) when there is one — on the 1080pt canvas that leaves a
    // 700pt poster, which is as tall as the type beside it wants.
    private static let chromeWithoutCast: CGFloat = 120
    private static let chromeWithCast: CGFloat = 350
    private static let posterMinHeight: CGFloat = 420
    private static let posterMaxHeight: CGFloat = 700
    private static let railValueSize: CGFloat = 24
    private static let certificationSize: CGFloat = 17
    #endif

    private var ratingValue: some View {
        HStack(spacing: 8) {
            Text("\u{2605}").foregroundStyle(tint)
            Text(movie.rating.isEmpty ? "\u{2014}" : movie.rating)
            if !movie.certification.isEmpty {
                Text(movie.certification)
                    .font(Typography.font(Self.certificationSize, .semibold))
                    .foregroundStyle(Palette.text(0.42))
            }
        }
        .font(Typography.font(Self.railValueSize, .heavy))
        .foregroundStyle(Palette.textPrimary)
    }

    private func railValue(_ text: String) -> some View {
        Text(text.isEmpty ? "\u{2014}" : text)
            .font(Typography.font(Self.railValueSize, .bold))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// "RESUME" once there is progress to resume from, otherwise "PLAY" — the
    /// remaining time rides under it and comes off the item, never invented.
    private var playLabel: String { movie.resumeProgress > 0 ? "RESUME" : "PLAY" }

    private var playSubLabel: String {
        movie.resumeProgress > 0 ? movie.resumeRemaining : movie.runtime
    }

    // MARK: - tvOS (the one-sheet, then the folds that sell the film)

    #if os(tvOS)
    /// Jellyfin's one wide backdrop first, then whatever TMDB added — the
    /// ambient slideshow's playlist.
    private var backdropURLs: [String] {
        var urls: [String] = []
        if let key = movie.keyArt, key.hasPrefix("http") { urls.append(key) }
        urls.append(contentsOf: (extras?.backdropURLs ?? []).filter { !urls.contains($0) })
        return urls
    }

    /// Only the chapters the server extracted a frame for.
    private var scenes: [Chapter] { movie.chapters.filter { $0.imageURL != nil } }

    private var focusedCastId: String? {
        if case .cast(let id) = focus { return id }
        return nil
    }

    /// The page: the pitch (poster + column) first, then the cast lineup,
    /// the scenes, and what else here is like it. Each fold is its own focus
    /// section; Down from the Play bar walks them and the scroll view follows.
    private var contentTV: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // The folds land one after another while the page itself is
                // still zooming out of its poster: the pitch first, then the
                // cast, the scenes, the shelf.
                HStack(alignment: .top, spacing: 64) {
                    OneSheetPoster(image: posterImage, artwork: movie.artwork, height: Self.posterMaxHeight)
                        .entrance(entered, delay: 0.04, rise: 10)
                    oneSheetInfoTV(height: Self.posterMaxHeight)
                        .entrance(entered, delay: 0.10)
                }

                // The folds below arrive with the detail fetch, a beat after
                // the page — they fade in rather than pop, so data landing
                // mid-transition doesn't read as a stutter.
                if !movie.cast.isEmpty {
                    CastLineup(cast: movie.cast, releaseYear: Int(movie.year), currentItemId: movie.id,
                               tint: tint, focusedMemberId: focusedCastId, focus: $focus,
                               onSelect: { presentedPerson = $0 })
                        .padding(.top, 56)
                        .entrance(entered, delay: 0.18)
                        .transition(.opacity)
                }

                if scenes.count >= 3 {
                    ScenesStrip(chapters: scenes, tint: tint, focus: $focus, onSelect: play(from:))
                        .padding(.top, 44)
                        .entrance(entered, delay: 0.24)
                        .transition(.opacity)
                }

                if !similar.isEmpty {
                    SimilarRow(items: similar, focus: $focus, onOpen: onOpenItem)
                        .padding(.top, 44)
                        .entrance(entered, delay: 0.30)
                        .transition(.opacity)
                }
            }
            .padding(.init(top: 52, leading: 64, bottom: 96, trailing: 64))
            .animation(.easeOut(duration: 0.45), value: foldSignature)
        }
        .onAppear { entered = true }
    }

    /// Changes whenever a fold appears or disappears with the data behind it.
    private var foldSignature: String { "\(movie.cast.isEmpty)-\(scenes.count >= 3)-\(similar.isEmpty)" }

    /// The text column, held to the poster's height so the Play bar lands on
    /// the poster's bottom edge. Everything in it is sized to fit that height
    /// at its worst case — one-line tagline, one-line (or logo) title, chips,
    /// facts, rail, three lines of synopsis, the bar — because a column that
    /// overflows here spills into the cast lineup below.
    private func oneSheetInfoTV(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(movie.studioLine.uppercased())
                .font(Typography.font(16, .heavy)).tracking(4)
                .foregroundStyle(tint)
                .lineLimit(1)

            // The tagline is the headline: one line, the hook, before the
            // title even lands.
            if let tagline = movie.tagline, !tagline.isEmpty {
                Text("\u{201C}\(tagline)\u{201D}")
                    .font(Typography.font(26, .medium)).italic()
                    .foregroundStyle(Palette.text(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 12)
            }

            titleTV
                .padding(.top, 10)

            HStack(spacing: 12) {
                RatingChips(imdb: imdbRating, rottenTomatoes: rottenTomatoes, metacritic: metacritic)
                if movie.awards?.academyAwardsLabel != nil { AwardsBadge(awards: movie.awards) }
            }
            .padding(.top, 22)

            MovieNightFactsRow(facts: movieNightFacts, tint: tint)
                .padding(.top, 16)

            HairlineRail {
                RailCell(label: "Rating", first: true) { ratingValue }
            } second: {
                RailCell(label: "Runtime") { railValue(movie.runtime) }
            } third: {
                RailCell(label: "Director") { railValue(movie.director) }
            } fourth: {
                RailCell(label: "Year") { railValue(movie.year) }
            }
            .padding(.top, 22)

            Text(movie.synopsis)
                .font(Typography.font(21, .regular)).foregroundStyle(Palette.text(0.74))
                .lineSpacing(6).lineLimit(3)
                .padding(.top, 20)

            Spacer(minLength: 20)

            actionsTV
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
    }

    /// Logo art as the title where the server has it — the same rule as the
    /// Home hero and the library pages — the title in type otherwise. One
    /// fixed slot either way, so the column below doesn't move between films.
    @ViewBuilder private var titleTV: some View {
        if let logo = movie.logoArt, let url = URL(string: logo) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                        .frame(maxWidth: 680, maxHeight: Self.titleSlotHeight, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.6), radius: 16, y: 4)
                        .accessibilityLabel(movie.title)
                case .failure:
                    titleTextTV
                default:
                    Color.clear
                }
            }
            .frame(height: Self.titleSlotHeight, alignment: .bottomLeading)
        } else {
            titleTextTV
                .frame(height: Self.titleSlotHeight, alignment: .bottomLeading)
        }
    }

    private static let titleSlotHeight: CGFloat = 124
    private static let playBarWidth: CGFloat = 352

    private var titleTextTV: some View {
        Text(movie.title)
            .font(Typography.font(88, .black)).foregroundStyle(Palette.textPrimary)
            .lineLimit(1).minimumScaleFactor(0.42)
    }

    /// The answers to "is this the one tonight?", each only when it is real —
    /// see `MovieNightFactsRow`. Ordered by how often a family actually asks.
    private var movieNightFacts: [MovieNightFact] {
        var facts: [MovieNightFact] = []
        if let ends = MovieNightFacts.endsAtLabel(now: Date(), runtimeTicks: movie.runtimeTicks,
                                                  resumeTicks: movie.resumePositionTicks) {
            facts.append(MovieNightFact(id: "ends", icon: "clock", text: ends))
        }
        // A brag, so only when it is one: "TOP 64% OF YOUR MOVIES" is a
        // statistic dressed as a compliment.
        if let topPercent, topPercent <= 25 {
            facts.append(MovieNightFact(id: "top", icon: "star.fill", text: "TOP \(topPercent)% OF YOUR MOVIES"))
        }
        if let awards = movie.awards?.academyAwardsLabel {
            facts.append(MovieNightFact(id: "oscars", icon: "trophy.fill", text: awards.uppercased()))
        }
        if !movie.audioLine.isEmpty {
            var text = movie.audioLine.uppercased()
            if let subs = MovieNightFacts.subtitlesLabel(movie.subtitleLanguages, streamsKnown: true) {
                text += " · \(subs)"
            }
            facts.append(MovieNightFact(id: "audio", icon: "speaker.wave.2.fill", text: text))
        }
        if let collection, let position = collection.position {
            facts.append(MovieNightFact(id: "collection", icon: "square.stack.fill",
                                        text: "PART \(position) OF \(collection.total) · SEEN \(collection.seen)"))
        }
        if !movie.director.isEmpty, let directorCredits, directorCredits > 0 {
            facts.append(MovieNightFact(id: "director", icon: "megaphone.fill",
                                        text: "\(movie.director.uppercased()): \(directorCredits) MORE IN YOUR LIBRARY"))
        }
        // Jellyfin's own tags carry TMDB's keywords on most servers, so the
        // vibe chips don't wait for the TMDB toggle — see `vibeChips`.
        for chip in MovieNightFacts.vibeChips(tags: movie.tags, keywords: extras?.keywords ?? []) {
            facts.append(MovieNightFact(id: "kw-\(chip)", icon: nil, text: chip, style: .outline))
        }
        return facts
    }

    /// One lit Play bar and the heart — every control here does something.
    private var actionsTV: some View {
        HStack(spacing: 18) {
            // A third of the column, not the whole of it. The bar inherited
            // the iPad's full width, where the right two-thirds carried a
            // readout; on TV that stretch was lit glass saying nothing
            // ("seems so empty"). A remote needs no finger-width target.
            TVNeonPlayBar(label: playLabel, sub: playSubLabel, progress: movie.resumeProgress,
                          tint: tint, action: play)
                .frame(width: Self.playBarWidth)
                .focused($focus, equals: .play)

            Button(action: toggleFavorite) {
                Image(systemName: effectiveIsFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(effectiveIsFavorite ? tint : Palette.text(0.85))
                    .frame(width: 84, height: 84)
                    .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(effectiveIsFavorite ? tint.opacity(0.5) : Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 7))
            .focused($focus, equals: .favorite)
            .accessibilityLabel(effectiveIsFavorite ? "Remove from favourites" : "Add to favourites")
        }
    }

    /// Start from a scene: the film's own playable item with its resume
    /// position swapped for the chapter's start — the same rebuild
    /// `restartMovie` does with zero.
    private func play(from chapter: Chapter) {
        let base = movie.asPlayableItem()
        let item = PlayableItem(
            id: base.id, seriesId: base.seriesId, title: base.title, subtitle: base.subtitle,
            runtimeTicks: base.runtimeTicks, resumePositionTicks: chapter.startTicks, isFavorite: base.isFavorite,
            imageURL: base.imageURL, logoURL: base.logoURL, tags: base.tags, hidesTitle: base.hidesTitle
        )
        appState.requestPlayback(.single(item))
    }

    /// The page's extras, fetched together once the detail has landed. Each
    /// lands on its own and none is waited on by anything visible; TMDB's
    /// are `nil` when the toggle is off, and the page is complete without.
    private func loadMovieNight(for movie: Movie) async {
        async let similarItems = appState.similarItems(to: movie.id)
        async let percentile = appState.movieRatingPercentile(for: movie.communityRating)
        async let directorCount = directorCreditCount(for: movie)
        async let tmdb = appState.movieExtras(imdbId: movie.imdbId, tmdbId: movie.tmdbId)
        similar = await similarItems
        topPercent = await percentile
        directorCredits = await directorCount
        extras = await tmdb
        if let extras, extras.collectionPartTmdbIds.count > 1 {
            collection = await appState.collectionProgress(partTmdbIds: extras.collectionPartTmdbIds,
                                                           currentTmdbId: movie.tmdbId)
        }
    }

    private func directorCreditCount(for movie: Movie) async -> Int? {
        guard let id = movie.directorId else { return nil }
        return await appState.libraryCredits(personId: id, excluding: movie.id).count
    }
    #endif

    // MARK: - Favourite (all platforms)

    private var effectiveIsFavorite: Bool { favoriteOverride ?? movie.isFavorite }

    /// Real Jellyfin endpoint (`setFavorite`/`clearFavorite`) — same call
    /// `ShowView.toggleFavorite()` makes for a series, here for the movie
    /// itself. Optimistic, reverted on failure. iPhone's FAVOURITE quick
    /// action and tvOS's control-bar heart both land here.
    private func toggleFavorite() {
        guard let client = appState.jellyfinClient else { return }
        let newValue = !effectiveIsFavorite
        favoriteOverride = newValue
        Task {
            do {
                if newValue {
                    try await client.setFavorite(userId: appState.currentUserId, itemId: movie.id)
                } else {
                    try await client.clearFavorite(userId: appState.currentUserId, itemId: movie.id)
                }
            } catch {
                favoriteOverride = !newValue
            }
        }
    }

    // MARK: - iOS/iPad (design 1b-onesheet)

    #if os(iOS)
    private var contentIOS: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                // Both columns are sized explicitly. Left to negotiate it
                // themselves inside a GeometryReader, the text column takes
                // its ideal (single-line) width from the synopsis and runs
                // straight off the right edge of the screen, trailing padding
                // and all.
                let posterH = posterHeight(in: geo.size)
                let posterW = OneSheetPoster.width(for: posterH)
                let infoW = max(340, geo.size.width - 128 - posterW - 56)
                HStack(alignment: .top, spacing: 56) {
                    OneSheetPoster(image: posterImage, artwork: movie.artwork, height: posterH)
                    oneSheetInfo(height: posterH, width: infoW)
                }
                .padding(.top, 34)

                if !movie.cast.isEmpty {
                    Spacer(minLength: 20)
                    CastBand(cast: movie.cast)
                }
            }
            .padding(.init(top: 44, leading: 64, bottom: 40, trailing: 64))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The text column, held to the poster's exact height so its controls line
    /// up with the poster's bottom edge instead of floating mid-air.
    private func oneSheetInfo(height: CGFloat, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(movie.studioLine.uppercased())
                .font(Typography.font(15, .heavy)).tracking(4)
                .foregroundStyle(tint)
                .lineLimit(1)

            if let tagline = movie.tagline, !tagline.isEmpty {
                Text("\u{201C}\(tagline)\u{201D}")
                    .font(Typography.font(20, .medium)).italic()
                    .foregroundStyle(Palette.text(0.62))
                    .lineLimit(2)
                    .padding(.top, 12)
            }

            Text(movie.title)
                .font(Typography.font(88, .black)).foregroundStyle(Palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.42).lineSpacing(-12)
                .padding(.top, 8)

            HStack(spacing: 10) {
                RatingChips(imdb: imdbRating, rottenTomatoes: rottenTomatoes, metacritic: metacritic)
                if movie.awards?.academyAwardsLabel != nil { AwardsBadge(awards: movie.awards) }
            }
            .padding(.top, 24)

            HairlineRail {
                RailCell(label: "Rating", first: true) { ratingValue }
            } second: {
                RailCell(label: "Runtime") { railValue(movie.runtime) }
            } third: {
                RailCell(label: "Director") { railValue(movie.director) }
            } fourth: {
                RailCell(label: "Year") { railValue(movie.year) }
            }
            .padding(.top, 26)

            Text(movie.synopsis)
                .font(Typography.font(20, .regular)).foregroundStyle(Palette.text(0.74))
                .lineSpacing(7).lineLimit(4)
                .padding(.top, 22)

            Spacer(minLength: 24)

            actionsIOS
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    /// The action row is one lit bar (design D2): Play/Resume and the progress
    /// are the same object, and the settings that used to be pills ride along
    /// its right side as a readout that lights only what is switched on.
    private var actionsIOS: some View {
        NeonTransportBar(label: playLabel, sub: playSubLabel,
                         progress: movie.resumeProgress, tint: tint, action: play) {
            HStack(spacing: 16) {
                NeonReadoutItem(label: "TRAILER", tint: tint)
                NeonReadoutItem(label: "AUDIO", value: "EN 5.1", tint: tint)
                NeonReadoutItem(label: "SUBS", value: "OFF", tint: tint)
                // Same empty stub it has always been on both detail screens —
                // left in place pending a decision on what it should do.
                NeonReadoutItem(label: "\u{FF0B} LIST", tint: tint)
            }
        }
        .focused($focus, equals: .play)
    }

    // MARK: - Phone (`Detail.dc.html`'s shape, adapted — a movie has no
    // seasons/episodes)
    //
    // Same one-column, vertically-scrolling shape `ShowView.phoneBody`
    // established: a contained key-art block (`PhoneShowKeyArt`, reused
    // as-is — it's already generic) that *ends*, centred identity, a
    // progress row gated on real resume progress, one full-width primary
    // pill, an icon-and-caption quick-actions row, then tabs. What differs
    // is what a movie actually has: no EPISODES tab (nothing to browse),
    // no SHUFFLE quick action (nothing to shuffle), and a "More Like This"
    // shelf below the tabs — real, already-fetched data (`movie.moreLikeThis`)
    // that neither iPad's one-sheet nor this phone layout should drop.

    private var phoneBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                PhoneShowKeyArt(image: movie.keyArt, artwork: movie.artwork, onClose: onDismiss)
                phoneIdentity
                    .padding(.top, 18)
                    .padding(.horizontal, 20)

                if movie.resumeProgress > 0 {
                    phoneProgressRow
                        .padding(.top, 22)
                        .padding(.horizontal, 20)
                }

                phonePrimaryButton
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                phoneQuickActions
                    .padding(.top, 18)

                phoneTabBar
                    .padding(.top, 26)
                    .padding(.horizontal, 20)

                phoneTabContent
                    .padding(.top, 18)
                    .padding(.horizontal, 20)

                if !movie.moreLikeThis.isEmpty {
                    phoneMoreLikeThis
                        .padding(.top, 28)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 50)
            .phoneTabBarClearance()
        }
        .background(Color(hex: "#07080C").ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
    }

    private var phoneIdentity: some View {
        VStack(spacing: 11) {
            Text(movie.title)
                .font(Typography.font(32, .black))
                .tracking(-1)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Palette.textPrimary)
                .shadow(color: .black.opacity(0.55), radius: 20)
                .frame(width: 350)

            HStack(spacing: 7) {
                ForEach(phoneSpecChips, id: \.self) { chip in
                    Text(chip)
                        .font(Mono.font(10, .bold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.text(0.78))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Palette.text(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Palette.text(0.13), lineWidth: 1))
                }
                if !movie.rating.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 9))
                        Text(movie.rating)
                    }
                    .font(Mono.font(10, .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Palette.text(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }

            if !phoneMetaLine.isEmpty {
                Text(phoneMetaLine)
                    .font(Typography.font(13, .semibold))
                    .foregroundStyle(Palette.text(0.55))
            }
        }
    }

    /// `movie.certification` plus a static "4K · HDR · ATMOS" tech line —
    /// real per-item certification, split apart to match `Detail.dc.html`'s
    /// row of separate chips. `Movie` (unlike `Show`) carries no per-item
    /// tech line of its own to split instead.
    private var phoneSpecChips: [String] {
        var chips: [String] = []
        if !movie.certification.isEmpty { chips.append(movie.certification) }
        chips.append(contentsOf: ["4K", "HDR", "ATMOS"])
        return chips
    }

    /// "2026 · Thriller · 2h 14m" — real year, the genre tail of `genreLabel`
    /// ("Movies / Thriller"), and the real runtime.
    private var phoneMetaLine: String {
        var parts: [String] = []
        if !movie.year.isEmpty { parts.append(movie.year) }
        let genreTail = movie.genreLabel.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !genreTail.isEmpty { parts.append(genreTail) }
        if !movie.runtime.isEmpty { parts.append(movie.runtime) }
        return parts.joined(separator: " · ")
    }

    /// Only shown against genuine in-progress playback — never a fake "0%"
    /// bar for a movie nobody has started (see `phoneBody`'s gate).
    private var phoneProgressRow: some View {
        HStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.text(0.16))
                    Capsule().fill(tint).frame(width: geo.size.width * movie.resumeProgress)
                }
            }
            .frame(height: 4)
            Text(movie.resumeRemaining.uppercased())
                .font(Mono.font(11, .bold))
                .foregroundStyle(Palette.text(0.55))
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// One full-width pill — the single primary action. No episode to name
    /// (unlike `ShowView.phoneContinueButton`), so the label alone is
    /// CONTINUE/PLAY; the remaining-time readout lives in `phoneProgressRow`
    /// directly above whenever there's real progress to show.
    private var phonePrimaryButton: some View {
        let label = movie.resumeProgress > 0 ? "CONTINUE" : "PLAY"
        return Button(action: play) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                Text(label).font(Typography.font(16, .heavy)).tracking(0.3)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(tint, in: Capsule())
            .shadow(color: tint.opacity(0.42), radius: 20, y: 8)
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1).blendMode(.overlay))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.02, cornerRadius: 999))
    }

    /// RESTART / FAVOURITE only — unlike `ShowView`, there's nothing here to
    /// SHUFFLE (a movie is one item, not a library of episodes), so that
    /// action is dropped rather than wired to something that does nothing.
    private var phoneQuickActions: some View {
        HStack(spacing: 64) {
            PhoneQuickAction(icon: "backward.end.fill", caption: "RESTART", action: restartMovie)
            PhoneQuickAction(icon: effectiveIsFavorite ? "heart.fill" : "heart", caption: "FAVOURITE",
                              tint: effectiveIsFavorite ? tint : .white, action: toggleFavorite)
        }
    }

    /// A real "from zero," not a relabeled resume — same idiom as
    /// `ShowView.restartPrimaryEpisode`, reconstructing just the one
    /// `PlayableItem` with `resumePositionTicks` zeroed rather than growing
    /// `Movie.asPlayableItem()` for a single call site.
    private func restartMovie() {
        let base = movie.asPlayableItem()
        let restarted = PlayableItem(
            id: base.id, seriesId: base.seriesId, title: base.title, subtitle: base.subtitle,
            runtimeTicks: base.runtimeTicks, resumePositionTicks: nil, isFavorite: base.isFavorite,
            imageURL: base.imageURL, logoURL: base.logoURL, tags: base.tags, hidesTitle: base.hidesTitle
        )
        appState.requestPlayback(.single(restarted))
    }

    private var phoneTabBar: some View {
        HStack(spacing: 26) {
            ForEach(PhoneMovieTab.allCases, id: \.self) { tab in
                Button { phoneTab = tab } label: {
                    Text(tab.label)
                        .font(Mono.font(12, .bold))
                        .tracking(1.6)
                        .foregroundStyle(phoneTab == tab ? Palette.textPrimary : Palette.text(0.42))
                        .padding(.bottom, 11)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(tint).frame(height: 2)
                                .opacity(phoneTab == tab ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottomLeading) {
            Rectangle().fill(Palette.text(0.1)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var phoneTabContent: some View {
        switch phoneTab {
        case .details: phoneDetailsTab
        case .cast: phoneCastTab
        }
    }

    /// The same real fields `oneSheetInfo`'s `HairlineRail` already reads,
    /// stacked full width instead of a 4-across rail, plus the synopsis and
    /// studio line below.
    private var phoneDetailsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            phoneDetailRow(label: "Rating") {
                HStack(spacing: 6) {
                    Text("★").foregroundStyle(tint)
                    Text(movie.rating.isEmpty ? "—" : movie.rating)
                    if !movie.certification.isEmpty {
                        Text(movie.certification).font(Typography.font(13, .semibold)).foregroundStyle(Palette.text(0.4))
                    }
                }
                .font(Typography.font(17, .heavy)).foregroundStyle(Palette.textPrimary)
            }
            phoneDetailRow(label: "Runtime") { phoneDetailValue(movie.runtime) }
            phoneDetailRow(label: "Director") { phoneDetailValue(movie.director) }
            phoneDetailRow(label: "Studio") { phoneDetailValue(movie.studios.first ?? "") }
            phoneDetailRow(label: "Year") { phoneDetailValue(movie.year) }
            if !movie.synopsis.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SYNOPSIS").font(Mono.font(11, .bold)).tracking(1.5).foregroundStyle(Palette.text(0.42))
                    Text(movie.synopsis)
                        .font(Typography.font(15, .regular))
                        .foregroundStyle(Palette.text(0.72))
                        .lineSpacing(5)
                }
                .padding(.top, 4)
            }
        }
    }

    private func phoneDetailRow<Value: View>(label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(label.uppercased()).font(Mono.font(12, .semibold)).tracking(1).foregroundStyle(Palette.text(0.42))
            Spacer(minLength: 12)
            value()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.text(0.08)).frame(height: 1).padding(.top, 22) }
    }

    private func phoneDetailValue(_ text: String) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(Typography.font(17, .bold))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private var phoneCastTab: some View {
        if movie.cast.isEmpty {
            Text("No cast information yet.")
                .font(Typography.font(15, .medium))
                .foregroundStyle(Palette.text(0.4))
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                ForEach(movie.cast) { member in
                    CastAvatar(member: member, size: 56, labelWidth: 96)
                }
            }
        }
    }

    /// Real, already-fetched data (`movie.moreLikeThis`) — the iPad one-sheet
    /// doesn't show this row today either (only tvOS's wider `content` does),
    /// but it's fetched regardless of platform and a phone shouldn't be the
    /// one layout that silently drops it. Below the tabs, not inside DETAILS —
    /// "what else to watch" isn't a spec-sheet fact about this film.
    private var phoneMoreLikeThis: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MORE LIKE THIS")
                .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.5))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(movie.moreLikeThis) { item in
                        MoreLikeThisCard(item: item)
                    }
                }
                .padding(.vertical, 4)
            }
            .horizontalEdgeFade()
        }
    }

    #endif
}
