import Foundation
import JellyTVKit

/// State for the Discover screen and the download centre.
///
/// Kept out of `AppState` deliberately: this is one screen's worth of state with its own
/// lifetime, and `AppState` is already the app's crossroads. It talks only to `YsojClient`.
///
/// **The load rule this whole type is shaped around:** an empty shelf and an unreachable
/// source must never look the same. Both of this app's anime sources are down as often as
/// not — AniList's API is disabled outright, and MyAnimeList/Jikan goes dark for minutes
/// at a time — so "nothing here" is the *common* case, and rendering it as a blank grid
/// would read as a broken feature forever. `ShelfState` keeps the two apart and the view
/// says which it is.
@MainActor
final class DiscoverStore: ObservableObject {

    /// Why a shelf is showing what it is showing.
    enum ShelfState: Equatable {
        case idle
        case loading
        /// Rows to draw.
        case loaded
        /// The shelf's own source could not be reached. Carries the name to blame and,
        /// when the server told us, the reason — shown verbatim rather than paraphrased.
        case unavailable(source: String, reason: String?)
        /// The source answered and genuinely had nothing.
        case empty
        case failed(String)
    }

    // MARK: - Published state

    @Published fileprivate(set) var categories: [YsojAPI.DiscoverCategory] = []
    @Published fileprivate(set) var sources: [YsojAPI.Capabilities.Source] = []
    @Published fileprivate(set) var items: [YsojAPI.DiscoverItem] = []
    @Published fileprivate(set) var shelfState: ShelfState = .idle
    @Published var selectedCategoryId: String?

    @Published var searchText: String = ""
    @Published fileprivate(set) var searchResults: [YsojAPI.DiscoverItem] = []
    @Published fileprivate(set) var isSearching = false
    /// Search is a mode, not a filter — entering it replaces the shelf entirely, because
    /// "trending, narrowed to your query" is not a thing any of these sources can answer.
    var isSearchMode: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    @Published fileprivate(set) var details: [String: YsojAPI.DiscoverDetail] = [:]

    @Published fileprivate(set) var jobs: [YsojAPI.DownloadJob] = [] {
        didSet { onActiveJobCountChange?(activeJobCount) }
    }
    @Published fileprivate(set) var canManageDownloads = false
    @Published fileprivate(set) var downloadsAreSimulated = false
    /// Whether the last download-centre poll got an answer. An unreachable server and an
    /// empty centre must not look the same — the same rule the shelves are built on.
    @Published fileprivate(set) var downloadsState: DownloadsState = .loading
    /// The rail badge's feed. Set by whoever owns the store, so the count is written in
    /// one place instead of by each screen that happens to be looking.
    var onActiveJobCountChange: ((Int) -> Void)?

    enum DownloadsState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// Set when a download action fails, cleared when the user acknowledges. The server's
    /// own message is shown — it is written for a person and says what to do.
    @Published var actionError: String?

    // MARK: Release search (the trackers)

    /// Whether the download centre shows the release search at all. The live answer is
    /// the capabilities document's (`offersReleaseSearch`: the owner, on a server that
    /// has the endpoint); this flag is what the screenshot fixture sets.
    @Published var offersReleaseSearch = false
    @Published var releaseQuery: String = ""
    @Published var releaseCategory: YsojAPI.ReleaseCategory = .all
    @Published fileprivate(set) var releaseSearch: YsojAPI.ReleaseSearch?
    @Published fileprivate(set) var releaseState: ReleaseState = .idle

    enum ReleaseState: Equatable {
        case idle
        case searching
        case loaded
        case failed(String)
    }

    /// A mode, like Discover's search: while there is a query the centre shows releases
    /// instead of jobs, and clearing it brings the jobs back.
    var isReleaseMode: Bool { !trimmedReleaseQuery.isEmpty }

    // MARK: - Private

    private let client: YsojClient
    fileprivate var hasLoadedCategories = false
    private var searchTask: Task<Void, Never>?
    private var shelfTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var consecutivePollFailures = 0
    /// Shelves already fetched, so walking back along the chip row is instant. The server
    /// caches too, but a round trip per chip press is still a visible stall on a TV.
    private var shelfCache: [String: [YsojAPI.DiscoverItem]] = [:]

