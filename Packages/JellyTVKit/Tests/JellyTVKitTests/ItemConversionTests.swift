import XCTest
@testable import JellyTVKit

final class ItemConversionTests: XCTestCase {

    func makeItem(id: String = "test-1", name: String = "Test Movie",
                  type: String = "Movie", genres: [String]? = ["Thriller"],
                  overview: String? = "An overview",
                  productionYear: Int? = 2026,
                  officialRating: String? = "PG-13",
                  communityRating: Double? = nil,
                  runTimeTicks: Int64? = 7_200_000_000_0,
                  seriesName: String? = nil,
                  indexNumber: Int? = nil,
                  parentIndexNumber: Int? = nil,
                  imageTags: [String: String]? = ["Primary": "tag1"],
                  backdropImageTags: [String]? = ["backdrop1"],
                  userData: JellyfinAPI.JellyfinUserData? = nil,
                  people: [JellyfinAPI.JellyfinPerson]? = nil,
                  criticRating: Double? = nil,
                  providerIds: [String: String]? = nil,
                  taglines: [String]? = nil,
                  studios: [JellyfinAPI.JellyfinNamedItem]? = nil) -> JellyfinAPI.JellyfinItem {
        JellyfinAPI.JellyfinItem(
            id: id, name: name, type: type, overview: overview,
            genres: genres, productionYear: productionYear,
            officialRating: officialRating, communityRating: communityRating,
            runTimeTicks: runTimeTicks,
            seriesName: seriesName, indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber,
            imageTags: imageTags, backdropImageTags: backdropImageTags,
            userData: userData,
            people: people, criticRating: criticRating, providerIds: providerIds,
            taglines: taglines, studios: studios
        )
    }

    func testToMediaItemMovie() {
        let item = makeItem(type: "Movie", genres: ["Thriller"])
        let media = item.toMediaItem(libraryCategory: .movies)
        XCTAssertEqual(media.title, "Test Movie")
        XCTAssertEqual(media.kind, .movie)
        XCTAssertTrue(media.meta.hasPrefix("Movie"))
    }

    func testToMediaItemSeries() {
        let item = makeItem(type: "Series", genres: ["Drama"])
        let media = item.toMediaItem(libraryCategory: .shows)
        XCTAssertEqual(media.kind, .series)
        XCTAssertTrue(media.meta.hasPrefix("Series"))
    }

    func testToContinueWatchingItemMovie() {
        let userData = JellyfinAPI.JellyfinUserData(
            playbackPositionTicks: 1_800_000_000_0,
            lastPlayedDate: "2026-07-10"
        )
        let item = makeItem(
            name: "Undertow", type: "Movie",
            runTimeTicks: 7_200_000_000_0,
            userData: userData
        )
        let cw = item.toContinueWatchingItem(libraryCategory: .movies)
        XCTAssertEqual(cw?.title, "Undertow")
        XCTAssertEqual(cw?.episodeLabel, "Movie")
        XCTAssertEqual(cw?.progress, 0.25)
        XCTAssertFalse(cw?.remaining.isEmpty ?? true)
    }

    func testToContinueWatchingItemEpisode() {
        let userData = JellyfinAPI.JellyfinUserData(
            playbackPositionTicks: 1_200_000_000_0,
            lastPlayedDate: "2026-07-10"
        )
        let item = JellyfinAPI.JellyfinItem(
            id: "test-1", name: "Trench", type: "Episode",
            overview: nil, genres: nil, productionYear: nil,
            officialRating: nil, runTimeTicks: 3_000_000_000_0,
            seriesName: "The Deep Signal",
            indexNumber: 4, parentIndexNumber: 3,
            imageTags: nil, backdropImageTags: nil,
            userData: userData
        )
        let cw = item.toContinueWatchingItem(libraryCategory: MetaCategory.shows)
        XCTAssertEqual(cw?.title, "The Deep Signal")
        XCTAssertTrue(cw?.episodeLabel.contains("S3") ?? false)
        XCTAssertTrue(cw?.episodeLabel.contains("E4") ?? false)
        XCTAssertTrue(cw?.episodeLabel.contains("\"Trench\"") ?? false)
        XCTAssertEqual(cw?.progress, 0.4)
    }

    func testToContinueWatchingItemNoProgress() {
        let item = makeItem(name: "New Movie", type: "Movie")
        let cw = item.toContinueWatchingItem(libraryCategory: .movies)
        XCTAssertEqual(cw?.progress, 0)
    }

    func testToHeroFeature() {
        let userData = JellyfinAPI.JellyfinUserData(
            playbackPositionTicks: 2_000_000_000_0,
            lastPlayedDate: "2026-07-10"
        )
        let item = makeItem(
            name: "The Deep Signal",
            type: "Movie",
            genres: ["Sci-Fi", "Drama"],
            overview: "A deep-sea research crew uncovers a signal.",
            productionYear: 2026,
            officialRating: "TV-MA",
            runTimeTicks: 8_000_000_000_0,
            backdropImageTags: ["backdrop1"],
            userData: userData
        )
        let hero = item.toHeroFeature(libraryCategory: .movies)
        XCTAssertEqual(hero.title, "The Deep Signal")
        XCTAssertEqual(hero.year, "2026")
        XCTAssertEqual(hero.certification, "TV-MA")
        XCTAssertEqual(hero.genre, "Sci-Fi Drama")
        XCTAssertEqual(hero.synopsis, "A deep-sea research crew uncovers a signal.")
        XCTAssertEqual(hero.resumeLabel, "Resume")
        XCTAssertTrue(hero.eyebrow.contains("Featured"))
    }

