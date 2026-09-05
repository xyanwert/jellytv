import XCTest
@testable import JellyTVKit

/// The movie page's "movie night" data: chapters and media streams decoded
/// off a detail item, the person mapping, the facts arithmetic, and the TMDB
/// extras reduction.
final class MovieNightTests: XCTestCase {

    // MARK: - Detail item → Movie

    private let detailJSON = """
    {
      "Id": "m1", "Name": "The Matrix", "Type": "Movie", "ProductionYear": 1999,
      "RunTimeTicks": 81660000000,
      "ProviderIds": {"Imdb": "tt0133093", "Tmdb": "603"},
      "Chapters": [
        {"Name": "Follow the White Rabbit", "StartPositionTicks": 0, "ImageTag": "aaa"},
        {"Name": "The Red Pill", "StartPositionTicks": 6000000000, "ImageTag": "bbb"},
        {"Name": "No Image", "StartPositionTicks": 12000000000}
      ],
      "MediaStreams": [
        {"Type": "Video", "Codec": "hevc"},
        {"Type": "Audio", "Language": "eng", "DisplayLanguage": "English", "Channels": 6, "ChannelLayout": "5.1", "IsDefault": true},
        {"Type": "Audio", "Language": "fra", "DisplayLanguage": "French", "Channels": 2},
        {"Type": "Subtitle", "Language": "eng", "DisplayLanguage": "English"},
        {"Type": "Subtitle", "Language": "spa", "DisplayLanguage": "Spanish"},
        {"Type": "Subtitle", "Language": "eng", "DisplayLanguage": "English"}
      ],
      "LocalTrailerCount": 0
    }
    """

    private func decodeDetail() throws -> JellyfinAPI.JellyfinItem {
        try JSONDecoder().decode(JellyfinAPI.JellyfinItem.self, from: Data(detailJSON.utf8))
    }

    func testChaptersDecodeAndOnlyImagedOnesGetURLs() throws {
        let movie = try decodeDetail().toMovie(libraryCategory: .movies, imageBaseURL: URL(string: "http://tv.local:8096"))
        XCTAssertEqual(movie.chapters.count, 3)
        XCTAssertEqual(movie.chapters[1].title, "The Red Pill")
        XCTAssertEqual(movie.chapters[1].startSeconds, 600)
        XCTAssertEqual(movie.chapters[1].timestamp, "10:00")
        XCTAssertEqual(movie.chapters[1].imageURL,
                       "http://tv.local:8096/Items/m1/Images/Chapter/1?tag=bbb&maxWidth=640")
        XCTAssertNil(movie.chapters[2].imageURL, "a chapter without an ImageTag has no frame to show")
        XCTAssertEqual(movie.chapters[2].startTicks, 12_000_000_000)
    }

    func testAudioAndSubtitleFactsComeFromStreams() throws {
        let movie = try decodeDetail().toMovie(libraryCategory: .movies)
        XCTAssertEqual(movie.audioLine, "English 5.1", "the default stream wins over the first one")
        XCTAssertEqual(movie.subtitleLanguages, ["English", "Spanish"], "distinct, in stream order")
        XCTAssertEqual(movie.tmdbId, "603")
    }

    func testMovieWithoutStreamsHasEmptyFacts() {
        let item = JellyfinAPI.JellyfinItem(id: "x", name: "Bare", type: "Movie")
        let movie = item.toMovie(libraryCategory: .movies)
        XCTAssertEqual(movie.audioLine, "")
        XCTAssertTrue(movie.subtitleLanguages.isEmpty)
        XCTAssertTrue(movie.chapters.isEmpty)
    }

    func testChapterTimestampPastTheHour() {
        XCTAssertEqual(Chapter(index: 0, title: "", startSeconds: 3735).timestamp, "1:02:15")
        XCTAssertEqual(Chapter(index: 0, title: "", startSeconds: 4).timestamp, "0:04")
    }

    // MARK: - Person

