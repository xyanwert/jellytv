import SwiftUI
import UIKit
import JellyTVKit

@MainActor
final class AppState: ObservableObject {
    @Published var libraries: [JellyfinAPI.JellyfinUserView] = []
    @Published var continueWatching: [ContinueWatchingItem] = []
    @Published var recommended: [MediaItem] = []
    @Published var heroes: [HeroFeature] = []
    /// Flips true once `refresh()` has completed (success or failure) at
    /// least once. Home gates its SampleCatalog fallback content on this —
    /// without it, the fully-rendered-but-non-interactive sample hero/rows
    /// are visible (and look tappable) for as long as the real fetch takes.
    @Published private(set) var hasLoadedHome = false
    @Published var hideNSFW: Bool {
        didSet { UserDefaults.standard.set(hideNSFW, forKey: "jelly:home.hideNSFW") }
    }
    /// The Search screen's TYPE/Unwatched/NSFW filter chips, remembered
    /// across visits and relaunches — same UserDefaults pattern as
    /// `hideNSFW` above. Search rebuilds its view fresh every time it's
    /// selected (it's not kept alive off-screen like a tab), so without this
    /// every visit silently dropped back to "All" with both toggles off.
    @Published var searchTypeFilter: SearchFilter {
        didSet { UserDefaults.standard.set(searchTypeFilter.rawValue, forKey: "jelly:search.typeFilter") }
    }
    @Published var searchUnwatchedOnly: Bool {
        didSet { UserDefaults.standard.set(searchUnwatchedOnly, forKey: "jelly:search.unwatchedOnly") }
    }
    @Published var searchIncludeNSFW: Bool {
        didSet { UserDefaults.standard.set(searchIncludeNSFW, forKey: "jelly:search.includeNSFW") }
    }
    /// Opt-in OMDb enrichment (awards/Oscars, true Rotten Tomatoes %, Metacritic).
    @Published var omdbEnabled: Bool {
        didSet { UserDefaults.standard.set(omdbEnabled, forKey: "jelly:omdb.enabled") }
    }
    @Published var omdbApiKey: String {
        didSet { UserDefaults.standard.set(omdbApiKey, forKey: "jelly:omdb.apiKey") }
    }
    /// Opt-in TMDB enrichment (real TV network logos — Jellyfin has no such field).
    @Published var tmdbEnabled: Bool {
        didSet { UserDefaults.standard.set(tmdbEnabled, forKey: "jelly:tmdb.enabled") }
    }
    @Published var tmdbApiKey: String {
        didSet { UserDefaults.standard.set(tmdbApiKey, forKey: "jelly:tmdb.apiKey") }
    }
    /// User-set NSFW/anime overrides, keyed by library id — set from Settings
    /// → Libraries. Jellyfin has no such concept natively, so this always
    /// wins over `LibraryClassifier`'s name-heuristic guess once present.
    @Published private(set) var libraryOverrides: [String: LibraryClassificationOverride] {
        didSet { persist(libraryOverrides, forKey: "jelly:library.overrides") }
    }
    /// Local, per-library tags (Settings → Libraries) — Jellyfin's own tags
    /// are item-level and global; these are library-scoped labels the user
    /// manages independently, matching the reference app's tag model.
    @Published private(set) var libraryTags: [String: [String]] {
        didSet { persist(libraryTags, forKey: "jelly:library.tags") }
    }
    /// How long Night mode plays before it stops itself (Settings →
    /// Playback). Read once when Night mode is engaged — the deadline is
    /// wall-clock from that moment, so changing this mid-sleep changes the
    /// *next* night, not the one already running.
    @Published var sleepTimer: SleepTimer {
        didSet { UserDefaults.standard.set(sleepTimer.rawValue, forKey: "jelly:player.sleepTimer") }
    }
    /// Set to present the player via `RootView`'s `.fullScreenCover(item:)`.
    /// `PlaybackRequest.id` is content-derived, so re-setting the same
    /// request (e.g. an unrelated `AppState` publish) doesn't retrigger it.
    @Published var activePlaybackRequest: PlaybackRequest?
    /// A one-shot navigation signal from a Libraries-submenu row tap:
    /// `RootView` observes this, routes to that category's dedicated screen
    /// (when one exists) and closes the submenu, then resets it back to nil —
    /// the same fire-once pattern as `activePlaybackRequest`.
    @Published var pendingLibraryNavigation: MetaCategory?
    /// Fetched once per category per launch — same in-memory convention as
    /// `omdbCache`/`tmdbCache`. A relaunch re-rolls the pool, so a given home
    /// video's stand-in picture is stable for a session rather than forever.
    private var wallhavenCache: [MetaCategory: UIImage] = [:]

    /// Whether the signed-in account may edit item metadata — Jellyfin gates
    /// `POST /Items/{id}` on `RequiresElevation`, so a non-admin gets a 403
    /// however the request is shaped. Asked once, on connect.
    ///
    /// **Three states, not two.** `nil` is "haven't asked yet", and it must
    /// not read as "no": v1 hid its whole tag control behind exactly this
    /// kind of unresolved async answer and left users on a slow server with
    /// no way to create a first tag (its `de310da` → `c4a472c`). Callers
    /// should offer the edit unless this is *definitely* false.
    @Published private(set) var canEditItemMetadata: Bool?
    /// Every tag in use on the server, for the player's tag picker. Fetched
    /// lazily, extended after a write so a tag invented once is offered the
    /// next time.
    ///
    /// This is a *search index*, not a menu: a real library runs to four
    /// figures (1,266 on the server this was built against), so no UI should
    /// try to list it.
    @Published private(set) var tagVocabulary: [String] = []
    /// The handful the user actually reaches for, most recent first — what a
    /// picker can show without asking anyone to read a thousand words.
    @Published private(set) var recentTags: [String] {
        didSet { persist(recentTags, forKey: "jelly:tags.recent") }
    }
    /// Tags written during this session, keyed by item id. The library
    /// screens hold their own fetched copies of a `MediaItem`, and the player
    /// sits over them as a cover — so nothing re-runs their loaders when a
    /// tag is applied mid-video. Rendering through this is what stops the
    /// card you just tagged still showing no chip when you back out to it.
    @Published private(set) var tagOverrides: [String: [String]] = [:]
    private var tagVocabularyTask: Task<Void, Never>?
    private static let maxRecentTags = 12

    /// Past Search terms, most recent first, persisted — the Search screen's
    /// idle state shows these instead of a blank field.
    @Published private(set) var recentSearches: [String] {
        didSet { persist(recentSearches, forKey: "jelly:search.recent") }
    }
    private static let maxRecentSearches = 6

    private var client: JellyfinClient?
    private var userId: String = ""
    private var imageBaseURL: URL?
    private var refreshTask: Task<Void, Never>?
    private var allItems: [JellyfinAPI.JellyfinItem] = []
    // On-demand enrichment caches, keyed by id / IMDb id — a selected/opened
    // item is only ever fetched once even as focus moves back and forth.
    private var itemDetailCache: [String: JellyfinAPI.JellyfinItem] = [:]
    private var omdbCache: [String: (ExternalRatings?, MovieAwards?)] = [:]
    private var tmdbCache: [String: Network?] = [:]
    // Seasons keyed by series id (episodes start empty); episodes keyed by
    // season id, fetched lazily per selection — never the whole show at once.
    private var seasonsCache: [String: [Season]] = [:]
    private var episodesCache: [String: [Episode]] = [:]
    // Jellyfin items don't carry a library/parent reference of their own —
    // `fetchItems(parentId:)` is the only place that knows which library an
    // item came from, so that's recorded here as items are fetched, keyed
    // by item id. `libraryCategory(for:)` reads it back to classify NSFW/
    // anime status. Rebuilt from scratch on every `refresh()`.
    private var itemLibraryId: [String: String] = [:]

    private let refreshInterval: TimeInterval = 300

