import XCTest
@testable import JellyTVKit

final class SampleCatalogTests: XCTestCase {

    func testRowCounts() {
        XCTAssertEqual(SampleCatalog.continueWatching.count, 5)
        XCTAssertEqual(SampleCatalog.recommended.count, 7)
        XCTAssertEqual(SampleCatalog.libraries.count, 8)
        XCTAssertEqual(SampleCatalog.settingsEntries.count, 4)
        XCTAssertEqual(SampleCatalog.navTabs, ["Home", "Movies", "Shows", "Search"])
    }

    func testAdultLibraries() {
        let adult = SampleCatalog.libraries.filter(\.isAdult).map(\.name)
        XCTAssertEqual(adult, ["After Dark", "Uncut Films"])
    }

    func testHeroFields() {
        let hero = SampleCatalog.hero
        XCTAssertEqual(hero.title, "The Deep Signal")
        XCTAssertEqual(hero.certification, "TV-MA")
        XCTAssertEqual(hero.qualityBadge, "4K HDR")
        XCTAssertEqual(hero.pageCount, 5)
        XCTAssertTrue(hero.resumeLabel.contains("Resume"))
    }

    func testContinueProgressInRange() {
        for item in SampleCatalog.continueWatching {
            XCTAssert((0...1).contains(item.progress), "\(item.title) progress out of range")
        }
    }

    func testProfileAndServer() {
        XCTAssertEqual(SampleCatalog.profile.name, "Marina")
        XCTAssertEqual(SampleCatalog.profile.role, "Administrator")
        XCTAssertEqual(SampleCatalog.profile.initial, "M")
        XCTAssertEqual(SampleCatalog.server.name, "reef.local")
        XCTAssertEqual(SampleCatalog.server.version, "v10.9.2")
        XCTAssertTrue(SampleCatalog.server.isConnected)
    }

    func testAccentOptions() {
        XCTAssertEqual(AccentOption.allCases.count, 4)
        XCTAssertEqual(AccentOption.default, .coral)
        XCTAssertEqual(AccentOption.coral.hex, "#F0525F")
        XCTAssertEqual(AccentOption.amber.hex, "#E8B44A")
        XCTAssertEqual(AccentOption.blue.hex, "#4AA8E8")
        XCTAssertEqual(AccentOption.green.hex, "#3FBF8F")
        XCTAssertEqual(AccentOption.coral.displayName, "Coral")
    }
}
