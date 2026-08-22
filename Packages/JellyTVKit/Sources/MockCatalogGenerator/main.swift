import Foundation
import JellyTVKit

// Dev-only CLI: seeds `Resources/MockCatalog/MockCatalog.json` with real
// metadata from TMDB (movies/shows) and AniList (anime, no key needed), so
// `JT_MOCK_SERVER=1` can exercise the app end-to-end without a live Jellyfin
// server. Rerunnable — ids are content-derived (`MockIdentifiers.stableId`),
// so regenerating never changes an existing item's id.
//
// Usage: swift run --package-path Packages/JellyTVKit MockCatalogGenerator
// Needs a free TMDB key — see `Packages/JellyTVKit/.env.local` (gitignored),
// either `TMDB_API_KEY=...` on its own line, or the `TMDB_API_KEY` env var.

// MARK: - Paths (resolved relative to this source file, not the CWD)

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // MockCatalogGenerator/
    .deletingLastPathComponent() // Sources/
    .deletingLastPathComponent() // package root
let envFile = packageRoot.appendingPathComponent(".env.local")
let outputFile = packageRoot.appendingPathComponent("Sources/JellyTVKit/Resources/MockCatalog/MockCatalog.json")

func loadTMDBKey() -> String? {
    if let key = ProcessInfo.processInfo.environment["TMDB_API_KEY"], !key.isEmpty { return key }
    guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
    for line in contents.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("TMDB_API_KEY=") else { continue }
        let value = trimmed.dropFirst("TMDB_API_KEY=".count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
    return nil
}

func envInt(_ name: String, default def: Int) -> Int {
    ProcessInfo.processInfo.environment[name].flatMap(Int.init) ?? def
}

// MARK: - TMDB

enum TMDB {
    static let base = "https://api.themoviedb.org/3"

    static func get<T: Decodable>(_ path: String, _ type: T.Type, apiKey: String,
                                   extraQuery: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: base + path)!
        var items = [URLQueryItem(name: "api_key", value: apiKey)]
        for (k, v) in extraQuery { items.append(URLQueryItem(name: k, value: v)) }
        components.queryItems = items
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "TMDB", code: http.statusCode,
                           userInfo: [NSLocalizedDescriptionKey: "TMDB \(path) returned \(http.statusCode)"])
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    struct ListResponse<T: Decodable>: Decodable { let results: [T] }
    struct MovieSummary: Decodable { let id: Int }
    struct TVSummary: Decodable { let id: Int }
    struct Genre: Decodable { let name: String }
    struct Company: Decodable { let name: String }
    struct CastMember: Decodable { let name: String; let character: String?; let profilePath: String? }
    struct CrewMember: Decodable { let name: String; let job: String }
    struct Credits: Decodable { let cast: [CastMember]?; let crew: [CrewMember]? }
    struct ExternalIds: Decodable { let imdbId: String? }

    struct MovieDetail: Decodable {
        let id: Int
        let title: String
        let overview: String?
        let genres: [Genre]?
        let releaseDate: String?
        let voteAverage: Double?
        let runtime: Int?
        let tagline: String?
        let productionCompanies: [Company]?
        let posterPath: String?
        let backdropPath: String?
        let imdbId: String?
        let credits: Credits?
    }

    struct SeasonSummary: Decodable { let seasonNumber: Int; let name: String?; let posterPath: String? }

    struct TVDetail: Decodable {
        let id: Int
        let name: String
        let overview: String?
        let genres: [Genre]?
        let firstAirDate: String?
        let voteAverage: Double?
        let tagline: String?
        let productionCompanies: [Company]?
        let posterPath: String?
        let backdropPath: String?
        let status: String?
        let lastAirDate: String?
        let seasons: [SeasonSummary]?
        let credits: Credits?
        let externalIds: ExternalIds?
    }

    struct EpisodeSummary: Decodable {
        let episodeNumber: Int
        let name: String?
        let overview: String?
        let runtime: Int?
        let stillPath: String?
    }
    struct SeasonDetail: Decodable { let episodes: [EpisodeSummary]? }

    static func imageURL(_ path: String?) -> String? {
        guard let path else { return nil }
        return "https://image.tmdb.org/t/p/original\(path)"
    }
}

func ticksFromMinutes(_ minutes: Int?) -> Int64? {
    guard let minutes else { return nil }
    return Int64(minutes) * 60 * 10_000_000
}

