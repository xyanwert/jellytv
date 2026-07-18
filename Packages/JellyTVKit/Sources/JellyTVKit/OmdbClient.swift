import Foundation

/// Minimal client for the OMDb API (omdbapi.com) — an optional, opt-in
/// enrichment source keyed by an item's IMDb id. It supplies the things
/// Jellyfin doesn't: awards/Oscars, a true Rotten Tomatoes %, and Metacritic.
///
/// Everything here degrades to `nil` rather than throwing loudly at call sites:
/// a missing key, an item with no IMDb id, a rate-limited response, or OMDb's
/// `{"Response":"False"}` all just mean "no external data this time".
public struct OmdbClient: Sendable {
    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Fetches OMDb data for an IMDb id (e.g. `tt0107977`). Throws on transport
    /// or decode errors; returns a result whose `isSuccess` is false when OMDb
    /// reports no match.
    public func fetch(imdbId: String) async throws -> OmdbResult {
        var components = URLComponents(string: "https://www.omdbapi.com/")
        components?.queryItems = [
            URLQueryItem(name: "i", value: imdbId),
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "tomatoes", value: "true"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(OmdbResult.self, from: data)
    }
}

/// A decoded OMDb response. OMDb serialises everything as strings and uses
/// PascalCase keys.
public struct OmdbResult: Decodable, Equatable, Sendable {
    public let imdbRating: String?
    public let metascore: String?
    public let awards: String?
    public let ratings: [OmdbRating]?
    public let response: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case imdbRating
        case metascore = "Metascore"
        case awards = "Awards"
        case ratings = "Ratings"
        case response = "Response"
        case error = "Error"
    }

    public init(imdbRating: String? = nil, metascore: String? = nil, awards: String? = nil,
                ratings: [OmdbRating]? = nil, response: String? = nil, error: String? = nil) {
        self.imdbRating = imdbRating
        self.metascore = metascore
        self.awards = awards
        self.ratings = ratings
        self.response = response
        self.error = error
    }

    /// True when OMDb actually found the title.
    public var isSuccess: Bool { response?.caseInsensitiveCompare("True") == .orderedSame }

    /// IMDb score on a 0–10 scale.
    public var imdbScore: Double? {
        guard let imdbRating, imdbRating != "N/A" else { return nil }
        return Double(imdbRating)
    }

    /// Rotten Tomatoes critic score as a whole percentage (e.g. 87).
    public var rottenTomatoesPercent: Int? {
        guard let value = ratings?.first(where: { $0.source == "Rotten Tomatoes" })?.value else { return nil }
        return Int(value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// Metacritic score (0–100), from the top-level `Metascore` or the Ratings list.
    public var metacriticScore: Int? {
        if let metascore, metascore != "N/A", let n = Int(metascore) { return n }
        guard let value = ratings?.first(where: { $0.source == "Metacritic" })?.value else { return nil }
        // Formatted like "74/100".
        return Int(value.split(separator: "/").first.map(String.init) ?? "")
    }

    /// The external ratings distilled into the app's domain type. `nil` when
    /// OMDb returned nothing usable.
    public var externalRatings: ExternalRatings? {
        let r = ExternalRatings(imdbRating: imdbScore,
                                rottenTomatoes: rottenTomatoesPercent,
                                metacritic: metacriticScore)
        return r.isEmpty ? nil : r
    }

    /// Structured awards parsed from the free-text `Awards` string, if any.
    public var parsedAwards: MovieAwards? {
        MovieAwards.parse(awards)
    }
}

/// One entry in OMDb's `Ratings` array (Internet Movie Database / Rotten
/// Tomatoes / Metacritic).
public struct OmdbRating: Decodable, Equatable, Sendable {
    public let source: String
    public let value: String

    enum CodingKeys: String, CodingKey {
        case source = "Source"
        case value = "Value"
    }

    public init(source: String, value: String) {
        self.source = source
        self.value = value
    }
}