    init() {
        hideNSFW = UserDefaults.standard.object(forKey: "jelly:home.hideNSFW") as? Bool ?? true
        let typeFilterRaw = UserDefaults.standard.string(forKey: "jelly:search.typeFilter")
        searchTypeFilter = typeFilterRaw.flatMap(SearchFilter.init(rawValue:)) ?? .all
        searchUnwatchedOnly = UserDefaults.standard.bool(forKey: "jelly:search.unwatchedOnly")
        searchIncludeNSFW = UserDefaults.standard.bool(forKey: "jelly:search.includeNSFW")
        omdbEnabled = UserDefaults.standard.object(forKey: "jelly:omdb.enabled") as? Bool ?? false
        omdbApiKey = UserDefaults.standard.string(forKey: "jelly:omdb.apiKey") ?? ""
        tmdbEnabled = UserDefaults.standard.object(forKey: "jelly:tmdb.enabled") as? Bool ?? false
        tmdbApiKey = UserDefaults.standard.string(forKey: "jelly:tmdb.apiKey") ?? ""
        let sleep = UserDefaults.standard.object(forKey: "jelly:player.sleepTimer") as? Double
        sleepTimer = sleep.flatMap(SleepTimer.init(rawValue:)) ?? .default
        libraryOverrides = Self.loadPersisted(forKey: "jelly:library.overrides") ?? [:]
        libraryTags = Self.loadPersisted(forKey: "jelly:library.tags") ?? [:]
        recentTags = Self.loadPersisted(forKey: "jelly:tags.recent") ?? []
        recentSearches = Self.loadPersisted(forKey: "jelly:search.recent") ?? []
    }

    private static func loadPersisted<T: Decodable>(forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func configure(baseURL: URL, apiKey: String, deviceId: String, userId: String) {
        let client = JellyfinClient(baseURL: baseURL, apiKey: apiKey, deviceId: deviceId)
        self.client = client
        self.userId = userId
        self.imageBaseURL = baseURL
        self.canEditItemMetadata = nil
        self.cardTrickplay = TrickplayClient(client: client, userId: userId)
        Task { await loadEditPermission() }
    }

    /// Trickplay sheets for the home-video cards' frame slideshow — one
    /// client per sign-in, shared by every card on the shelf so a sheet is
    /// fetched once however many cards page through it. The player keeps
    /// its own (`PlayerEngine.trickplayClient`) for the scenes panel.
    private(set) var cardTrickplay: TrickplayClient?

    // MARK: - Tags

    private func loadEditPermission() async {
        guard let client else { return }
        // A failure here means "we don't know", which has to read as "no" —
        // offering an edit that 403s is worse than not offering it.
        guard let user = try? await client.fetchCurrentUser() else { return }
        canEditItemMetadata = user.isAdministrator
    }

    /// The server's tag vocabulary, fetched once per launch and after each
    /// write. Never blocks a picker: callers render what they have and this
    /// fills in.
    func loadTagVocabulary() {
        guard tagVocabularyTask == nil, let client else { return }
        tagVocabularyTask = Task { [userId] in
            let tags = (try? await client.fetchTagVocabulary(userId: userId)) ?? []
            if !tags.isEmpty { tagVocabulary = tags }
            tagVocabularyTask = nil
        }
    }

    /// Write an item's tags through to Jellyfin, then keep every local copy
    /// of that item in step so the chip rows behind the player don't lie
    /// until the next refresh.
    ///
    /// Returns false on any failure — the caller is expected to have applied
    /// the change optimistically and to put it back.
    @discardableResult
    func setTags(_ tags: [String], forItem id: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.setItemTags(itemId: id, userId: userId, tags: tags)
        } catch {
            // A 403 here is the permission answer arriving the hard way —
            // record it so the UI stops offering the edit.
            if case JellyfinRequestError.server(let status, _) = error, status == 403 {
                canEditItemMetadata = false
            }
            return false
        }
        applyTagsLocally(tags, itemId: id)
        // A newly-invented tag has to join the vocabulary, or the picker
        // won't offer it on the next item.
        for tag in tags where !JellyfinTags.contains(tag, in: tagVocabulary) {
            tagVocabulary.append(tag)
        }
        tagVocabulary.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        noteRecentTags(tags)
        return true
    }

    /// Whatever was just applied goes to the front of the recents. Removing a
    /// tag doesn't demote it — you often take one off precisely because you
    /// meant a different one, and it stays the likeliest next choice.
    private func noteRecentTags(_ tags: [String]) {
        for tag in tags.reversed() {
            recentTags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
            recentTags.insert(tag, at: 0)
        }
        if recentTags.count > Self.maxRecentTags {
            recentTags = Array(recentTags.prefix(Self.maxRecentTags))
        }
    }

    /// Vocabulary entries matching `text`, for the picker's live search.
    /// Prefix matches first — typing "ca" means "casero" long before it means
    /// "musical".
    func tagSuggestions(matching text: String, limit: Int = 8) -> [String] {
        guard let needle = JellyfinTags.normalized(text)?.lowercased() else { return [] }
        var prefixed: [String] = []
        var contained: [String] = []
        for tag in tagVocabulary {
            let lower = tag.lowercased()
            if lower.hasPrefix(needle) { prefixed.append(tag) }
            else if lower.contains(needle) { contained.append(tag) }
            if prefixed.count >= limit { break }
        }
        return Array((prefixed + contained).prefix(limit))
    }

    private func applyTagsLocally(_ tags: [String], itemId: String) {
        itemDetailCache[itemId]?.tags = tags
        if let index = allItems.firstIndex(where: { $0.id == itemId }) {
            allItems[index].tags = tags
        }
        tagOverrides[itemId] = tags
    }

    /// `items` with any tag written this session applied. Cheap and a no-op
    /// until something is actually tagged.
    func applyingTagOverrides(_ items: [MediaItem]) -> [MediaItem] {
        guard !tagOverrides.isEmpty else { return items }
        return items.map { item in
            guard let tags = tagOverrides[item.id] else { return item }
            var updated = item
            updated.tags = tags
            return updated
        }
    }

