import Foundation

/// Minimal client for TMDB (themoviedb.org) — an optional, opt-in enrichment
/// source keyed by an item's IMDb id. Jellyfin has no distinct "TV network"
/// concept (it folds networks into the generic `Studios` field, with no
/// reliable logo image); TMDB is the only source this app uses for a real
/// network logo.
///
/// Two round trips: `/find` resolves an IMDb id to a TMDB TV id, then
/// `/tv/{id}` returns that show's `networks[]`. Both degrade to `nil` rather
/// than throwing loudly at call sites — a missing key, no TMDB match, or a
/// show with no network listed all just mean "no network branding this time".
public struct TMDBClient: Sendable {
    private let apiKey: String
    private let baseURL = "https://api.themoviedb.org/3"

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Resolves an IMDb id (e.g. `tt0903747`) to that title's primary TV
    /// network branding, or `nil` if there's no TMDB match or no network listed.
    public func fetchNetwork(imdbId: String) async throws -> Network? {
        guard let tmdbId = try await findTVId(imdbId: imdbId) else { return nil }
        let detail = try await fetchTVDetail(tmdbId: tmdbId)
        return detail.primaryNetwork
    }

    private func findTVId(imdbId: String) async throws -> Int? {
        try await find(imdbId: imdbId).tvResults?.first?.id
    }

    private func find(imdbId: String) async throws -> TMDBFindResult {
        var components = URLComponents(string: "\(baseURL)/find/\(imdbId)")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "external_source", value: "imdb_id"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        return try await get(url)
    }

    // MARK: - Movie extras

    /// What the movie page can use beyond what Jellyfin has: more backdrops
    /// (Jellyfin keeps one), keywords, the collection a film belongs to, its
    /// budget and box office. `nil` when TMDB has no match for the id; each
    /// field inside degrades on its own. `tmdbId` skips the `/find` round trip
    /// when Jellyfin already has it in `ProviderIds`.
    public func fetchMovieExtras(imdbId: String?, tmdbId: String? = nil) async throws -> TMDBMovieExtras? {
        let id: Int
        if let tmdbId, let known = Int(tmdbId) {
            id = known
        } else if let imdbId, let found = try await find(imdbId: imdbId).movieResults?.first?.id {
            id = found
        } else {
            return nil
        }
        var components = URLComponents(string: "\(baseURL)/movie/\(id)")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "append_to_response", value: "images,keywords"),
            // Textless backdrops first — a backdrop with a burned-in title in
            // another language is not "art", it is someone else's poster.
            URLQueryItem(name: "include_image_language", value: "null,en"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let detail: TMDBMovieDetail = try await get(url)
        var parts: [TMDBCollectionPart] = []
        if let collection = detail.belongsToCollection {
            parts = (try? await fetchCollection(id: collection.id))?.parts ?? []
        }
        return detail.extras(collectionParts: parts)
    }

    private func fetchCollection(id: Int) async throws -> TMDBCollection {
        var components = URLComponents(string: "\(baseURL)/collection/\(id)")
        components?.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        guard let url = components?.url else { throw URLError(.badURL) }
        return try await get(url)
    }

