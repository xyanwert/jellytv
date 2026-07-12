import Foundation

/// Demo content matching the reference design (`Design/jelly-tv-screens.dc.html`).
/// This is the seam a future Jellyfin-backed catalog will replace — the screens
/// bind to these types, not to the sample data directly.
public enum SampleCatalog {

    /// The hero rotates through these slides (crumble/fade between backdrops).
    public static let heroes: [HeroFeature] = [
        HeroFeature(
            id: "hero-deep-signal",
            image: "HeroBackdrop",
            eyebrow: "Featured · New Season",
            title: "The Deep Signal",
            certification: "TV-MA",
            year: "2026",
            genre: "Sci-Fi Drama",
            episode: "S3 · E4 — “Trench”",
            qualityBadge: "4K HDR",
            synopsis: "A deep-sea research crew uncovers a signal older than the ocean itself — and something down there is answering back.",
            resumeLabel: "Resume · E4",
            artwork: .gradient(l: 0.42, c: 0.11, hue: 250, hue2: 210)
        ),
        HeroFeature(
            id: "hero-bobs-burgers",
            image: "HeroBob",
            eyebrow: "Featured · Fan Favorite",
            title: "Bob's Burgers",
            certification: "TV-14",
            year: "2026",
            genre: "Comedy",
            episode: "S14 · E6 — “Bacon-ings”",
            qualityBadge: "HD",
            synopsis: "Bob, Linda, and the kids keep the grill running and the schemes cooking at the greasiest little burger joint on the pier.",
            resumeLabel: "Resume · E6",
            artwork: .gradient(l: 0.55, c: 0.14, hue: 250, hue2: 60)
        ),
    ]

    /// First hero slide (back-compat for call sites that want a single hero).
    public static var hero: HeroFeature { heroes[0] }

    public static let continueWatching: [ContinueWatchingItem] = [
        .init(id: "cw-deep-signal", title: "The Deep Signal", episodeLabel: "S3 · E4 — Trench",
              remaining: "31 min", progress: 0.62, image: "Preview1", artwork: .gradient(l: 0.42, c: 0.11, hue: 250)),
        .init(id: "cw-copper-season", title: "Copper Season", episodeLabel: "S1 · E7 — Harvest",
              remaining: "12 min", progress: 0.84, image: "PreviewBob1", artwork: .gradient(l: 0.45, c: 0.10, hue: 60, hue2: 30)),
        .init(id: "cw-night-cartographers", title: "Night Cartographers", episodeLabel: "S2 · E2 — Meridian",
              remaining: "48 min", progress: 0.18, image: "Preview3", artwork: .gradient(l: 0.38, c: 0.10, hue: 310, hue2: 270)),
        .init(id: "cw-undertow", title: "Undertow", episodeLabel: "Movie",
              remaining: "1h 40m", progress: 0.26, image: "PreviewBob2", artwork: .gradient(l: 0.40, c: 0.09, hue: 210, hue2: 250)),
        .init(id: "cw-field-notes", title: "Field Notes", episodeLabel: "S4 · E1 — Thaw",
              remaining: "22 min", progress: 0.55, image: "PreviewBob3", artwork: .gradient(l: 0.40, c: 0.09, hue: 150, hue2: 120)),
    ]

    public static let recommended: [MediaItem] = [
        .init(id: "rec-undertow", title: "Undertow", meta: "Movie · Thriller",
              image: "PreviewBob1", artwork: .gradient(l: 0.44, c: 0.11, hue: 230, hue2: 190)),
        .init(id: "rec-copper-season", title: "Copper Season", meta: "Series · Drama",
              image: "Preview2", artwork: .gradient(l: 0.44, c: 0.11, hue: 55, hue2: 25)),
        .init(id: "rec-glasshouse", title: "Glasshouse", meta: "Movie · Mystery",
              image: "PreviewBob2", artwork: .gradient(l: 0.44, c: 0.11, hue: 160, hue2: 130)),
        .init(id: "rec-long-static", title: "The Long Static", meta: "Series · Sci-Fi",
              image: "Preview1", artwork: .gradient(l: 0.44, c: 0.11, hue: 280, hue2: 320)),
        .init(id: "rec-salt-line", title: "Salt Line", meta: "Movie · Drama",
              image: "PreviewBob3", artwork: .gradient(l: 0.44, c: 0.11, hue: 20, hue2: 350)),
        .init(id: "rec-night-cartographers", title: "Night Cartographers", meta: "Series · Adventure",
              image: "Preview3", artwork: .gradient(l: 0.44, c: 0.11, hue: 260, hue2: 220)),
        .init(id: "rec-meridian-zero", title: "Meridian Zero", meta: "Movie · Action",
              image: "Preview1", artwork: .gradient(l: 0.44, c: 0.11, hue: 10, hue2: 40)),
    ]

