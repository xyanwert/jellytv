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

    init(client: YsojClient) {
        self.client = client
    }

    deinit {
        searchTask?.cancel()
        shelfTask?.cancel()
        pollTask?.cancel()
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

    /// Fetch a title's detail again, ignoring the cache.
    ///
    /// Exists for one moment: a download of this title has just landed, so the
    /// server's answer to "is it in your library?" has changed and the cached
    /// one says no. Without this the page that just finished downloading a film
    /// goes on offering to download it, which reads as the download having done
    /// nothing.
    @discardableResult
    func reloadDetail(ref: String) async -> YsojAPI.DiscoverDetail? {
        guard let fetched = try? await client.fetchDetail(ref: ref) else { return nil }
        details[ref] = fetched
        return fetched
    }

    // MARK: - Downloads

    func plan(ref: String, scope: YsojAPI.DownloadScope,
              target: YsojAPI.DownloadTarget? = nil) async -> YsojAPI.DownloadPlan? {
        do {
            return try await client.planDownload(ref: ref, scope: scope, target: target)
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

    var isPolling: Bool { pollTask != nil }

    // MARK: - Jobs by title

    /// Finished jobs read on a title's page and put away. The download centre still
    /// lists them — putting away is about the page, not the job.
    @Published var dismissedJobIds: Set<String> = []

    /// How long a finished job stays on its title's page unprompted. A landing from
    /// last week is the centre's business, not a banner on the film.
    private static let finishedJobShelfLife: TimeInterval = 24 * 3600

    /// The job this title's page shows in place of its Download bar: the running one
    /// if there is one, else the most recent finished one not yet put away.
    func jobToShow(for ref: String) -> YsojAPI.DownloadJob? {
        let mine = jobs.filter { $0.ref == ref }
        if let active = mine.first(where: \.isActive) { return active }
        let cutoff = Date().timeIntervalSince1970 - Self.finishedJobShelfLife
        return mine.first { job in
            !dismissedJobIds.contains(job.id) && (job.finishedAt ?? job.updatedAt) > cutoff
        }
    }

    func hasActiveJob(for ref: String) -> Bool {
        jobs.contains { $0.ref == ref && $0.isActive }
    }

    func dismiss(_ job: YsojAPI.DownloadJob) {
        dismissedJobIds.insert(job.id)
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
    /// The fixture title whose season is mid-download (`Fixture.jobs`' `job_a`).
    static let demoDetailRef = "tmdb:series:1396"

    /// Two more states the download flow ends in, neither reachable from a stub server:
    ///
    /// - `landed` (`…_SHOW_DISCOVER=landed`) — the season finished, carrying the item
    ///   ids a real engine reports, so the panel offers **Play**. It marks the title
    ///   owned as well, because that is what landing *means*; a job that landed while
    ///   the library still says "not yours" is a state that cannot happen.
    /// - `owned` (`…_SHOW_DISCOVER=owned`) — a film already in the library and no job
    ///   at all, where Play replaces Download as the bar.
    @MainActor
    static func demo(landed: Bool = false, owned: Bool = false,
                     idle: Bool = false, failed: Bool = false) -> DiscoverStore {
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
        // A server that can only fetch films has no job for a *show* — the fixture must
        // not contradict the capabilities it is shown with.
        let jobsJSON: String
        if owned || idle {
            jobsJSON = "[]"
        } else if failed {
            jobsJSON = Fixture.failedJob
        } else {
            jobsJSON = landed ? Fixture.landedJobs : Fixture.jobs
        }
        store.jobs = decode([YsojAPI.DownloadJob].self, jobsJSON)
        // The title `job_a` is fetching, so `=detail` can open on a page mid-download.
        store.details[demoDetailRef] = decode(
            YsojAPI.DiscoverDetail.self,
            owned ? Fixture.ownedFilm : (landed ? Fixture.landedDetail : Fixture.detail))
        store.selectedCategoryId = "tmdb:trending_movies"
        store.shelfState = .loaded
        store.hasLoadedCategories = true
        store.canManageDownloads = true
        // A landed job carries a real engine name, so the stub banner must not be over
        // it — the fixture would otherwise show a contradiction the server cannot send.
        store.downloadsAreSimulated = !landed
        return store
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        // A fixture that fails to decode is a programming error in this file, and one
        // that would otherwise present as a mysteriously empty screen.
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private enum Fixture {
        /// The download that could not be made. The message is the shape a real engine
        /// sends — what it looked for and why it gave up — because that sentence is the
        /// whole reason the panel shows one.
        static var failedJob: String {
            // Minutes ago, like the landed one: a title's page only shows a finished job
            // from the last day, so a fixture stamped with a fixed date stops appearing
            // the day after it is written — which is exactly what it did.
            let finished = Date().timeIntervalSince1970 - 240
            return """
            [{"id":"job_x","ref":"tmdb:series:1396","title":"Copper Season",
              "subtitle":"Season 2 · 13 episodes","posterURL":null,
              "scope":{"kind":"season","seasonNumber":2,"episodeNumbers":null},
              "state":"failed","progress":0.0,"bytesTotal":18200000000,"bytesDownloaded":0,
              "speedBytesPerSecond":0,"etaSeconds":null,"seeds":0,"peers":0,
              "message":"No source had every episode of season 2 — the best had 9 of 13.",
              "engine":"media-downloader","landedItemIds":[],
              "createdAt":\(finished - 600),"updatedAt":\(finished),"finishedAt":\(finished),
              "isActive":false}]
            """
        }

        /// The same season, finished and in the library — `engine` is not "stub" and
        /// `landedItemIds` names what it became, which is exactly what a real engine
        /// must send for the Play button to appear. Written out rather than patched
        /// from `jobs` with a string replace: a replacement that stops matching fails
        /// silently, and a fixture that quietly shows the wrong state is worse than no
        /// fixture at all.
        ///
        /// **Its clock is relative to now, unlike every other fixture here.** A finished
        /// job only stands on a title's page for a day (`jobToShow(for:)`), so a literal
        /// timestamp makes this fixture work on the afternoon it is written and silently
        /// show the Download bar every day after.
        static var landedJobs: String {
            let finished = Date().timeIntervalSince1970 - 120
            return """
            [{"id":"job_a","ref":"tmdb:series:1396","title":"Copper Season",
              "subtitle":"Season 2 · 13 episodes","posterURL":null,
              "scope":{"kind":"season","seasonNumber":2,"episodeNumbers":null},
              "state":"landed","progress":1.0,"bytesTotal":18200000000,
              "bytesDownloaded":18200000000,"speedBytesPerSecond":0,"etaSeconds":null,
              "seeds":null,"peers":null,"message":"13 episodes added to your library.",
              "engine":"qbittorrent","landedItemIds":["jf-ep-1","jf-ep-2","jf-ep-3"],
              "createdAt":\(finished - 900),"updatedAt":\(finished),"finishedAt":\(finished),
              "isActive":false}]
            """
        }


        /// The series `job_a` is downloading season 2 of — three seasons, so the season
        /// and episode pickers have something to show.
        static let detail = """
        {"ref":"tmdb:series:1396","title":"Copper Season","type":"series","year":2025,
         "overview":"A river town's last smelter changes hands the week the water turns green, and the three families who own the bank, the mine and the newspaper each decide the others did it.",
         "genres":["Drama","Mystery"],"runtimeMinutes":52,"rating":8.4,"certification":"TV-MA",
         "posterURL":null,"backdropURL":null,
         "cast":[{"name":"Ines Marlow","role":"Ada Kell","imageURL":null},
                 {"name":"Tobias Wren","role":"Sheriff Dunmore","imageURL":null},
                 {"name":"Priya Anand","role":"Lena Voss","imageURL":null}],
         "seasons":[{"seasonNumber":1,"name":"Season 1","episodeCount":10,"year":2024,"overview":"","posterURL":null},
                    {"seasonNumber":2,"name":"Season 2","episodeCount":13,"year":2025,"overview":"","posterURL":null},
                    {"seasonNumber":3,"name":"Season 3","episodeCount":8,"year":2026,"overview":"","posterURL":null}],
         "episodeCount":31,"status":"Returning Series","sourceId":"tmdb","sourceName":"TMDB",
         "sourceURL":"https://www.themoviedb.org/tv/1396","externalIds":{"imdb":"tt0000000"},
         "inLibrary":{"present":false,"jellyfinItemId":null,"known":true},"trailers":[]}
        """

        /// The same series once its season has landed: in the library, as it must be.
        static let landedDetail = detail.replacingOccurrences(
            of: #""inLibrary":{"present":false,"jellyfinItemId":null,"known":true}"#,
            with: #""inLibrary":{"present":true,"jellyfinItemId":"jf-copper","known":true}"#)

        /// A film already in the library — where Play *is* the bar, since asking for a
        /// film you own again would only duplicate it.
        static let ownedFilm = """
        {"ref":"tmdb:series:1396","title":"The Long Static","type":"movie","year":2025,
         "overview":"A night-shift radio operator starts answering a frequency that should be empty, and the voice on it knows the town better than she does.",
         "genres":["Thriller","Mystery"],"runtimeMinutes":104,"rating":7.6,"certification":"R",
         "posterURL":null,"backdropURL":null,
         "cast":[{"name":"Ines Marlow","role":"Wren Halliday","imageURL":null},
                 {"name":"Tobias Wren","role":"Cal","imageURL":null}],
         "seasons":[],"episodeCount":null,"status":"Released","sourceId":"tmdb","sourceName":"TMDB",
         "sourceURL":"https://www.themoviedb.org/movie/1396","externalIds":{"imdb":"tt0000001"},
         "inLibrary":{"present":true,"jellyfinItemId":"jf-long-static","known":true},"trailers":[]}
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