func fetchPopularMovies(apiKey: String, count: Int) async throws -> [MockMovie] {
    let list = try await TMDB.get("/movie/popular", TMDB.ListResponse<TMDB.MovieSummary>.self, apiKey: apiKey)
    var movies: [MockMovie] = []
    for summary in list.results.prefix(count) {
        guard let detail = try? await TMDB.get("/movie/\(summary.id)", TMDB.MovieDetail.self, apiKey: apiKey,
                                                extraQuery: ["append_to_response": "credits"]) else { continue }
        let cast = (detail.credits?.cast ?? []).prefix(8).enumerated().map { index, c in
            MockCastMember(id: MockIdentifiers.stableId("person-tmdb-\(detail.id)-\(index)"),
                            name: c.name, role: c.character, imageURL: TMDB.imageURL(c.profilePath))
        }
        movies.append(MockMovie(
            id: MockIdentifiers.stableId("movie-tmdb-\(detail.id)"),
            libraryId: MockLibraryKind.movies.id,
            name: detail.title,
            overview: detail.overview,
            genres: (detail.genres ?? []).map(\.name),
            productionYear: detail.releaseDate.flatMap { Int($0.prefix(4)) },
            premiereDate: detail.releaseDate,
            communityRating: detail.voteAverage,
            criticRating: detail.voteAverage.map { $0 * 10 },
            runtimeTicks: ticksFromMinutes(detail.runtime),
            tagline: (detail.tagline?.isEmpty == false) ? detail.tagline : nil,
            studios: (detail.productionCompanies ?? []).map(\.name),
            director: detail.credits?.crew?.first { $0.job == "Director" }?.name,
            imdbId: detail.imdbId,
            cast: Array(cast),
            posterURL: TMDB.imageURL(detail.posterPath),
            backdropURL: TMDB.imageURL(detail.backdropPath)
        ))
    }
    return movies
}

func fetchPopularShows(apiKey: String, count: Int, seasonsPerShow: Int, episodesPerSeason: Int) async throws -> [MockShow] {
    let list = try await TMDB.get("/tv/popular", TMDB.ListResponse<TMDB.TVSummary>.self, apiKey: apiKey)
    var shows: [MockShow] = []
    for summary in list.results.prefix(count) {
        guard let detail = try? await TMDB.get("/tv/\(summary.id)", TMDB.TVDetail.self, apiKey: apiKey,
                                                extraQuery: ["append_to_response": "credits,external_ids"]) else { continue }

        var seasons: [MockSeason] = []
        let candidateSeasons = (detail.seasons ?? []).filter { $0.seasonNumber > 0 }.prefix(seasonsPerShow)
        for seasonSummary in candidateSeasons {
            let seasonDetail = try? await TMDB.get(
                "/tv/\(summary.id)/season/\(seasonSummary.seasonNumber)", TMDB.SeasonDetail.self, apiKey: apiKey)
            let episodes = (seasonDetail?.episodes ?? []).prefix(episodesPerSeason).map { ep in
                MockEpisode(id: MockIdentifiers.stableId("episode-tmdb-\(summary.id)-\(seasonSummary.seasonNumber)-\(ep.episodeNumber)"),
                            indexNumber: ep.episodeNumber, name: ep.name ?? "Episode \(ep.episodeNumber)",
                            overview: ep.overview, runtimeTicks: ticksFromMinutes(ep.runtime),
                            imageURL: TMDB.imageURL(ep.stillPath))
            }
            seasons.append(MockSeason(
                id: MockIdentifiers.stableId("season-tmdb-\(summary.id)-\(seasonSummary.seasonNumber)"),
                indexNumber: seasonSummary.seasonNumber,
                name: seasonSummary.name ?? "Season \(seasonSummary.seasonNumber)",
                posterURL: TMDB.imageURL(seasonSummary.posterPath), episodes: Array(episodes)))
        }

        let cast = (detail.credits?.cast ?? []).prefix(8).enumerated().map { index, c in
            MockCastMember(id: MockIdentifiers.stableId("person-tmdb-tv-\(detail.id)-\(index)"),
                            name: c.name, role: c.character, imageURL: TMDB.imageURL(c.profilePath))
        }
        let ended = detail.status == "Ended" || detail.status == "Canceled"

        shows.append(MockShow(
            id: MockIdentifiers.stableId("show-tmdb-\(detail.id)"),
            libraryId: MockLibraryKind.shows.id,
            name: detail.name,
            overview: detail.overview,
            genres: (detail.genres ?? []).map(\.name),
            productionYear: detail.firstAirDate.flatMap { Int($0.prefix(4)) },
            premiereDate: detail.firstAirDate,
            communityRating: detail.voteAverage,
            criticRating: detail.voteAverage.map { $0 * 10 },
            tagline: (detail.tagline?.isEmpty == false) ? detail.tagline : nil,
            studios: (detail.productionCompanies ?? []).map(\.name),
            imdbId: detail.externalIds?.imdbId,
            status: ended ? "Ended" : "Continuing",
            endDate: ended ? detail.lastAirDate : nil,
            cast: Array(cast),
            posterURL: TMDB.imageURL(detail.posterPath),
            backdropURL: TMDB.imageURL(detail.backdropPath),
            seasons: seasons
        ))
    }
    return shows
}

