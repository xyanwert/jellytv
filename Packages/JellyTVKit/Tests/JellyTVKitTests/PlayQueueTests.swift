import XCTest
@testable import JellyTVKit

/// The queue-building rules — "what plays next" — without a server.
final class PlayQueueTests: XCTestCase {

    private func episode(id: String, name: String = "Episode", seriesId: String? = "series-1",
                         seriesName: String? = "The Show", season: Int? = 2, number: Int? = 4,
                         locationType: String? = "FileSystem",
                         userData: JellyfinAPI.JellyfinUserData? = nil) -> JellyfinAPI.JellyfinItem {
        JellyfinAPI.JellyfinItem(
            id: id, name: name, type: "Episode",
            runTimeTicks: 29_000_000,
            seriesName: seriesName, seriesId: seriesId,
            indexNumber: number, parentIndexNumber: season,
            userData: userData, locationType: locationType
        )
    }

    private func movie(id: String, name: String = "A Film",
                       locationType: String? = "FileSystem") -> JellyfinAPI.JellyfinItem {
        JellyfinAPI.JellyfinItem(id: id, name: name, type: "Movie",
                                 runTimeTicks: 72_000_000_000, locationType: locationType)
    }

    // MARK: - Virtual items

    /// The single most important filter here: Jellyfin's metadata-only rows
    /// look like ordinary episodes and have no file behind them. 859 of one
    /// real library's 3,525 episodes are virtual, so letting them through
    /// would make roughly a quarter of a shuffle a dead end.
    func testVirtualItemsAreNotPlayable() {
        XCTAssertFalse(PlayQueue.isPlayable(episode(id: "v", locationType: "Virtual")))
        XCTAssertTrue(PlayQueue.isPlayable(episode(id: "r", locationType: "FileSystem")))
    }

    /// A server that didn't return `LocationType` at all must not have every
    /// item treated as virtual — that would empty the queue entirely.
    func testMissingLocationTypeIsPlayable() {
        XCTAssertTrue(PlayQueue.isPlayable(episode(id: "r", locationType: nil)))
    }

    func testVirtualItemsProduceNoPlayableItem() {
        XCTAssertNil(PlayQueue.playableItem(from: episode(id: "v", locationType: "Virtual")))
    }

    // MARK: - Episodes

    /// A shuffled queue and a season queue have to read identically in the
    /// chrome: the series is the title, the episode is the subtitle.
    func testEpisodeBecomesSeriesTitledPlayableItem() {
        let item = PlayQueue.playableItem(from: episode(
            id: "e1", name: "The Undertow",
            userData: JellyfinAPI.JellyfinUserData(playbackPositionTicks: 5_000_000, isFavorite: true)
        ))
        XCTAssertEqual(item?.title, "The Show")
        XCTAssertEqual(item?.subtitle, "S2 · E4 — \"The Undertow\"")
        XCTAssertEqual(item?.seriesId, "series-1")
        XCTAssertEqual(item?.runtimeTicks, 29_000_000)
        XCTAssertEqual(item?.resumePositionTicks, 5_000_000)
        XCTAssertEqual(item?.isFavorite, true)
    }

    /// Logo artwork and tags live on the *series*, so a cross-series queue
    /// has to carry each episode's own series' pair — not the first one's.
    func testEpisodeBorrowsIdentityFromItsOwnSeries() {
        let identity: [String: (logoURL: String?, tags: [String])] = [
            "series-1": ("https://example.com/one.png", ["comfort"]),
            "series-2": ("https://example.com/two.png", ["late"]),
        ]
        let first = PlayQueue.playableItem(from: episode(id: "a", seriesId: "series-1"),
                                           seriesIdentity: identity)
        let second = PlayQueue.playableItem(from: episode(id: "b", seriesId: "series-2"),
                                            seriesIdentity: identity)
        XCTAssertEqual(first?.logoURL, "https://example.com/one.png")
        XCTAssertEqual(first?.tags, ["comfort"])
        XCTAssertEqual(second?.logoURL, "https://example.com/two.png")
        XCTAssertEqual(second?.tags, ["late"])
    }

    /// A series absent from the lookup degrades to no logo and no tags rather
    /// than borrowing another show's.
    func testEpisodeWithUnknownSeriesHasNoBorrowedIdentity() {
        let item = PlayQueue.playableItem(from: episode(id: "a", seriesId: "series-9"),
                                          seriesIdentity: ["series-1": ("logo", ["tag"])])
        XCTAssertNil(item?.logoURL)
        XCTAssertEqual(item?.tags, [])
    }

    // MARK: - Movies and home videos

    func testMovieUsesItsOwnName() {
        let item = PlayQueue.playableItem(from: movie(id: "m1", name: "Sorcerer"))
        XCTAssertEqual(item?.title, "Sorcerer")
        XCTAssertNil(item?.subtitle)
        XCTAssertNil(item?.seriesId)
        XCTAssertFalse(item?.hidesTitle ?? true)
    }