    public static let libraries: [Library] = [
        .init(id: "lib-movies", name: "Movies", itemCount: "428"),
        .init(id: "lib-tv", name: "TV Shows", itemCount: "96"),
        .init(id: "lib-anime", name: "Anime", itemCount: "213"),
        .init(id: "lib-docs", name: "Documentaries", itemCount: "154"),
        .init(id: "lib-music", name: "Music", itemCount: "1.2k"),
        .init(id: "lib-home-videos", name: "Home Videos", itemCount: "37"),
        .init(id: "lib-after-dark", name: "After Dark", isAdult: true, itemCount: "62"),
        .init(id: "lib-uncut", name: "Uncut Films", isAdult: true, itemCount: "18"),
    ]

    public static let profile = UserProfile(
        name: "Marina", email: "marina@home.local", role: "Administrator"
    )

    public static let server = ServerStatus(
        name: "reef.local", version: "v10.9.2", isConnected: true
    )

    /// The Settings screen's category list.
    public static let settingsCategories: [SettingsCategory] = [
        .init(kind: .playback, label: "Playback", description: "Quality, auto-play"),
        .init(kind: .subtitles, label: "Subtitles", description: "Language, size"),
        .init(kind: .audio, label: "Audio", description: "Output, passthrough"),
        .init(kind: .parental, label: "Parental", description: "PIN, 18+ libraries"),
        .init(kind: .server, label: "Server", description: "Connection, sync"),
        .init(kind: .account, label: "Account", description: "Profile, sign out"),
        .init(kind: .about, label: "About", description: "Version, licenses"),
    ]

    /// Playback category: streaming-quality options (last is the sample default).
    public static let playbackQualityOptions = ["Auto", "1080p", "4K"]
    public static let defaultPlaybackQuality = "4K"

    /// Playback category: playback-method options (first is the sample default).
    public static let playbackMethodOptions = ["Direct Play", "Transcode"]
    public static let defaultPlaybackMethod = "Direct Play"

    /// Playback category: toggle rows.
    public static let playbackToggles: [PlaybackToggle] = [
        .init(label: "Auto-play next episode", description: "Start the next episode automatically", isOnByDefault: true),
        .init(label: "Skip intros", description: "Detect and skip recaps & title sequences", isOnByDefault: true),
        .init(label: "HDR passthrough", description: "Send HDR metadata to your display", isOnByDefault: false),
    ]

    // MARK: - Show view

    /// Preview assets cycled for episode thumbnails (no per-episode art needed).
    private static let episodeImages = ["Preview1", "Preview2", "Preview3", "PreviewBob1", "PreviewBob2", "PreviewBob3"]

    /// Builds the four demo seasons; season 3 holds the current/resume episode.
    private static func demoSeasons() -> [Season] {
        // (title, runtime) for the fully-authored Season 3.
        let s3: [(String, String)] = [
            ("Descent", "52m"), ("Pressure", "48m"), ("Blackwater", "55m"), ("Trench", "49m"),
            ("The Answer", "51m"), ("Surfacing", "58m"), ("Undertow", "47m"), ("Origin", "61m"),
        ]
        func episodes(season: Int, count: Int, titles: [(String, String)]? = nil, currentEp: Int? = nil,
                      hueBase: Double) -> [Episode] {
            (1...count).map { n in
                let t = titles?[safe: n - 1]
                return Episode(
                    id: "s\(season)e\(n)",
                    number: n,
                    title: t?.0 ?? "Episode \(n)",
                    runtime: t?.1 ?? "\(46 + (n * 3) % 14)m",
                    isCurrent: n == currentEp,
                    image: episodeImages[(season * 3 + n) % episodeImages.count],
                    artwork: .gradient(l: 0.42, c: 0.11, hue: hueBase + Double(n) * 12)
                )
            }
        }
        return [
            Season(id: "season-1", number: 1, name: "Season 1", episodes: episodes(season: 1, count: 8, hueBase: 250)),
            Season(id: "season-2", number: 2, name: "Season 2", episodes: episodes(season: 2, count: 8, hueBase: 220)),
            Season(id: "season-3", number: 3, name: "Season 3", episodes: episodes(season: 3, count: 8, titles: s3, currentEp: 4, hueBase: 235)),
            Season(id: "season-0", number: 0, name: "Specials", episodes: episodes(season: 0, count: 3, hueBase: 300)),
        ]
    }

