import XCTest
@testable import JellyTVKit

/// Intro/credits markers: decoding what `GET /MediaSegments/{itemId}` really
/// returns, and the rules that turn several providers' opinions into the one
/// skip the player offers.
final class MediaSegmentTests: XCTestCase {

    // MARK: - Decode

    /// Captured verbatim from xyan-media (Jellyfin 12.0.0) — The Simpsons
    /// S1E2, after an Intro Skipper scan. Note the envelope is the same
    /// `{Items, TotalRecordCount, StartIndex}` every list endpoint uses, and
    /// that the segment carries no `Action` and no `StreamIndex`.
    private let capturedJSON = """
    {
      "Items": [
        {
          "Id": "01a0b23ee8397617bea64d751c82d691",
          "ItemId": "095a5741ca7acbcb89b36039c02afa0b",
          "Type": "Intro",
          "StartTicks": 0,
          "EndTicks": 775479481
        },
        {
          "Id": "01a0b23f282b7dcbb8cd3b4c9a339dc7",
          "ItemId": "095a5741ca7acbcb89b36039c02afa0b",
          "Type": "Outro",
          "StartTicks": 13323156490,
          "EndTicks": 13885552220
        }
      ],
      "TotalRecordCount": 2,
      "StartIndex": 0
    }
    """

    func testDecodesTheServersOwnBytes() throws {
        let response = try JSONDecoder().decode(
            JellyfinAPI.ItemsResponse<JellyfinAPI.MediaSegment>.self,
            from: Data(capturedJSON.utf8)
        )
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.totalRecordCount, 2)

        let segments = MediaSegments.from(response.items)
        XCTAssertEqual(segments.count, 2)

        let intro = try XCTUnwrap(segments.first { $0.kind == .intro })
        XCTAssertEqual(intro.startSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(intro.endSeconds, 77.5479481, accuracy: 0.01)

        let outro = try XCTUnwrap(segments.first { $0.kind == .outro })
        XCTAssertEqual(outro.startSeconds, 1332.315649, accuracy: 0.01)
        XCTAssertEqual(outro.endSeconds, 1388.555222, accuracy: 0.01)
    }

