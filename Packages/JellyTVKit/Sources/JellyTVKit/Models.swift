import Foundation

/// A poster/tile item (movie or series entry).
public struct MediaItem: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    /// Secondary line, e.g. "Movie · Thriller".
    public var meta: String
    /// Optional artwork image asset name; falls back to `artwork` gradient.
    public var image: String?
    public var artwork: Artwork

    public init(id: String, title: String, meta: String, image: String? = nil, artwork: Artwork) {
        self.id = id
        self.title = title
        self.meta = meta
        self.image = image
        self.artwork = artwork
    }
}

/// A user library shown as a chip in the Home libraries row and as a row in the
/// rail's Libraries submenu.
public struct Library: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var isAdult: Bool
    /// Display-ready item count, e.g. `"428"` or `"1.2k"`.
    public var itemCount: String

    public init(id: String, name: String, isAdult: Bool = false, itemCount: String) {
        self.id = id
        self.name = name
        self.isAdult = isAdult
        self.itemCount = itemCount
    }
}

/// A featured hero slide. The Home hero rotates through a list of these.
public struct HeroFeature: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var image: String          // backdrop asset name
    public var eyebrow: String        // "Featured · New Season"
    public var title: String          // "The Deep Signal"
    public var certification: String  // "TV-MA"
    public var year: String           // "2026"
    public var genre: String          // "Sci-Fi Drama"
    public var episode: String        // "S3 · E4 — “Trench”"
    public var qualityBadge: String   // "4K HDR"
    public var synopsis: String
    public var resumeLabel: String    // "Resume · E4"
    public var artwork: Artwork

    public init(id: String, image: String, eyebrow: String, title: String,
                certification: String, year: String, genre: String, episode: String,
                qualityBadge: String, synopsis: String, resumeLabel: String, artwork: Artwork) {
        self.id = id
        self.image = image
        self.eyebrow = eyebrow
        self.title = title
        self.certification = certification
        self.year = year
        self.genre = genre
        self.episode = episode
        self.qualityBadge = qualityBadge
        self.synopsis = synopsis
        self.resumeLabel = resumeLabel
        self.artwork = artwork
    }
}

/// An in-progress item in the Continue Watching row.
public struct ContinueWatchingItem: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var episodeLabel: String   // "S3 · E4 — Trench" or "Movie"
    public var remaining: String      // "31 min"
    /// Watched fraction, 0...1.
    public var progress: Double
    /// Optional artwork image asset name; falls back to `artwork` gradient.
    public var image: String?
    public var artwork: Artwork

    public init(id: String, title: String, episodeLabel: String, remaining: String,
                progress: Double, image: String? = nil, artwork: Artwork) {
        self.id = id
        self.title = title
        self.episodeLabel = episodeLabel
        self.remaining = remaining
        self.progress = progress
        self.image = image
        self.artwork = artwork
    }
}

/// The signed-in user shown in the top bar and Settings panel.
public struct UserProfile: Equatable, Sendable, Hashable {
    public var name: String     // "Marina"
    public var email: String    // "marina@home.local"
    public var role: String     // "Administrator"

    public init(name: String, email: String, role: String) {
        self.name = name
        self.email = email
        self.role = role
    }

    /// First character, used for the avatar.
    public var initial: String { String(name.prefix(1)) }
}

/// The connected Jellyfin server, shown in the Settings → Server row.
public struct ServerStatus: Equatable, Sendable, Hashable {
    public var name: String     // "reef.local"
    public var version: String  // "v10.9.2"
    public var isConnected: Bool

    public init(name: String, version: String, isConnected: Bool) {
        self.name = name
        self.version = version
        self.isConnected = isConnected
    }
}

/// A category row in the Settings screen's category list.
public struct SettingsCategory: Equatable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case playback, subtitles, audio, parental, server, account, about
    }

    public var kind: Kind
    public var label: String
    public var description: String

    public var id: String { kind.rawValue }

    public init(kind: Kind, label: String, description: String) {
        self.kind = kind
        self.label = label
        self.description = description
    }
}

/// A toggle row in the Settings Playback detail pane.
public struct PlaybackToggle: Equatable, Sendable, Hashable, Identifiable {
    public var id: String { label }
    public var label: String
    public var description: String
    public var isOnByDefault: Bool

    public init(label: String, description: String, isOnByDefault: Bool) {
        self.label = label
        self.description = description
        self.isOnByDefault = isOnByDefault
    }
}

/// One episode in a season's strip on the Show view.
public struct Episode: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var number: Int
    public var title: String
    public var runtime: String        // "49m"
    public var isCurrent: Bool        // the resume/NOW episode
    public var image: String?         // artwork asset name; falls back to `artwork`
    public var artwork: Artwork

    public init(id: String, number: Int, title: String, runtime: String,
                isCurrent: Bool = false, image: String? = nil, artwork: Artwork) {
        self.id = id
        self.number = number
        self.title = title
        self.runtime = runtime
        self.isCurrent = isCurrent
        self.image = image
        self.artwork = artwork
    }

    /// Zero-padded episode number, e.g. "04".
    public var numberLabel: String { String(format: "%02d", number) }
}

/// A season of a show: a named group of episodes.
public struct Season: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var number: Int
    public var name: String            // "Season 3" / "Specials"
    public var episodes: [Episode]

    public init(id: String, number: Int, name: String, episodes: [Episode]) {
        self.id = id
        self.number = number
        self.name = name
        self.episodes = episodes
    }

    /// Short segmented-control label, e.g. "S03" / "SPECIALS".
    public var shortLabel: String { number == 0 ? "SPECIALS" : String(format: "S%02d", number) }
}

/// A collection (series) shown on the Show view: spec-sheet metadata, a resume
/// point, and its seasons/episodes.
public struct Show: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var studioLine: String      // "Series 003 // Benthic Pictures"
    public var rating: String          // "8.9"
    public var certification: String   // "TV-MA"
    public var runSummary: String      // "3 seasons · 24 ep"
    public var createdBy: String       // "Mara Ellingsen"
    public var years: String           // "2023 – 2026"
    public var genreLabel: String      // spine text, "TV Shows / Sci-Fi Drama"
    public var techLine: String        // "4K · HDR · ATMOS"
    public var keyArt: String?         // artwork asset name; falls back to `artwork`
    public var artwork: Artwork
    public var resumeEpisodeLabel: String  // "S3 · E4 — Trench"
    public var resumeProgress: Double       // 0...1
    public var resumeRemaining: String      // "31:04 LEFT · 62%"
    public var seasons: [Season]

    public init(id: String, title: String, studioLine: String, rating: String,
                certification: String, runSummary: String, createdBy: String,
                years: String, genreLabel: String, techLine: String,
                keyArt: String? = nil, artwork: Artwork,
                resumeEpisodeLabel: String, resumeProgress: Double,
                resumeRemaining: String, seasons: [Season]) {
        self.id = id
        self.title = title
        self.studioLine = studioLine
        self.rating = rating
        self.certification = certification
        self.runSummary = runSummary
        self.createdBy = createdBy
        self.years = years
        self.genreLabel = genreLabel
        self.techLine = techLine
        self.keyArt = keyArt
        self.artwork = artwork
        self.resumeEpisodeLabel = resumeEpisodeLabel
        self.resumeProgress = resumeProgress
        self.resumeRemaining = resumeRemaining
        self.seasons = seasons
    }

    /// Index of the season containing the current/resume episode (or the last).
    public var currentSeasonIndex: Int {
        seasons.firstIndex { $0.episodes.contains(where: \.isCurrent) } ?? max(0, seasons.count - 1)
    }
}
