import Foundation

/// Demo content matching the reference design (`Design/jelly-tv-screens.dc.html`).
/// This is the seam a future Jellyfin-backed catalog will replace — the screens
/// bind to these types, not to the sample data directly.
public enum SampleCatalog {

    public static let hero = HeroFeature(
        eyebrow: "Featured · New Season",
        title: "The Deep Signal",
        certification: "TV-MA",
        year: "2026",
        genre: "Sci-Fi Drama",
        episode: "S3 · E4 — “Trench”",
        qualityBadge: "4K HDR",
        synopsis: "A deep-sea research crew uncovers a signal older than the ocean itself — and something down there is answering back.",
        resumeLabel: "Resume · E4",
        pageCount: 5,
        activePage: 0,
        artwork: .gradient(l: 0.42, c: 0.11, hue: 250, hue2: 210)
    )

    public static let continueWatching: [ContinueWatchingItem] = [
        .init(id: "cw-deep-signal", title: "The Deep Signal", episodeLabel: "S3 · E4 — Trench",
              remaining: "31 min", progress: 0.62, artwork: .gradient(l: 0.42, c: 0.11, hue: 250)),
        .init(id: "cw-copper-season", title: "Copper Season", episodeLabel: "S1 · E7 — Harvest",
              remaining: "12 min", progress: 0.84, artwork: .gradient(l: 0.45, c: 0.10, hue: 60, hue2: 30)),
        .init(id: "cw-night-cartographers", title: "Night Cartographers", episodeLabel: "S2 · E2 — Meridian",
              remaining: "48 min", progress: 0.18, artwork: .gradient(l: 0.38, c: 0.10, hue: 310, hue2: 270)),
        .init(id: "cw-undertow", title: "Undertow", episodeLabel: "Movie",
              remaining: "1h 40m", progress: 0.26, artwork: .gradient(l: 0.40, c: 0.09, hue: 210, hue2: 250)),
        .init(id: "cw-field-notes", title: "Field Notes", episodeLabel: "S4 · E1 — Thaw",
              remaining: "22 min", progress: 0.55, artwork: .gradient(l: 0.40, c: 0.09, hue: 150, hue2: 120)),
    ]

    public static let recommended: [MediaItem] = [
        .init(id: "rec-undertow", title: "Undertow", meta: "Movie · Thriller",
              artwork: .gradient(l: 0.44, c: 0.11, hue: 230, hue2: 190)),
        .init(id: "rec-copper-season", title: "Copper Season", meta: "Series · Drama",
              artwork: .gradient(l: 0.44, c: 0.11, hue: 55, hue2: 25)),
        .init(id: "rec-glasshouse", title: "Glasshouse", meta: "Movie · Mystery",
              artwork: .gradient(l: 0.44, c: 0.11, hue: 160, hue2: 130)),
        .init(id: "rec-long-static", title: "The Long Static", meta: "Series · Sci-Fi",
              artwork: .gradient(l: 0.44, c: 0.11, hue: 280, hue2: 320)),
        .init(id: "rec-salt-line", title: "Salt Line", meta: "Movie · Drama",
              artwork: .gradient(l: 0.44, c: 0.11, hue: 20, hue2: 350)),
        .init(id: "rec-night-cartographers", title: "Night Cartographers", meta: "Series · Adventure",
              artwork: .gradient(l: 0.44, c: 0.11, hue: 260, hue2: 220)),
        .init(id: "rec-meridian-zero", title: "Meridian Zero", meta: "Movie · Action",
              artwork: .gradient(l: 0.44, c: 0.11, hue: 10, hue2: 40)),
    ]

    public static let libraries: [Library] = [
        .init(id: "lib-movies", name: "Movies"),
        .init(id: "lib-tv", name: "TV Shows"),
        .init(id: "lib-anime", name: "Anime"),
        .init(id: "lib-docs", name: "Documentaries"),
        .init(id: "lib-music", name: "Music"),
        .init(id: "lib-home-videos", name: "Home Videos"),
        .init(id: "lib-after-dark", name: "After Dark", isAdult: true),
        .init(id: "lib-uncut", name: "Uncut Films", isAdult: true),
    ]

    public static let navTabs = ["Home", "Movies", "Shows", "Search"]

    public static let profile = UserProfile(
        name: "Marina", email: "marina@home.local", role: "Administrator"
    )

    public static let server = ServerStatus(
        name: "reef.local", version: "v10.9.2", isConnected: true
    )

    /// Settings rows. Theme's value is refreshed live from the current accent,
    /// and Server's from `server`, at the view layer.
    public static let settingsEntries: [SettingsEntry] = [
        .init(kind: .profile, label: "Profile", subtitle: "Name, avatar, PIN lock", value: "Marina"),
        .init(kind: .settings, label: "Settings", subtitle: "Playback, subtitles, parental controls", value: ""),
        .init(kind: .theme, label: "Theme", subtitle: "Appearance & accent color", value: "Dark · Coral"),
        .init(kind: .server, label: "Server", subtitle: "reef.local · v10.9.2", value: "Connected"),
    ]
}
