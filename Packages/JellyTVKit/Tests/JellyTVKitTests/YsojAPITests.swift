import XCTest
@testable import JellyTVKit

/// Decoding tests against **real bytes captured from the live YSOJ-server**, not from
/// payloads invented to match the structs. A hand-written fixture only proves the decoder
/// agrees with itself; these prove it agrees with the server.
final class YsojAPITests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Capabilities

    /// Verbatim from `GET /ysoj/capabilities` on 2026-09-06.
    private let capabilitiesJSON = """
    {"ysojVersion":"0.2.0","serverName":"xyan-media (YSOJ)","owner":true,"features":{
    "discover":{"enabled":true,"search":true,"sources":[{"id":"anilist","name":"AniList"},
    {"id":"tvmaze","name":"TVmaze"}],"hasMovieSource":false},
    "downloads":{"enabled":true,"engine":"stub","simulated":true,
    "granularity":["movie","episode","season","series"],"pollSeconds":2},
    "libraryOverrides":{"enabled":true,"scope":"server"},
    "profiles":{"enabled":true,"guests":true,"manageFromClient":false},
    "wan":{"enabled":true,"manageFromClient":false},"remote":{"enabled":false}}}
    """

    func testCapabilitiesDecodeFromLiveServer() throws {
        let caps = try decode(YsojAPI.Capabilities.self, capabilitiesJSON)
        XCTAssertEqual(caps.ysojVersion, "0.2.0")
        XCTAssertEqual(caps.serverName, "xyan-media (YSOJ)")
        XCTAssertTrue(caps.owner)
        XCTAssertTrue(caps.offersDiscover)
        XCTAssertEqual(caps.features.discover?.sources.map(\.id), ["anilist", "tvmaze"])
        XCTAssertEqual(caps.features.discover?.hasMovieSource, false, "no TMDB key on that server yet")
        XCTAssertEqual(caps.features.downloads?.pollSeconds, 2)
    }

    /// The one flag that must never be missed: a stub engine reports real progress and
    /// fetches nothing.
    func testSimulatedEngineIsVisible() throws {
        let caps = try decode(YsojAPI.Capabilities.self, capabilitiesJSON)
        XCTAssertEqual(caps.features.downloads?.engine, "stub")
        XCTAssertEqual(caps.features.downloads?.simulated, true)
    }

    /// `reachable`/`lastError` are being added server-side after this client was written.
    /// Absent must mean "usable", not "broken" — otherwise the client hides every source
    /// the moment it talks to a server that predates the field.
    func testSourceWithoutHealthFieldsIsTreatedAsUsable() throws {
        let source = try decode(YsojAPI.Capabilities.Source.self,
                                #"{"id":"tvmaze","name":"TVmaze"}"#)
        XCTAssertNil(source.reachable)
        XCTAssertTrue(source.isUsable)
    }

    func testSourceReportedUnreachableIsNotUsable() throws {
        let source = try decode(
            YsojAPI.Capabilities.Source.self,
            #"{"id":"anilist","name":"AniList","reachable":false,"lastError":"API disabled"}"#
        )
        XCTAssertFalse(source.isUsable)
        XCTAssertEqual(source.lastError, "API disabled")
    }

    // MARK: - Discover

    /// Verbatim from `GET /ysoj/discover/search?q=cowboy%20bebop`, trimmed to one row.
    private let searchItemJSON = """
    {"ref":"tvmaze:series:1121","title":"Cowboy Bebop","type":"series","year":1998,
    "rating":8.3,"genres":["Action","Adventure","Anime","Science-Fiction"],
    "overview":"In the year 2071, the crew of the spaceship Bebop travel the solar system.",
    "posterURL":"https://static.tvmaze.com/uploads/images/original_untouched/178/446548.jpg",
    "backdropURL":null,"sourceId":"tvmaze","sourceName":"TVmaze",
    "inLibrary":{"present":false,"jellyfinItemId":null,"known":true}}
    """

    func testDiscoverItemDecodesFromLiveSearch() throws {
        let item = try decode(YsojAPI.DiscoverItem.self, searchItemJSON)
        XCTAssertEqual(item.id, "tvmaze:series:1121")
        XCTAssertEqual(item.title, "Cowboy Bebop")
        XCTAssertTrue(item.isSeries)
        XCTAssertEqual(item.year, 1998)
        XCTAssertEqual(item.posterURL?.host, "static.tvmaze.com")
        XCTAssertNil(item.backdropURL, "a null backdrop must not fail the row")
        XCTAssertFalse(item.alreadyOwned)
    }

    /// A malformed URL from a third-party source must cost that one image, not the shelf.
    func testAnUnparseableImageURLDoesNotFailTheRow() throws {
        let json = #"""
        {"ref":"tmdb:movie:1","title":"X","type":"movie","year":2020,"rating":null,
        "genres":[],"overview":"","posterURL":"ht tp://not a url","backdropURL":null,
        "sourceId":"tmdb","sourceName":"TMDB","inLibrary":null}
        """#
        let item = try decode(YsojAPI.DiscoverItem.self, json)
        XCTAssertEqual(item.title, "X")
        XCTAssertNil(item.posterURL)
    }

    /// `known: false` means the library index could not be read — not that the item is
    /// absent. The client must not report "you don't have this" on a failed check.
    func testUnknownLibraryPresenceIsNotAnAbsence() throws {
        let presence = try decode(
            YsojAPI.LibraryPresence.self,
            #"{"present":false,"jellyfinItemId":null,"known":false}"#
        )
        XCTAssertFalse(presence.known)
        XCTAssertFalse(presence.present)
    }

    func testSpecialsAreExcludedFromDownloadableSeasons() throws {
        let json = """
        {"ref":"tvmaze:series:169","title":"Breaking Bad","type":"series","year":2008,
        "overview":"","genres":[],"runtimeMinutes":47,"rating":9.5,"certification":null,
        "posterURL":null,"backdropURL":null,"cast":[],"seasons":[
        {"seasonNumber":0,"name":"Specials","episodeCount":3,"year":null,"overview":"","posterURL":null},
        {"seasonNumber":1,"name":"Season 1","episodeCount":7,"year":2008,"overview":"","posterURL":null},
        {"seasonNumber":2,"name":"Season 2","episodeCount":13,"year":2009,"overview":"","posterURL":null}],
        "episodeCount":20,"status":"Ended","sourceId":"tvmaze","sourceName":"TVmaze",
        "sourceURL":null,"externalIds":{},"inLibrary":null}
        """
        let detail = try decode(YsojAPI.DiscoverDetail.self, json)
        XCTAssertEqual(detail.seasons.count, 3)
        XCTAssertEqual(detail.downloadableSeasons.map(\.seasonNumber), [1, 2],
                       "season 0 is real, but is never what 'download everything' means")
        XCTAssertTrue(detail.seasons[0].isSpecials)
    }

    // MARK: - Download scope

    func testScopeEncodesTheShapeTheServerValidates() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let season = String(decoding: try encoder.encode(YsojAPI.DownloadScope.season(2)), as: UTF8.self)
        XCTAssertEqual(season, #"{"kind":"season","seasonNumber":2}"#)

        let episode = try encoder.encode(YsojAPI.DownloadScope.episode(season: 2, number: 4))
        XCTAssertEqual(String(decoding: episode, as: UTF8.self),
                       #"{"episodeNumbers":[4],"kind":"episode","seasonNumber":2}"#)

        let whole = try encoder.encode(YsojAPI.DownloadScope.wholeSeries)
        XCTAssertEqual(String(decoding: whole, as: UTF8.self), #"{"kind":"series"}"#)
    }

    func testTheFourGranularitiesExist() {
        XCTAssertEqual(YsojAPI.DownloadScope.movie.kind, .movie)
        XCTAssertEqual(YsojAPI.DownloadScope.episode(season: 1, number: 1).kind, .episode)
        XCTAssertEqual(YsojAPI.DownloadScope.season(1).kind, .season)
        XCTAssertEqual(YsojAPI.DownloadScope.wholeSeries.kind, .series)
        XCTAssertEqual(YsojAPI.DownloadScope.episodes(season: 1, numbers: [1, 2, 3]).episodeNumbers,
                       [1, 2, 3])
    }

    // MARK: - Downloads

    /// Verbatim from `GET /ysoj/downloads` with no jobs.
    func testAnEmptyDownloadCentreDecodes() throws {
        let list = try decode(
            YsojAPI.DownloadList.self,
            #"{"jobs":[],"activeCount":0,"engine":"stub","canManage":true}"#
        )
        XCTAssertTrue(list.jobs.isEmpty)
        XCTAssertEqual(list.activeCount, 0)
        XCTAssertTrue(list.canManage, "the owner may start and cancel")
    }

    func testAMemberCannotManage() throws {
        let list = try decode(
            YsojAPI.DownloadList.self,
            #"{"jobs":[],"activeCount":0,"engine":"stub","canManage":false}"#
        )
        XCTAssertFalse(list.canManage)
    }

    private func job(state: String, progress: Double = 0.42) -> String {
        """
        {"id":"job_c6484870e253ea85","ref":"tvmaze:series:169","title":"Breaking Bad",
        "subtitle":"Season 2 · 13 episodes","posterURL":null,
        "scope":{"kind":"season","seasonNumber":2,"episodeNumbers":null},
        "state":"\(state)","progress":\(progress),"bytesTotal":18200000000,
        "bytesDownloaded":7644000000,"speedBytesPerSecond":243000000,"etaSeconds":43,
        "seeds":24,"peers":9,"message":"Downloading…","engine":"stub","landedItemIds":[],
        "createdAt":1788736000.0,"updatedAt":1788736040.0,"finishedAt":null,"isActive":true}
        """
    }

    func testADownloadingJobDecodesWithItsNumbers() throws {
        let decoded = try decode(YsojAPI.DownloadJob.self, job(state: "downloading"))
        XCTAssertEqual(decoded.state, .downloading)
        XCTAssertEqual(decoded.bytesTotal, 18_200_000_000)
        XCTAssertEqual(decoded.etaSeconds, 43)
        XCTAssertEqual(decoded.scope.seasonNumber, 2)
        XCTAssertTrue(decoded.isSimulated)
        XCTAssertTrue(decoded.canPause)
        XCTAssertFalse(decoded.canResume)
    }

    /// A server that grows a state must not make the whole download centre undecodable.
    func testAnUnknownStateFallsBackInsteadOfThrowing() throws {
        let decoded = try decode(YsojAPI.DownloadJob.self, job(state: "verifying"))
        XCTAssertEqual(decoded.state, .unknown)
        XCTAssertFalse(decoded.state.isTerminal)
        XCTAssertFalse(decoded.state.showsProgress)
    }

    func testTerminalStates() {
        for state: YsojAPI.DownloadJob.State in [.landed, .failed, .cancelled] {
            XCTAssertTrue(state.isTerminal, "\(state) should be terminal")
        }
        for state: YsojAPI.DownloadJob.State in [.searching, .queued, .downloading, .importing] {
            XCTAssertFalse(state.isTerminal, "\(state) should not be terminal")
        }
    }

    /// "Searching" has no denominator, so a progress bar there would be a lie.
    func testProgressIsOnlyShownOnceItMeansSomething() {
        XCTAssertFalse(YsojAPI.DownloadJob.State.searching.showsProgress)
        XCTAssertFalse(YsojAPI.DownloadJob.State.queued.showsProgress)
        XCTAssertTrue(YsojAPI.DownloadJob.State.downloading.showsProgress)
        XCTAssertTrue(YsojAPI.DownloadJob.State.landed.showsProgress)
    }

    // MARK: - Plans

    func testAPlanCarriesItsWarningsVerbatim() throws {
        let json = """
        {"planId":"plan_56f8da54fdde0c89","ref":"tvmaze:series:169","title":"Breaking Bad",
        "subtitle":"Season 2 · 13 episodes","type":"series","year":2008,"posterURL":null,
        "scope":{"kind":"season","seasonNumber":2,"episodeNumbers":null},"episodeCount":13,
        "estimatedBytes":18200000000,"quality":"1080p","candidateCount":0,
        "warnings":["No download engine is installed yet, so this will be simulated."],
        "inLibrary":{"present":false,"jellyfinItemId":null,"known":true},
        "engine":"stub","expiresAt":1788739600.0}
        """
        let plan = try decode(YsojAPI.DownloadPlan.self, json)
        XCTAssertEqual(plan.id, "plan_56f8da54fdde0c89")
        XCTAssertEqual(plan.episodeCount, 13)
        XCTAssertEqual(plan.warnings.count, 1)
        XCTAssertTrue(plan.isSimulated)
    }

    // MARK: - Library overrides

    func testLibraryOverrideRoundTrips() throws {
        let json = """
        {"libraryId":"abc123","displayName":"Anime","isNSFW":false,"isAnime":true,
        "layout":null,"updatedAt":"2026-09-06 21:00:00"}
        """
        let override = try decode(YsojAPI.LibraryOverride.self, json)
        XCTAssertEqual(override.id, "abc123")
        XCTAssertTrue(override.isAnime)
        XCTAssertFalse(override.isNSFW)

        // And it encodes back into what PUT expects.
        let encoded = try JSONEncoder().encode(override)
        let again = try JSONDecoder().decode(YsojAPI.LibraryOverride.self, from: encoded)
        XCTAssertEqual(again, override)
    }

    // MARK: - Review additions

    /// A server predating `remote` — and one that dropped a key — still decodes; the
    /// missing feature reads as not offered rather than taking Discover down.
    func testACapabilitiesDocumentMissingFeaturesStillDecodes() throws {
        let old = try decode(YsojAPI.Capabilities.self, #"""
        {"ysojVersion":"0.1.0","serverName":"x","owner":false,
         "features":{"discover":{"enabled":true,"search":true,"sources":[],"hasMovieSource":false}}}
        """#)
        XCTAssertNil(old.features.remote)
        XCTAssertNil(old.features.downloads)
        XCTAssertTrue(old.offersDiscover)
        XCTAssertFalse(old.hasMovieSource)
        let bare = try decode(YsojAPI.Capabilities.self,
                              #"{"ysojVersion":"0.3.0","serverName":"x","owner":true,"features":{}}"#)
        XCTAssertFalse(bare.offersDiscover)
    }

    /// The bug that shipped: a hand-encoded ref went out double-encoded and every detail
    /// page spun forever. The path is handed over *decoded* and encoded exactly once.
    func testADiscoverRefSurvivesTheURLBuild() throws {
        let base = URL(string: "http://192.168.1.150:8097")!
        let url = try XCTUnwrap(YsojClient.url(base: base, path: "/ysoj/discover/item/tmdb:movie:27205", query: nil))
        XCTAssertEqual(url.absoluteString, "http://192.168.1.150:8097/ysoj/discover/item/tmdb:movie:27205")
        let odd = try XCTUnwrap(YsojClient.url(base: base, path: "/ysoj/downloads/job a#1", query: [URLQueryItem(name: "q", value: "x y")]))
        XCTAssertEqual(odd.absoluteString, "http://192.168.1.150:8097/ysoj/downloads/job%20a%231?q=x%20y")
        let subpath = try XCTUnwrap(YsojClient.url(base: URL(string: "http://h/jelly")!, path: "/ysoj/capabilities", query: nil))
        XCTAssertEqual(subpath.absoluteString, "http://h/jelly/ysoj/capabilities", "a base with its own path keeps it")
    }

    func testATrailerIsALinkTheClientCanOpen() throws {
        let trailer = try decode(YsojAPI.Trailer.self, #"""
        {"site":"YouTube","key":"abc123","name":"Official Trailer","type":"Trailer","official":true,
         "publishedAt":"2026-04-01","url":"https://www.youtube.com/watch?v=abc123"}
        """#)
        XCTAssertTrue(trailer.isYouTube)
        XCTAssertEqual(trailer.pageURL?.absoluteString, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(trailer.appURL?.absoluteString, "youtube://abc123")
        XCTAssertEqual(trailer.embedURL?.host, "www.youtube-nocookie.com")

        let keyOnly = try decode(YsojAPI.Trailer.self,
                                 #"{"site":"youtube","key":"k","name":"","type":"Teaser","url":null}"#)
        XCTAssertEqual(keyOnly.pageURL?.absoluteString, "https://www.youtube.com/watch?v=k", "derived from the key when the server sent no URL")
        let vimeo = try decode(YsojAPI.Trailer.self,
                               #"{"site":"Vimeo","key":"9","name":"","type":"Trailer","url":null}"#)
        XCTAssertNil(vimeo.pageURL)
        XCTAssertNil(vimeo.appURL)

        let detail = try decode(YsojAPI.DiscoverDetail.self, #"""
        {"ref":"tmdb:movie:1","title":"T","type":"movie","overview":"","genres":[],"cast":[],"seasons":[],
         "sourceId":"tmdb","sourceName":"TMDB","externalIds":{},
         "trailers":[{"site":"Vimeo","key":"9","name":"","type":"Trailer"},
                     {"site":"YouTube","key":"ok","name":"","type":"Trailer"}]}
        """#)
        XCTAssertEqual(detail.bestTrailer?.key, "ok", "the first trailer the client can actually open")
    }

    func testDownloadFormattingReadsLikeARow() {
        XCTAssertEqual(DownloadFormatting.eta(43), "43s")
        XCTAssertEqual(DownloadFormatting.eta(754), "12m")
        XCTAssertEqual(DownloadFormatting.eta(3900), "1h 05m")
        XCTAssertEqual(DownloadFormatting.eta(-5), "0s")
        XCTAssertTrue(DownloadFormatting.bytes(18_200_000_000).hasSuffix("GB"))
        XCTAssertTrue(DownloadFormatting.bytes(7_644_000).hasSuffix("MB"))
        XCTAssertFalse(DownloadFormatting.bytes(-1).contains("-"))
    }

    // MARK: - What the engine can actually fetch

    /// The stub simulates all four scopes; a real engine that resolves one link to one
    /// release can do films long before seasons, and narrows `granularity` to say so.
    func testGranularityNarrowsWhatThePageMayOffer() throws {
        let all = try decode(YsojAPI.Capabilities.self, capabilitiesJSON)
        XCTAssertEqual(all.downloadScopes, [.movie, .episode, .season, .series])
        XCTAssertFalse(all.downloadsAreFilmOnly)
        XCTAssertTrue(all.canDownload(.season))

        let filmOnly = try decode(YsojAPI.Capabilities.self, capabilitiesJSON.replacingOccurrences(
            of: #""granularity":["movie","episode","season","series"]"#,
            with: #""granularity":["movie"]"#))
        XCTAssertEqual(filmOnly.downloadScopes, [.movie])
        XCTAssertTrue(filmOnly.downloadsAreFilmOnly)
        XCTAssertFalse(filmOnly.canDownload(.season))
    }

    /// Silence is not "nothing". A server that never narrowed the list, or one that sends
    /// only names this client has never heard of, must not hide every download control.
    func testAnEmptyOrUnknownGranularityReadsAsEverything() throws {
        for raw in [#"[]"#, #"["chapters"]"#] {
            let caps = try decode(YsojAPI.Capabilities.self, capabilitiesJSON.replacingOccurrences(
                of: #""granularity":["movie","episode","season","series"]"#,
                with: #""granularity":\#(raw)"#))
            XCTAssertEqual(caps.downloadScopes, YsojAPI.DownloadScope.Kind.allCases,
                           "\(raw) must read as everything, not as nothing")
        }
    }

    func testScopesAreNamedForTheSentenceThatExplainsThem() {
        XCTAssertEqual(YsojAPI.DownloadScope.Kind.season.label, "seasons")
        XCTAssertEqual(YsojAPI.DownloadScope.Kind.movie.label, "films")
    }
}