    func testPersonMappingReadsJellyfinsReusedItemFields() {
        let item = JellyfinAPI.JellyfinItem(
            id: "p1", name: "Christopher Plummer", type: "Person",
            overview: "  A Canadian actor whose career spanned seven decades.\n",
            premiereDate: "1929-12-13T07:00:00.0000000Z",
            productionLocations: ["Toronto, Ontario, Canada"],
            endDate: "2021-02-05T07:00:00.0000000Z"
        )
        let person = item.toPerson()
        XCTAssertEqual(person.name, "Christopher Plummer")
        XCTAssertEqual(person.bio, "A Canadian actor whose career spanned seven decades.")
        XCTAssertEqual(person.birthplace, "Toronto, Ontario, Canada")
        XCTAssertEqual(MovieNightFacts.lifespan(birthDate: person.birthDate, deathDate: person.deathDate), "1929 – 2021")
        XCTAssertEqual(MovieNightFacts.ageAtRelease(birthDate: person.birthDate, releaseYear: 2009), 80)
    }

    // MARK: - Facts

    func testJellyfinDatesWithSevenFractionalDigitsParse() {
        let date = MovieNightFacts.date(fromJellyfin: "1929-12-13T07:00:00.0000000Z")
        XCTAssertNotNil(date)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(calendar.component(.year, from: date!), 1929)
        XCTAssertEqual(calendar.component(.month, from: date!), 12)
        XCTAssertNil(MovieNightFacts.date(fromJellyfin: nil))
        XCTAssertNil(MovieNightFacts.date(fromJellyfin: "1929"))
    }