// MARK: - AniList (no key needed)

enum AniList {
    struct Response: Decodable { let data: DataField }
    struct DataField: Decodable { let Page: PageField }
    struct PageField: Decodable { let media: [Media] }
    struct Title: Decodable { let romaji: String?; let english: String? }
    struct FuzzyDate: Decodable { let year: Int?; let month: Int?; let day: Int? }
    struct CoverImage: Decodable { let extraLarge: String?; let large: String? }
    struct StudioNode: Decodable { let name: String }
    struct StudioConnection: Decodable { let nodes: [StudioNode] }
    struct CharacterImage: Decodable { let large: String? }
    struct CharacterName: Decodable { let full: String? }
    struct CharacterNode: Decodable { let id: Int; let name: CharacterName; let image: CharacterImage? }
    struct CharacterEdge: Decodable { let role: String?; let node: CharacterNode }
    struct CharacterConnection: Decodable { let edges: [CharacterEdge] }
    struct StreamingEpisode: Decodable { let title: String?; let thumbnail: String? }

    struct Media: Decodable {
        let id: Int
        let title: Title
        let description: String?
        let genres: [String]?
        let averageScore: Int?
        let seasonYear: Int?
        let startDate: FuzzyDate?
        let endDate: FuzzyDate?
        let status: String?
        let episodes: Int?
        let duration: Int?
        let format: String?
        let coverImage: CoverImage?
        let bannerImage: String?
        let studios: StudioConnection?
        let characters: CharacterConnection?
        let streamingEpisodes: [StreamingEpisode]?
    }

    static let query = """
    query ($page: Int, $perPage: Int) {
      Page(page: $page, perPage: $perPage) {
        media(type: ANIME, sort: POPULARITY_DESC) {
          id
          title { romaji english }
          description(asHtml: false)
          genres
          averageScore
          seasonYear
          startDate { year month day }
          endDate { year month day }
          status
          episodes
          duration
          format
          coverImage { extraLarge large }
          bannerImage
          studios(isMain: true) { nodes { name } }
          characters(sort: ROLE, perPage: 8) {
            edges { role node { id name { full } image { large } } }
          }
          streamingEpisodes { title thumbnail }
        }
      }
    }
    """

    static func fetch(count: Int) async throws -> [Media] {
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["query": query, "variables": ["page": 1, "perPage": count]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Response.self, from: data).data.Page.media
    }
}

func htmlStripped(_ s: String?) -> String? {
    guard let s else { return nil }
    return s.replacingOccurrences(of: "<br>", with: "\n")
        .replacingOccurrences(of: "<i>", with: "").replacingOccurrences(of: "</i>", with: "")
        .replacingOccurrences(of: "<b>", with: "").replacingOccurrences(of: "</b>", with: "")
}

func aniListDateString(_ d: AniList.FuzzyDate?) -> String? {
    guard let d, let year = d.year else { return nil }
    return String(format: "%04d-%02d-%02dT00:00:00.000Z", year, d.month ?? 1, d.day ?? 1)
}

func aniListCast(_ media: AniList.Media) -> [MockCastMember] {
    (media.characters?.edges ?? []).prefix(8).map { edge in
        MockCastMember(id: MockIdentifiers.stableId("person-anilist-\(edge.node.id)"),
                        name: edge.node.name.full ?? "Unknown", role: edge.role,
                        imageURL: edge.node.image?.large)
    }
}

func aniListTitle(_ media: AniList.Media) -> String { media.title.english ?? media.title.romaji ?? "Untitled" }