    func testUnknownTypeDoesNotFailTheDecode() {
        // A provider inventing its own kind, or a newer server adding one,
        // must not cost us the segments we *do* understand.
        let wire = [
            JellyfinAPI.MediaSegment(id: "a", type: "Intro", startTicks: 0, endTicks: 600_000_000),
            JellyfinAPI.MediaSegment(id: "b", type: "Annotation", startTicks: 0, endTicks: 600_000_000),
        ]
        let segments = MediaSegments.from(wire)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.filter { $0.kind == .unknown }.count, 1)
    }

    func testCreditsIsSpeltOutroHere() {
        XCTAssertEqual(MediaSegment.Kind(serverType: "Credits"), .outro)
        XCTAssertEqual(MediaSegment.Kind(serverType: "OUTRO"), .outro)
        XCTAssertEqual(MediaSegment.Kind(serverType: nil), .unknown)
    }

    func testSegmentsMissingTicksAreDropped() {
        let wire = [
            JellyfinAPI.MediaSegment(id: "a", type: "Intro", startTicks: nil, endTicks: 600_000_000),
            JellyfinAPI.MediaSegment(id: nil, type: "Intro", startTicks: 0, endTicks: 600_000_000),
        ]
        XCTAssertTrue(MediaSegments.from(wire).isEmpty)
    }

    func testTooShortToBeWorthAButton() {
        // A two-second "intro" is a detector artefact; offering a skip for it
        // costs more attention than it saves.
        let wire = [JellyfinAPI.MediaSegment(id: "a", type: "Intro",
                                             startTicks: 0, endTicks: 20_000_000)]
        XCTAssertTrue(MediaSegments.from(wire).isEmpty)
    }

    func testEndPastTheRuntimeIsClamped() throws {
        // Providers do report ends past the file's own runtime. Left alone,
        // the skip target trips end-of-item handling and auto-advances —
        // "skip the credits" would start the next episode.
        let wire = [JellyfinAPI.MediaSegment(id: "a", type: "Outro",
                                             startTicks: 12_000_000_000,
                                             endTicks: 99_000_000_000)]
        let segments = MediaSegments.from(wire, runtimeSeconds: 1400)
        let outro = try XCTUnwrap(segments.first)
        XCTAssertEqual(outro.endSeconds, 1400, accuracy: 0.001)
    }

    // MARK: - Collapse: several providers, one answer

    private func segment(_ id: String, _ kind: MediaSegment.Kind,
                         _ start: Double, _ end: Double) -> MediaSegment {
        MediaSegment(id: id, kind: kind, startSeconds: start, endSeconds: end)
    }

    func testOverlappingSameKindKeepsTheShorterOne() throws {
        // Two providers disagree about the same intro. Over-skipping cuts into
        // the first scene; under-skipping leaves a little theme playing. The
        // narrower claim wins.
        let collapsed = MediaSegments.collapse([
            segment("wide", .intro, 0, 95),
            segment("tight", .intro, 17, 78),
        ])
        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed.first?.id, "tight")
    }

    func testTheShorterOneWinsRegardlessOfInputOrder() {
        let a = segment("wide", .intro, 0, 95)
        let b = segment("tight", .intro, 17, 78)
        XCTAssertEqual(MediaSegments.collapse([a, b]).first?.id, "tight")
        XCTAssertEqual(MediaSegments.collapse([b, a]).first?.id, "tight")
    }

    func testSameKindApartIsTwoRealSegments() {
        // An intro at the top and a second one after a cold open are both true.
        let collapsed = MediaSegments.collapse([
            segment("first", .intro, 0, 60),
            segment("second", .intro, 300, 360),
        ])
        XCTAssertEqual(collapsed.count, 2)
    }

    func testDifferentKindsOverlappingAreBothKept() {
        // A recap and an intro covering the same stretch are two true
        // statements; only same-kind disagreement is a conflict.
        let collapsed = MediaSegments.collapse([
            segment("r", .recap, 0, 60),
            segment("i", .intro, 30, 90),
        ])
        XCTAssertEqual(collapsed.count, 2)
    }

    func testCollapseReturnsChronologicalOrder() {
        let collapsed = MediaSegments.collapse([
            segment("o", .outro, 1300, 1400),
            segment("i", .intro, 0, 60),
            segment("r", .recap, 60, 120),
        ])
        XCTAssertEqual(collapsed.map(\.id), ["i", "r", "o"])
    }

    // MARK: - What the player asks

    func testOnlyIntroAndCreditsAreOffered() {
        // A recap is often the only reminder of what happened last week, a
        // preview is the thing people stay for, and an ad break inside a
        // recording has no reliable end.
        XCTAssertTrue(MediaSegment.Kind.intro.isSkippable)
        XCTAssertTrue(MediaSegment.Kind.outro.isSkippable)
        XCTAssertFalse(MediaSegment.Kind.recap.isSkippable)
        XCTAssertFalse(MediaSegment.Kind.preview.isSkippable)
        XCTAssertFalse(MediaSegment.Kind.commercial.isSkippable)
        XCTAssertFalse(MediaSegment.Kind.unknown.isSkippable)
    }

    func testSkippableAtFindsTheSegmentUnderTheClock() throws {
        let segments = [segment("i", .intro, 17, 78), segment("o", .outro, 1330, 1388)]
        XCTAssertEqual(MediaSegments.skippable(at: 40, in: segments)?.id, "i")
        XCTAssertEqual(MediaSegments.skippable(at: 1350, in: segments)?.id, "o")
        XCTAssertNil(MediaSegments.skippable(at: 600, in: segments))
    }

    func testSkippableIgnoresKindsWeDoNotOffer() {
        let segments = [segment("r", .recap, 0, 60)]
        XCTAssertNil(MediaSegments.skippable(at: 30, in: segments))
    }

    func testTheEndIsExclusiveSoTheButtonLeavesWithTheSegment() {
        let intro = segment("i", .intro, 17, 78)
        XCTAssertTrue(intro.contains(17))
        XCTAssertTrue(intro.contains(77.9))
        XCTAssertFalse(intro.contains(78))
        XCTAssertFalse(intro.contains(16.9))
    }
}
