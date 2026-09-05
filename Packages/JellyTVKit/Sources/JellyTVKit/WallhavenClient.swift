import Foundation

/// Wallhaven search — stand-in artwork for items the server has no image for.
///
/// Ported from `/Users/xyan/code/jelly-tv-ios`'s `Core/Wallhaven/WallhavenClient.swift`,
/// stripped of the parts that existed only to back its wallpaper *picker
/// sheet* (per-library query overrides, sort/category/pool-size controls, a
/// rotation cursor). This is the automatic path only: a fixed query per
/// category, one request, a handful of URLs back.
///
/// **Not an actor, unlike v1's.** That actor's stated job was to serialise
/// requests and back off Wallhaven's 45/min limit — but it implemented no
/// queueing, no 429 handling and no backoff, so it never did that. One
/// request per screen visit is nowhere near the ceiling, and a plain
/// `Sendable` struct matches how `OmdbClient`/`TMDBClient` are already built
/// here.
public struct WallhavenClient: Sendable {
    /// Wallhaven's own filter bitmasks, as 3-character strings.
    ///
    /// `categories` reads `general|anime|people`; `purity` reads
    /// `sfw|sketchy|nsfw`.
    ///
    /// **The NSFW bit is never set, by design.** Wallhaven only honours it for
    /// an API key belonging to an account that has enabled NSFW browsing, and
    /// silently drops those results otherwise — so requesting it without one
    /// buys nothing. v1 reached suggestive imagery a different way and this
    /// keeps that: ask for the *sketchy* tier and let the search term do the
    /// work. Verified against the live API: `q=porn` with `purity=110` comes
    /// back roughly two-thirds sketchy.
    public struct Filters: Sendable {
        public var query: String
        public var categories: String
        public var purity: String
        public var atLeast: String
        public var ratios: String

        public init(query: String, categories: String = "100", purity: String = "100",
                    atLeast: String = "1920x1080", ratios: String = "16x9,16x10,21x9") {
            self.query = query
            self.categories = categories
            self.purity = purity
            self.atLeast = atLeast
            self.ratios = ratios
        }

        /// Landscape wallpapers loosely about home video. Strictly SFW: the
        /// only guard on that boundary is this bitmask, since nothing
        /// re-checks what comes back.
        public static let homeVideos = Filters(query: "video", categories: "100", purity: "100")

        /// The adult counterpart. `categories: "001"` is people-only, and the
        /// purity ceiling stays at sketchy — see the note on `Filters`.
        public static let adultVideos = Filters(query: "porn", categories: "001", purity: "110")
    }

    public struct Wallpaper: Decodable, Sendable, Identifiable {
        public struct Thumbs: Decodable, Sendable {
            public let large: String
            public let original: String
            public let small: String
        }

        public let id: String
        /// The full-resolution image. Far too big for a grid cell — prefer
        /// `thumbs.large`.
        public let path: String
        public let thumbs: Thumbs
        public let purity: String
        public let resolution: String

        /// The card-sized image (`th.wallhaven.cc/lg/…`).
        public var thumbnailURL: URL? { URL(string: thumbs.large) }
        public var fullImageURL: URL? { URL(string: path) }
    }

    private struct SearchResponse: Decodable {
        let data: [Wallpaper]
    }

    /// Optional. Anonymous requests work for everything this app asks for —
    /// a key only matters for the NSFW purity bit, which is deliberately never
    /// requested. Kept as a parameter so a future Settings field has somewhere
    /// to go, but nothing sets it today.
    private let apiKey: String?
    private let session: URLSession

    public init(apiKey: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// One page of results — Wallhaven returns 24. Throws on any failure; the
    /// caller is expected to be the single choke point that turns that into
    /// "no artwork" rather than an error the user sees.
    public func search(_ filters: Filters) async throws -> [Wallpaper] {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")
        var query = [
            URLQueryItem(name: "q", value: filters.query),
            URLQueryItem(name: "categories", value: filters.categories),
            URLQueryItem(name: "purity", value: filters.purity),
            URLQueryItem(name: "atleast", value: filters.atLeast),
            URLQueryItem(name: "ratios", value: filters.ratios),
            // Wallhaven reshuffles server-side per request, so repeat visits
            // don't all land on the same top-24.
            URLQueryItem(name: "sorting", value: "random"),
        ]
        if let apiKey, !apiKey.isEmpty {
            query.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        components?.queryItems = query
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(SearchResponse.self, from: data).data
    }

    /// A random sample of one search — what a screen actually needs.
    ///
    /// The default takes the whole page. Wallhaven returns 24 per request
    /// either way, so a smaller sample saves nothing at the API and only makes
    /// a grid visibly repeat itself; the cost of the extra images is a few
    /// hundred KB, once.
    ///
    /// Sampled client-side on top of the server's own random sort, so two
    /// visits rarely draw the same set even out of an identical page.
    public func pool(_ filters: Filters, count: Int = 24) async throws -> [URL] {
        try await search(filters)
            .shuffled()
            .prefix(count)
            .compactMap(\.thumbnailURL)
    }
}
