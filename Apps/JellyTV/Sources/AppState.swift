import SwiftUI
import JellyTVKit

@MainActor
final class AppState: ObservableObject {
    @Published var libraries: [JellyfinAPI.JellyfinUserView] = []
    @Published var continueWatching: [ContinueWatchingItem] = []
    @Published var recommended: [MediaItem] = []
    @Published var heroes: [HeroFeature] = []
    @Published var hideNSFW: Bool {
        didSet { UserDefaults.standard.set(hideNSFW, forKey: "jelly:home.hideNSFW") }
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
    /// Set to present the player via `RootView`'s `.fullScreenCover(item:)`.
    /// `PlaybackRequest.id` is content-derived, so re-setting the same
    /// request (e.g. an unrelated `AppState` publish) doesn't retrigger it.
    @Published var activePlaybackRequest: PlaybackRequest?

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
        omdbEnabled = UserDefaults.standard.object(forKey: "jelly:omdb.enabled") as? Bool ?? false
        omdbApiKey = UserDefaults.standard.string(forKey: "jelly:omdb.apiKey") ?? ""
        tmdbEnabled = UserDefaults.standard.object(forKey: "jelly:tmdb.enabled") as? Bool ?? false
        tmdbApiKey = UserDefaults.standard.string(forKey: "jelly:tmdb.apiKey") ?? ""
    }

    func configure(baseURL: URL, apiKey: String, deviceId: String, userId: String) {
        self.client = JellyfinClient(baseURL: baseURL, apiKey: apiKey, deviceId: deviceId)
        self.userId = userId
        self.imageBaseURL = baseURL
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
        guard let client else { return }
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
        return LibraryClassifier.classify(collectionType: lib.collectionType, name: lib.name)
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
    func loadMovies(sortBy: String = "SortName", sortOrder: String = "Ascending") async -> [MediaItem] {
        guard let client else { return [] }
        let movieLibs = libraries.filter {
            LibraryClassifier.classify(collectionType: $0.collectionType, name: $0.name)?.collectionType == "movies"
        }
        var results: [JellyfinAPI.JellyfinItem] = []
        for lib in movieLibs {
            guard let items = try? await client.fetchItems(
                userId: userId,
                parentId: lib.id,
                includeItemTypes: "Movie",
                sortBy: sortBy,
                sortOrder: sortOrder,
                limit: 500,
                fields: "Overview,Genres,OfficialRating,CommunityRating,PremiereDate,BackdropImageTags,ParentBackdropImageTags"
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

    /// The full, sortable TV Shows-library catalog — the `loadMovies` sibling
    /// for the Shows screen. Not cached on `AppState`: the Shows screen owns
    /// its own `@State` and re-calls this when the sort chip changes.
    func loadShows(sortBy: String = "SortName", sortOrder: String = "Ascending") async -> [MediaItem] {
        guard let client else { return [] }
        let showLibs = libraries.filter {
            LibraryClassifier.classify(collectionType: $0.collectionType, name: $0.name)?.collectionType == "tvshows"
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
                fields: "Overview,Genres,OfficialRating,CommunityRating,PremiereDate,BackdropImageTags,ParentBackdropImageTags"
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
        libraries.compactMap { lib in
            lib.toLibrary(classifier: LibraryClassifier.classify(collectionType:name:))
        }
    }

    func items(for collectionType: String) -> [MediaItem] {
        let libIds = Set(libraries.filter { lib in
            LibraryClassifier.classify(collectionType: lib.collectionType, name: lib.name)?.collectionType == collectionType
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

    /// A season's episodes, already loaded by `ShowView` — sync, no fetch.
    func episodeQueueRequest(episodes: [Episode], seriesTitle: String, seasonNumber: Int,
                             startEpisodeId: String) -> PlaybackRequest? {
        guard !episodes.isEmpty else { return nil }
        let items = episodes.map { $0.asPlayableItem(seriesTitle: seriesTitle, seasonNumber: seasonNumber) }
        let startIndex = items.firstIndex { $0.id == startEpisodeId } ?? 0
        return .queue(items, startIndex: startIndex)
    }

    /// Flattens every season's episodes into one shuffled queue.
    func shufflePlayRequest(seriesId: String, seriesTitle: String) async -> PlaybackRequest? {
        guard let allSeasons = await seasons(for: seriesId) else { return nil }
        var items: [PlayableItem] = []
        for season in allSeasons {
            guard let episodes = await episodes(seriesId: seriesId, seasonId: season.id) else { continue }
            items.append(contentsOf: episodes.map { $0.asPlayableItem(seriesTitle: seriesTitle, seasonNumber: season.number) })
        }
        guard !items.isEmpty else { return nil }
        return .shuffled(items)
    }

    func resumeRequest(for hero: HeroFeature) async -> PlaybackRequest? {
        guard let item = await resumePlayableItem(id: hero.id, itemType: hero.itemType,
                                                   seriesId: hero.seriesId, fallbackTitle: hero.title) else { return nil }
        return .single(item)
    }

    func resumeRequest(for item: ContinueWatchingItem) async -> PlaybackRequest? {
        guard let playable = await resumePlayableItem(id: item.id, itemType: item.itemType,
                                                       seriesId: item.seriesId, fallbackTitle: item.title) else { return nil }
        return .single(playable)
    }

    private func resumePlayableItem(id: String, itemType: String?, seriesId: String?, fallbackTitle: String) async -> PlayableItem? {
        switch itemType {
        case "Movie":
            guard let movie = await movieDetail(for: id) else { return nil }
            return movie.asPlayableItem()
        case "Episode":
            guard let raw = await detailItem(for: id) else { return nil }
            let episode = raw.toEpisode(imageBaseURL: imageBaseURL, seriesId: seriesId ?? raw.seriesId)
            return episode.asPlayableItem(seriesTitle: raw.seriesName ?? fallbackTitle, seasonNumber: raw.parentIndexNumber ?? 0)
        default:
            return nil
        }
    }
}
