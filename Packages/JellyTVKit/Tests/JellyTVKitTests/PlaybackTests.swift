import XCTest
@testable import JellyTVKit

/// Thread-safe box — `URLProtocol` callbacks and test assertions run on
/// different threads/tasks.
final class Locked<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ newValue: T) { lock.lock(); value = newValue; lock.unlock() }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); body(&value); lock.unlock() }
}

/// Records each request it sees and replays a scripted sequence of
/// responses (status code + body), one per call — lets the retry-policy
/// tests simulate "500, 500, 200" without touching the network.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let status: Int
        let body: Data
    }

    /// Queue of responses to hand out, in order, one per intercepted request.
    static let responses = Locked<[Response]>([])
    static let requestCount = Locked<Int>(0)
    static let requestMethods = Locked<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount.mutate { $0 += 1 }
        Self.requestMethods.mutate { $0.append(request.httpMethod ?? "GET") }

        var next: Response?
        Self.responses.mutate { queue in
            guard !queue.isEmpty else { return }
            next = queue.removeFirst()
        }
        guard let next else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status,
                                        httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset(responses: [Response]) {
        Self.responses.set(responses)
        Self.requestCount.set(0)
        Self.requestMethods.set([])
    }
}

final class PlaybackTests: XCTestCase {

