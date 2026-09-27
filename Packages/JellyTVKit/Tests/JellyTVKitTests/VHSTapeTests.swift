import XCTest
@testable import JellyTVKit

/// The shape of a skip's fast-forward: slow away, fast through the middle,
/// slow onto the landing, then held there until the picture is back.
final class VHSTapeTests: XCTestCase {

    private func timeline(_ elapsed: Double, duration: Double = 1.6) -> VHSTapeTimeline {
        VHSTapeTimeline(tapeDuration: duration, elapsed: elapsed)
    }

    func testTravelStartsAtThePressAndEndsOnTheLanding() {
        XCTAssertEqual(VHSTapeTimeline.travel(0), 0, accuracy: 1e-9)
        XCTAssertEqual(VHSTapeTimeline.travel(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(VHSTapeTimeline.travel(1), 1, accuracy: 1e-9)
    }

    func testTravelIsMonotonic() {
        var last = -1.0
        for i in 0...200 {
            let t = VHSTapeTimeline.travel(Double(i) / 200)
            XCTAssertGreaterThanOrEqual(t, last)
            last = t
        }
    }

    func testSlowThenFastThenSlow() {
        // The first quarter of the run barely moves, the middle third covers
        // most of the span, and the last quarter barely moves again.
        let firstQuarter = VHSTapeTimeline.travel(0.25)
        let middleThird = VHSTapeTimeline.travel(2.0 / 3) - VHSTapeTimeline.travel(1.0 / 3)
        let lastQuarter = 1 - VHSTapeTimeline.travel(0.75)
        XCTAssertLessThan(firstQuarter, 0.05)
        XCTAssertGreaterThan(middleThird, 0.8)
        XCTAssertLessThan(lastQuarter, 0.05)
    }

    func testSpeedPeaksInTheMiddleAndRestsAtTheEnds() {
        XCTAssertEqual(VHSTapeTimeline.speed(0), 0, accuracy: 1e-9)
        XCTAssertEqual(VHSTapeTimeline.speed(0.5), 1, accuracy: 1e-9)
        XCTAssertEqual(VHSTapeTimeline.speed(1), 0, accuracy: 1e-9)
        // Symmetric: the deck slows down the way it sped up.
        XCTAssertEqual(VHSTapeTimeline.speed(0.3), VHSTapeTimeline.speed(0.7), accuracy: 1e-9)
        // And it never exceeds the normalised peak.
        for i in 0...100 {
            XCTAssertLessThanOrEqual(VHSTapeTimeline.speed(Double(i) / 100), 1 + 1e-9)
        }
    }

    func testHoldBeginsWhereTheTravelEnds() {
        XCTAssertFalse(timeline(1.59).isHolding)
        XCTAssertTrue(timeline(1.6).isHolding)
        XCTAssertEqual(timeline(1.6).travel, 1, accuracy: 1e-9)
        XCTAssertEqual(timeline(4).travel, 1, accuracy: 1e-9)
        XCTAssertEqual(timeline(4).holdElapsed, 2.4, accuracy: 1e-9)
        XCTAssertEqual(timeline(0.4).holdElapsed, 0)
    }

    func testFrameIndexSpansTheFramesAndParksOnTheLast() {
        XCTAssertEqual(timeline(0).frameIndex(count: 45), 0)
        XCTAssertEqual(timeline(0.8).frameIndex(count: 45), 22)
        XCTAssertEqual(timeline(1.6).frameIndex(count: 45), 44)
        XCTAssertEqual(timeline(9).frameIndex(count: 45), 44)
        XCTAssertEqual(timeline(0.8).frameIndex(count: 0), 0)
        XCTAssertEqual(timeline(0.8).frameIndex(count: 1), 0)
    }

    func testFlipsComeSlowlyAtTheEndsAndFastInTheMiddle() {
        func flips(_ a: Double, _ b: Double) -> Int {
            timeline(b).flipStep(restRate: 2, raceFlips: 6, holdRate: 1)
                - timeline(a).flipStep(restRate: 2, raceFlips: 6, holdRate: 1)
        }
        let opening = flips(0, 0.4)
        let middle = flips(0.6, 1.0)
        let closing = flips(1.2, 1.6)
        XCTAssertGreaterThan(middle, opening)
        XCTAssertGreaterThan(middle, closing)
        // And the counter never runs backwards, travel or hold.
        var last = -1
        for i in 0...400 {
            let step = timeline(Double(i) / 100).flipStep(restRate: 2, raceFlips: 6, holdRate: 1)
            XCTAssertGreaterThanOrEqual(step, last)
            last = step
        }
    }

    func testTheHoldKeepsWobblingAtItsOwnRate() {
        let parked = timeline(1.6).flipStep(restRate: 2, raceFlips: 6, holdRate: 1)
        XCTAssertEqual(timeline(3.6).flipStep(restRate: 2, raceFlips: 6, holdRate: 1), parked + 2)
    }

    func testCounterRidesTheTravel() {
        XCTAssertEqual(timeline(0).position(from: 105, to: 131), 105, accuracy: 1e-9)
        XCTAssertEqual(timeline(0.8).position(from: 105, to: 131), 118, accuracy: 1e-9)
        XCTAssertEqual(timeline(5).position(from: 105, to: 131), 131, accuracy: 1e-9)
    }

    func testZeroDurationIsAlreadyHolding() {
        let t = timeline(0, duration: 0)
        XCTAssertTrue(t.isHolding)
        XCTAssertEqual(t.travel, 1, accuracy: 1e-9)
    }
}
