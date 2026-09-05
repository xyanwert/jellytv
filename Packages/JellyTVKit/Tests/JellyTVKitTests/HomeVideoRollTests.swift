import XCTest
@testable import JellyTVKit

final class HomeVideoRollTests: XCTestCase {
    private let art = Artwork(top: OKLCH(l: 0.3, c: 0.05, h: 200), bottom: OKLCH(l: 0.2, c: 0.05, h: 200))
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    private func video(_ id: String, taken: String?, w: Int? = 1920, h: Int? = 1080, seconds: Double = 60) -> MediaItem {
        MediaItem(id: id, title: id, meta: "Video", artwork: art, runtimeTicks: Int64(seconds * 10_000_000),
                  takenAt: MovieNightFacts.date(fromJellyfin: taken), width: w, height: h)
    }

    func testSectionsGroupByMonthNewestFirstWithUndatedLast() {
        let items = [video("a", taken: "2023-12-18"), video("b", taken: "2024-03-02"),
                     video("c", taken: nil), video("d", taken: "2023-12-01")]
        let sections = HomeVideoRoll.sections(items, calendar: utc, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(sections.map(\.title), ["March 2024", "December 2023", "Undated"])
        XCTAssertEqual(sections[1].items.map(\.id), ["a", "d"])   // newest first inside the month
        XCTAssertEqual(HomeVideoRoll.flattened(sections).map(\.id), ["b", "a", "d", "c"])
    }

    func testOnThisDayFindsEarlierYearsWithinTheWindowAndWrapsNewYear() {
        let today = MovieNightFacts.date(fromJellyfin: "2026-01-02")!
        let items = [video("hit", taken: "2023-12-31"),      // 2 days off, across New Year
                     video("exact", taken: "2025-01-02"),
                     video("far", taken: "2024-06-10"),
                     video("thisYear", taken: "2026-01-02"),
                     video("undated", taken: nil)]
        let found = HomeVideoRoll.onThisDay(items, today: today, window: 3, calendar: utc)
        XCTAssertEqual(found.map(\.item.id), ["exact", "hit"])
        XCTAssertEqual(found.map(\.label), ["LAST YEAR", "3 YEARS AGO"])
    }

    func testJustifiedRowsFillTheWidthAndKeepAspects() {
        let items = [video("l1", taken: nil), video("p1", taken: nil, w: 608, h: 1080),
                     video("l2", taken: nil), video("l3", taken: nil), video("p2", taken: nil, w: 720, h: 1280)]
        let rows = HomeVideoRoll.justifiedRows(items, width: 1200, targetHeight: 220, spacing: 12)
        XCTAssertFalse(rows.isEmpty)
        for row in rows.dropLast() {
            let total = row.map(\.width).reduce(0, +) + 12 * Double(row.count - 1)
            XCTAssertEqual(total, 1200, accuracy: Double(row.count) + 1)   // rounding per tile
            let heights = Set(row.map(\.height))
            XCTAssertEqual(heights.count, 1)
        }
        // A portrait clip stays portrait.
        let portrait = rows.flatMap { $0 }.first { $0.item.id == "p1" }!
        XCTAssertLessThan(portrait.width, portrait.height)
        // The last row is not stretched.
        XCTAssertEqual(rows.last!.first!.height, 220)
    }

    func testClampedAspectBoundsAndDefault() {
        XCTAssertEqual(HomeVideoRoll.clampedAspect(nil), 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(HomeVideoRoll.clampedAspect(0.3), 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(HomeVideoRoll.clampedAspect(4), 2, accuracy: 0.001)
    }

    func testFrameTimesAreDistinctGridAlignedAndSkipTheFirstAndLastFrames() {
        // 60s at 10s intervals → frames at 10…50: neither the black opening
        // frame nor the end-of-file one.
        XCTAssertEqual(HomeVideoRoll.frameTimes(runtimeTicks: 600_000_000, intervalMs: 10_000),
                       [10, 20, 30, 40, 50])
        // 20s: only the 10s frame sits strictly inside — one frame is nothing to page through.
        XCTAssertEqual(HomeVideoRoll.frameTimes(runtimeTicks: 200_000_000, intervalMs: 10_000), [10])
        // 90 minutes → eight spread frames, all on the 10s grid.
        let long = HomeVideoRoll.frameTimes(runtimeTicks: 54_000_000_000, intervalMs: 10_000)
        XCTAssertEqual(long.count, 8)
        XCTAssertTrue(long.allSatisfy { $0.truncatingRemainder(dividingBy: 10) == 0 })
        XCTAssertEqual(long, long.sorted())
        XCTAssertEqual(Set(long).count, long.count)
        // Shorter than one interval: nothing to page through.
        XCTAssertEqual(HomeVideoRoll.frameTimes(runtimeTicks: 50_000_000, intervalMs: 10_000), [])
        XCTAssertEqual(HomeVideoRoll.frameTimes(runtimeTicks: nil, intervalMs: 10_000), [])
    }

    func testBestTrickplayPicksTheWidestResolution() {
        let info = { (w: Int) in JellyfinAPI.TrickplayInfo(width: w, height: w * 9 / 16, tileWidth: 10, tileHeight: 10, interval: 10_000, thumbnailCount: 1, bandwidth: nil) }
        let pick = HomeVideoRoll.bestTrickplay(["src": ["320": info(320), "1280": info(1280)]])
        XCTAssertEqual(pick?.mediaSourceId, "src")
        XCTAssertEqual(pick?.widthKey, "1280")
        XCTAssertNil(HomeVideoRoll.bestTrickplay(nil))
        XCTAssertNil(HomeVideoRoll.bestTrickplay(["src": [:]]))
    }
}
