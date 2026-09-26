import XCTest
@testable import JellyTVKit

final class SeasonGuideTests: XCTestCase {
    private func season(_ n: Int, pct: Double? = nil, left: Int? = nil, eps: Int? = 10,
                        played: Bool = false, id: String? = nil) -> Season {
        Season(id: id ?? "s\(n)", number: n, name: n == 0 ? "Specials" : "Season \(n)", episodes: [],
               playedPercentage: pct, unplayedCount: left, episodeCount: eps, isPlayed: played)
    }

    func testNextUpWins() {
        let seasons = [season(0), season(1, pct: 100, left: 0), season(2, pct: 40, left: 6), season(3)]
        XCTAssertEqual(SeasonGuide.suggestedIndex(seasons: seasons, nextUpSeasonId: "s3"), 3)
    }

    func testFirstInProgressThenFirstUnfinished() {
        // Bob's Burgers shape: every season partly watched — the first one wins.
        let partial = [season(0), season(1, pct: 53, left: 6), season(2, pct: 11, left: 8)]
        XCTAssertEqual(SeasonGuide.suggestedIndex(seasons: partial, nextUpSeasonId: nil), 1)
        // Nothing started beyond a finished S1: the next unfinished season.
        let fresh = [season(0), season(1, played: true), season(2), season(3)]
        XCTAssertEqual(SeasonGuide.suggestedIndex(seasons: fresh, nextUpSeasonId: nil), 2)
    }

    func testNeverOpensOnSpecialsOrTheLastSeason() {
        // The old fallback opened the *last* season; a fresh show opens on S1.
        let seasons = [season(0), season(1), season(2), season(3)]
        XCTAssertEqual(SeasonGuide.suggestedIndex(seasons: seasons, nextUpSeasonId: nil), 1)
        // All watched: back to the first regular season, not Specials.
        let done = [season(0), season(1, played: true), season(2, played: true)]
        XCTAssertEqual(SeasonGuide.suggestedIndex(seasons: done, nextUpSeasonId: nil), 1)
        // Only Specials: that's all there is.
        XCTAssertEqual(SeasonGuide.suggestedIndex(seasons: [season(0)], nextUpSeasonId: nil), 0)
        // A next-up id that isn't one of these seasons falls through the rules.
        XCTAssertEqual(SeasonGuide.suggestedIndex(seasons: seasons, nextUpSeasonId: "nope"), 1)
    }

    func testStates() {
        XCTAssertEqual(SeasonGuide.state(of: season(1)), .unwatched)
        XCTAssertEqual(SeasonGuide.state(of: season(1, pct: 50, left: 5)), .inProgress(0.5))
        XCTAssertEqual(SeasonGuide.state(of: season(1, played: true)), .finished)
        XCTAssertEqual(SeasonGuide.state(of: season(1, left: 0, eps: 10)), .finished)
        // An empty season with no unplayed episodes is not "finished".
        XCTAssertEqual(SeasonGuide.state(of: season(1, left: 0, eps: 0)), .unwatched)
    }

    func testDisplayOrderPutsSpecialsLast() {
        let seasons = [season(0), season(2), season(1)]
        XCTAssertEqual(SeasonGuide.displayOrder(seasons), [2, 1, 0])
    }

    func testReadout() {
        XCTAssertEqual(SeasonGuide.readout(for: season(1, pct: 40, left: 6)), "6 LEFT")
        XCTAssertEqual(SeasonGuide.readout(for: season(1, played: true)), "DONE")
        XCTAssertEqual(SeasonGuide.readout(for: season(1, eps: 13)), "13 EPS")
        XCTAssertEqual(SeasonGuide.readout(for: season(1, eps: 1)), "1 EP")
    }

    func testDecodesSeasonUserData() throws {
        // Bytes shaped like this server's `/Shows/{id}/Seasons` answer.
        let json = """
        {"Id":"a1","Name":"Season 1","IndexNumber":1,"ChildCount":13,"Type":"Season",
         "UserData":{"PlayedPercentage":53.8,"UnplayedItemCount":6,"Played":false}}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(JellyfinAPI.JellyfinItem.self, from: json)
        let s = item.toSeason()
        XCTAssertEqual(s.playedPercentage ?? 0, 53.8, accuracy: 0.01)
        XCTAssertEqual(s.unplayedCount, 6)
        XCTAssertEqual(s.episodeCount, 13)
        XCTAssertEqual(SeasonGuide.readout(for: s), "6 LEFT")
    }
}
