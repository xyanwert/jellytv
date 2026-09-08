import XCTest
@testable import JellyTVKit

/// The sending half of remote control, tested where it can be: the session decode against
/// real `/Sessions` bytes, the presence rule, what a play becomes on the wire, and the
/// clock between reports.
final class RemoteLinkTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Sessions

    /// Verbatim from `GET /Sessions` through the live YSOJ-server on 2026-09-07 (one
    /// Jellyfin Web session; `DeviceId` was redacted by the probe and is filled in here).
    private let sessionsJSON = """
    [{"PlayState":{"CanSeek":false,"IsPaused":false,"IsMuted":false,"RepeatMode":"RepeatNone","PlaybackOrder":"Default"},"AdditionalUsers":[],"Capabilities":{"PlayableMediaTypes":["Audio","Video"],"SupportedCommands":["MoveUp","DisplayMessage"],"SupportsMediaControl":true,"SupportsPersistentIdentifier":false},"RemoteEndPoint":"192.168.1.209","PlayableMediaTypes":["Audio","Video"],"Id":"54061cd1ac897e637f8fadde4eed59ae","UserId":"89b2ae71b4514311bb24ea1c4ca0461d","UserName":"xyan","Client":"Jellyfin Web","LastActivityDate":"2026-09-07T18:59:09.0250869Z","LastPlaybackCheckIn":"0001-01-01T00:00:00.0000000Z","DeviceName":"Chrome","DeviceId":"TW96aWxsYS81LjAg","ApplicationVersion":"10.11.11","IsActive":true,"SupportsMediaControl":true,"SupportsRemoteControl":true,"NowPlayingQueue":[],"NowPlayingQueueFullItems":[],"HasCustomDeviceName":false,"ServerId":"e95e938baafb4ba18d3ef9a82808722f","SupportedCommands":["MoveUp","DisplayMessage"]}]
    """

    func testSessionsDecodeFromLiveServer() throws {
        let sessions = try decode([JellyfinAPI.SessionInfo].self, sessionsJSON)
        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.id, "54061cd1ac897e637f8fadde4eed59ae")
        XCTAssertEqual(session.deviceId, "TW96aWxsYS81LjAg")
        XCTAssertEqual(session.deviceName, "Chrome")
        XCTAssertEqual(session.client, "Jellyfin Web")
        XCTAssertEqual(session.isActive, true)
        XCTAssertNil(session.nowPlayingItem, "nothing playing → no item, not a decode failure")
        XCTAssertEqual(session.playState?.isPaused, false)
    }

    func testASessionPlayingSomethingCarriesTheItemAndPosition() throws {
        let json = #"""
        {"Id":"s1","DeviceId":"tv-1","IsActive":true,"SupportsRemoteControl":true,
         "NowPlayingItem":{"Id":"m1","Name":"Heat","Type":"Movie","RunTimeTicks":102000000000},
         "PlayState":{"PositionTicks":6000000000,"IsPaused":true,"CanSeek":true}}
        """#
        let session = try decode(JellyfinAPI.SessionInfo.self, json)
        XCTAssertEqual(session.nowPlayingItem?.name, "Heat")
        XCTAssertEqual(session.nowPlayingItem?.runTimeTicks, 102_000_000_000)
        XCTAssertEqual(session.playState?.positionTicks, 6_000_000_000)
        XCTAssertEqual(session.playState?.isPaused, true)
    }

    // MARK: - Presence

    func testOnlineMeansAnOpenSocketThatTakesCommands() throws {
        let live = try decode(JellyfinAPI.SessionInfo.self,
                              #"{"Id":"a","IsActive":true,"SupportsRemoteControl":true}"#)
        let closed = try decode(JellyfinAPI.SessionInfo.self,
                                #"{"Id":"b","IsActive":false,"SupportsRemoteControl":true}"#)
        let deaf = try decode(JellyfinAPI.SessionInfo.self,
                              #"{"Id":"c","IsActive":true,"SupportsRemoteControl":false,"SupportsMediaControl":false}"#)
        let unknown = try decode(JellyfinAPI.SessionInfo.self, #"{"Id":"d"}"#)
        XCTAssertTrue(TVPresence.isOnline(live))
        XCTAssertFalse(TVPresence.isOnline(closed), "a lingering session with its socket gone is not a TV you can drive")
        XCTAssertFalse(TVPresence.isOnline(deaf))
        XCTAssertFalse(TVPresence.isOnline(unknown), "absent flags mean offline, never online")
    }

    func testMediaControlAloneIsTheDocumentedFallback() throws {
        let legacy = try decode(JellyfinAPI.SessionInfo.self,
                                #"{"Id":"a","IsActive":true,"SupportsMediaControl":true}"#)
        XCTAssertTrue(TVPresence.isOnline(legacy), "a server that only reports SupportsMediaControl still counts")
    }

    func testTheTVIsFoundByDeviceId() throws {
        let sessions = try decode([JellyfinAPI.SessionInfo].self,
                                  #"[{"Id":"a","DeviceId":"x"},{"Id":"b","DeviceId":"tv-1"}]"#)
        XCTAssertEqual(TVPresence.session(forDevice: "tv-1", in: sessions)?.id, "b")
        XCTAssertNil(TVPresence.session(forDevice: "nope", in: sessions))
    }

    // MARK: - Dispatch

    private func item(_ id: String, resume: Int64? = nil) -> PlayableItem {
        PlayableItem(id: id, title: id, resumePositionTicks: resume)
    }

    func testASingleItemGoesAloneSoTheTVCanExpandIt() {
        let command = RemoteDispatch.playCommand(for: .single(item("ep4", resume: 42)))
        XCTAssertEqual(command, .init(itemIds: ["ep4"], startIndex: 0, startPositionTicks: 42))
    }

    func testAQueueIsSentFromItsStartItemRebasedToZero() {
        let request = PlaybackRequest.queue([item("a"), item("b", resume: 7), item("c")], startIndex: 1)
        let command = RemoteDispatch.playCommand(for: request)
        XCTAssertEqual(command?.itemIds, ["b", "c"], "what the phone already skipped stays skipped")
        XCTAssertEqual(command?.startIndex, 0)
        XCTAssertEqual(command?.startPositionTicks, 7, "the start item's resume position rides along")
    }

    func testAQueueIsCappedToWhatARequestLineCanCarry() {
        let items = (0..<400).map { item("i\($0)") }
        let command = RemoteDispatch.playCommand(for: .queue(items, startIndex: 10))
        XCTAssertEqual(command?.itemIds.count, RemoteDispatch.maxItemIds)
        XCTAssertEqual(command?.itemIds.first, "i10")
    }

    func testAnOutOfRangeStartIsClampedAndAnEmptyQueueIsNothing() {
        XCTAssertNil(RemoteDispatch.playCommand(for: PlaybackRequest(items: [], startIndex: 0)))
        let command = RemoteDispatch.playCommand(for: .queue([item("a"), item("b")], startIndex: 99))
        XCTAssertEqual(command?.itemIds, ["b"])
        let negative = RemoteDispatch.playCommand(for: PlaybackRequest(items: [item("a"), item("b")], startIndex: -3))
        XCTAssertEqual(negative?.itemIds, ["a", "b"], "a negative start clamps to the first item")
    }

    // MARK: - Clock

    private func session(ticks: Int64, paused: Bool) throws -> JellyfinAPI.SessionInfo {
        try decode(JellyfinAPI.SessionInfo.self, """
        {"Id":"s","NowPlayingItem":{"Id":"m"},"PlayState":{"PositionTicks":\(ticks),"IsPaused":\(paused)}}
        """)
    }

    func testTheClockCountsForwardFromTheLastReport() throws {
        let t0 = Date(timeIntervalSince1970: 1000)
        let clock = try XCTUnwrap(RemoteClock(session: session(ticks: 600_000_000, paused: false), at: t0))
        XCTAssertEqual(clock.positionSeconds(at: t0.addingTimeInterval(4)), 64, accuracy: 0.001)
    }

    func testTheSameReportOnANewPollDoesNotRebaseTheClock() throws {
        let t0 = Date(timeIntervalSince1970: 1000)
        let first = try XCTUnwrap(RemoteClock(session: session(ticks: 600_000_000, paused: false), at: t0))
        // 1.5 s later the phone polls and sees the same ticks — the TV has not reported yet.
        let same = try XCTUnwrap(first.updated(with: session(ticks: 600_000_000, paused: false),
                                               at: t0.addingTimeInterval(1.5)))
        XCTAssertEqual(same, first, "re-basing here would make the readout jump backwards")
        XCTAssertEqual(same.positionSeconds(at: t0.addingTimeInterval(3)), 63, accuracy: 0.001)
    }

    func testANewReportRebasesAndPauseStopsTheClock() throws {
        let t0 = Date(timeIntervalSince1970: 1000)
        let first = try XCTUnwrap(RemoteClock(session: session(ticks: 600_000_000, paused: false), at: t0))
        let seeked = try XCTUnwrap(first.updated(with: session(ticks: 3_000_000_000, paused: false),
                                                 at: t0.addingTimeInterval(2)))
        XCTAssertEqual(seeked.positionSeconds(at: t0.addingTimeInterval(2)), 300, accuracy: 0.001)
        let paused = try XCTUnwrap(seeked.updated(with: session(ticks: 3_050_000_000, paused: true),
                                                  at: t0.addingTimeInterval(7)))
        XCTAssertEqual(paused.positionSeconds(at: t0.addingTimeInterval(60)), 305, accuracy: 0.001,
                       "a paused TV's clock does not move")
    }

    func testANewItemWithTheSameTicksRebasesTheClock() throws {
        let t0 = Date(timeIntervalSince1970: 1000)
        let first = try XCTUnwrap(RemoteClock(session: session(ticks: 0, paused: false), at: t0))
        // Stop, then start something else: its first report is also 0 / playing.
        let other = try decode(JellyfinAPI.SessionInfo.self,
                               #"{"Id":"s","NowPlayingItem":{"Id":"m2"},"PlayState":{"PositionTicks":0,"IsPaused":false}}"#)
        let rebased = try XCTUnwrap(first.updated(with: other, at: t0.addingTimeInterval(30)))
        XCTAssertEqual(rebased.itemId, "m2")
        XCTAssertEqual(rebased.positionSeconds(at: t0.addingTimeInterval(31)), 1, accuracy: 0.001,
                       "counting on from the previous film's clock would say 31")
    }

    func testTheClockIsClampedToTheRuntimeAndVanishesWhenNothingPlays() throws {
        let t0 = Date(timeIntervalSince1970: 1000)
        let clock = try XCTUnwrap(RemoteClock(session: session(ticks: 990_000_000, paused: false), at: t0))
        XCTAssertEqual(clock.positionSeconds(at: t0.addingTimeInterval(30), runtimeSeconds: 100), 100)
        let idle = try decode(JellyfinAPI.SessionInfo.self, #"{"Id":"s"}"#)
        XCTAssertNil(RemoteClock(session: idle, at: t0))
        XCTAssertNil(clock.updated(with: idle, at: t0))
    }

    // MARK: - Words

    func testAnEpisodeIsNamedOneWay() throws {
        let episode = try decode(JellyfinAPI.JellyfinItem.self,
                                 #"{"Id":"e","Name":"Killing Utne","Type":"Episode","ParentIndexNumber":1,"IndexNumber":4}"#)
        XCTAssertEqual(episode.episodeMarker, "S1 · E4")
        XCTAssertEqual(episode.episodeLine, "S1 · E4 — Killing Utne")
        let noSeason = try decode(JellyfinAPI.JellyfinItem.self,
                                  #"{"Id":"e","Name":"Pilot","Type":"Episode","IndexNumber":1}"#)
        XCTAssertNil(noSeason.episodeMarker, "half a marker is no marker")
        XCTAssertEqual(noSeason.episodeLine, "Pilot")
        let film = try decode(JellyfinAPI.JellyfinItem.self, #"{"Id":"m","Name":"Heat","Type":"Movie"}"#)
        XCTAssertEqual(film.episodeLine, "Heat")
        let nameless = try decode(JellyfinAPI.JellyfinItem.self, #"{"Id":"x","Type":"Episode"}"#)
        XCTAssertEqual(nameless.episodeLine, "Untitled")
    }

    func testTheServersOwnSentenceWinsWhenItSentOne() {
        let refusal = JellyfinRequestError.server(status: 403, body: #"{"detail":"Be on the same Wi‑Fi as the TV to pair."}"#)
        XCTAssertEqual(ServerMessage.text(for: refusal, fallback: "no"), "Be on the same Wi‑Fi as the TV to pair.")
        XCTAssertEqual(ServerMessage.text(for: JellyfinRequestError.server(status: 500, body: "<html>"), fallback: "no"), "no")
        XCTAssertEqual(ServerMessage.text(for: JellyfinRequestError.server(status: 500, body: #"{"detail":""}"#), fallback: "no"), "no")
        XCTAssertEqual(ServerMessage.text(for: JellyfinRequestError.server(status: 422, body: #"{"detail":{"loc":["body"]}}"#), fallback: "no"), "no",
                       "a typed error body is not a sentence")
        XCTAssertEqual(ServerMessage.text(for: URLError(.timedOut), fallback: "no"), "no")
    }

    func testHeaderValuesAreMadeSafe() {
        XCTAssertEqual(JellyfinAPI.headerSafe("Living Room"), "Living Room")
        XCTAssertEqual(JellyfinAPI.headerSafe("Salón"), "Salon")
        XCTAssertEqual(JellyfinAPI.headerSafe("Ana\"s TV"), "Anas TV")
        XCTAssertEqual(JellyfinAPI.headerSafe("TV 📺"), "TV")
        XCTAssertEqual(JellyfinAPI.headerSafe("Wohnzimmer\\"), "Wohnzimmer")
        let header = JellyfinAPI.authorizationHeader(token: "t", client: "JellyTV", device: "Ana\"s TV",
                                                     deviceId: "d", version: "1")
        XCTAssertFalse(header.contains("Ana\"s"), "a quote inside a quoted value breaks the parse")
    }

    // MARK: - Pairing shapes

    func testABeaconInAStateWeDoNotKnowReadsAsExpired() throws {
        let beacon = try decode(YsojAPI.RemoteBeacon.self, #"""
        {"id":"b","tvDeviceId":"tv","tvName":"TV","expiresAt":1,"state":"something-new","pairing":null}
        """#)
        XCTAssertFalse(beacon.isWaiting)
        XCTAssertFalse(beacon.isPaired)
        XCTAssertNil(beacon.sameNetwork, "absent means the server could not tell")
    }

    func testBeaconsAndPairingsDecodeAndThePairingRoundTripsLocally() throws {
        let beacon = try decode(YsojAPI.RemoteBeacon.self, #"""
        {"id":"beacon_1","tvDeviceId":"tv-1","tvName":"Living Room","expiresAt":1788814873.0,
         "state":"waiting","pairing":null,"sameNetwork":true}
        """#)
        XCTAssertTrue(beacon.isWaiting)
        XCTAssertEqual(beacon.sameNetwork, true)

        let pairing = YsojAPI.RemotePairing(id: "pair_1", tvDeviceId: "tv-1", tvName: "Living Room",
                                            remoteDeviceId: "ph-1", remoteName: "iPhone", createdAt: 1)
        let data = try JSONEncoder().encode([pairing])
        XCTAssertEqual(try JSONDecoder().decode([YsojAPI.RemotePairing].self, from: data), [pairing])
    }
}