func makeMockAnimeMovie(_ media: AniList.Media) -> MockMovie {
    MockMovie(
        id: MockIdentifiers.stableId("movie-anilist-\(media.id)"),
        libraryId: MockLibraryKind.animeMovies.id,
        name: aniListTitle(media),
        overview: htmlStripped(media.description),
        genres: media.genres ?? [],
        productionYear: media.seasonYear ?? media.startDate?.year,
        premiereDate: aniListDateString(media.startDate),
        communityRating: media.averageScore.map { Double($0) / 10 },
        criticRating: media.averageScore.map(Double.init),
        runtimeTicks: ticksFromMinutes(media.duration),
        studios: (media.studios?.nodes ?? []).map(\.name),
        cast: aniListCast(media),
        posterURL: media.coverImage?.extraLarge ?? media.coverImage?.large,
        backdropURL: media.bannerImage
    )
}

func makeMockAnimeShow(_ media: AniList.Media) -> MockShow {
    let episodeCount = max(media.episodes ?? 12, 1)
    let streaming = media.streamingEpisodes ?? []
    let episodes = (1...episodeCount).map { i -> MockEpisode in
        let streamEntry = streaming.count >= i ? streaming[i - 1] : nil
        return MockEpisode(id: MockIdentifiers.stableId("episode-anilist-\(media.id)-\(i)"),
                            indexNumber: i, name: streamEntry?.title ?? "Episode \(i)",
                            runtimeTicks: ticksFromMinutes(media.duration), imageURL: streamEntry?.thumbnail)
    }
    let season = MockSeason(id: MockIdentifiers.stableId("season-anilist-\(media.id)-1"), indexNumber: 1,
                             name: "Season 1", posterURL: media.coverImage?.extraLarge ?? media.coverImage?.large,
                             episodes: episodes)
    let ended = media.status != "RELEASING"
    return MockShow(
        id: MockIdentifiers.stableId("show-anilist-\(media.id)"),
        libraryId: MockLibraryKind.anime.id,
        name: aniListTitle(media),
        overview: htmlStripped(media.description),
        genres: media.genres ?? [],
        productionYear: media.seasonYear ?? media.startDate?.year,
        premiereDate: aniListDateString(media.startDate),
        communityRating: media.averageScore.map { Double($0) / 10 },
        criticRating: media.averageScore.map(Double.init),
        studios: (media.studios?.nodes ?? []).map(\.name),
        status: ended ? "Ended" : "Continuing",
        endDate: ended ? aniListDateString(media.endDate) : nil,
        cast: aniListCast(media),
        posterURL: media.coverImage?.extraLarge ?? media.coverImage?.large,
        backdropURL: media.bannerImage,
        seasons: [season]
    )
}

// MARK: - Entry point

guard let tmdbKey = loadTMDBKey() else {
    print("""
    No TMDB API key found. Either:
      - set TMDB_API_KEY in the environment, or
      - create \(envFile.path) containing a line: TMDB_API_KEY=your_key_here
    Register a free key at https://www.themoviedb.org/settings/api
    """)
    exit(1)
}

let movieCount = envInt("TMDB_MOVIE_COUNT", default: 12)
let showCount = envInt("TMDB_SHOW_COUNT", default: 8)
let animeCount = envInt("ANILIST_COUNT", default: 8)
let seasonsPerShow = envInt("TMDB_SEASONS_PER_SHOW", default: 2)
let episodesPerSeason = envInt("TMDB_EPISODES_PER_SEASON", default: 6)

do {
    print("Fetching \(movieCount) movies + \(showCount) shows from TMDB, \(animeCount) anime from AniList…")

    async let popularMovies = fetchPopularMovies(apiKey: tmdbKey, count: movieCount)
    async let popularShows = fetchPopularShows(apiKey: tmdbKey, count: showCount,
                                                seasonsPerShow: seasonsPerShow, episodesPerSeason: episodesPerSeason)
    async let aniListMedia = AniList.fetch(count: animeCount)

    let (movies, shows, anime) = try await (popularMovies, popularShows, aniListMedia)

    var allMovies = movies
    var allShows = shows
    for media in anime {
        if media.format == "MOVIE" {
            allMovies.append(makeMockAnimeMovie(media))
        } else {
            allShows.append(makeMockAnimeShow(media))
        }
    }

    let libraries = MockLibraryKind.allCases.map { MockLibrary(id: $0.id, name: $0.rawValue, collectionType: $0.collectionType) }
    let catalog = MockCatalog(libraries: libraries, movies: allMovies, shows: allShows)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(catalog)
    try FileManager.default.createDirectory(at: outputFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: outputFile)

    print("Wrote \(allMovies.count) movies, \(allShows.count) shows (\(libraries.count) libraries) to \(outputFile.path)")
} catch {
    print("Generation failed: \(error)")
    exit(1)
}
