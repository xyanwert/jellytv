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
        var components = URLComponents(string: "\(baseURL)/find/\(imdbId)")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "external_source", value: "imdb_id"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let result: TMDBFindResult = try await get(url)
        return result.tvResults?.first?.id
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

/// TMDB's `/find/{imdbId}` response — just enough to pull a TV id.
public struct TMDBFindResult: Decodable, Equatable, Sendable {
    public let tvResults: [TMDBFindTVResult]?

    enum CodingKeys: String, CodingKey {
        case tvResults = "tv_results"
    }

    public init(tvResults: [TMDBFindTVResult]? = nil) {
        self.tvResults = tvResults
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
