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