    private static let searchDebounce: Duration = .milliseconds(300)
    private var releaseTask: Task<Void, Never>?
    /// Longer than Discover's: a tracker search is two or three upstream requests, the
    /// slow ones take seconds, and the server caches the exact question — so a keystroke
    /// must not be a search, and Return searches at once.
    private static let releaseDebounce: Duration = .milliseconds(700)

    init(client: YsojClient) {
        self.client = client
    }

    deinit {
        searchTask?.cancel()
        shelfTask?.cancel()
        pollTask?.cancel()
        releaseTask?.cancel()
    }

    // MARK: - Shelves

    /// Categories and source health together — the second is what lets an empty shelf
    /// explain itself, so fetching one without the other would mean a window where it
    /// can't.
    func loadCategories() async {
        guard !hasLoadedCategories else { return }
        async let categoriesResult = try? await client.fetchCategories()
        async let sourcesResult = try? await client.fetchSources()
        let (fetched, health) = await (categoriesResult, sourcesResult)

        sources = health ?? []
        categories = fetched ?? []
        // Set once on the first success, never reset by a later refresh — the same rule
        // the library screens follow, so a transient failure can't re-trigger a load.
        hasLoadedCategories = !categories.isEmpty

        if categories.isEmpty {
            // Nothing to select means nothing will ever load a shelf, and the grid would
            // sit blank with no word about why. Say which of the two it was.
            shelfState = fetched == nil ? .failed("Couldn't reach the server.") : .empty
            return
        }
        if selectedCategoryId == nil {
            // Open on a shelf that can actually answer. Landing the user on a dead anime
            // source when films are working would be a bad first impression of a feature
            // that is, in fact, working.
            selectedCategoryId = (categories.first { isUsable($0) } ?? categories.first)?.id
        }
        if let selectedCategoryId {
            await loadShelf(selectedCategoryId)
        }
    }

    private func source(for category: YsojAPI.DiscoverCategory) -> YsojAPI.Capabilities.Source? {
        sources.first { $0.id == category.sourceId }
    }

    private func isUsable(_ category: YsojAPI.DiscoverCategory) -> Bool {
        source(for: category)?.isUsable ?? true
    }

    func selectCategory(_ id: String) {
        guard selectedCategoryId != id else { return }
        selectedCategoryId = id
        shelfTask?.cancel()
        shelfTask = Task { await loadShelf(id) }
    }

    func loadShelf(_ categoryId: String) async {
        if let cached = shelfCache[categoryId] {
            items = cached
            // The same reason as a fresh fetch: a cached empty for a source that is down
            // must still say so, not degrade to "nothing here" on the second visit.
            shelfState = cached.isEmpty ? emptyReason(for: categoryId) : .loaded
            return
        }
        items = []
        shelfState = .loading
        do {
            let fetched = try await client.fetchCatalog(category: categoryId)
            guard !Task.isCancelled, selectedCategoryId == categoryId else { return }
            shelfCache[categoryId] = fetched
            items = fetched
            shelfState = fetched.isEmpty ? emptyReason(for: categoryId) : .loaded
        } catch {
            guard !Task.isCancelled else { return }
            shelfState = .failed(Self.message(for: error))
        }
    }

    /// A shelf came back with nothing. Was that an answer, or a silence?
    ///
    /// The server swallows a provider failure and serves the shelf empty rather than
    /// failing the request — right for robustness, useless for the user — so source
    /// health is what tells the two apart after the fact.
    private func emptyReason(for categoryId: String) -> ShelfState {
        guard let category = categories.first(where: { $0.id == categoryId }),
              let source = source(for: category), !source.isUsable else {
            return .empty
        }
        return .unavailable(source: source.name, reason: source.lastError)
    }

    /// Health goes stale — a source that was down at launch may be up now. Called when
    /// the screen reappears, not on a timer: these are somebody else's servers.
    func refreshSourceHealth() async {
        guard let health = try? await client.fetchSources() else { return }
        sources = health
        // A source that recovered should stop claiming to be broken, so drop the cached
        // empties that its health was the explanation for.
        for category in categories where !(source(for: category)?.isUsable ?? true) {
            shelfCache[category.id] = nil
        }
        if case .unavailable = shelfState, let selectedCategoryId {
            shelfCache[selectedCategoryId] = nil
            await loadShelf(selectedCategoryId)
        }
    }

    // MARK: - Search

