import Foundation

/// Loads the bundled `MockCatalog.json` once and answers the same query
/// shapes `JellyfinClient` issues (`parentId`/`includeItemTypes`/`filters`/
/// `sortBy`/`sortOrder`/`limit`), translating to Jellyfin's PascalCase wire
/// JSON on demand. Read only by `MockJellyfinURLProtocol` — never touches
/// `AppState`/`JellyfinClient` directly.
public final class MockCatalogLoader: @unchecked Sendable {
    public static let shared = MockCatalogLoader()

    private let catalog: MockCatalog
    /// Keyed by `"\(itemId)|\(imageType)|\(index)"` → the real external CDN
    /// URL to proxy for that Jellyfin-shaped image request.
    private var imageURLs: [String: String] = [:]

    private init() {
        catalog = Self.load()
        buildImageIndex()
    }

    private static func load() -> MockCatalog {
        guard let url = Bundle.module.url(forResource: "MockCatalog", withExtension: "json", subdirectory: "MockCatalog"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(MockCatalog.self, from: data) else {
            return MockCatalog()
        }
        return decoded
    }

    private func buildImageIndex() {
        func key(_ id: String, _ type: String, _ index: Int? = nil) -> String { "\(id)|\(type)|\(index ?? -1)" }
        for movie in catalog.movies {
            if let p = movie.posterURL { imageURLs[key(movie.id, "Primary")] = p }
            if let b = movie.backdropURL { imageURLs[key(movie.id, "Backdrop", 0)] = b }
            for c in movie.cast where c.imageURL != nil { imageURLs[key(c.id, "Primary")] = c.imageURL }
        }
        for show in catalog.shows {
            if let p = show.posterURL { imageURLs[key(show.id, "Primary")] = p }
            if let b = show.backdropURL { imageURLs[key(show.id, "Backdrop", 0)] = b }
            for c in show.cast where c.imageURL != nil { imageURLs[key(c.id, "Primary")] = c.imageURL }
            for season in show.seasons {
                if let p = season.posterURL { imageURLs[key(season.id, "Primary")] = p }
                for ep in season.episodes where ep.imageURL != nil { imageURLs[key(ep.id, "Primary")] = ep.imageURL }
            }
        }
    }

    // MARK: - Wire responses

    public func systemInfoJSON() -> [String: Any] {
        ["ServerName": "Mock Jellyfin", "Version": "mock-1.0", "Id": "mock-server", "ProductName": "Jellyfin Mock"]
    }

    public func userViewsJSON() -> [String: Any] {
        let items: [[String: Any]] = catalog.libraries.map {
            ["Id": $0.id, "Name": $0.name, "CollectionType": $0.collectionType, "ImageTags": [String: String]()]
        }
        return ["Items": items, "TotalRecordCount": items.count, "StartIndex": 0]
    }

    public func itemsJSON(parentId: String?, includeItemTypes: String?, filters: String?,
                           sortBy: String?, sortOrder: String?, limit: Int?) -> [String: Any] {
        var items: [[String: Any]] = []
        let wantsMovie = includeItemTypes?.contains("Movie") ?? true
        let wantsSeries = includeItemTypes?.contains("Series") ?? true

        if wantsMovie {
            items += catalog.movies.filter { parentId == nil || $0.libraryId == parentId }.map(movieWire)
        }
        if wantsSeries {
            items += catalog.shows.filter { parentId == nil || $0.libraryId == parentId }.map(showWire)
        }

        // The mock never has in-progress playback, so `IsResumable` always
        // yields an empty Continue Watching row — a fresh-install look, not a bug.
        if filters?.contains("IsResumable") == true {
            items = []
        }

        if sortBy == "Random" {
            items.shuffle()
        } else {
            items.sort { ($0["Name"] as? String ?? "") < ($1["Name"] as? String ?? "") }
            if sortOrder == "Descending" { items.reverse() }
        }

        if let limit, items.count > limit {
            items = Array(items.prefix(limit))
        }

        return ["Items": items, "TotalRecordCount": items.count, "StartIndex": 0]
    }

    public func itemDetailJSON(itemId: String) -> [String: Any]? {
        if let movie = catalog.movies.first(where: { $0.id == itemId }) { return movieWire(movie) }
        if let show = catalog.shows.first(where: { $0.id == itemId }) { return showWire(show) }
        return nil
    }

    public func seasonsJSON(seriesId: String) -> [String: Any] {
        let show = catalog.shows.first { $0.id == seriesId }
        let items = (show?.seasons ?? []).map(seasonWire)
        return ["Items": items, "TotalRecordCount": items.count, "StartIndex": 0]
    }

    public func episodesJSON(seriesId: String, seasonId: String?) -> [String: Any] {
        guard let show = catalog.shows.first(where: { $0.id == seriesId }),
              let season = show.seasons.first(where: { seasonId == nil || $0.id == seasonId }) else {
            return ["Items": [[String: Any]](), "TotalRecordCount": 0, "StartIndex": 0]
        }
        let items = season.episodes.map {
            episodeWire($0, seasonIndex: season.indexNumber, seriesId: show.id, seriesName: show.name)
        }
        return ["Items": items, "TotalRecordCount": items.count, "StartIndex": 0]
    }

    public func playbackInfoJSON(itemId: String) -> [String: Any] {
        [
            "PlaySessionId": UUID().uuidString,
            "MediaSources": [[
                "Id": "\(itemId)-media",
                "Container": "mp4",
                "SupportsDirectPlay": true,
                "SupportsDirectStream": true,
                "MediaStreams": [["Type": "Video", "Codec": "h264", "Width": 1920, "Height": 1080]],
            ]],
        ]
    }

    /// The real external CDN URL to proxy for a Jellyfin-shaped image request.
    public func imageURL(itemId: String, type: String, index: Int?) -> URL? {
        imageURLs["\(itemId)|\(type)|\(index ?? -1)"].flatMap(URL.init(string:))
    }

    // MARK: - Wire builders

    private func personWire(_ c: MockCastMember, roleType: String) -> [String: Any] {
        var dict: [String: Any] = ["Id": c.id, "Name": c.name, "Type": roleType]
        if let role = c.role { dict["Role"] = role }
        if c.imageURL != nil { dict["PrimaryImageTag"] = "1" }
        return dict
    }

    private func movieWire(_ m: MockMovie) -> [String: Any] {
        var people: [[String: Any]] = m.cast.map { personWire($0, roleType: "Actor") }
        if let director = m.director {
            people.insert(["Id": MockIdentifiers.stableId("person-director-\(m.id)"), "Name": director, "Type": "Director"], at: 0)
        }
        var imageTags: [String: String] = [:]
        if m.posterURL != nil { imageTags["Primary"] = "1" }

        var dict: [String: Any] = [
            "Id": m.id,
            "Name": m.name,
            "Type": "Movie",
            "Genres": m.genres,
            "Tags": [String](),
            "ImageTags": imageTags,
            "BackdropImageTags": m.backdropURL != nil ? ["1"] : [String](),
            "Studios": m.studios.map { ["Id": MockIdentifiers.stableId("studio-\($0)"), "Name": $0] },
            "Taglines": m.tagline.map { [$0] } ?? [String](),
            "People": people,
        ]
        if let overview = m.overview { dict["Overview"] = overview }
        if let year = m.productionYear { dict["ProductionYear"] = year }
        if let date = m.premiereDate { dict["PremiereDate"] = date }
        if let rating = m.officialRating { dict["OfficialRating"] = rating }
        if let cr = m.communityRating { dict["CommunityRating"] = cr }
        if let cr = m.criticRating { dict["CriticRating"] = cr }
        if let rt = m.runtimeTicks { dict["RunTimeTicks"] = rt }
        if let imdb = m.imdbId { dict["ProviderIds"] = ["Imdb": imdb] }
        return dict
    }

    private func showWire(_ s: MockShow) -> [String: Any] {
        var imageTags: [String: String] = [:]
        if s.posterURL != nil { imageTags["Primary"] = "1" }

        var dict: [String: Any] = [
            "Id": s.id,
            "Name": s.name,
            "Type": "Series",
            "Genres": s.genres,
            "Tags": [String](),
            "ImageTags": imageTags,
            "BackdropImageTags": s.backdropURL != nil ? ["1"] : [String](),
            "Studios": s.studios.map { ["Id": MockIdentifiers.stableId("studio-\($0)"), "Name": $0] },
            "Taglines": s.tagline.map { [$0] } ?? [String](),
            "People": s.cast.map { personWire($0, roleType: "Actor") },
            "ChildCount": s.seasons.count,
        ]
        if let overview = s.overview { dict["Overview"] = overview }
        if let year = s.productionYear { dict["ProductionYear"] = year }
        if let date = s.premiereDate { dict["PremiereDate"] = date }
        if let rating = s.officialRating { dict["OfficialRating"] = rating }
        if let cr = s.communityRating { dict["CommunityRating"] = cr }
        if let cr = s.criticRating { dict["CriticRating"] = cr }
        if let imdb = s.imdbId { dict["ProviderIds"] = ["Imdb": imdb] }
        if let status = s.status { dict["Status"] = status }
        if let endDate = s.endDate { dict["EndDate"] = endDate }
        return dict
    }

    private func seasonWire(_ season: MockSeason) -> [String: Any] {
        var imageTags: [String: String] = [:]
        if season.posterURL != nil { imageTags["Primary"] = "1" }
        return [
            "Id": season.id,
            "Name": season.name,
            "Type": "Season",
            "IndexNumber": season.indexNumber,
            "ImageTags": imageTags,
            "ChildCount": season.episodes.count,
        ]
    }

    private func episodeWire(_ ep: MockEpisode, seasonIndex: Int, seriesId: String, seriesName: String) -> [String: Any] {
        var imageTags: [String: String] = [:]
        if ep.imageURL != nil { imageTags["Primary"] = "1" }
        var dict: [String: Any] = [
            "Id": ep.id,
            "Name": ep.name,
            "Type": "Episode",
            "IndexNumber": ep.indexNumber,
            "ParentIndexNumber": seasonIndex,
            "SeriesId": seriesId,
            "SeriesName": seriesName,
            "ImageTags": imageTags,
        ]
        if let overview = ep.overview { dict["Overview"] = overview }
        if let rt = ep.runtimeTicks { dict["RunTimeTicks"] = rt }
        return dict
    }
}
