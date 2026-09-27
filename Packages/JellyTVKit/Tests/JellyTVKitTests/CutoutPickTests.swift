import XCTest
@testable import JellyTVKit

final class CutoutPickTests: XCTestCase {
    private func cut(_ source: String, _ score: Double) -> YsojAPI.Cutout {
        YsojAPI.Cutout(url: "/ysoj/cutouts/x/\(source)-\(score).png", source: source, score: score)
    }

    func testCharacterArtWinsOverACleanerSegmentedCut() {
        let pick = YsojAPI.bestCutout([cut("segmented", 0.95), cut("characterart", 0.7)])
        XCTAssertEqual(pick?.source, "characterart")
    }

    func testClearArtBeatsSegmented() {
        let pick = YsojAPI.bestCutout([cut("segmented", 0.9), cut("clearart", 0.6)])
        XCTAssertEqual(pick?.source, "clearart")
    }

    func testSameSourcePrefersTheHigherScore() {
        let pick = YsojAPI.bestCutout([cut("segmented", 0.6), cut("segmented", 0.8)])
        XCTAssertEqual(pick?.score, 0.8)
    }

    func testNothingBelowTheFloor() {
        XCTAssertNil(YsojAPI.bestCutout([cut("characterart", 0.3), cut("segmented", 0.5)]))
        XCTAssertNil(YsojAPI.bestCutout([]))
    }

    func testDecodesTheServersList() throws {
        let json = #"{"itemId":"abc","cutouts":[{"url":"/ysoj/cutouts/abc/0.png","source":"segmented","score":0.81,"width":1200,"height":1400,"character":null}]}"#
        let list = try JSONDecoder().decode(YsojAPI.CutoutList.self, from: Data(json.utf8))
        XCTAssertEqual(list.cutouts.first?.width, 1200)
        XCTAssertNil(list.cutouts.first?.character)
    }

    func testCapabilitiesWithoutCutoutsStillDecode() throws {
        let json = #"{"ysojVersion":"1","serverName":"box","owner":true,"features":{}}"#
        let caps = try JSONDecoder().decode(YsojAPI.Capabilities.self, from: Data(json.utf8))
        XCTAssertFalse(caps.offersCutouts)
    }
}
