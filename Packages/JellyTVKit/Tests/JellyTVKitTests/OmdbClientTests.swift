import XCTest
@testable import JellyTVKit

final class OmdbClientTests: XCTestCase {

    // MARK: - MovieAwards.parse

    func testParseWonOscars() {
        let a = MovieAwards.parse("Won 2 Oscars. 15 wins & 30 nominations total")
        XCTAssertEqual(a?.oscarsWon, 2)
        XCTAssertEqual(a?.oscarNominations, 0)
        XCTAssertEqual(a?.wins, 15)
        XCTAssertEqual(a?.nominations, 30)
        XCTAssertEqual(a?.badge, "★ 2 OSCARS")
    }

    func testParseSingleOscarWinnerBadge() {
        let a = MovieAwards.parse("Won 1 Oscar. 3 wins & 2 nominations total")
        XCTAssertEqual(a?.oscarsWon, 1)
        XCTAssertEqual(a?.badge, "★ ACADEMY AWARD WINNER")
    }

    func testParseNominatedForOscars() {
        let a = MovieAwards.parse("Nominated for 3 Oscars. 5 wins & 12 nominations total")
        XCTAssertEqual(a?.oscarsWon, 0)
        XCTAssertEqual(a?.oscarNominations, 3)
        XCTAssertEqual(a?.wins, 5)
        XCTAssertEqual(a?.badge, "★ 3 OSCAR NOMS")
    }

    func testParseWinsOnlyBadge() {
        let a = MovieAwards.parse("8 wins & 20 nominations total")
        XCTAssertEqual(a?.oscarsWon, 0)
        XCTAssertEqual(a?.wins, 8)
        XCTAssertEqual(a?.badge, "8 WINS")
    }

    func testParseEmptyAndNA() {
        XCTAssertNil(MovieAwards.parse(nil))
        XCTAssertNil(MovieAwards.parse(""))
        XCTAssertNil(MovieAwards.parse("N/A"))
    }

    // MARK: - OmdbResult parsing

    func testOmdbResultRatingsExtraction() {
        let result = OmdbResult(
            imdbRating: "7.8",
            metascore: "74",
            awards: "Won 2 Oscars. 15 wins & 30 nominations total",
            ratings: [
                .init(source: "Internet Movie Database", value: "7.8/10"),
                .init(source: "Rotten Tomatoes", value: "88%"),
                .init(source: "Metacritic", value: "74/100"),
            ],
            response: "True"
        )
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.imdbScore, 7.8)
        XCTAssertEqual(result.rottenTomatoesPercent, 88)
        XCTAssertEqual(result.metacriticScore, 74)
        XCTAssertEqual(result.parsedAwards?.oscarsWon, 2)
        let ext = result.externalRatings
        XCTAssertEqual(ext?.imdbRating, 7.8)
        XCTAssertEqual(ext?.rottenTomatoes, 88)
        XCTAssertEqual(ext?.metacritic, 74)
    }

    func testOmdbResultFailureIsNotSuccess() {
        let result = OmdbResult(response: "False", error: "Incorrect IMDb ID.")
        XCTAssertFalse(result.isSuccess)
    }

    func testOmdbResultDecodesFromJSON() throws {
        let json = """
        {"imdbRating":"8.5","Metascore":"81","Awards":"Won 1 Oscar. 4 wins.",
         "Ratings":[{"Source":"Rotten Tomatoes","Value":"92%"}],"Response":"True"}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(OmdbResult.self, from: json)
        XCTAssertEqual(result.imdbScore, 8.5)
        XCTAssertEqual(result.metacriticScore, 81)
        XCTAssertEqual(result.rottenTomatoesPercent, 92)
        XCTAssertEqual(result.parsedAwards?.oscarsWon, 1)
    }

    func testExternalRatingsEmptyWhenAllNil() {
        let result = OmdbResult(imdbRating: "N/A", metascore: "N/A", ratings: [], response: "True")
        XCTAssertNil(result.externalRatings)
    }
}