    /// The reference demo show ("The Deep Signal") backing design screen 2a.
    public static let show = Show(
        id: "show-deep-signal",
        title: "The Deep Signal",
        studioLine: "Series 003 // Benthic Pictures",
        rating: "8.9",
        certification: "TV-MA",
        runSummary: "3 seasons · 24 ep",
        createdBy: "Mara Ellingsen",
        years: "2023 – 2026",
        genreLabel: "TV Shows / Sci-Fi Drama",
        techLine: "4K · HDR · ATMOS",
        synopsis: "A deep-sea research crew uncovers a signal older than the ocean itself — rhythmic, deliberate, patient. As the pings draw closer, they realize something down there is not echoing them back. It is answering.",
        keyArt: "HeroBackdrop",
        artwork: .gradient(l: 0.42, c: 0.11, hue: 250, hue2: 210),
        resumeEpisodeLabel: "S3 · E4 — “Trench”",
        resumeProgress: 0.62,
        resumeRemaining: "31:04 LEFT · 62%",
        seasons: demoSeasons()
    )

    /// A `Show` for any media item — the demo template carrying that item's
    /// title and key art, so any Recommended poster opens as a show.
    public static func show(for item: MediaItem) -> Show {
        let s = show
        return Show(
            id: "show-\(item.id)",
            title: item.title,
            studioLine: s.studioLine,
            rating: s.rating,
            certification: s.certification,
            runSummary: s.runSummary,
            createdBy: s.createdBy,
            years: s.years,
            genreLabel: "TV Shows / \(genrePart(item.meta, fallback: "Sci-Fi Drama"))",
            techLine: s.techLine,
            synopsis: s.synopsis,
            keyArt: item.image ?? s.keyArt,
            artwork: item.artwork,
            resumeEpisodeLabel: s.resumeEpisodeLabel,
            resumeProgress: s.resumeProgress,
            resumeRemaining: s.resumeRemaining,
            seasons: s.seasons
        )
    }

    /// The reference demo movie ("Undertow") backing design screen 1b.
    public static let movie = Movie(
        id: "movie-undertow",
        title: "Undertow",
        studioLine: "Feature Film // Benthic Pictures",
        rating: "8.6",
        certification: "PG-13",
        runtime: "2h 14m",
        director: "Mara Ellingsen",
        year: "2026",
        genreLabel: "Movies / Thriller",
        synopsis: "When a coastal town’s tide stops turning, a marine acoustician returns home to trace the silence — and finds her own past waiting beneath the surface. As the water grows still and the townsfolk begin to forget the sound of the sea, she must descend to the source before the quiet swallows her too. From the director of Salt Line.",
        keyArt: "HeroBob",
        artwork: .gradient(l: 0.40, c: 0.09, hue: 210, hue2: 250),
        resumeLabel: "Undertow",
        resumeProgress: 0.26,
        resumeRemaining: "1:40:12 LEFT · 26%",
        starring: "Ines Duval, Theo Marsh",
        audioLine: "EN · FR · 12 subtitles",
        moreLikeThis: recommended
    )

    /// A `Movie` for any media item — the demo template carrying that item's
    /// title and key art, so a Recommended movie poster opens as a movie.
    public static func movie(for item: MediaItem) -> Movie {
        let m = movie
        return Movie(
            id: "movie-\(item.id)",
            title: item.title,
            studioLine: m.studioLine,
            rating: m.rating,
            certification: m.certification,
            runtime: m.runtime,
            director: m.director,
            year: m.year,
            genreLabel: "Movies / \(genrePart(item.meta, fallback: "Thriller"))",
            synopsis: m.synopsis,
            keyArt: item.image ?? m.keyArt,
            artwork: item.artwork,
            resumeLabel: item.title,
            resumeProgress: m.resumeProgress,
            resumeRemaining: m.resumeRemaining,
            starring: m.starring,
            audioLine: m.audioLine,
            moreLikeThis: m.moreLikeThis
        )
    }
}

/// The genre portion of a "Movie · Thriller" / "Series · Drama" meta line.
private func genrePart(_ meta: String, fallback: String) -> String {
    let tail = meta.split(separator: "·").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    return tail.isEmpty ? fallback : tail
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