    private func mockClient() -> JellyfinClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return JellyfinClient(baseURL: URL(string: "https://jelly.example")!, apiKey: "key",
                              deviceId: "device", session: session)
    }

    // MARK: - Retry policy

    func testProgressReportRetriesOn500ThenSucceeds() async throws {
        MockURLProtocol.reset(responses: [
            .init(status: 500, body: Data()),
            .init(status: 500, body: Data()),
            .init(status: 200, body: Data()),
        ])
        let client = mockClient()
        try await client.reportPlaybackProgress(.init(itemId: "i", mediaSourceId: "m", playSessionId: "p",
                                                       positionTicks: 0, isPaused: false))
        XCTAssertEqual(MockURLProtocol.requestCount.get(), 3)
    }

    func testPlaybackStartDoesNotRetryOn500() async throws {
        MockURLProtocol.reset(responses: [.init(status: 500, body: Data())])
        let client = mockClient()
        do {
            try await client.reportPlaybackStart(.init(itemId: "i", mediaSourceId: "m", playSessionId: "p", positionTicks: 0))
            XCTFail("expected throw")
        } catch {
            // Only one attempt — /Sessions/Playing must never retry (ghost sessions).
            XCTAssertEqual(MockURLProtocol.requestCount.get(), 1)
        }
    }

    func testPlaybackStoppedDoesNotRetryOn500() async throws {
        MockURLProtocol.reset(responses: [.init(status: 500, body: Data())])
        let client = mockClient()
        do {
            try await client.reportPlaybackStop(.init(itemId: "i", mediaSourceId: "m", playSessionId: "p", positionTicks: 0))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(MockURLProtocol.requestCount.get(), 1)
        }
    }

    func test401NeverRetries() async throws {
        MockURLProtocol.reset(responses: [.init(status: 401, body: Data())])
        let client = mockClient()
        do {
            try await client.reportPlaybackProgress(.init(itemId: "i", mediaSourceId: "m", playSessionId: "p",
                                                           positionTicks: 0, isPaused: false))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(MockURLProtocol.requestCount.get(), 1)
            guard case JellyfinRequestError.unauthorized = error else {
                return XCTFail("expected .unauthorized, got \(error)")
            }
        }
    }

    func testFavoriteRetriesOnServerError() async throws {
        // DELETE/PUT-like verbs (POST here is used for setFavorite, but the
        // policy under test is GET/PUT/DELETE always retry — exercise via
        // clearFavorite which issues DELETE).
        MockURLProtocol.reset(responses: [
            .init(status: 503, body: Data()),
            .init(status: 200, body: Data()),
        ])
        let client = mockClient()
        try await client.clearFavorite(userId: "u", itemId: "i")
        XCTAssertEqual(MockURLProtocol.requestCount.get(), 2)
        XCTAssertEqual(MockURLProtocol.requestMethods.get(), ["DELETE", "DELETE"])
    }

    func testGivesUpAfterMaxAttempts() async throws {
        MockURLProtocol.reset(responses: [
            .init(status: 500, body: Data()),
            .init(status: 500, body: Data()),
            .init(status: 500, body: Data()),
        ])
        let client = mockClient()
        do {
            try await client.reportPlaybackProgress(.init(itemId: "i", mediaSourceId: "m", playSessionId: "p",
                                                           positionTicks: 0, isPaused: false))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(MockURLProtocol.requestCount.get(), 3)   // capped at maxAttempts
        }
    }

    // MARK: - PlaybackInfoResolver (URL composition + direct-vs-HLS decision)

    private func playbackInfoJSON(playSessionId: String?, mediaSources: String) -> Data {
        let sessionField = playSessionId.map { "\"PlaySessionId\":\"\($0)\"," } ?? ""
        return """
        {\(sessionField)"MediaSources":[\(mediaSources)]}
        """.data(using: .utf8)!
    }

    func testResolverBuildsDirectURLWhenSupported() async throws {
        let body = playbackInfoJSON(
            playSessionId: "sess-1",
            mediaSources: #"{"Id":"ms-1","Container":"mp4","SupportsDirectPlay":true}"#
        )
        MockURLProtocol.reset(responses: [.init(status: 200, body: body)])
        let client = mockClient()
        let resolver = PlaybackInfoResolver(client: client, userId: "u")
        let resolved = try await resolver.resolve(itemId: "item-1")
        XCTAssertNotNil(resolved.directURL)
        XCTAssertTrue(resolved.directURL?.absoluteString.contains("/Videos/item-1/stream") ?? false)
        XCTAssertTrue(resolved.hlsURL.absoluteString.contains("/Videos/item-1/master.m3u8"))
        XCTAssertEqual(resolved.playSessionId, "sess-1")
        XCTAssertEqual(resolved.mediaSourceId, "ms-1")
    }

    func testResolverSkipsDirectURLWhenNotSupported() async throws {
        let body = playbackInfoJSON(
            playSessionId: "sess-2",
            mediaSources: #"{"Id":"ms-2","Container":"avi","SupportsDirectPlay":false}"#
        )
        MockURLProtocol.reset(responses: [.init(status: 200, body: body)])
        let client = mockClient()
        let resolver = PlaybackInfoResolver(client: client, userId: "u")
        let resolved = try await resolver.resolve(itemId: "item-2")
        XCTAssertNil(resolved.directURL)
        XCTAssertTrue(resolved.hlsURL.absoluteString.contains("master.m3u8"))
    }

    func testResolverThrowsOnMissingMediaSource() async throws {
        let body = playbackInfoJSON(playSessionId: "sess-3", mediaSources: "")
        MockURLProtocol.reset(responses: [.init(status: 200, body: body)])
        let client = mockClient()
        let resolver = PlaybackInfoResolver(client: client, userId: "u")
        do {
            _ = try await resolver.resolve(itemId: "item-3")
            XCTFail("expected throw")
        } catch let error as PlaybackInfoError {
            XCTAssertTrue(error.isItemLevel)
        }
    }

    func testResolverThrowsOnMissingPlaySessionId() async throws {
        let body = playbackInfoJSON(
            playSessionId: nil,
            mediaSources: #"{"Id":"ms-4","SupportsDirectPlay":true}"#
        )
        MockURLProtocol.reset(responses: [.init(status: 200, body: body)])
        let client = mockClient()
        let resolver = PlaybackInfoResolver(client: client, userId: "u")
        do {
            _ = try await resolver.resolve(itemId: "item-4")
            XCTFail("expected throw")
        } catch is PlaybackInfoError {
            // expected
        }
    }

    // MARK: - ProgressReporter stale-session detection

    /// The public API throttles to one POST per 10s, so driving three real
    /// consecutive 404s through `reportProgressIfDue` isn't practical in a
    /// unit test. This exercises the one call this test *can* make
    /// deterministically: a single 404 must not fire the callback early.
    func testStaleSessionCallbackDoesNotFireOnFirst404() async throws {
        MockURLProtocol.reset(responses: [.init(status: 404, body: Data())])
        let client = mockClient()
        let reporter = await ProgressReporter(client: client, itemId: "i", playSessionId: "p", mediaSourceId: "m")
        let fired = Locked(false)
        await reporter.setStaleCallback { fired.set(true) }
        await reporter.reportProgressIfDue(positionTicks: 0, isPaused: false)
        XCTAssertFalse(fired.get())
    }

    // MARK: - Generation

    func testGenerationCancelsSupersededTokens() {
        let generation = Generation()
        let first = generation.next()
        let second = generation.next()
        XCTAssertTrue(generation.isCancelled(first))
        XCTAssertFalse(generation.isCancelled(second))
    }

    // MARK: - Throttle

    func testThrottleFiresOnceThenBlocksWithinInterval() {
        let throttle = Throttle(interval: 60)
        var fireCount = 0
        XCTAssertTrue(throttle.fire { fireCount += 1 })
        XCTAssertFalse(throttle.fire { fireCount += 1 })
        XCTAssertEqual(fireCount, 1)
    }

    // MARK: - PlayableItem mapping

    private func fixtureArtwork() -> Artwork {
        Artwork(top: OKLCH(l: 0.5, c: 0.1, h: 200), bottom: OKLCH(l: 0.4, c: 0.1, h: 200))
    }

    func testMovieAsPlayableItem() {
        let movie = Movie(id: "movie-1", title: "Undertow", studioLine: "Feature Film", rating: "8.6",
                          certification: "PG-13", runtime: "2h 14m", director: "Mara Ellingsen",
                          year: "2026", genreLabel: "Movies / Thriller", synopsis: "...",
                          keyArt: "https://example.com/art.jpg", artwork: fixtureArtwork(),
                          resumeLabel: "Undertow", resumeProgress: 0.3, resumeRemaining: "1:40:12 LEFT",
                          starring: "Ines Duval", audioLine: "EN", moreLikeThis: [],
                          runtimeTicks: 80_000_000, resumePositionTicks: 24_000_000, isFavorite: true)
        let playable = movie.asPlayableItem()
        XCTAssertEqual(playable.id, "movie-1")
        XCTAssertNil(playable.seriesId)
        XCTAssertEqual(playable.title, "Undertow")
        XCTAssertNil(playable.subtitle)
        XCTAssertEqual(playable.runtimeTicks, 80_000_000)
        XCTAssertEqual(playable.resumePositionTicks, 24_000_000)
        XCTAssertTrue(playable.isFavorite)
        XCTAssertEqual(playable.imageURL, "https://example.com/art.jpg")
    }

    func testEpisodeAsPlayableItem() {
        let episode = Episode(id: "ep-1", number: 4, title: "The Undertow", runtime: "49m",
                              image: "https://example.com/ep.jpg", artwork: fixtureArtwork(),
                              runtimeTicks: 29_000_000, resumePositionTicks: 5_000_000,
                              isFavorite: false, seriesId: "series-1")
        let playable = episode.asPlayableItem(seriesTitle: "Deep Water", seasonNumber: 2)
        XCTAssertEqual(playable.id, "ep-1")
        XCTAssertEqual(playable.seriesId, "series-1")
        XCTAssertEqual(playable.title, "Deep Water")
        XCTAssertEqual(playable.subtitle, "S2 · E4 — \"The Undertow\"")
        XCTAssertEqual(playable.runtimeTicks, 29_000_000)
        XCTAssertEqual(playable.resumePositionTicks, 5_000_000)
        XCTAssertFalse(playable.isFavorite)
        XCTAssertEqual(playable.imageURL, "https://example.com/ep.jpg")
    }

    // MARK: - PlaybackRequest identity

    func testPlaybackRequestIdIsContentDerived() {
        let item = PlayableItem(id: "a", title: "A")
        let requestOne = PlaybackRequest.single(item)
        let requestTwo = PlaybackRequest.single(item)
        XCTAssertEqual(requestOne.id, requestTwo.id)

        let queue = PlaybackRequest.queue([item, PlayableItem(id: "b", title: "B")], startIndex: 1)
        XCTAssertNotEqual(queue.id, requestOne.id)
    }
}

private extension ProgressReporter {
    func setStaleCallback(_ callback: @escaping @MainActor () -> Void) {
        onStaleSessionDetected = callback
    }
}
