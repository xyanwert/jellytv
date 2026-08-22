import Foundation

public enum MetaCategory: String, CaseIterable, Sendable, Hashable {
    case movies
    case moviesxxx
    case animefilm
    case shows
    case anime
    case hentai
    case videos
    case porn

    public var isNSFW: Bool {
        switch self {
        case .moviesxxx, .hentai, .porn: return true
        default: return false
        }
    }

    public var isAnime: Bool {
        switch self {
        case .animefilm, .anime, .hentai: return true
        default: return false
        }
    }

    public var collectionType: String {
        switch self {
        case .movies, .moviesxxx, .animefilm: return "movies"
        case .shows, .anime, .hentai: return "tvshows"
        case .videos, .porn: return "homevideos"
        }
    }

    /// Whether a Jellyfin collection type has an NSFW/anime variant at all —
    /// drives which classification toggles Settings → Libraries shows per
    /// library (e.g. home videos have no anime concept).
    public static func supportsNSFW(collectionType: String) -> Bool {
        collectionType == "movies" || collectionType == "tvshows" || collectionType == "homevideos"
    }

    public static func supportsAnime(collectionType: String) -> Bool {
        collectionType == "movies" || collectionType == "tvshows"
    }

    /// Resolves the effective category from a collection type plus the two
    /// user/heuristic-set flags. Movies has no combined NSFW+anime category
    /// (unlike tvshows' `.hentai`), so NSFW takes priority there — Settings
    /// keeps the two toggles mutually exclusive for movies libraries.
    public static func resolve(collectionType: String, isNSFW: Bool, isAnime: Bool) -> MetaCategory? {
        switch collectionType {
        case "movies":
            if isNSFW { return .moviesxxx }
            if isAnime { return .animefilm }
            return .movies
        case "tvshows":
            if isNSFW && isAnime { return .hentai }
            if isAnime { return .anime }
            if isNSFW { return .hentai }
            return .shows
        case "homevideos":
            if isNSFW { return .porn }
            return .videos
        default:
            return nil
        }
    }
}

/// A user-set classification override for one Jellyfin library, persisted
/// locally (Jellyfin has no native "anime"/"NSFW" library concept). Once set
/// in Settings → Libraries, it always wins over `LibraryClassifier`'s
/// name-heuristic guess.
public struct LibraryClassificationOverride: Codable, Equatable, Sendable {
    public var isNSFW: Bool
    public var isAnime: Bool

    public init(isNSFW: Bool, isAnime: Bool) {
        self.isNSFW = isNSFW
        self.isAnime = isAnime
    }
}
