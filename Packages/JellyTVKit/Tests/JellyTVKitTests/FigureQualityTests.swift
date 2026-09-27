import XCTest
@testable import JellyTVKit

/// The numbers here are measurements off the server's own art (see the
/// commit that added `FigureQuality`): what Vision's mask came to for each
/// image, and what a person looking at the cut wanted done with it.
final class FigureQualityTests: XCTestCase {
    private func measure(_ coverage: Double, _ fill: Double, _ aspect: Double, _ height: Int,
                         _ touches: String = "", text: Double = 0) -> FigureMeasure {
        FigureMeasure(coverage: coverage, fill: fill, aspect: aspect, pixelHeight: height,
                      touchesLeft: touches.contains("L"), touchesRight: touches.contains("R"),
                      touchesTop: touches.contains("T"), textOverlap: text)
    }

    // MARK: Figures that should stand

    func testACleanPosterFigurePasses() {
        // Takamine-san's poster: one girl, arms crossed, feet off the bottom.
        let s = FigureQuality.score(measure(0.602, 0.660, 1.57, 1284, "TB"))
        XCTAssertTrue(FigureQuality.passes(s), "\(s)")
    }

    func testADuoOnAPosterPasses() {
        // DanDaDan's poster, both instances together.
        let s = FigureQuality.score(measure(0.117, 0.308, 1.04, 676))
        XCTAssertGreaterThan(s, 0.9)
    }

    func testOneInstanceOutOfAGroupSceneCanPass() {
        // Tales of Wedding Rings' backdrop, its third instance alone.
        XCTAssertTrue(FigureQuality.passes(FigureQuality.score(measure(0.175, 0.611, 1.11, 812))))
    }

    // MARK: Scenes that must not

    func testABackdropThatIsTheWholeShotIsRejected() {
        // Frieren's backdrop: the party sitting in a field, sky cut away.
        XCTAssertEqual(FigureQuality.score(measure(0.659, 0.659, 0.56, 1080, "LRTB")), 0)
    }

    func testACrowdedPosterIsRejected() {
        // Peter Grill's poster: seven characters and the title, edge to edge.
        XCTAssertEqual(FigureQuality.score(measure(0.767, 0.774, 1.41, 1270, "LRB")), 0)
    }

    func testAWideBlobTouchingBothSidesIsRejected() {
        XCTAssertEqual(FigureQuality.score(measure(0.40, 0.60, 0.9, 900, "LR")), 0)
    }

    func testATinyCutStaysUnderTheBar() {
        // Urotsukidōji's backdrop: a 360px figure in a 1366px frame — a fine
        // shape that would go soft at 500pt on a 4K panel.
        XCTAssertFalse(FigureQuality.passes(FigureQuality.score(measure(0.070, 0.431, 0.77, 360))))
        // And below 260px it is not even weighed.
        XCTAssertEqual(FigureQuality.score(measure(0.070, 0.431, 0.77, 200)), 0)
    }

    func testAMediocreSceneStaysUnderTheBar() {
        // Peter Grill's backdrop: a group scene that Vision cut as one slab.
        let s = FigureQuality.score(measure(0.554, 0.566, 0.57, 1080, "LTB"))
        XCTAssertFalse(FigureQuality.passes(s), "\(s)")
    }

    // MARK: Resolution and text

    func testResolutionBreaksATie() {
        // DanDaDan: the 414px thumb duo against the 676px poster duo.
        let thumb = FigureQuality.score(measure(0.156, 0.551, 1.08, 414))
        let poster = FigureQuality.score(measure(0.117, 0.308, 1.04, 676))
        XCTAssertGreaterThan(poster, thumb)
    }

    func testATitleLyingAcrossTheFigureCostsThePass() {
        // Nagatoro's thumb: her figure with "DON'T TOY WITH ME" over its right half.
        let clean = FigureQuality.score(measure(0.449, 0.639, 0.77, 550))
        let lettered = FigureQuality.score(measure(0.449, 0.639, 0.77, 550, text: 0.14))
        XCTAssertTrue(FigureQuality.passes(clean))
        XCTAssertFalse(FigureQuality.passes(lettered))
    }

    func testTextOverlapIsTheShareOfTheBox() {
        let box = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let text = [CGRect(x: 0.6, y: 0.5, width: 0.2, height: 0.1),  // wholly inside: 0.02 of 0.5
                    CGRect(x: 0, y: 0, width: 0.3, height: 0.3)]      // wholly outside
        XCTAssertEqual(FigureQuality.textOverlap(box: box, text: text), 0.04, accuracy: 1e-9)
        XCTAssertEqual(FigureQuality.textOverlap(box: box, text: []), 0)
    }

    func testRampIsClampedAndLinear() {
        XCTAssertEqual(FigureQuality.ramp(-1, from: 0, to: 1), 0)
        XCTAssertEqual(FigureQuality.ramp(0.25, from: 0, to: 1), 0.25)
        XCTAssertEqual(FigureQuality.ramp(9, from: 0, to: 1), 1)
    }
}
