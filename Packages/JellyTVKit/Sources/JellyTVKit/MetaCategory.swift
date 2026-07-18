import Foundation

public enum MetaCategory: String, CaseIterable, Sendable {
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
}
