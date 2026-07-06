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

/// A user library shown as a chip in the Home libraries row.
public struct Library: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var isAdult: Bool

    public init(id: String, name: String, isAdult: Bool = false) {
        self.id = id
        self.name = name
        self.isAdult = isAdult
    }
}

/// The featured hero on the Home screen.
public struct HeroFeature: Equatable, Sendable, Hashable {
    public var eyebrow: String        // "Featured · New Season"
    public var title: String          // "The Deep Signal"
    public var certification: String  // "TV-MA"
    public var year: String           // "2026"
    public var genre: String          // "Sci-Fi Drama"
    public var episode: String        // "S3 · E4 — “Trench”"
    public var qualityBadge: String   // "4K HDR"
    public var synopsis: String
    public var resumeLabel: String    // "Resume · E4"
    public var pageCount: Int         // pager dots
    public var activePage: Int
    public var artwork: Artwork

    public init(eyebrow: String, title: String, certification: String, year: String,
                genre: String, episode: String, qualityBadge: String, synopsis: String,
                resumeLabel: String, pageCount: Int, activePage: Int, artwork: Artwork) {
        self.eyebrow = eyebrow
        self.title = title
        self.certification = certification
        self.year = year
        self.genre = genre
        self.episode = episode
        self.qualityBadge = qualityBadge
        self.synopsis = synopsis
        self.resumeLabel = resumeLabel
        self.pageCount = pageCount
        self.activePage = activePage
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

/// A row in the Settings account panel.
public struct SettingsEntry: Equatable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case profile, settings, theme, server }

    public var kind: Kind
    public var label: String
    public var subtitle: String
    /// Trailing value (may be overridden live, e.g. Theme reflects the accent).
    public var value: String

    public var id: String { kind.rawValue }

    public init(kind: Kind, label: String, subtitle: String, value: String) {
        self.kind = kind
        self.label = label
        self.subtitle = subtitle
        self.value = value
    }
}
