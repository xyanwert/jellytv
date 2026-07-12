import XCTest
@testable import JellyTVKit

final class SampleCatalogTests: XCTestCase {

    func testRowCounts() {
        XCTAssertEqual(SampleCatalog.continueWatching.count, 5)
        XCTAssertEqual(SampleCatalog.recommended.count, 7)
        XCTAssertEqual(SampleCatalog.libraries.count, 8)
        XCTAssertEqual(SampleCatalog.settingsCategories.count, 7)
    }

    func testAdultLibraries() {
        let adult = SampleCatalog.libraries.filter(\.isAdult).map(\.name)
        XCTAssertEqual(adult, ["After Dark", "Uncut Films"])
    }

    func testLibraryItemCounts() {
        XCTAssertTrue(SampleCatalog.libraries.allSatisfy { !$0.itemCount.isEmpty })
        XCTAssertEqual(SampleCatalog.libraries.first?.itemCount, "428")
    }

    func testSettingsCategories() {
        let kinds = Set(SampleCatalog.settingsCategories.map(\.kind))
        XCTAssertEqual(kinds, Set(SettingsCategory.Kind.allCases))
    }

    func testPlaybackSampleData() {
        XCTAssertEqual(SampleCatalog.playbackQualityOptions, ["Auto", "1080p", "4K"])
        XCTAssertTrue(SampleCatalog.playbackQualityOptions.contains(SampleCatalog.defaultPlaybackQuality))
        XCTAssertEqual(SampleCatalog.playbackMethodOptions, ["Direct Play", "Transcode"])
        XCTAssertTrue(SampleCatalog.playbackMethodOptions.contains(SampleCatalog.defaultPlaybackMethod))
        XCTAssertEqual(SampleCatalog.playbackToggles.count, 3)
    }

    func testSampleShow() {
        let show = SampleCatalog.show
        XCTAssertEqual(show.title, "The Deep Signal")
        XCTAssertEqual(show.seasons.count, 4)
        XCTAssertTrue(show.seasons.allSatisfy { !$0.episodes.isEmpty })
        // exactly one current episode across the whole show
        let current = show.seasons.flatMap(\.episodes).filter(\.isCurrent)
        XCTAssertEqual(current.count, 1)
        XCTAssertEqual(current.first?.number, 4)
        // resume fields populated
        XCTAssertFalse(show.resumeEpisodeLabel.isEmpty)
        XCTAssertFalse(show.resumeRemaining.isEmpty)
        XCTAssert((0...1).contains(show.resumeProgress))
        // current episode lives in season 3 (index 2)
        XCTAssertEqual(show.currentSeasonIndex, 2)
    }

    func testShowForItemCarriesTitle() {
        let item = SampleCatalog.recommended[0]
        let show = SampleCatalog.show(for: item)
        XCTAssertEqual(show.title, item.title)
        XCTAssertEqual(show.keyArt, item.image)
        XCTAssertEqual(show.seasons.count, SampleCatalog.show.seasons.count)
    }

    func testEpisodeNumberLabel() {
        XCTAssertEqual(SampleCatalog.show.seasons[2].episodes[3].numberLabel, "04")
        XCTAssertEqual(SampleCatalog.show.seasons[3].shortLabel, "SPECIALS")
        XCTAssertEqual(SampleCatalog.show.seasons[2].shortLabel, "S03")
    }

    func testHeroFields() {
        let hero = SampleCatalog.hero
        XCTAssertEqual(hero.title, "The Deep Signal")
        XCTAssertEqual(hero.certification, "TV-MA")
        XCTAssertEqual(hero.qualityBadge, "4K HDR")
        XCTAssertEqual(hero.image, "HeroBackdrop")
        XCTAssertTrue(hero.resumeLabel.contains("Resume"))
    }

    func testHeroCarousel() {
        XCTAssertEqual(SampleCatalog.heroes.count, 2)
        XCTAssertEqual(SampleCatalog.heroes.first?.id, SampleCatalog.hero.id)
        XCTAssertEqual(SampleCatalog.heroes[1].image, "HeroBob")
        XCTAssertEqual(SampleCatalog.heroes[1].title, "Bob's Burgers")
        // ids are unique (carousel keys off them)
        XCTAssertEqual(Set(SampleCatalog.heroes.map(\.id)).count, SampleCatalog.heroes.count)
    }

    func testHeroPrefEnums() {
        XCTAssertEqual(HeroTransitionStyle.allCases.count, 2)
        XCTAssertEqual(HeroTransitionStyle.default, .crumble)
        XCTAssertEqual(HeroRotation.allCases.count, 3)
        XCTAssertEqual(HeroRotation.default, .s15)
        XCTAssertEqual(HeroRotation.s30.seconds, 30)
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