    func testHomeVideosHideTheirTitle() {
        let item = PlayQueue.playableItem(from: movie(id: "m1", name: "0C5F6BEE-0AF4"),
                                          hidesTitle: true)
        XCTAssertEqual(item?.hidesTitle, true)
    }

    // MARK: - Merging

    /// The same item reachable through two libraries must appear once — a
    /// duplicate would make the player's own "3/500" position lie.
    func testMergeDeduplicatesById() {
        let shared = PlayableItem(id: "same", title: "Same")
        let merged = PlayQueue.merge([[shared, PlayableItem(id: "a", title: "A")],
                                      [shared, PlayableItem(id: "b", title: "B")]])
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.filter { $0.id == "same" }.count, 1)
    }

    func testMergeRespectsTheLimit() {
        let group = (0..<40).map { PlayableItem(id: "i\($0)", title: "Item \($0)") }
        XCTAssertEqual(PlayQueue.merge([group], limit: 10).count, 10)
    }

    /// Concatenating two already-random lists would play all of library A and
    /// then all of library B. The merge re-shuffles across them, so a
    /// half-length draw pulls from both.
    func testMergeInterleavesLibrariesRatherThanConcatenating() {
        let first = (0..<200).map { PlayableItem(id: "a\($0)", title: "A") }
        let second = (0..<200).map { PlayableItem(id: "b\($0)", title: "B") }
        let merged = PlayQueue.merge([first, second], limit: 200)
        XCTAssertEqual(merged.count, 200)
        XCTAssertTrue(merged.contains { $0.id.hasPrefix("a") })
        XCTAssertTrue(merged.contains { $0.id.hasPrefix("b") })
    }

    func testMergeOfNothingIsEmpty() {
        XCTAssertTrue(PlayQueue.merge([]).isEmpty)
        XCTAssertTrue(PlayQueue.merge([[], []]).isEmpty)
    }

    // MARK: - A new press means a new queue

    /// Pressing Random twice has to produce a request the presentation layer
    /// treats as different, or `.fullScreenCover(item:)` would consider the
    /// second press a re-render of the first and keep playing the old order.
    func testReorderedQueueIsADifferentRequest() {
        let items = (0..<20).map { PlayableItem(id: "i\($0)", title: "Item \($0)") }
        let first = PlaybackRequest.shuffled(items)
        let second = PlaybackRequest.shuffled(items.reversed())
        XCTAssertNotEqual(first.id, second.id)
    }

    /// …while the same queue stays the same request, which is what keeps an
    /// unrelated `AppState` publish from tearing down a playing film.
    func testIdenticalQueueIsTheSameRequest() {
        let items = (0..<20).map { PlayableItem(id: "i\($0)", title: "Item \($0)") }
        XCTAssertEqual(PlaybackRequest.shuffled(items).id, PlaybackRequest.shuffled(items).id)
    }

    // MARK: - A list becomes a queue

    /// What a tap on a home video card builds: the whole visible list, in the
    /// order it is on screen, starting where the finger landed.
    func testMediaItemCarriesResumeAndFavoriteIntoTheQueue() {
        let item = MediaItem(id: "v1", title: "Clip", meta: "Video",
                             artwork: Artwork(top: OKLCH(l: 0.5, c: 0.1, h: 200),
                                              bottom: OKLCH(l: 0.4, c: 0.1, h: 200)),
                             tags: ["beach"], runtimeTicks: 900_000_000,
                             resumePositionTicks: 120_000_000, isFavorite: true)
        let playable = item.asPlayableItem(hidesTitle: true)
        XCTAssertEqual(playable.id, "v1")
        XCTAssertEqual(playable.resumePositionTicks, 120_000_000)
        XCTAssertTrue(playable.isFavorite)
        XCTAssertEqual(playable.tags, ["beach"])
        XCTAssertTrue(playable.hidesTitle)
    }

    /// Jellyfin returns `UserData` on every user-scoped list response, so the
    /// grid already holds what a queue needs — this is the wiring that lets a
    /// tap start a queue with no extra fetch.
    func testListRowsCarryUserDataThroughToMediaItem() {
        let raw = JellyfinAPI.JellyfinItem(
            id: "v1", name: "Clip", type: "Video",
            runTimeTicks: 900_000_000,
            userData: JellyfinAPI.JellyfinUserData(playbackPositionTicks: 120_000_000,
                                                   isFavorite: true)
        )
        let item = raw.toMediaItem(libraryCategory: .videos)
        XCTAssertEqual(item.resumePositionTicks, 120_000_000)
        XCTAssertTrue(item.isFavorite)
    }
}
