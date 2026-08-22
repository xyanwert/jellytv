import Foundation
import CryptoKit

/// The on-disk schema for the dev-only mock Jellyfin catalog
/// (`Resources/MockCatalog/MockCatalog.json`), seeded with real metadata from
/// TMDB (movies/shows) and AniList (anime) by `MockCatalogGenerator`, and
/// served back as Jellyfin-shaped wire JSON by `MockJellyfinURLProtocol`.
///
/// This is deliberately its own lightweight interchange format (not a mirror
/// of `JellyfinAPI.JellyfinItem`, which is `Decodable`-only) — the generator
/// writes it, `MockCatalogLoader` reads it and translates to Jellyfin's
/// PascalCase wire shape on demand.
public struct MockCatalog: Codable, Sendable {
    public var libraries: [MockLibrary]
    public var movies: [MockMovie]
    public var shows: [MockShow]

    public init(libraries: [MockLibrary] = [], movies: [MockMovie] = [], shows: [MockShow] = []) {
        self.libraries = libraries
        self.movies = movies
        self.shows = shows
    }
}

/// A mock Jellyfin library (`/UserViews` entry). `name` is what drives
/// `LibraryClassifier`'s anime/NSFW name-heuristic — see `MockLibraryKind`.
public struct MockLibrary: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var collectionType: String // "movies" | "tvshows"

    public init(id: String, name: String, collectionType: String) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
    }
}

/// The 5 libraries needed to exercise every library screen
/// (Movies/Shows/Anime[+Anime Movies]/Late Night), matching
/// `LibraryClassifier`'s name-heuristic tokens exactly.
public enum MockLibraryKind: String, CaseIterable, Sendable {
    case movies = "Movies"
    case shows = "TV Shows"
    case animeMovies = "Anime Movies"
    case anime = "Anime"
    case adultShows = "Adult Shows"

    public var collectionType: String {
        switch self {
        case .movies, .animeMovies: return "movies"
        case .shows, .anime, .adultShows: return "tvshows"
        }
    }

    public var id: String { MockIdentifiers.stableId("library-\(rawValue)") }
}

public struct MockCastMember: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: String?
    public var imageURL: String?

    public init(id: String, name: String, role: String? = nil, imageURL: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.imageURL = imageURL
    }
}

public struct MockMovie: Codable, Sendable, Identifiable {
    public var id: String
    public var libraryId: String
    public var name: String
    public var overview: String?
    public var genres: [String]
    public var productionYear: Int?
    public var premiereDate: String?
    public var officialRating: String?
    public var communityRating: Double?
    public var criticRating: Double?
    public var runtimeTicks: Int64?
    public var tagline: String?
    public var studios: [String]
    public var director: String?
    public var imdbId: String?
    public var cast: [MockCastMember]
    public var posterURL: String?
    public var backdropURL: String?

    public init(id: String, libraryId: String, name: String, overview: String? = nil,
                genres: [String] = [], productionYear: Int? = nil, premiereDate: String? = nil,
                officialRating: String? = nil, communityRating: Double? = nil, criticRating: Double? = nil,
                runtimeTicks: Int64? = nil, tagline: String? = nil, studios: [String] = [],
                director: String? = nil, imdbId: String? = nil, cast: [MockCastMember] = [],
                posterURL: String? = nil, backdropURL: String? = nil) {
        self.id = id
        self.libraryId = libraryId
        self.name = name
        self.overview = overview
        self.genres = genres
        self.productionYear = productionYear
        self.premiereDate = premiereDate
        self.officialRating = officialRating
        self.communityRating = communityRating
        self.criticRating = criticRating
        self.runtimeTicks = runtimeTicks
        self.tagline = tagline
        self.studios = studios
        self.director = director
        self.imdbId = imdbId
        self.cast = cast
        self.posterURL = posterURL
        self.backdropURL = backdropURL
    }
}

public struct MockEpisode: Codable, Sendable, Identifiable {
    public var id: String
    public var indexNumber: Int
    public var name: String
    public var overview: String?
    public var runtimeTicks: Int64?
    public var imageURL: String?

    public init(id: String, indexNumber: Int, name: String, overview: String? = nil,
                runtimeTicks: Int64? = nil, imageURL: String? = nil) {
        self.id = id
        self.indexNumber = indexNumber
        self.name = name
        self.overview = overview
        self.runtimeTicks = runtimeTicks
        self.imageURL = imageURL
    }
}

public struct MockSeason: Codable, Sendable, Identifiable {
    public var id: String
    public var indexNumber: Int
    public var name: String
    public var posterURL: String?
    public var episodes: [MockEpisode]

    public init(id: String, indexNumber: Int, name: String, posterURL: String? = nil, episodes: [MockEpisode] = []) {
        self.id = id
        self.indexNumber = indexNumber
        self.name = name
        self.posterURL = posterURL
        self.episodes = episodes
    }
}

public struct MockShow: Codable, Sendable, Identifiable {
    public var id: String
    public var libraryId: String
    public var name: String
    public var overview: String?
    public var genres: [String]
    public var productionYear: Int?
    public var premiereDate: String?
    public var officialRating: String?
    public var communityRating: Double?
    public var criticRating: Double?
    public var tagline: String?
    public var studios: [String]
    public var imdbId: String?
    public var status: String? // "Continuing" | "Ended"
    public var endDate: String?
    public var cast: [MockCastMember]
    public var posterURL: String?
    public var backdropURL: String?
    public var seasons: [MockSeason]

    public init(id: String, libraryId: String, name: String, overview: String? = nil,
                genres: [String] = [], productionYear: Int? = nil, premiereDate: String? = nil,
                officialRating: String? = nil, communityRating: Double? = nil, criticRating: Double? = nil,
                tagline: String? = nil, studios: [String] = [], imdbId: String? = nil,
                status: String? = nil, endDate: String? = nil, cast: [MockCastMember] = [],
                posterURL: String? = nil, backdropURL: String? = nil, seasons: [MockSeason] = []) {
        self.id = id
        self.libraryId = libraryId
        self.name = name
        self.overview = overview
        self.genres = genres
        self.productionYear = productionYear
        self.premiereDate = premiereDate
        self.officialRating = officialRating
        self.communityRating = communityRating
        self.criticRating = criticRating
        self.tagline = tagline
        self.studios = studios
        self.imdbId = imdbId
        self.status = status
        self.endDate = endDate
        self.cast = cast
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.seasons = seasons
    }
}

/// Deterministic 32-hex-char (Jellyfin-GUID-shaped) ids derived from a stable
/// seed string (e.g. `"movie-tmdb-27205"`), so regenerating the catalog never
/// changes existing items' ids — `AppState`'s by-id caches stay valid across
/// reruns of `MockCatalogGenerator`.
public enum MockIdentifiers {
    public static func stableId(_ seed: String) -> String {
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