    func testToHeroFeatureNoProgress() {
        let item = makeItem(name: "Fresh Movie", type: "Movie", genres: ["Action"])
        let hero = item.toHeroFeature(libraryCategory: .movies)
        XCTAssertEqual(hero.resumeLabel, "Play")
    }

    func testToHeroFeatureEpisode() {
        let userData = JellyfinAPI.JellyfinUserData(
            playbackPositionTicks: 1_000_000_000_0,
            lastPlayedDate: "2026-07-10"
        )
        let item = JellyfinAPI.JellyfinItem(
            id: "test-ep", name: "Trench", type: "Episode",
            overview: nil, genres: nil, productionYear: 2026,
            officialRating: "TV-MA", runTimeTicks: 3_000_000_000_0,
            seriesName: "The Deep Signal",
            indexNumber: 4, parentIndexNumber: 3,
            imageTags: nil, backdropImageTags: ["backdrop1"],
            userData: userData
        )
        let hero = item.toHeroFeature(libraryCategory: .shows)
        XCTAssertEqual(hero.resumeLabel, "Resume · E4")
        XCTAssertTrue(hero.episode.contains("S3"))
        XCTAssertTrue(hero.episode.contains("\"Trench\""))
    }

    func testFormatTicksFullMovie() {
        let item = makeItem(
            name: "Movie", type: "Movie",
            runTimeTicks: 7_200_000_000_0  // 7200 seconds = 2h
        )
        let media = item.toMediaItem(libraryCategory: .movies)
        XCTAssertEqual(media.title, "Movie")
    }

    // MARK: - toMovie enrichment

    private var richPeople: [JellyfinAPI.JellyfinPerson] {
        [
            .init(id: "d1", name: "Lena Marchetti", role: nil, type: "Director", primaryImageTag: nil),
            .init(id: "a1", name: "Ines Duval", role: "Maren", type: "Actor", primaryImageTag: "ptag1"),
            .init(id: "a2", name: "Theo Marsh", role: "Elias", type: "Actor", primaryImageTag: nil),
            .init(id: "w1", name: "Sam Reed", role: nil, type: "Writer", primaryImageTag: nil),
        ]
    }

    func testToMovieExtractsDirectorAndCast() {
        let item = makeItem(
            name: "Undertow", communityRating: 8.6,
            people: richPeople, criticRating: 88,
            providerIds: ["Imdb": "tt1234567"],
            taglines: ["The tide remembers."],
            studios: [.init(id: "s1", name: "Benthic Pictures")]
        )
        let movie = item.toMovie(libraryCategory: .movies)
        XCTAssertEqual(movie.director, "Lena Marchetti")
        // Only actors, in billing order, first is lead.
        XCTAssertEqual(movie.cast.map(\.name), ["Ines Duval", "Theo Marsh"])
        XCTAssertTrue(movie.cast.first?.isLead ?? false)
        XCTAssertFalse(movie.cast.last?.isLead ?? true)
        XCTAssertEqual(movie.cast.first?.role, "Maren")
        XCTAssertEqual(movie.tagline, "The tide remembers.")
        XCTAssertEqual(movie.studios, ["Benthic Pictures"])
        XCTAssertEqual(movie.communityRating, 8.6)
        XCTAssertEqual(movie.criticRating, 88)
        XCTAssertEqual(movie.imdbId, "tt1234567")
        XCTAssertEqual(movie.rating, "8.6")
    }

    func testToMovieHeadshotURL() {
        let base = URL(string: "https://jelly.example")!
        let item = makeItem(people: richPeople)
        let movie = item.toMovie(libraryCategory: .movies, imageBaseURL: base)
        // Actor with a PrimaryImageTag gets a headshot URL; the one without stays nil.
        let lead = movie.cast.first { $0.name == "Ines Duval" }
        XCTAssertNotNil(lead?.imageURL)
        XCTAssertTrue(lead?.imageURL?.contains("/Items/a1/Images/Primary") ?? false)
        XCTAssertNil(movie.cast.first { $0.name == "Theo Marsh" }?.imageURL)
    }

    func testEnrichShowKeepsSeasons() {
        let base = SampleCatalog.show
        let item = makeItem(
            name: base.title, type: "Series",
            communityRating: 8.9, people: richPeople, criticRating: 92,
            providerIds: ["Imdb": "tt7654321"], taglines: ["It is answering."]
        )
        let enriched = item.enrich(base)
        XCTAssertEqual(enriched.seasons.count, base.seasons.count)   // seasons preserved
        XCTAssertEqual(enriched.cast.map(\.name), ["Ines Duval", "Theo Marsh"])
        XCTAssertEqual(enriched.tagline, "It is answering.")
        XCTAssertEqual(enriched.imdbId, "tt7654321")
        XCTAssertEqual(enriched.criticRating, 92)
    }
}