    func startRefreshTimer() {
        stopRefreshTimer()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshInterval))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    func stopRefreshTimer() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard let client else {
            hasLoadedHome = true
            return
        }
        do {
            let views = try await client.fetchUserViews(userId: userId)
            let supported = views.filter { view in
                guard let ct = view.collectionType else { return false }
                return ct == "movies" || ct == "tvshows" || ct == "homevideos"
            }
            libraries = supported
            itemLibraryId.removeAll()

            let cwItems = try await fetchContinueWatching(client: client)
            continueWatching = applyNSFWFilter(cwItems)

            let pool = try await fetchItemPool(client: client)
            allItems = pool

            recommended = applyNSFWFilter(computeRecommended())
            heroes = applyNSFWFilter(computeHeroes())
        } catch {
            #if DEBUG
            print("[AppState] refresh failed: \(error)")
            #endif
        }
        // Set unconditionally — success or failure — so a failed fetch also
        // stops Home from showing SampleCatalog fallback content forever.
        hasLoadedHome = true
    }

    private func fetchContinueWatching(client: JellyfinClient) async throws -> [ContinueWatchingItem] {
        var results: [JellyfinAPI.JellyfinItem] = []
        for lib in libraries {
            guard let items = try? await client.fetchItems(
                userId: userId,
                parentId: lib.id,
                filters: "IsResumable",
                sortBy: "DatePlayed",
                sortOrder: "Descending",
                limit: 10
            ) else { continue }
            for item in items { itemLibraryId[item.id] = lib.id }
            results.append(contentsOf: items)
        }
        results.sort { a, b in
            let aDate = a.userData?.lastPlayedDate ?? ""
            let bDate = b.userData?.lastPlayedDate ?? ""
            return aDate > bDate
        }
        let top = Array(results.prefix(6))
        return top.compactMap { item in
            let category = libraryCategory(for: item)
            return item.toContinueWatchingItem(libraryCategory: category, imageBaseURL: imageBaseURL)
        }
    }

    private func fetchItemPool(client: JellyfinClient) async throws -> [JellyfinAPI.JellyfinItem] {
        var results: [JellyfinAPI.JellyfinItem] = []
        for lib in libraries {
            guard let items = try? await client.fetchItems(
                userId: userId,
                parentId: lib.id,
                includeItemTypes: "Movie,Series",
                sortBy: "Random",
                limit: 30
            ) else { continue }
            for item in items { itemLibraryId[item.id] = lib.id }
            results.append(contentsOf: items)
        }
        return results
    }

    /// True when an item has enough real metadata to show in a presentable
    /// slot (Recommended, Hero) — unidentified files Jellyfin couldn't match
    /// to a metadata provider (raw camera/export filenames, etc.) have no
    /// Overview and no real artwork, so they'd show as a blank card there.
    private func isPresentable(_ item: JellyfinAPI.JellyfinItem) -> Bool {
        let hasOverview = !(item.overview ?? "").isEmpty
        let hasArtwork = item.imageTags?["Primary"] != nil
            || !(item.backdropImageTags ?? []).isEmpty
            || !(item.parentBackdropImageTags ?? []).isEmpty
        return hasOverview && hasArtwork
    }

    /// `allItems` reordered so identified items (real Overview + artwork)
    /// sort first; unidentified ones still pad the pool if there aren't
    /// enough presentable items to fill a row.
    private var presentablePool: [JellyfinAPI.JellyfinItem] {
        let presentable = allItems.filter(isPresentable)
        let rest = allItems.filter { !isPresentable($0) }
        return presentable + rest
    }

    private func computeRecommended() -> [MediaItem] {
        let pool = presentablePool
        var picks: [JellyfinAPI.JellyfinItem] = []

        let recentlyWatched = allItems.filter { item in
            guard let data = item.userData, let date = data.lastPlayedDate, !date.isEmpty else { return false }
            return true
        }.sorted { a, b in
            (a.userData?.lastPlayedDate ?? "") > (b.userData?.lastPlayedDate ?? "")
        }

        if let last = recentlyWatched.first, let affinity = libraryCategory(for: last) {
            let affinityType = affinity.collectionType
            let same = pool.filter { item in
                guard let cat = libraryCategory(for: item) else { return false }
                return cat.collectionType == affinityType && item.id != last.id
            }
            picks.append(contentsOf: same.prefix(3))
        }

        let remaining = pool.filter { item in
            if recentlyWatched.contains(where: { $0.id == item.id }) { return false }
            if picks.contains(where: { $0.id == item.id }) { return false }
            return true
        }
        picks.append(contentsOf: remaining.prefix(6 - picks.count))

        return Array(picks.prefix(6)).compactMap { item in
            item.toMediaItem(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
        }
    }

    private func computeHeroes() -> [HeroFeature] {
        var heroItems: [HeroFeature] = []

        let cwHeroes = continueWatching.prefix(3).compactMap { cw -> HeroFeature? in
            guard let item = allItems.first(where: { $0.id == cw.id }) else { return nil }
            return item.toHeroFeature(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
        }
        heroItems.append(contentsOf: cwHeroes)

        let recHeroes = recommended.prefix(3).compactMap { rec -> HeroFeature? in
            guard let item = allItems.first(where: { $0.id == rec.id }) else { return nil }
            return item.toHeroFeature(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
        }
        heroItems.append(contentsOf: recHeroes)

        if heroItems.isEmpty {
            let randoms = presentablePool.prefix(3).compactMap { item in
                item.toHeroFeature(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
            }
            heroItems.append(contentsOf: randoms)
        }

        return heroItems
    }

    private func libraryCategory(for item: JellyfinAPI.JellyfinItem) -> MetaCategory? {
        guard let libId = itemLibraryId[item.id],
              let lib = libraries.first(where: { $0.id == libId }) else { return nil }
        return metaCategory(for: lib)
    }

    // MARK: - Library classification (Settings → Libraries)

    /// Effective NSFW/anime flags for a library — a saved override always
    /// wins; otherwise falls back to `LibraryClassifier`'s name guess.
    func classificationFlags(for library: JellyfinAPI.JellyfinUserView) -> (isNSFW: Bool, isAnime: Bool) {
        if let override = libraryOverrides[library.id] {
            return (override.isNSFW, override.isAnime)
        }
        return (
            LibraryClassifier.guessIsNSFW(name: library.name),
            LibraryClassifier.guessIsAnime(name: library.name)
        )
    }

    func metaCategory(for library: JellyfinAPI.JellyfinUserView) -> MetaCategory? {
        guard let collectionType = library.collectionType else { return nil }
        let flags = classificationFlags(for: library)
        return MetaCategory.resolve(collectionType: collectionType, isNSFW: flags.isNSFW, isAnime: flags.isAnime)
    }

    func setLibraryClassification(libraryId: String, isNSFW: Bool, isAnime: Bool) {
        libraryOverrides[libraryId] = LibraryClassificationOverride(isNSFW: isNSFW, isAnime: isAnime)
    }

    // MARK: - Library tags (Settings → Libraries)

    enum LibraryTagError: LocalizedError, Equatable {
        case empty
        case duplicate

        var errorDescription: String? {
            switch self {
            case .empty: return "Tag name can't be empty."
            case .duplicate: return "That tag already exists in this library."
            }
        }
    }

    func tags(forLibrary libraryId: String) -> [String] {
        libraryTags[libraryId] ?? []
    }

    func addTag(_ raw: String, toLibrary libraryId: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryTagError.empty }
        var existing = libraryTags[libraryId] ?? []
        guard !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw LibraryTagError.duplicate
        }
        existing.append(trimmed)
        libraryTags[libraryId] = existing
    }

    func deleteTag(_ name: String, fromLibrary libraryId: String) {
        libraryTags[libraryId]?.removeAll { $0 == name }
    }

    private func applyNSFWFilter(_ items: [ContinueWatchingItem]) -> [ContinueWatchingItem] {
        guard hideNSFW else { return items }
        return items.filter { item in
            guard let jfItem = allItems.first(where: { $0.id == item.id }),
                  let category = libraryCategory(for: jfItem) else { return true }
            return !category.isNSFW
        }
    }

    private func applyNSFWFilter(_ items: [MediaItem]) -> [MediaItem] {
        guard hideNSFW else { return items }
        return items.filter { item in
            guard let jfItem = allItems.first(where: { $0.id == item.id }),
                  let category = libraryCategory(for: jfItem) else { return true }
            return !category.isNSFW
        }
    }

    private func applyNSFWFilter(_ items: [HeroFeature]) -> [HeroFeature] {
        guard hideNSFW else { return items }
        return items.filter { item in
            guard let jfItem = allItems.first(where: { $0.id == item.id }),
                  let category = libraryCategory(for: jfItem) else { return true }
            return !category.isNSFW
        }
    }

    /// The full, sortable Movies-library catalog for the Movies screen — a
    /// separate fetch from `recommended`'s capped random sample, since that
    /// screen needs the *whole* library in a server-driven order rather than
    /// a small shuffled pool. Not cached on `AppState`: the Movies screen
    /// owns its own `@State` and re-calls this when the sort chip changes.
    ///
    /// Filters strictly to the plain `.movies` category (not just the
    /// `movies` collection type) so a library classified as anime or NSFW
    /// gets its own dedicated screen (see `loadAnimeMovies`) instead of also
    /// showing up here — `.movies` is never NSFW by construction, so there's
    /// no separate hideNSFW pass needed on top.
    func loadMovies(sortBy: String = "SortName", sortOrder: String = "Ascending") async -> [MediaItem] {
        guard let client else { return [] }
        let movieLibs = libraries.filter { metaCategory(for: $0) == .movies }
        var results: [JellyfinAPI.JellyfinItem] = []
        for lib in movieLibs {
            guard let items = try? await client.fetchItems(
                userId: userId,
                parentId: lib.id,
                includeItemTypes: "Movie",
                sortBy: sortBy,
                sortOrder: sortOrder,
                limit: 500,
                fields: "Overview,Genres,Tags,OfficialRating,CommunityRating,PremiereDate,BackdropImageTags,ParentBackdropImageTags"
            ) else { continue }
            for item in items { itemLibraryId[item.id] = lib.id }
            results.append(contentsOf: items)
        }
        return results.compactMap { item in
            item.toMediaItem(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
        }
    }

    /// The `loadMovies` sibling for the Anime library screen (design 4b) —
    /// same fetch shape, filtered to the `.animefilm` meta-category (a
    /// movies-collection library the user has flagged as anime, and not also
    /// NSFW) so anime films get their own browsing surface instead of being
    /// mixed into the plain Movies grid.
    /// Stand-in artwork for a home-video library, whose items have no poster
    /// of their own.
    ///
    /// **One request per category, cached, not one per item.** A pool of a few
    /// URLs is fetched once and every card hashes onto one of them
    /// (`VideosLibraryView.fallbackArtwork(for:)`) — Nalguitas alone has 1033
    /// items, and a request each would be both absurd and rate-limited.
    ///
    /// The single choke point for this feature: returns `[]` on any failure,
    /// so a card falls back to its own gradient and nothing surfaces an error
    /// for what is decoration.
    /// The atmospheric backdrop for a home-video library.
    ///
    /// These libraries have no artwork of their own worth building a page
    /// around — no logo, no hero still — so the screen borrows one wallpaper
    /// to sit behind the grid. `"video"` for a plain library, `"porn"` for one
    /// marked NSFW in Settings → Libraries.
    ///
    /// **One image, once, per category.** Not per card: the cards show
    /// Jellyfin's own thumbnails. Cached for the launch, so returning to the
    /// screen doesn't re-roll the background under the user.
    ///
    /// The single choke point for this feature: returns nil on any failure, so
    /// the screen simply has no backdrop and nothing surfaces an error for
    /// what is decoration.
    func wallhavenBackdrop(for category: MetaCategory) async -> UIImage? {
        if let cached = wallhavenCache[category] { return cached }
        let filters: WallhavenClient.Filters = category.isNSFW ? .adultVideos : .homeVideos
        guard let urls = try? await WallhavenClient().pool(filters),
              let url = urls.randomElement(),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        wallhavenCache[category] = image
        return image
    }

    /// Server-side search across every library the user can see.
    ///
    /// Deliberately one request against `/Items` with `searchTerm` rather than
    /// filtering something already fetched: the library loaders cap at 500
    /// items each, so a client-side filter would quietly only ever search the
    /// first 500 of anything.
    func search(_ term: String) async -> [MediaItem] {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, needle.count >= 2 else { return [] }
        guard let items = try? await client.fetchItems(
            userId: userId,
            includeItemTypes: "Movie,Series,Episode,Video",
            sortBy: "SortName",
            sortOrder: "Ascending",
            limit: 120,
            searchTerm: needle,
            fields: "Overview,Genres,Tags,OfficialRating,CommunityRating,PremiereDate,BackdropImageTags,ParentBackdropImageTags"
        ) else { return [] }
        return items.compactMap {
            $0.toMediaItem(libraryCategory: libraryCategory(for: $0), imageBaseURL: imageBaseURL)
        }
    }

    /// The four sections the tvOS Search screen groups its results into.
    enum SearchGroupKind { case movies, shows, anime, videos }

    /// Search results, grouped by content type — what `searchGrouped(_:)`
    /// returns and the tvOS Search screen sections into shelves.
    struct SearchResults {
        var movies: [MediaItem] = []
        var shows: [MediaItem] = []
        var anime: [MediaItem] = []
        var videos: [MediaItem] = []
        var isEmpty: Bool { movies.isEmpty && shows.isEmpty && anime.isEmpty && videos.isEmpty }
        var count: Int { movies.count + shows.count + anime.count + videos.count }
    }

    /// Remembers a completed search term, most recent first, deduped
    /// case-insensitively and capped — same shape as `recentTags`.
    func noteRecentSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > Self.maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(Self.maxRecentSearches))
        }
    }

    /// One of the four groups the tvOS Search screen sections its results
    /// into. A category with no search destination (there isn't one today)
    /// resolves to `nil` and is dropped.
    private func searchBucket(for category: MetaCategory) -> SearchGroupKind? {
        switch category {
        case .movies, .moviesxxx: return .movies
        case .shows: return .shows
        case .anime, .animefilm, .hentai: return .anime
        case .videos, .porn: return .videos
        }
    }

    /// Server-side search, grouped by content type — what the tvOS Search
    /// screen sections into Movies/TV Shows/Anime/Home Videos.
    ///
    /// **Scoped per library and fanned out in parallel, not one global
    /// `/Items?searchTerm=` call** (mirrors `queueSources`/`randomQueue`'s
    /// per-library shape). A global search has no reliable way to know which
    /// group a hit belongs to: that's a *library-level* classification
    /// (`metaCategory`), and the per-item cache that resolves it elsewhere
    /// (`itemLibraryId`) only covers whatever this session has already
    /// loaded — most hits from a fresh global search would land in an
    /// unknown bucket. Searching each library directly, already knowing its
    /// category, means every hit's group is known outright, never guessed.
    ///
    /// TV-content libraries are searched for `Series` only, not episodes —
    /// finding the show by name is the useful case; matching every episode
    /// title in a library would flood the section with rows for one show.
    ///
    /// **Matches on Jellyfin's own per-item `Tags`, not just title/genre.**
    /// `searchTerm` never looks inside `Tags` — it's a name/overview match
    /// only — so a heavily-tagged library (an adult-anime library like
    /// "hentai-fin" routinely carries hundreds of descriptive tags per item)
    /// would otherwise be invisible to anything but an exact title search.
    /// `tags=` itself is exact-membership, not substring (`tags=elf` never
    /// matches an item tagged "dark elf"), so the substring step happens
    /// first, client-side, against the already-loaded tag vocabulary
    /// (`tagSuggestions`, the same lookup the player's tag editor uses) —
    /// "elf" resolves to every vocabulary tag *containing* it, and only
    /// those real tag names go to the server, OR-joined in one `tags=`
    /// call. Always a second request alongside the `searchTerm` one, never
    /// combined into it — Jellyfin doesn't OR the two server-side.
    ///
    /// `includeNSFW` overrides the global "hide adult content" default for
    /// this one search — a deliberate, per-search opt-in the screen's own
    /// filter chip drives, not a change to the user's standing preference.
    func searchGrouped(_ term: String, includeNSFW: Bool = false) async -> SearchResults {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, needle.count >= 2 else { return SearchResults() }
        let userId = userId
        let imageBaseURL = imageBaseURL
        let fetchFields = "Overview,Genres,Tags,OfficialRating,CommunityRating,PremiereDate,BackdropImageTags,ParentBackdropImageTags"
        let matchingTags = tagSuggestions(matching: needle, limit: 20)
        let tagQuery = matchingTags.isEmpty ? nil : matchingTags.joined(separator: "|")

        let scopes: [(libraryId: String, bucket: SearchGroupKind, itemTypes: String, category: MetaCategory)] =
            libraries.compactMap { lib in
                guard let category = metaCategory(for: lib), let bucket = searchBucket(for: category) else { return nil }
                guard includeNSFW || !(hideNSFW && category.isNSFW) else { return nil }
                let itemTypes: String
                switch bucket {
                case .movies: itemTypes = "Movie"
                case .shows: itemTypes = "Series"
                case .anime: itemTypes = category.collectionType == "movies" ? "Movie" : "Series"
                case .videos: itemTypes = "Movie,Video"
                }
                return (lib.id, bucket, itemTypes, category)
            }
        guard !scopes.isEmpty else { return SearchResults() }

        let rows: [(SearchGroupKind, MetaCategory, [JellyfinAPI.JellyfinItem])] = await withTaskGroup(
            of: (SearchGroupKind, MetaCategory, [JellyfinAPI.JellyfinItem]).self
        ) { group in
            for scope in scopes {
                group.addTask {
                    let byTerm = (try? await client.fetchItems(
                        userId: userId,
                        parentId: scope.libraryId,
                        includeItemTypes: scope.itemTypes,
                        sortBy: "SortName",
                        sortOrder: "Ascending",
                        limit: 40,
                        searchTerm: needle,
                        fields: fetchFields
                    )) ?? []
                    var byTag: [JellyfinAPI.JellyfinItem] = []
                    if let tagQuery {
                        byTag = (try? await client.fetchItems(
                            userId: userId,
                            parentId: scope.libraryId,
                            includeItemTypes: scope.itemTypes,
                            sortBy: "SortName",
                            sortOrder: "Ascending",
                            limit: 60,
                            tags: tagQuery,
                            fields: fetchFields
                        )) ?? []
                    }
                    var seen = Set<String>()
                    var merged: [JellyfinAPI.JellyfinItem] = []
                    for item in byTerm + byTag where seen.insert(item.id).inserted {
                        merged.append(item)
                    }
                    return (scope.bucket, scope.category, merged)
                }
            }
            var collected: [(SearchGroupKind, MetaCategory, [JellyfinAPI.JellyfinItem])] = []
            for await row in group { collected.append(row) }
            return collected
        }

        var results = SearchResults()
        for (bucket, category, items) in rows {
            let mediaItems = items.compactMap { $0.toMediaItem(libraryCategory: category, imageBaseURL: imageBaseURL) }
            switch bucket {
            case .movies: results.movies.append(contentsOf: mediaItems)
            case .shows: results.shows.append(contentsOf: mediaItems)
            case .anime: results.anime.append(contentsOf: mediaItems)
            case .videos: results.videos.append(contentsOf: mediaItems)
            }
        }
        let byTitle: (MediaItem, MediaItem) -> Bool = { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        results.movies.sort(by: byTitle)
        results.shows.sort(by: byTitle)
        results.anime.sort(by: byTitle)
        results.videos.sort(by: byTitle)
        return results
    }

    /// Everything in the `homevideos` libraries for one category — `.videos`
    /// (plain) or `.porn` (marked NSFW in Settings → Libraries).
    ///
    /// Jellyfin files a home-videos library's contents as `Movie` *or* `Video`
    /// depending on how it was scanned, and the two mix freely inside one
    /// library, so both are requested. Nothing loaded this collection type
    /// before — a `homevideos` library appeared in the Libraries submenu and
    /// then had no screen to open.
    func loadHomeVideos(category: MetaCategory, sortBy: String = "SortName",
                        sortOrder: String = "Ascending") async -> [MediaItem] {
        guard let client else { return [] }
        let libs = libraries.filter { metaCategory(for: $0) == category }
        var results: [JellyfinAPI.JellyfinItem] = []
        for lib in libs {
            guard let items = try? await client.fetchItems(
                userId: userId,
                parentId: lib.id,
                includeItemTypes: "Movie,Video",
                sortBy: sortBy,
                sortOrder: sortOrder,
                limit: 500,
                // `Trickplay` for the cards' frame slideshow, `Width`/`Height`
                // for the mosaic's tile shapes, `PremiereDate` for the camera
                // roll's months — see `HomeVideoRoll`.
                fields: "Overview,Genres,Tags,OfficialRating,CommunityRating,PremiereDate,DateCreated,Width,Height,Trickplay,BackdropImageTags,ParentBackdropImageTags"
            ) else { continue }
            results.append(contentsOf: items)
        }
        return results.compactMap {
            $0.toMediaItem(libraryCategory: category, imageBaseURL: imageBaseURL)
        }
    }

    /// A playable item for a home video. `movieDetail(for:)` only answers for
    /// `Movie`-typed items; a `Video` needs building straight off the raw
    /// item, which is all the player needs anyway.
    func homeVideoPlaybackRequest(for id: String, hidesTitle: Bool = false) async -> PlaybackRequest? {
        guard let raw = await detailItem(for: id) else { return nil }
        let identity = raw.playerIdentity(imageBaseURL: imageBaseURL)
        return .single(PlayableItem(
            id: id,
            title: raw.name ?? "Untitled",
            runtimeTicks: raw.runTimeTicks,
            resumePositionTicks: raw.userData?.playbackPositionTicks,
            isFavorite: raw.userData?.isFavorite ?? false,
            logoURL: identity.logoURL,
            tags: identity.tags,
            hidesTitle: hidesTitle
        ))
    }

    func loadAnimeMovies(sortBy: String = "SortName", sortOrder: String = "Ascending") async -> [MediaItem] {
        guard let client else { return [] }
        let animeLibs = libraries.filter { metaCategory(for: $0) == .animefilm }
        var results: [JellyfinAPI.JellyfinItem] = []
        for lib in animeLibs {
            guard let items = try? await client.fetchItems(
                userId: userId,
                parentId: lib.id,
                includeItemTypes: "Movie",
                sortBy: sortBy,
                sortOrder: sortOrder,
                limit: 500,
                fields: "Overview,Genres,Tags,OfficialRating,CommunityRating,PremiereDate,BackdropImageTags,ParentBackdropImageTags"
            ) else { continue }
            for item in items { itemLibraryId[item.id] = lib.id }
            results.append(contentsOf: items)
        }
        return results.compactMap { item in
            item.toMediaItem(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
        }
    }

    /// The `loadShows` sibling for the Late Night library screen (design 4c)
    /// — the `.hentai` meta-category (tvshows + anime + NSFW). Movies has no
    /// combined NSFW+anime category (`MetaCategory.resolve` always resolves
    /// a movies-collection NSFW+anime library to `.moviesxxx`, dropping the
    /// anime flag), so this category is tvshows-only — no movies fetch to
    /// merge in, unlike `loadAnimeMovies`/`loadAnimeShows`.
    func loadLateNightShows(sortBy: String = "SortName", sortOrder: String = "Ascending") async -> [MediaItem] {
        guard let client else { return [] }
        let lateLibs = libraries.filter { metaCategory(for: $0) == .hentai }
        var results: [JellyfinAPI.JellyfinItem] = []
        for lib in lateLibs {
            guard let items = try? await client.fetchItems(
                userId: userId,
                parentId: lib.id,
                includeItemTypes: "Series",
                sortBy: sortBy,
                sortOrder: sortOrder,
                limit: 500,
                fields: "Overview,Genres,Tags,OfficialRating,CommunityRating,PremiereDate,BackdropImageTags,ParentBackdropImageTags"
            ) else { continue }
            for item in items { itemLibraryId[item.id] = lib.id }
            results.append(contentsOf: items)
        }
        return results.compactMap { item in
            item.toMediaItem(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
        }
    }

    /// The `loadShows` sibling for the Anime library screen — most anime
    /// actually lives in a tvshows-collection library (episodic series), not
    /// a movies one, so the Anime screen fetches both this and
    /// `loadAnimeMovies` and shows them together as one library.
    func loadAnimeShows(sortBy: String = "SortName", sortOrder: String = "Ascending") async -> [MediaItem] {
        guard let client else { return [] }
        let animeLibs = libraries.filter { metaCategory(for: $0) == .anime }
        var results: [JellyfinAPI.JellyfinItem] = []
        for lib in animeLibs {
            guard let items = try? await client.fetchItems(
                userId: userId,
                parentId: lib.id,
                includeItemTypes: "Series",
                sortBy: sortBy,
                sortOrder: sortOrder,
                limit: 500,
                fields: "Overview,Genres,Tags,OfficialRating,CommunityRating,PremiereDate,BackdropImageTags,ParentBackdropImageTags"
            ) else { continue }
            for item in items { itemLibraryId[item.id] = lib.id }
            results.append(contentsOf: items)
        }
        return results.compactMap { item in
            item.toMediaItem(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
        }
    }

    /// The full, sortable TV Shows-library catalog — the `loadMovies` sibling
    /// for the Shows screen. Not cached on `AppState`: the Shows screen owns
    /// its own `@State` and re-calls this when the sort chip changes.
    func loadShows(sortBy: String = "SortName", sortOrder: String = "Ascending") async -> [MediaItem] {
        guard let client else { return [] }
        let showLibs = libraries.filter {
            metaCategory(for: $0)?.collectionType == "tvshows"
        }
        var results: [JellyfinAPI.JellyfinItem] = []
        for lib in showLibs {
            guard let items = try? await client.fetchItems(
                userId: userId,
                parentId: lib.id,
                includeItemTypes: "Series",
                sortBy: sortBy,
                sortOrder: sortOrder,
                limit: 500,
                fields: "Overview,Genres,Tags,OfficialRating,CommunityRating,PremiereDate,BackdropImageTags,ParentBackdropImageTags"
            ) else { continue }
            for item in items { itemLibraryId[item.id] = lib.id }
            results.append(contentsOf: items)
        }
        let visible = hideNSFW
            ? results.filter { !(libraryCategory(for: $0)?.isNSFW ?? false) }
            : results
        return visible.compactMap { item in
            item.toMediaItem(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
        }
    }

    // MARK: - On-demand detail enrichment

    /// Full Jellyfin metadata for one item (cast, critic rating, tagline,
    /// studios, IMDb id), cached by id. `nil` if there's no server yet.
    private func detailItem(for id: String) async -> JellyfinAPI.JellyfinItem? {
        if let cached = itemDetailCache[id] { return cached }
        guard let client else { return nil }
        guard let item = try? await client.fetchItemDetail(userId: userId, itemId: id) else { return nil }
        itemDetailCache[id] = item
        return item
    }

    /// A fully-populated `Movie` for the detail/dossier surfaces (real cast,
    /// ratings, tagline, director). Falls back to `nil` before the server is up.
    func movieDetail(for id: String) async -> Movie? {
        guard let item = await detailItem(for: id) else { return nil }
        return item.toMovie(libraryCategory: libraryCategory(for: item),
                            imageBaseURL: imageBaseURL,
                            moreLikeThis: recommended)
    }

    /// Enriches a `Show` (keeping its seasons) with real cast/ratings/tagline.
    func enrichedShow(_ base: Show) async -> Show? {
        guard let item = await detailItem(for: base.id) else { return nil }
        return item.enrich(base, imageBaseURL: imageBaseURL)
    }

    /// A series' real seasons (episodes start empty — fetched separately, per
    /// selection). Cached by series id; `nil` before the server is up or on
    /// failure, so the caller can keep whatever it already has.
    func seasons(for seriesId: String) async -> [Season]? {
        if let cached = seasonsCache[seriesId] { return cached }
        guard let client else { return nil }
        guard let items = try? await client.fetchSeasons(userId: userId, seriesId: seriesId) else { return nil }
        let seasons = items.map { $0.toSeason(imageBaseURL: imageBaseURL) }.sorted { $0.number < $1.number }
        seasonsCache[seriesId] = seasons
        return seasons
    }

    /// One season's real episodes (thumbnail, runtime, resume state). Cached
    /// by season id — switching back to an already-viewed season is instant.
    func episodes(seriesId: String, seasonId: String) async -> [Episode]? {
        if let cached = episodesCache[seasonId] { return cached }
        guard let client else { return nil }
        guard let items = try? await client.fetchEpisodes(userId: userId, seriesId: seriesId, seasonId: seasonId) else { return nil }
        let episodes = items.map { $0.toEpisode(imageBaseURL: imageBaseURL, seriesId: seriesId) }.sorted { $0.number < $1.number }
        episodesCache[seasonId] = episodes
        return episodes
    }

    // MARK: - Movie night (the tvOS movie page's extras)

    private var personCache: [String: Person] = [:]
    private var creditsCache: [String: [MediaItem]] = [:]
    private var similarCache: [String: [MediaItem]] = [:]
    private var extrasCache: [String: TMDBMovieExtras?] = [:]
    private var movieRatings: [Double]?

    /// A person's facts — bio, dates, birthplace — from their own item.
    /// Fetched once per person; the cast lineup asks as the remote moves
    /// across it, so this is what makes the second look at someone free.
    func person(for id: String) async -> Person? {
        if let cached = personCache[id] { return cached }
        guard let client else { return nil }
        guard let item = try? await client.fetchItemDetail(userId: userId, itemId: id) else { return nil }
        let person = item.toPerson(imageBaseURL: imageBaseURL)
        personCache[id] = person
        return person
    }

    /// Everything else in the library with this person in it — "3 more in
    /// your library", and the person sheet's poster row. `excluding` is the
    /// film being looked at; it is trivially in the list.
    func libraryCredits(personId: String, excluding itemId: String? = nil) async -> [MediaItem] {
        if let cached = creditsCache[personId] { return cached.filter { $0.id != itemId } }
        guard let client else { return [] }
        let rows = (try? await client.fetchItems(userId: userId, personIds: [personId])) ?? []
        let items = rows.map { $0.toMediaItem(libraryCategory: libraryCategory(for: $0), imageBaseURL: imageBaseURL) }
        creditsCache[personId] = items
        return items.filter { $0.id != itemId }
    }

    /// What the server considers similar, restricted to this user's library —
    /// the movie page's real "More like this".
    func similarItems(to itemId: String) async -> [MediaItem] {
        if let cached = similarCache[itemId] { return cached }
        guard let client else { return [] }
        let rows = (try? await client.fetchSimilar(userId: userId, itemId: itemId)) ?? []
        let items = rows.filter { $0.id != itemId }
            .map { $0.toMediaItem(libraryCategory: libraryCategory(for: $0), imageBaseURL: imageBaseURL) }
        similarCache[itemId] = items
        return items
    }

    /// TMDB's extras for a film (more backdrops, keywords, collection, box
    /// office). The single choke point, like `omdbEnrichment`: `nil` whenever
    /// the feature is off, unconfigured, the ids are missing, or the call
    /// fails — the page is complete without it.
    func movieExtras(imdbId: String?, tmdbId: String?) async -> TMDBMovieExtras? {
        guard tmdbEnabled, !tmdbApiKey.isEmpty else { return nil }
        guard let key = tmdbId ?? imdbId else { return nil }
        if let cached = extrasCache[key] { return cached }
        let extras = (try? await TMDBClient(apiKey: tmdbApiKey).fetchMovieExtras(imdbId: imdbId, tmdbId: tmdbId)) ?? nil
        extrasCache[key] = extras
        return extras
    }

    /// "TOP 8% OF YOUR MOVIES" — where a rating sits among every movie in the
    /// library. The library's ratings are fetched once per launch; nil until
    /// they are, and nil for a library too small to rank (see
    /// `MovieNightFacts.topPercent`).
    func movieRatingPercentile(for rating: Double?) async -> Int? {
        if movieRatings == nil {
            movieRatings = await loadMovies().compactMap(\.rating)
        }
        return MovieNightFacts.topPercent(rating: rating, among: movieRatings ?? [])
    }

    /// "PART 2 OF 3 · SEEN 1": a TMDB collection's films matched against the
    /// library by provider id. `position` is where the current film sits in
    /// release order; `seen` counts the parts this user owns and has watched.
    func collectionProgress(partTmdbIds: [Int], currentTmdbId: String?) async -> (position: Int?, total: Int, seen: Int)? {
        guard partTmdbIds.count > 1, let client else { return nil }
        let ids = partTmdbIds.map { "Tmdb.\($0)" }
        let owned = (try? await client.fetchItems(userId: userId, anyProviderIdEquals: ids)) ?? []
        let seen = owned.filter { $0.userData?.played == true }.count
        let position = currentTmdbId.flatMap(Int.init).flatMap { id in partTmdbIds.firstIndex(of: id).map { $0 + 1 } }
        return (position, partTmdbIds.count, seen)
    }

    /// OMDb enrichment (awards + true RT/Metacritic), keyed by IMDb id. The
    /// single choke point for graceful degradation: returns `nil` whenever the
    /// feature is off, unconfigured, the id is missing, or the call fails.
    func omdbEnrichment(imdbId: String?) async -> (ratings: ExternalRatings?, awards: MovieAwards?)? {
        guard omdbEnabled, !omdbApiKey.isEmpty, let imdbId, !imdbId.isEmpty else { return nil }
        if let cached = omdbCache[imdbId] { return cached }
        guard let result = try? await OmdbClient(apiKey: omdbApiKey).fetch(imdbId: imdbId),
              result.isSuccess else { return nil }
        let enrichment = (result.externalRatings, result.parsedAwards)
        omdbCache[imdbId] = enrichment
        return enrichment
    }

    /// TMDB network branding, keyed by IMDb id. The single choke point for
    /// graceful degradation: returns `nil` whenever the feature is off,
    /// unconfigured, the id is missing, or the call fails — the dossier's
    /// network element simply doesn't render.
    func tmdbNetwork(imdbId: String?) async -> Network? {
        guard tmdbEnabled, !tmdbApiKey.isEmpty, let imdbId, !imdbId.isEmpty else { return nil }
        if let cached = tmdbCache[imdbId] { return cached }
        let network = try? await TMDBClient(apiKey: tmdbApiKey).fetchNetwork(imdbId: imdbId)
        let result = network ?? nil
        tmdbCache[imdbId] = result
        return result
    }

    func libraryUIItems() -> [Library] {
        libraries.compactMap { lib -> Library? in
            guard let category = metaCategory(for: lib) else { return nil }
            if isDefaultPrimaryLibrary(lib, category: category) { return nil }
            return Library(id: lib.id, name: lib.name, isAdult: category.isNSFW, itemCount: "", category: category)
        }
    }

    /// True for a library named exactly "Movies" or "TV Shows" (case-insensitive)
    /// that's still its plain, un-overridden default category — redundant with
    /// the dedicated Movies/TV rail icons, so hidden from the rail's generic
    /// Libraries submenu. Settings → Libraries still lists it unfiltered (via
    /// `libraries` directly) so it can still be tagged/reclassified there.
    private func isDefaultPrimaryLibrary(_ lib: JellyfinAPI.JellyfinUserView, category: MetaCategory) -> Bool {
        let name = lib.name.trimmingCharacters(in: .whitespaces).lowercased()
        switch category {
        case .movies: return name == "movies"
        case .shows: return name == "tv shows"
        default: return false
        }
    }

    func items(for collectionType: String) -> [MediaItem] {
        let libIds = Set(libraries.filter { lib in
            metaCategory(for: lib)?.collectionType == collectionType
        }.map(\.id))
        return allItems.filter { item in
            libIds.contains { item.id.hasPrefix($0) } || libIds.contains(item.id)
        }.compactMap { item in
            item.toMediaItem(libraryCategory: libraryCategory(for: item), imageBaseURL: imageBaseURL)
        }
    }

    // MARK: - Playback

    /// Read-only accessors so `PlayerView` can build its own `PlayerEngine`
    /// without `AppState` handing out its mutable `client`/`userId` storage.
    var jellyfinClient: JellyfinClient? { client }
    var currentUserId: String { userId }

    func requestPlayback(_ request: PlaybackRequest) {
        activePlaybackRequest = request
    }

    /// The controller of whatever is playing right now — registered by
    /// `PlayerView` for as long as it is up — so a remote-control transport
    /// command (`RemoteControl`) has something to pause. Weak: the player
    /// owns it, and a stale reference after teardown must read as "nothing
    /// playing", never as a controller that swallows commands.
    weak var activePlayerController: PlayerController?

    /// A queue for items another client asked this one to play (a "Play On"
    /// from a phone — see `RemoteControl`).
    ///
    /// One item takes the same road a tap here would: a film alone, an
    /// episode with the rest of its show queued behind it (`resumeRequest`),
    /// so auto-advance works for a remote start too. Several items become a
    /// queue in the order they were sent, through the same `PlayQueue`
    /// conversion a shuffle uses — virtual/fileless rows dropped, series logo
    /// and tags borrowed in one batched fetch. `startPositionTicks`, when the
    /// sender gave one, overrides the first item's own resume position: the
    /// phone said where to start.
    func playbackRequest(forItemIds ids: [String], startIndex: Int,
                         startPositionTicks: Int64?) async -> PlaybackRequest? {
        guard let client, !ids.isEmpty else { return nil }

        if ids.count == 1, let raw = await detailItem(for: ids[0]),
           let request = await resumeRequest(id: raw.id, itemType: raw.type, seriesId: raw.seriesId,
                                             fallbackTitle: raw.name ?? "") {
            return applyingStartPosition(startPositionTicks, to: request)
        }

        guard let rows = try? await client.fetchItems(userId: userId, ids: ids) else { return nil }
        let ordered = ids.compactMap { id in rows.first { $0.id == id } }
        let identities = await seriesIdentities(in: ordered)
        let items = ordered.compactMap {
            PlayQueue.playableItem(from: $0, seriesIdentity: identities, imageBaseURL: imageBaseURL)
        }
        guard !items.isEmpty else { return nil }
        let start = min(max(0, startIndex), items.count - 1)
        return applyingStartPosition(startPositionTicks, to: .queue(items, startIndex: start))
    }

    private func applyingStartPosition(_ ticks: Int64?, to request: PlaybackRequest) -> PlaybackRequest {
        guard let ticks, ticks > 0, request.items.indices.contains(request.startIndex) else { return request }
        var items = request.items
        let item = items[request.startIndex]
        items[request.startIndex] = PlayableItem(
            id: item.id, seriesId: item.seriesId, title: item.title, subtitle: item.subtitle,
            runtimeTicks: item.runtimeTicks, resumePositionTicks: ticks, isFavorite: item.isFavorite,
            imageURL: item.imageURL, logoURL: item.logoURL, tags: item.tags, hidesTitle: item.hidesTitle
        )
        return PlaybackRequest(items: items, startIndex: request.startIndex, shuffled: request.shuffled)
    }

    /// A season's episodes, already loaded by `ShowView` — sync, no fetch.
    func episodeQueueRequest(episodes: [Episode], seriesTitle: String, seasonNumber: Int,
                             startEpisodeId: String,
                             seriesLogoURL: String? = nil, seriesTags: [String] = []) -> PlaybackRequest? {
        guard !episodes.isEmpty else { return nil }
        let items = episodes.map {
            $0.asPlayableItem(seriesTitle: seriesTitle, seasonNumber: seasonNumber,
                              logoURL: seriesLogoURL, tags: seriesTags)
        }
        let startIndex = items.firstIndex { $0.id == startEpisodeId } ?? 0
        return .queue(items, startIndex: startIndex)
    }

    /// Flattens every season's episodes into one shuffled queue.
    ///
    /// **One recursive call, not one per season.** `parentId` accepts a
    /// series just as happily as a library, so Jellyfin does the flattening;
    /// the previous version walked `/Shows/{id}/Seasons` and then fetched
    /// each season's episodes, which is a round trip per season to reach the
    /// same list. `seriesTitle` still comes from the caller because the
    /// lean queue fetch doesn't ask for anything the series row would carry.
    func shufflePlayRequest(seriesId: String, seriesTitle: String) async -> PlaybackRequest? {
        guard let client else { return nil }
        let series = await seriesIdentity(for: seriesId)
        guard let rows = try? await client.fetchPlayQueueItems(
            userId: userId, parentId: seriesId, includeItemTypes: "Episode"
        ) else { return nil }
        let identity = seriesId.isEmpty ? [:] : [seriesId: series]
        let items = rows.compactMap {
            PlayQueue.playableItem(from: $0, seriesIdentity: identity, imageBaseURL: imageBaseURL)
        }
        guard !items.isEmpty else { return nil }
        return .shuffled(PlayQueue.merge([items]))
    }

    /// The whole series, in broadcast order, starting at episode one — the
    /// deterministic sibling of `shufflePlayRequest`, for a caller that
    /// wants "just start this show" rather than a shuffle. Search's Play
    /// button uses this for a Series result; `seriesQueueRequest` (below)
    /// covers the resume-from-here case where a specific episode is known.
    func firstEpisodeQueueRequest(seriesId: String) async -> PlaybackRequest? {
        guard let client else { return nil }
        let series = await seriesIdentity(for: seriesId)
        guard let rows = try? await client.fetchPlayQueueItems(
            userId: userId, parentId: seriesId, includeItemTypes: "Episode",
            sortBy: "ParentIndexNumber,IndexNumber", limit: PlayQueue.seriesLimit
        ) else { return nil }
        let identity = seriesId.isEmpty ? [:] : [seriesId: series]
        // Never through `PlayQueue.merge` — that shuffles, which is the one
        // thing this queue must not do.
        let items = rows.compactMap {
            PlayQueue.playableItem(from: $0, seriesIdentity: identity, imageBaseURL: imageBaseURL)
        }
        guard !items.isEmpty else { return nil }
        return .queue(items, startIndex: 0)
    }

    // MARK: - Play queues
    /// Every episode of a series from a given one onward, in broadcast order
    /// — season by season, episode by episode, across the whole run.
    ///
    /// **Playing an episode means "carry on from here", not "finish this
    /// season".** The queue used to stop at the season boundary, so the last
    /// episode of a season ended the queue and auto-advance had nowhere to
    /// go, in the middle of a show with nine more seasons sitting one tap
    /// away. `sortBy=ParentIndexNumber,IndexNumber` is what puts them in that
    /// order — the same single recursive call the shuffle uses, only sorted
    /// instead of randomised, so it inherits `isMissing=false` and the
    /// `LocationType` guard and cannot queue a fileless episode.
    ///
    /// Specials (season 0) sort *before* season 1, which is the right answer
    /// for free: starting at the tapped episode skips everything ahead of it,
    /// so a normal episode never gets a pile of specials in front of it,
    /// while someone who deliberately taps a special gets the specials.
    ///
    /// Returns nil when the fetch fails or the episode isn't in the result —
    /// callers fall back to the narrower queue they can already build rather
    /// than not playing at all.
    func seriesQueueRequest(seriesId: String, seriesTitle: String, startEpisodeId: String,
                            logoURL: String? = nil, tags: [String] = []) async -> PlaybackRequest? {
        guard let client else { return nil }
        let identity: (logoURL: String?, tags: [String])
        if logoURL != nil || !tags.isEmpty {
            identity = (logoURL, tags)
        } else {
            identity = await seriesIdentity(for: seriesId)
        }
        guard let rows = try? await client.fetchPlayQueueItems(
            userId: userId, parentId: seriesId, includeItemTypes: "Episode",
            sortBy: "ParentIndexNumber,IndexNumber", limit: PlayQueue.seriesLimit
        ) else { return nil }
        // Never through `PlayQueue.merge` — that shuffles, which is the one
        // thing this queue must not do.
        let items = rows.compactMap {
            PlayQueue.playableItem(from: $0, seriesIdentity: [seriesId: identity],
                                   imageBaseURL: imageBaseURL)
        }
        guard let startIndex = items.firstIndex(where: { $0.id == startEpisodeId }) else { return nil }
        return .queue(items, startIndex: startIndex)
    }


    /// What a library screen's Random button shuffles over.
    ///
    /// Each case names the same library set that screen's *list* loader uses,
    /// deliberately: "random" has to mean "random out of what this page
    /// shows", or the button plays something the user can't find on the page
    /// they pressed it from. The item type is what that screen counts as a
    /// video to play — for the two episodic scopes that's `Episode`, never
    /// `Series`, because a queue of shows isn't a queue of anything playable.
    enum PlaylistScope {
        case movies
        case shows
        case anime
        case lateNight
        case homeVideos(MetaCategory)
    }

    /// The libraries a scope draws on, each paired with the item type to pull
    /// out of it.
    private func queueSources(for scope: PlaylistScope) -> [(libraryId: String, itemTypes: String)] {
        switch scope {
        case .movies:
            return libraries.filter { metaCategory(for: $0) == .movies }
                .map { ($0.id, "Movie") }

        case .shows:
            // Mirrors `loadShows`: every tvshows-collection library, with the
            // NSFW ones dropped when the user has hidden them — filtered here
            // at the source rather than after the fetch, since a queue has no
            // reason to download what it must then discard.
            return libraries.filter { library in
                guard let category = metaCategory(for: library),
                      category.collectionType == "tvshows" else { return false }
                return !(hideNSFW && category.isNSFW)
            }.map { ($0.id, "Episode") }

        case .anime:
            // The Anime screen is two loaders shown as one library, so its
            // queue is both: episodes from the tvshows-collection anime
            // libraries, films from the movies-collection ones.
            return libraries.compactMap { library in
                switch metaCategory(for: library) {
                case .anime: return (library.id, "Episode")
                case .animefilm: return (library.id, "Movie")
                default: return nil
                }
            }

        case .lateNight:
            return libraries.filter { metaCategory(for: $0) == .hentai }
                .map { ($0.id, "Episode") }

        case .homeVideos(let category):
            // Jellyfin files a home-videos library's contents as `Movie` *or*
            // `Video` depending on how it was scanned — same pair
            // `loadHomeVideos` asks for.
            return libraries.filter { metaCategory(for: $0) == category }
                .map { ($0.id, "Movie,Video") }
        }
    }

    /// A fresh randomly-ordered queue over a whole scope — what Random plays.
    ///
    /// **Every press builds a new one.** The order comes from the server
    /// (`sortBy=Random`), which re-rolls per request, so this is genuinely a
    /// different queue each time rather than a re-entry into a stored one.
    /// Nothing is persisted and nothing is written to Jellyfin's `/Playlists`
    /// — a queue lives exactly as long as the player showing it.
    ///
    /// Libraries are fetched in parallel and merged. One that is empty, slow
    /// or erroring contributes nothing instead of failing the press: v1's
    /// equivalent picked a single library up front and, per its own commit
    /// message, came back empty most of the time because of it.
    func randomQueue(for scope: PlaylistScope) async -> PlaybackRequest? {
        guard let client else { return nil }
        let sources = queueSources(for: scope)
        guard !sources.isEmpty else { return nil }
        let hidesTitle: Bool
        if case .homeVideos = scope { hidesTitle = true } else { hidesTitle = false }
        let userId = userId

        let groups: [[JellyfinAPI.JellyfinItem]] = await withTaskGroup(
            of: [JellyfinAPI.JellyfinItem].self
        ) { group in
            for source in sources {
                group.addTask {
                    (try? await client.fetchPlayQueueItems(
                        userId: userId,
                        parentId: source.libraryId,
                        includeItemTypes: source.itemTypes
                    )) ?? []
                }
            }
            var collected: [[JellyfinAPI.JellyfinItem]] = []
            for await rows in group { collected.append(rows) }
            return collected
        }

        let identity = await seriesIdentities(in: groups.flatMap { $0 })
        let items = PlayQueue.merge(groups.map { rows in
            rows.compactMap {
                PlayQueue.playableItem(from: $0, seriesIdentity: identity,
                                       imageBaseURL: imageBaseURL, hidesTitle: hidesTitle)
            }
        })
        guard !items.isEmpty else { return nil }
        return .shuffled(items)
    }

    /// The queue behind a tap in a list: that item, then everything after it,
    /// in the order the list is showing.
    ///
    /// Built from the rows the grid already holds rather than re-fetched, so
    /// the user's current search and sort carry into the queue — press Next
    /// and you get the card that was to the right of the one you tapped.
    /// (That is the opposite of the Random path, which deliberately reaches
    /// past the visible page to the whole library.)
    func listQueueRequest(_ items: [MediaItem], startingAt itemId: String,
                          hidesTitle: Bool = false) -> PlaybackRequest? {
        guard let startIndex = items.firstIndex(where: { $0.id == itemId }) else { return nil }
        let playable = items.map { $0.asPlayableItem(hidesTitle: hidesTitle) }
        return .queue(playable, startIndex: startIndex)
    }

    /// Logo artwork and tags for every series represented in a set of rows.
    ///
    /// A cross-series shuffle mixes episodes from dozens of shows, and both
    /// of those live on the *series* — Jellyfin almost never puts either on
    /// an episode. One batched call per 100 series answers the whole queue;
    /// the chunking is only to keep the `ids` query string a sane length.
    private func seriesIdentities(
        in rows: [JellyfinAPI.JellyfinItem]
    ) async -> [String: (logoURL: String?, tags: [String])] {
        guard let client else { return [:] }
        let ids = Array(Set(rows.compactMap { $0.type == "Episode" ? $0.seriesId : nil }))
        guard !ids.isEmpty else { return [:] }
        var identities: [String: (logoURL: String?, tags: [String])] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 100).map({ Array(ids[$0..<min($0 + 100, ids.count)]) }) {
            guard let series = try? await client.fetchItems(userId: userId, ids: chunk) else { continue }
            for item in series {
                identities[item.id] = item.playerIdentity(imageBaseURL: imageBaseURL)
            }
        }
        return identities
    }

    func resumeRequest(for hero: HeroFeature) async -> PlaybackRequest? {
        await resumeRequest(id: hero.id, itemType: hero.itemType,
                            seriesId: hero.seriesId, fallbackTitle: hero.title)
    }

    func resumeRequest(for item: ContinueWatchingItem) async -> PlaybackRequest? {
        await resumeRequest(id: item.id, itemType: item.itemType,
                            seriesId: item.seriesId, fallbackTitle: item.title)
    }

    /// **Resuming an episode queues the rest of the show, not just that one
    /// episode.**
    ///
    /// Carrying on from Home used to build a single-item queue, which quietly
    /// disabled everything downstream that depends on there being a next
    /// episode: auto-advance when the episode ends, and the player's own
    /// next-video affordances. Someone resuming episode 4 plainly means to
    /// keep watching, so the queue runs from episode 4 to the end of the
    /// series — the same queue the Show screen builds when you press play
    /// there. It stopped at the season boundary until the season boundary
    /// turned out to be an arbitrary place to end a night.
    ///
    /// A movie stays a single item: there is nothing to advance to.
    private func resumeRequest(id: String, itemType: String?, seriesId: String?,
                               fallbackTitle: String) async -> PlaybackRequest? {
        switch itemType {
        case "Movie":
            guard let movie = await movieDetail(for: id) else { return nil }
            return .single(movie.asPlayableItem())

        case "Episode":
            guard let raw = await detailItem(for: id) else { return nil }
            let owningSeriesId = seriesId ?? raw.seriesId
            let seriesTitle = raw.seriesName ?? fallbackTitle
            let seasonNumber = raw.parentIndexNumber ?? 0
            let series = await seriesIdentity(for: owningSeriesId)

            // The rest of the show from here — every remaining episode of this
            // season and then every season after it.
            if let owningSeriesId,
               let request = await seriesQueueRequest(
                   seriesId: owningSeriesId, seriesTitle: seriesTitle, startEpisodeId: id,
                   logoURL: series.logoURL, tags: series.tags) {
                return request
            }

            // Series fetch didn't answer: the season alone still beats a
            // queue of one. Cached, so this is usually free by the time
            // anyone reaches it.
            if let owningSeriesId, let seasonId = raw.seasonId,
               let episodes = await episodes(seriesId: owningSeriesId, seasonId: seasonId),
               let startIndex = episodes.firstIndex(where: { $0.id == id }) {
                let items = episodes.map {
                    $0.asPlayableItem(seriesTitle: seriesTitle, seasonNumber: seasonNumber,
                                      logoURL: series.logoURL, tags: series.tags)
                }
                return .queue(items, startIndex: startIndex)
            }

            // No season listing (a stray episode, or the fetch failed): still
            // play the thing that was asked for.
            let episode = raw.toEpisode(imageBaseURL: imageBaseURL, seriesId: owningSeriesId)
            return .single(episode.asPlayableItem(
                seriesTitle: seriesTitle, seasonNumber: seasonNumber,
                logoURL: series.logoURL, tags: series.tags))

        default:
            return nil
        }
    }

    /// The owning series' logo artwork and tags, for an episode being queued.
    /// Jellyfin puts neither on the episode itself, so the player chrome would
    /// otherwise fall back to plain type and show no chips. Goes through
    /// `detailItem(for:)`, so a season's worth of episodes costs one fetch.
    private func seriesIdentity(for seriesId: String?) async -> (logoURL: String?, tags: [String]) {
        guard let seriesId, let raw = await detailItem(for: seriesId) else { return (nil, []) }
        return raw.playerIdentity(imageBaseURL: imageBaseURL)
    }
}