    private func fetchTVDetail(tmdbId: Int) async throws -> TMDBTVResult {
        var components = URLComponents(string: "\(baseURL)/tv/\(tmdbId)")
        components?.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        guard let url = components?.url else { throw URLError(.badURL) }
        return try await get(url)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// TMDB's `/find/{imdbId}` response — just enough to pull a TV or movie id.
public struct TMDBFindResult: Decodable, Equatable, Sendable {
    public let tvResults: [TMDBFindTVResult]?
    public let movieResults: [TMDBFindTVResult]?

    enum CodingKeys: String, CodingKey {
        case tvResults = "tv_results"
        case movieResults = "movie_results"
    }

    public init(tvResults: [TMDBFindTVResult]? = nil, movieResults: [TMDBFindTVResult]? = nil) {
        self.tvResults = tvResults
        self.movieResults = movieResults
    }
}

/// TMDB's `/movie/{id}?append_to_response=images,keywords` — the handful of
/// fields the movie page's extras are built from.
public struct TMDBMovieDetail: Decodable, Equatable, Sendable {
    public let budget: Int?
    public let revenue: Int?
    public let belongsToCollection: TMDBCollectionRef?
    public let images: TMDBImages?
    public let keywords: TMDBKeywords?

    enum CodingKeys: String, CodingKey {
        case budget, revenue, images, keywords
        case belongsToCollection = "belongs_to_collection"
    }

    public init(budget: Int? = nil, revenue: Int? = nil, belongsToCollection: TMDBCollectionRef? = nil,
                images: TMDBImages? = nil, keywords: TMDBKeywords? = nil) {
        self.budget = budget
        self.revenue = revenue
        self.belongsToCollection = belongsToCollection
        self.images = images
        self.keywords = keywords
    }

    /// The parsed detail as the app's own extras — separate from the request
    /// so the selection rules are unit-testable against a fixture.
    public func extras(collectionParts: [TMDBCollectionPart]) -> TMDBMovieExtras {
        // Textless first (no `iso_639_1`), then English, best-voted first;
        // six is plenty for an ambient slideshow and keeps the page from
        // downloading a gallery.
        let backdrops = (images?.backdrops ?? [])
            .sorted { lhs, rhs in
                let lhsTextless = lhs.iso6391 == nil, rhsTextless = rhs.iso6391 == nil
                if lhsTextless != rhsTextless { return lhsTextless }
                return (lhs.voteAverage ?? 0) > (rhs.voteAverage ?? 0)
            }
            .prefix(6)
            .map { "https://image.tmdb.org/t/p/w1280\($0.filePath)" }
        let sortedParts = collectionParts.sorted { ($0.releaseDate ?? "9999") < ($1.releaseDate ?? "9999") }
        return TMDBMovieExtras(
            backdropURLs: backdrops,
            keywords: (keywords?.keywords ?? []).map(\.name),
            collectionName: belongsToCollection?.name,
            collectionPartTmdbIds: sortedParts.map(\.id),
            budget: (budget ?? 0) > 0 ? budget : nil,
            revenue: (revenue ?? 0) > 0 ? revenue : nil
        )
    }
}

public struct TMDBImages: Decodable, Equatable, Sendable {
    public let backdrops: [TMDBImage]?
    public init(backdrops: [TMDBImage]? = nil) { self.backdrops = backdrops }
}

public struct TMDBImage: Decodable, Equatable, Sendable {
    public let filePath: String
    public let voteAverage: Double?
    public let iso6391: String?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case voteAverage = "vote_average"
        case iso6391 = "iso_639_1"
    }

    public init(filePath: String, voteAverage: Double? = nil, iso6391: String? = nil) {
        self.filePath = filePath
        self.voteAverage = voteAverage
        self.iso6391 = iso6391
    }
}

public struct TMDBKeywords: Decodable, Equatable, Sendable {
    public let keywords: [TMDBKeyword]?
    public init(keywords: [TMDBKeyword]? = nil) { self.keywords = keywords }
}

public struct TMDBKeyword: Decodable, Equatable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct TMDBCollectionRef: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

/// TMDB's `/collection/{id}` — the films in a series, so the page can say
/// "Part 2 of 3" and, against the library, how many of them you have seen.
public struct TMDBCollection: Decodable, Equatable, Sendable {
    public let parts: [TMDBCollectionPart]?
    public init(parts: [TMDBCollectionPart]? = nil) { self.parts = parts }
}

public struct TMDBCollectionPart: Decodable, Equatable, Sendable {
    public let id: Int
    public let title: String?
    public let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case releaseDate = "release_date"
    }

    public init(id: Int, title: String? = nil, releaseDate: String? = nil) {
        self.id = id
        self.title = title
        self.releaseDate = releaseDate
    }
}

/// The movie page's TMDB extras, already reduced to what it draws.
public struct TMDBMovieExtras: Equatable, Sendable {
    public let backdropURLs: [String]
    public let keywords: [String]
    public let collectionName: String?
    /// The collection's films in release order — TMDB ids, to match against
    /// the library's `ProviderIds`.
    public let collectionPartTmdbIds: [Int]
    public let budget: Int?
    public let revenue: Int?

    public init(backdropURLs: [String] = [], keywords: [String] = [], collectionName: String? = nil,
                collectionPartTmdbIds: [Int] = [], budget: Int? = nil, revenue: Int? = nil) {
        self.backdropURLs = backdropURLs
        self.keywords = keywords
        self.collectionName = collectionName
        self.collectionPartTmdbIds = collectionPartTmdbIds
        self.budget = budget
        self.revenue = revenue
    }
}

public struct TMDBFindTVResult: Decodable, Equatable, Sendable {
    public let id: Int

    public init(id: Int) {
        self.id = id
    }
}

/// TMDB's `/tv/{id}` response — just the `networks` field this app needs.
public struct TMDBTVResult: Decodable, Equatable, Sendable {
    public let networks: [TMDBNetwork]?

    public init(networks: [TMDBNetwork]? = nil) {
        self.networks = networks
    }

    /// The show's first listed network, as the app's domain `Network` type —
    /// kept separate from the network call so this parsing is unit-testable
    /// against a fixture without a real request.
    public var primaryNetwork: Network? {
        networks?.first?.asNetwork
    }
}

/// One entry in TMDB's `networks` array.
public struct TMDBNetwork: Decodable, Equatable, Sendable {
    public let name: String
    public let logoPath: String?

    enum CodingKeys: String, CodingKey {
        case name
        case logoPath = "logo_path"
    }

    public init(name: String, logoPath: String? = nil) {
        self.name = name
        self.logoPath = logoPath
    }

    /// TMDB image URLs are built from a fixed CDN base + size + path — `w300`
    /// is plenty for a dossier-panel logo lockup.
    var asNetwork: Network {
        let logoURL = logoPath.map { "https://image.tmdb.org/t/p/w300\($0)" }
        return Network(name: name, logoURL: logoURL)
    }
}