    func testEndsAtUsesRemainingRuntime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let twoHours: Int64 = 2 * 3600 * 10_000_000
        let halfHourIn: Int64 = 1800 * 10_000_000
        XCTAssertEqual(MovieNightFacts.endsAt(now: now, runtimeTicks: twoHours, resumeTicks: nil)?
            .timeIntervalSince(now), 7200)
        XCTAssertEqual(MovieNightFacts.endsAt(now: now, runtimeTicks: twoHours, resumeTicks: halfHourIn)?
            .timeIntervalSince(now), 5400)
        XCTAssertNil(MovieNightFacts.endsAt(now: now, runtimeTicks: nil, resumeTicks: nil))
        XCTAssertNil(MovieNightFacts.endsAt(now: now, runtimeTicks: 0, resumeTicks: nil))
    }

    func testEndsAtLabelIsAnUppercaseClockTime() {
        let now = Date(timeIntervalSince1970: 0)   // 00:00 UTC
        let label = MovieNightFacts.endsAtLabel(now: now, runtimeTicks: 90 * 60 * 10_000_000, resumeTicks: nil,
                                                locale: Locale(identifier: "en_US"),
                                                timeZone: TimeZone(identifier: "UTC")!)
        // Foundation separates "1:30" and "AM" with a narrow no-break space on
        // recent OSes; the assertion is about the words, not the whitespace.
        let normalized = label?.replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(normalized, "ENDS 1:30 AM")
    }

    func testAgeAtReleaseRejectsNonsense() {
        let birth = MovieNightFacts.date(fromJellyfin: "1964-09-02")
        XCTAssertEqual(MovieNightFacts.ageAtRelease(birthDate: birth, releaseYear: 1999), 35)
        XCTAssertNil(MovieNightFacts.ageAtRelease(birthDate: birth, releaseYear: 1950), "born after the film")
        XCTAssertNil(MovieNightFacts.ageAtRelease(birthDate: nil, releaseYear: 1999))
    }

    func testTopPercentNeedsTwentyRatingsAndNeverSaysZero() {
        let few = Array(repeating: 5.0, count: 10)
        XCTAssertNil(MovieNightFacts.topPercent(rating: 9, among: few))
        let many = (1...25).map { Double($0) / 3 }   // 0.33 … 8.33
        XCTAssertEqual(MovieNightFacts.topPercent(rating: 9, among: many), 1, "the best film is top 1%, not top 0%")
        XCTAssertEqual(MovieNightFacts.topPercent(rating: 4.0, among: many), 52, "13 of 25 are higher → 52%")
        XCTAssertNil(MovieNightFacts.topPercent(rating: nil, among: many))
    }

    func testSubtitlesLabel() {
        XCTAssertNil(MovieNightFacts.subtitlesLabel([], streamsKnown: false))
        XCTAssertEqual(MovieNightFacts.subtitlesLabel([], streamsKnown: true), "NO SUBTITLES")
        XCTAssertEqual(MovieNightFacts.subtitlesLabel(["English", "Spanish", "French", "German"], streamsKnown: true),
                       "SUBS: ENGLISH, SPANISH, FRENCH")
    }

    // MARK: - TMDB extras

    func testMovieExtrasPreferTextlessBackdropsAndOrderCollectionByRelease() throws {
        let json = """
        {
          "budget": 63000000, "revenue": 463517383,
          "belongs_to_collection": {"id": 2344, "name": "The Matrix Collection"},
          "images": {"backdrops": [
            {"file_path": "/en.jpg", "vote_average": 9.0, "iso_639_1": "en"},
            {"file_path": "/clean1.jpg", "vote_average": 5.0, "iso_639_1": null},
            {"file_path": "/clean2.jpg", "vote_average": 7.0, "iso_639_1": null}
          ]},
          "keywords": {"keywords": [{"id": 1, "name": "artificial intelligence"}, {"id": 2, "name": "dystopia"}]}
        }
        """.data(using: .utf8)!
        let detail = try JSONDecoder().decode(TMDBMovieDetail.self, from: json)
        let parts = [
            TMDBCollectionPart(id: 604, title: "Reloaded", releaseDate: "2003-05-15"),
            TMDBCollectionPart(id: 603, title: "The Matrix", releaseDate: "1999-03-30"),
            TMDBCollectionPart(id: 605, title: "Revolutions", releaseDate: "2003-11-05"),
        ]
        let extras = detail.extras(collectionParts: parts)
        XCTAssertEqual(extras.backdropURLs, [
            "https://image.tmdb.org/t/p/w1280/clean2.jpg",
            "https://image.tmdb.org/t/p/w1280/clean1.jpg",
            "https://image.tmdb.org/t/p/w1280/en.jpg",
        ])
        XCTAssertEqual(extras.keywords, ["artificial intelligence", "dystopia"])
        XCTAssertEqual(extras.collectionName, "The Matrix Collection")
        XCTAssertEqual(extras.collectionPartTmdbIds, [603, 604, 605])
        XCTAssertEqual(extras.budget, 63_000_000)
        XCTAssertEqual(extras.revenue, 463_517_383)
    }

    func testMovieExtrasZeroMoneyIsUnknown() throws {
        let json = #"{"budget": 0, "revenue": 0}"#.data(using: .utf8)!
        let extras = try JSONDecoder().decode(TMDBMovieDetail.self, from: json).extras(collectionParts: [])
        XCTAssertNil(extras.budget)
        XCTAssertNil(extras.revenue)
        XCTAssertNil(extras.collectionName)
        XCTAssertTrue(extras.backdropURLs.isEmpty)
    }

    func testVibeChipsLeadWithStingersAndDropPlacesAndRunOnTokens() {
        let tags = ["berlin, germany", "paris, france", "alcohol", "pen pals", "travel", "marijuana",
                    "nudism", "duringcreditsstinger"]
        XCTAssertEqual(MovieNightFacts.vibeChips(tags: tags),
                       ["STAY FOR THE CREDITS", "ALCOHOL", "PEN PALS", "TRAVEL"])
        // TMDB's own keywords lead when present; tags only fill in what's left, once.
        XCTAssertEqual(MovieNightFacts.vibeChips(tags: ["road trip", "Heist"], keywords: ["heist", "con artist"]),
                       ["HEIST", "CON ARTIST", "ROAD TRIP"])
        XCTAssertEqual(MovieNightFacts.vibeChips(tags: ["aftercreditsstinger", "womandirectorlongtoken"]),
                       ["SCENE AFTER THE CREDITS"])
        XCTAssertEqual(MovieNightFacts.vibeChips(tags: []), [])
    }

    func testFindResultCarriesMovieMatches() throws {
        let json = #"{"movie_results":[{"id":603}],"tv_results":[],"person_results":[]}"#.data(using: .utf8)!
        let result = try JSONDecoder().decode(TMDBFindResult.self, from: json)
        XCTAssertEqual(result.movieResults?.first?.id, 603)
        XCTAssertNil(result.tvResults?.first)
    }
}
