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
}