    /// Debounced, because this is a TV keyboard and every keystroke would otherwise be a
    /// round trip to three third-party APIs.
    func searchTextChanged() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
            let found = (try? await client.search(query: query)) ?? []
            guard !Task.isCancelled else { return }
            searchResults = found
            isSearching = false
        }
    }

    /// What the grid is actually showing right now.
    var visibleItems: [YsojAPI.DiscoverItem] { isSearchMode ? searchResults : items }

    // MARK: - Detail

    @discardableResult
    func loadDetail(ref: String) async -> YsojAPI.DiscoverDetail? {
        if let cached = details[ref] { return cached }
        guard let fetched = try? await client.fetchDetail(ref: ref) else { return nil }
        details[ref] = fetched
        return fetched
    }

    // MARK: - Downloads

    func plan(ref: String, scope: YsojAPI.DownloadScope) async -> YsojAPI.DownloadPlan? {
        do {
            return try await client.planDownload(ref: ref, scope: scope)
        } catch {
            actionError = Self.message(for: error)
            return nil
        }
    }

    /// Confirming is the point of no return, so its failure is always surfaced — unlike a
    /// shelf, which can quietly show what it has.
    @discardableResult
    func confirm(planId: String) async -> Bool {
        do {
            let job = try await client.confirmDownload(planId: planId)
            jobs.insert(job, at: 0)
            return true
        } catch {
            actionError = Self.message(for: error)
            return false
        }
    }

    func refreshDownloads() async {
        do {
            let list = try await client.fetchDownloads()
            jobs = list.jobs
            canManageDownloads = list.canManage
            downloadsAreSimulated = list.engine == "stub"
            downloadsState = .loaded
            consecutivePollFailures = 0
        } catch {
            guard !Task.isCancelled else { return }
            consecutivePollFailures += 1
            downloadsState = .failed(Self.message(for: error))
        }
    }

    /// Polls only while the centre is on screen. A download that takes an hour must not
    /// mean an hour of requests from a TV nobody is looking at — and a server that has
    /// stopped answering gets asked every fifteen seconds, not every two.
    func startPolling(every seconds: Int) {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                await refreshDownloads()
                let interval = consecutivePollFailures >= 3 ? 15 : max(1, seconds)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pause(jobId: String) async { await mutate(jobId) { try await client.pauseDownload(jobId: $0) } }
    func resume(jobId: String) async { await mutate(jobId) { try await client.resumeDownload(jobId: $0) } }

    private func mutate(_ jobId: String,
                        _ action: (String) async throws -> YsojAPI.DownloadJob) async {
        do {
            let updated = try await action(jobId)
            if let index = jobs.firstIndex(where: { $0.id == jobId }) { jobs[index] = updated }
        } catch {
            actionError = Self.message(for: error)
        }
    }

    /// Cancels a running job or forgets a finished one — the server decides which from
    /// the state it is in, so the row needs only one gesture.
    func remove(jobId: String) async {
        do {
            try await client.removeDownload(jobId: jobId)
            await refreshDownloads()
        } catch {
            actionError = Self.message(for: error)
        }
    }

    var activeJobCount: Int { jobs.filter(\.isActive).count }

    // MARK: - Release search

    /// Debounced. A cleared field ends the mode at once: the jobs come back and any
    /// search still in flight is dropped rather than landing over them.
    func releaseQueryChanged() {
        releaseTask?.cancel()
        let query = trimmedReleaseQuery
        guard !query.isEmpty else {
            releaseSearch = nil
            releaseState = .idle
            return
        }
        releaseState = .searching
        releaseTask = Task {
            try? await Task.sleep(for: Self.releaseDebounce)
            guard !Task.isCancelled else { return }
            await runReleaseSearch(query)
        }
    }

    /// Return pressed: search now, without waiting out the debounce.
    func searchReleasesNow() {
        releaseTask?.cancel()
        let query = trimmedReleaseQuery
        guard !query.isEmpty else { return }
        releaseState = .searching
        releaseTask = Task { await runReleaseSearch(query) }
    }

    func selectReleaseCategory(_ category: YsojAPI.ReleaseCategory) {
        guard releaseCategory != category else { return }
        releaseCategory = category
        if isReleaseMode { searchReleasesNow() }
    }

    func clearReleaseSearch() {
        releaseTask?.cancel()
        releaseQuery = ""
        releaseSearch = nil
        releaseState = .idle
    }

    private var trimmedReleaseQuery: String {
        releaseQuery.trimmingCharacters(in: .whitespaces)
    }

    private func runReleaseSearch(_ query: String) async {
        let category = releaseCategory
        do {
            let found = try await client.searchReleases(query: query, category: category)
            // The question may have changed while the trackers were thinking; an answer
            // to the old one must not land on the new one.
            guard !Task.isCancelled, trimmedReleaseQuery == query,
                  releaseCategory == category else { return }
            releaseSearch = found
            releaseState = .loaded
        } catch {
            guard !Task.isCancelled, trimmedReleaseQuery == query else { return }
            releaseSearch = nil
            // 503 carries the server's own sentence — "the download service isn't
            // running" — and that is what the screen shows.
            releaseState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Errors

    /// The server writes its refusals for a person to read — "Season 9 isn't listed
    /// (available: 1, 2, 3)" — so its own text is preferred over anything invented here.
    private static func message(for error: Error) -> String {
        switch error {
        case JellyfinRequestError.server(_, let body):
            if let detail = detailString(from: body), !detail.isEmpty { return detail }
            return "The server couldn't do that."
        case JellyfinRequestError.unauthorized:
            return "You're not signed in as someone who can do that."
        default:
            return "Couldn't reach the server."
        }
    }

    private static func detailString(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["detail"] as? String
    }
}

/// Holds the one `DiscoverStore` for a session.
///
/// `@StateObject` must be initialised when the view is, and this store cannot exist until
/// a server has been connected and announced itself as a YSOJ-server — so the box is the
/// `@StateObject` and the store arrives later.
@MainActor
final class DiscoverStoreBox: ObservableObject {
    var store: DiscoverStore?
}

// MARK: - Screenshot fixture

extension DiscoverStore {
    /// A store preloaded with fixture rows, for `RT_SHOW_DISCOVER=demo` /
    /// `JT_SHOW_DISCOVER=demo`.
    ///
    /// Discover needs a *YSOJ-server* to show anything, which means it cannot be
    /// screenshotted or iterated on from a simulator that is signed out, or signed in to
    /// a plain Jellyfin — which is what every dev simulator here actually is. Same
    /// convention as `JT_SCAN_DEMO` and `PlayerPreviewFixture`: a permanent hook, inert
    /// unless its environment variable is set, so there is nothing to revert.
    ///
    /// **This is a fixture, not a fallback.** Nothing reaches for it when a real fetch
    /// fails — that path shows a loading state and then the truth, per the project's
    /// never-show-fake-data rule. It exists only behind an explicit env var.
    ///
    /// Built by **decoding the server's own JSON** rather than by calling memberwise
    /// initialisers. Two reasons: `YsojAPI`'s types are `Decodable`-only by design, so
    /// they carry no public inits to call; and this way the fixture exercises the real
    /// decoder, which means a payload shape that drifts breaks the screenshot hook
    /// instead of quietly diverging from what the server sends.
    ///
    /// `releases: true` (`RT_SHOW_DOWNLOADS=search` / `JT_SHOW_DOWNLOADS=search`) opens
    /// the centre on a finished release search — every row state worth looking at, one
    /// tracker down, and the title already in the library.
    @MainActor
    static func demo(releases: Bool = false) -> DiscoverStore {
        let store = DiscoverStore(
            client: YsojClient(baseURL: URL(string: "http://demo.invalid")!,
                               apiKey: "demo", deviceId: "demo")
        )
        store.categories = decode([YsojAPI.DiscoverCategory].self, Fixture.categories)
        // The real health of this server as measured today: films and television up,
        // both anime sources down. That is deliberately what the fixture shows — the
        // unavailable state is the one most worth being able to look at.
        store.sources = decode([YsojAPI.Capabilities.Source].self, Fixture.sources)
        store.items = decode([YsojAPI.DiscoverItem].self, Fixture.items)
        store.jobs = decode([YsojAPI.DownloadJob].self, Fixture.jobs)
        store.selectedCategoryId = "tmdb:trending_movies"
        store.shelfState = .loaded
        store.hasLoadedCategories = true
        store.canManageDownloads = true
        store.downloadsAreSimulated = true
        store.offersReleaseSearch = true
        if releases {
            store.releaseQuery = "the matrix"
            store.releaseCategory = .movies
            store.releaseSearch = decode(YsojAPI.ReleaseSearch.self, Fixture.releases)
            store.releaseState = .loaded
        }
        return store
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        // A fixture that fails to decode is a programming error in this file, and one
        // that would otherwise present as a mysteriously empty screen.
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private enum Fixture {
        /// The server's own payload shape: apibay answered, nyaa timed out, one row's
        /// file count is a guess from its name, and the film is already owned.
        static let releases = """
        {"query":"the matrix","normalized":"the matrix","category":"movies",
         "results":[
          {"name":"The Matrix 1999 2160p UHD BluRay x265 HDR TrueHD Atmos 7.1","infoHash":"A1B2C3D4E5F60718293A4B5C6D7E8F9012345678",
           "magnet":"magnet:?xt=urn:btih:A1B2C3D4E5F60718293A4B5C6D7E8F9012345678","sizeBytes":24696061952,
           "seeders":412,"leechers":37,"fileCount":2,"fileCountExact":true,"quality":"2160p",
           "qualityTier":3,"category":"HD Movies","provider":"TPB","sourceId":"1","score":[5,3,412]},
          {"name":"The Matrix 1999 1080p WEB-DL DDP5.1 H.264","infoHash":"B2C3D4E5F60718293A4B5C6D7E8F901234567890",
           "magnet":"magnet:?xt=urn:btih:B2C3D4E5F60718293A4B5C6D7E8F901234567890","sizeBytes":8482560000,
           "seeders":96,"leechers":8,"fileCount":3,"fileCountExact":true,"quality":"1080p",
           "qualityTier":2,"category":"HD Movies","provider":"TPB","sourceId":"2","score":[4,3,96]},
          {"name":"The Matrix (1999) 1080p BluRay x264","infoHash":"C3D4E5F60718293A4B5C6D7E8F90123456789012",
           "magnet":"magnet:?xt=urn:btih:C3D4E5F60718293A4B5C6D7E8F90123456789012","sizeBytes":2254857830,
           "seeders":38,"leechers":4,"fileCount":1,"fileCountExact":true,"quality":"1080p",
           "qualityTier":2,"category":"HD Movies","provider":"TPB","sourceId":"3","score":[4,2,38]},
          {"name":"[Nyaa] The Matrix Trilogy 01-03 [720p][Dual Audio]","infoHash":"D4E5F60718293A4B5C6D7E8F9012345678901234",
           "magnet":"magnet:?xt=urn:btih:D4E5F60718293A4B5C6D7E8F9012345678901234","sizeBytes":6120328397,
           "seeders":7,"leechers":21,"fileCount":3,"fileCountExact":false,"quality":"720p",
           "qualityTier":1,"category":"Anime/Eng","provider":"nyaa","sourceId":"4","score":[3,1,7]},
          {"name":"The Matrix 1999 REMUX 1080p AVC DTS-HD MA 5.1","infoHash":"E5F60718293A4B5C6D7E8F901234567890123456",
           "magnet":"magnet:?xt=urn:btih:E5F60718293A4B5C6D7E8F901234567890123456","sizeBytes":33822867456,
           "seeders":2,"leechers":0,"fileCount":0,"fileCountExact":false,"quality":"1080p",
           "qualityTier":2,"category":"Movies","provider":"torrents-csv","sourceId":"5","score":[4,1,2]}],
         "sources":[{"id":"apibay","ok":true,"rows":100,"tookMs":312},
                    {"id":"nyaa","ok":false,"rows":0,"tookMs":10004,"detail":"ReadTimeout"}],
         "cached":false,"tookMs":10360,"inLibrary":{"present":true,"jellyfinItemId":"jf-matrix"}}
        """

        static let categories = """
        [{"id":"tmdb:trending_movies","title":"Trending Films","kind":"movie","sourceId":"tmdb"},
         {"id":"tmdb:popular_tv","title":"Popular TV","kind":"series","sourceId":"tmdb"},
         {"id":"tmdb:top_movies","title":"Top Rated Films","kind":"movie","sourceId":"tmdb"},
         {"id":"jikan:top","title":"Top Rated Anime","kind":"anime","sourceId":"jikan"},
         {"id":"anilist:trending","title":"Trending Anime","kind":"anime","sourceId":"anilist"},
         {"id":"tvmaze:airing","title":"Airing This Week","kind":"series","sourceId":"tvmaze"}]
        """

        static let sources = """
        [{"id":"tmdb","name":"TMDB","reachable":true,"lastError":null},
         {"id":"anilist","name":"AniList","reachable":false,
          "lastError":"HTTP 403: Client error '403 Forbidden' for url 'https://graphql.anilist.co'"},
         {"id":"jikan","name":"MyAnimeList","reachable":false,
          "lastError":"HTTP 504: Server error '504 Gateway Time-out' for url 'https://api.jikan.moe/v4/top/anime'"},
         {"id":"tvmaze","name":"TVmaze","reachable":true,"lastError":null}]
        """

        static let items: String = {
            let rows: [(String, Int, Double, Bool)] = [
                ("The Deep Signal", 2026, 8.4, false), ("Copper Season", 2025, 7.9, true),
                ("Night Cartographers", 2024, 8.1, false), ("Undertow", 2026, 7.2, false),
                ("Glasshouse", 2023, 8.8, false), ("The Long Static", 2025, 6.9, false),
                ("Salt Line", 2024, 7.5, true), ("Meridian Zero", 2026, 8.0, false),
                ("Field Notes", 2025, 7.7, false), ("Harrow & Vale", 2024, 8.3, false),
                ("The Quiet Coast", 2023, 7.1, false), ("Ledger", 2026, 8.6, false),
            ]
            let body = rows.enumerated().map { index, row in
                """
                {"ref":"tmdb:movie:\(9000 + index)","title":"\(row.0)","type":"movie",
                 "year":\(row.1),"rating":\(row.2),"genres":["Drama"],"overview":"",
                 "posterURL":null,"backdropURL":null,"sourceId":"tmdb","sourceName":"TMDB",
                 "inLibrary":{"present":\(row.3),
                 "jellyfinItemId":\(row.3 ? "\"jf-\(index)\"" : "null"),"known":true}}
                """
            }.joined(separator: ",")
            return "[\(body)]"
        }()

        /// One job in each state worth looking at: running with real numbers, still
        /// searching (no bar — there is no denominator yet), finished, and failed.
        static let jobs = """
        [{"id":"job_a","ref":"tmdb:series:1396","title":"Copper Season",
          "subtitle":"Season 2 · 13 episodes","posterURL":null,
          "scope":{"kind":"season","seasonNumber":2,"episodeNumbers":null},
          "state":"downloading","progress":0.42,"bytesTotal":18200000000,
          "bytesDownloaded":7644000000,"speedBytesPerSecond":243000000,"etaSeconds":43,
          "seeds":24,"peers":9,"message":"Downloading…","engine":"stub","landedItemIds":[],
          "createdAt":1788700000,"updatedAt":1788700300,"finishedAt":null,"isActive":true},
         {"id":"job_b","ref":"tmdb:series:1400","title":"The Deep Signal",
          "subtitle":"Whole series · 3 seasons · 28 episodes","posterURL":null,
          "scope":{"kind":"series","seasonNumber":null,"episodeNumbers":null},
          "state":"searching","progress":0,"bytesTotal":39000000000,"bytesDownloaded":0,
          "speedBytesPerSecond":0,"etaSeconds":null,"seeds":null,"peers":null,
          "message":"Looking for a source…","engine":"stub","landedItemIds":[],
          "createdAt":1788700100,"updatedAt":1788700320,"finishedAt":null,"isActive":true},
         {"id":"job_c","ref":"tmdb:movie:9003","title":"Undertow","subtitle":"Film",
          "posterURL":null,"scope":{"kind":"movie","seasonNumber":null,"episodeNumbers":null},
          "state":"landed","progress":1.0,"bytesTotal":2400000000,"bytesDownloaded":2400000000,
          "speedBytesPerSecond":0,"etaSeconds":null,"seeds":null,"peers":null,
          "message":"Simulated download finished — no file was fetched, because no download engine is installed yet.",
          "engine":"stub","landedItemIds":[],"createdAt":1788699000,"updatedAt":1788699400,
          "finishedAt":1788699400,"isActive":false},
         {"id":"job_d","ref":"tmdb:series:1402","title":"Glasshouse",
          "subtitle":"Season 1 · 8 episodes","posterURL":null,
          "scope":{"kind":"season","seasonNumber":1,"episodeNumbers":null},
          "state":"failed","progress":0.18,"bytesTotal":11000000000,"bytesDownloaded":1980000000,
          "speedBytesPerSecond":0,"etaSeconds":null,"seeds":0,"peers":0,
          "message":"No source had every episode of this season.","engine":"stub",
          "landedItemIds":[],"createdAt":1788698000,"updatedAt":1788698500,
          "finishedAt":1788698500,"isActive":false}]
        """
    }
}
