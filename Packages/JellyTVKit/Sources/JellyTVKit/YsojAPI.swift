import Foundation

/// The shapes a YSOJ-server serves under `/ysoj/*` — Discover, and the download centre.
///
/// **These are deliberately not `BaseItemDto`s.** The server's first design expressed
/// Discover through endpoints an unmodified client already called: a synthetic library
/// injected into `/UserViews`, fake seasons and episodes, and favouriting an item as the
/// download gesture. That was the right answer while this app could not be changed and
/// the wrong one now — favourite already means something on real library items (and this
/// app hearts optimistically, so it would report success before a search had run), and
/// download *progress* has no representation as a Jellyfin item at all. Discover items
/// are their own type, addressed by their own refs, and never mixed into a Jellyfin
/// response.
///
/// The server emits camelCase, so no `keyDecodingStrategy` is needed. Every URL arrives
/// as a `String` and is exposed as a lazily-parsed `URL?` — a malformed poster path from
/// a third-party source must not fail the decode of a whole shelf.
public enum YsojAPI {

    // MARK: - Capabilities

    /// What this server can actually do, fetched once on connect.
    ///
    /// **Never gate a feature on `ysojVersion`.** Two installs on the same version differ
    /// by whether a TMDB key was entered and whether a download engine exists — the same
    /// reason `PublicSystemInfo.version` is untrustworthy for this (it is the real
    /// Jellyfin's, forwarded truthfully). Gate on the flags.
    public struct Capabilities: Decodable, Sendable, Equatable {
        public let ysojVersion: String
        public let serverName: String
        /// Whether *this session* is the owner. Reported, not enforced — every endpoint
        /// still checks for itself.
        public let owner: Bool
        public let features: Features

        /// Every feature is optional on the wire. The document has grown keys twice
        /// already (`profiles`, `wan`, `remote`), and a renamed or dropped one must hide
        /// *that* feature, not make the whole capabilities decode fail and take Discover
        /// down with it. Absent reads as "not offered".
        public struct Features: Decodable, Sendable, Equatable {
            public let discover: Discover?
            public let downloads: Downloads?
            public let libraryOverrides: LibraryOverrides?
            /// Pairing a phone to this server's TVs. Absent on servers predating it.
            public let remote: Remote?
        }

        public struct Discover: Decodable, Sendable, Equatable {
            public let enabled: Bool
            public let search: Bool
            public let sources: [Source]
            /// False when no TMDB key is configured — the client says *why* Discover has
            /// no films rather than showing an empty shelf.
            public let hasMovieSource: Bool
        }

        public struct Source: Decodable, Sendable, Equatable, Identifiable {
            public let id: String
            public let name: String
            /// Added by the server after the first cut; absent means "not reported",
            /// which is treated as reachable rather than as a failure.
            public let reachable: Bool?
            public let lastError: String?

            public var isUsable: Bool { reachable ?? true }
        }

        public struct Downloads: Decodable, Sendable, Equatable {
            public let enabled: Bool
            public let engine: String
            /// **The flag that must never be missed.** A stub job reports real progress
            /// and fetches nothing; the download centre shows a banner when this is true.
            public let simulated: Bool
            public let granularity: [String]
            public let pollSeconds: Int?
            /// Whether `/ysoj/downloads/search` exists here — a release search over the
            /// trackers. Absent on servers predating it. Whether the trackers' satellite
            /// is *running* is reported by that endpoint per search, not here: the
            /// capabilities document is read once on connect and a service can stop
            /// between then and the press.
            public let search: Bool?
            /// The category ids the search accepts; `ReleaseCategory` names them.
            public let searchCategories: [String]?
        }

        public struct LibraryOverrides: Decodable, Sendable, Equatable {
            public let enabled: Bool
        }

        /// The LAN-remote feature: whether a phone may pair with a TV here, and how often
        /// it should ask whether one is looking for it.
        public struct Remote: Decodable, Sendable, Equatable {
            public let enabled: Bool
            public let pollSeconds: Int?
            public let beaconSeconds: Int?
        }

        /// The one question the nav asks: should a Discover entry exist at all?
        public var offersDiscover: Bool { features.discover?.enabled ?? false }
        /// Films need a TMDB key on the server; without one Discover is television and
        /// anime only, and the screen says so rather than looking short of films.
        public var hasMovieSource: Bool { features.discover?.hasMovieSource ?? false }
        /// Release search is the owner's: the rows carry magnets, and spending the
        /// household's bandwidth on what they find is the owner's call — the same rule
        /// that keeps a member from starting a download.
        public var offersReleaseSearch: Bool {
            owner && (features.downloads?.search ?? false)
        }
        /// The categories this server's search accepts, as the client's own enum, in the
        /// enum's order. A server that names none gets all four; one that names an id
        /// this client does not know simply does not offer it.
        public var releaseCategories: [ReleaseCategory] {
            guard let ids = features.downloads?.searchCategories else {
                return ReleaseCategory.allCases
            }
            return ReleaseCategory.allCases.filter { ids.contains($0.rawValue) }
        }
    }

    // MARK: - Discover

    /// Whether a discovered title is already on the user's own server.
    ///
    /// `known` is false when the library index could not be read — the shelf is served
    /// unannotated rather than not at all, so `present: false` there means "we could not
    /// check", not "we checked and it is absent".
    public struct LibraryPresence: Decodable, Sendable, Equatable {
        public let present: Bool
        public let jellyfinItemId: String?
        public let known: Bool

        public static let unknown = LibraryPresence(present: false, jellyfinItemId: nil, known: false)

        public init(present: Bool, jellyfinItemId: String?, known: Bool) {
            self.present = present
            self.jellyfinItemId = jellyfinItemId
            self.known = known
        }
    }

    /// A poster on a Discover shelf.
    public struct DiscoverItem: Decodable, Sendable, Equatable, Identifiable {
        public let ref: String
        public let title: String
        public let type: String
        public let year: Int?
        public let rating: Double?
        public let genres: [String]
        public let overview: String
        public let posterURLString: String?
        public let backdropURLString: String?
        public let sourceId: String
        public let sourceName: String
        public let inLibrary: LibraryPresence?

        public var id: String { ref }
        public var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
        public var backdropURL: URL? { backdropURLString.flatMap(URL.init(string:)) }
        public var isSeries: Bool { type == "series" }
        public var alreadyOwned: Bool { inLibrary?.present ?? false }

        private enum CodingKeys: String, CodingKey {
            case ref, title, type, year, rating, genres, overview, sourceId, sourceName, inLibrary
            case posterURLString = "posterURL"
            case backdropURLString = "backdropURL"
        }
    }

    public struct DiscoverPerson: Decodable, Sendable, Equatable {
        public let name: String
        public let role: String
        public let imageURLString: String?

        public var imageURL: URL? { imageURLString.flatMap(URL.init(string:)) }

        private enum CodingKeys: String, CodingKey {
            case name, role
            case imageURLString = "imageURL"
        }
    }

    /// A season that can be downloaded. Episode *numbers* are 1...episodeCount — the
    /// server validates a requested number against this before making a job, so a
    /// "download episode 99" of a 13-episode season fails at the plan, not an hour later.
    public struct DiscoverSeason: Decodable, Sendable, Equatable, Identifiable {
        public let seasonNumber: Int
        public let name: String
        public let episodeCount: Int
        public let year: Int?
        public let overview: String
        public let posterURLString: String?

        public var id: Int { seasonNumber }
        public var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
        /// Season 0 is specials — real, but never what "download everything" means.
        public var isSpecials: Bool { seasonNumber == 0 }

        private enum CodingKeys: String, CodingKey {
            case seasonNumber, name, episodeCount, year, overview
            case posterURLString = "posterURL"
        }
    }

    /// A trailer, which is a **link** and nothing more.
    ///
    /// TMDB hands over a YouTube key alongside the rest of the detail, so this is free.
    /// Playing it in-app was tried and abandoned: resolving the page to a stream meant
    /// yt-dlp, a dependency that breaks whenever YouTube changes something, for a video
    /// that is somebody else's either way. So the client opens the link — embedded on
    /// iOS, handed to the YouTube app on tvOS.
    public struct Trailer: Decodable, Sendable, Equatable, Identifiable {
        public let site: String
        public let key: String
        public let name: String
        public let type: String
        public let official: Bool?
        public let publishedAt: String?
        public let urlString: String?

        public var id: String { "\(site):\(key)" }
        public var isYouTube: Bool { site.caseInsensitiveCompare("YouTube") == .orderedSame }

        /// The page, for handing to a browser or the YouTube app.
        public var pageURL: URL? {
            if let urlString, let url = URL(string: urlString) { return url }
            return isYouTube ? URL(string: "https://www.youtube.com/watch?v=\(key)") : nil
        }

        /// What the in-app web view loads. `youtube-nocookie` because this is somebody
        /// watching a trailer inside a media app, not visiting YouTube.
        public var embedURL: URL? {
            guard isYouTube else { return nil }
            return URL(string:
                "https://www.youtube-nocookie.com/embed/\(key)?autoplay=1&playsinline=1&rel=0")
        }

        /// Deep link into the YouTube app — the only route on tvOS, which has no browser.
        public var appURL: URL? {
            isYouTube ? URL(string: "youtube://\(key)") : nil
        }

        private enum CodingKeys: String, CodingKey {
            case site, key, name, type, official, publishedAt
            case urlString = "url"
        }
    }

    public struct DiscoverDetail: Decodable, Sendable, Equatable {
        public let ref: String
        public let title: String
        public let type: String
        public let year: Int?
        public let overview: String
        public let genres: [String]
        public let runtimeMinutes: Int?
        public let rating: Double?
        public let certification: String?
        public let posterURLString: String?
        public let backdropURLString: String?
        public let cast: [DiscoverPerson]
        public let seasons: [DiscoverSeason]
        public let episodeCount: Int?
        public let status: String?
        public let sourceId: String
        public let sourceName: String
        public let sourceURLString: String?
        public let externalIds: [String: String]
        public let inLibrary: LibraryPresence?
        /// Optional so a server predating the field still decodes.
        public let trailers: [Trailer]?

        public var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
        public var backdropURL: URL? { backdropURLString.flatMap(URL.init(string:)) }
        public var sourceURL: URL? { sourceURLString.flatMap(URL.init(string:)) }
        public var isSeries: Bool { type == "series" }
        public var alreadyOwned: Bool { inLibrary?.present ?? false }
        /// Specials are offered explicitly or not at all — never folded into "everything".
        public var downloadableSeasons: [DiscoverSeason] { seasons.filter { !$0.isSpecials } }

        /// The one trailer worth offering. Exactly one, never a list — choosing between
        /// "Official Trailer", "Trailer 2" and "Teaser" is not a decision anyone wants to
        /// make from a sofa. The server already sorts them, so this is just the first
        /// that the client can actually open.
        public var bestTrailer: Trailer? {
            (trailers ?? []).first { $0.pageURL != nil }
        }

        private enum CodingKeys: String, CodingKey {
            case ref, title, type, year, overview, genres, runtimeMinutes, rating
            case certification, cast, seasons, episodeCount, status
            case sourceId, sourceName, externalIds, inLibrary, trailers
            case posterURLString = "posterURL"
            case backdropURLString = "backdropURL"
            case sourceURLString = "sourceURL"
        }
    }

    public struct DiscoverCategory: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let kind: String
        public let sourceId: String
    }

    // MARK: - Downloads

    /// The granularity requirement, made explicit: a film, one episode, one season, or
    /// the whole show.
    public struct DownloadScope: Codable, Sendable, Equatable, Hashable {
        public let kind: Kind
        public let seasonNumber: Int?
        public let episodeNumbers: [Int]?

        public enum Kind: String, Codable, Sendable, Equatable, Hashable {
            case movie, episode, season, series
        }

        public init(kind: Kind, seasonNumber: Int? = nil, episodeNumbers: [Int]? = nil) {
            self.kind = kind
            self.seasonNumber = seasonNumber
            self.episodeNumbers = episodeNumbers
        }

        public static let movie = DownloadScope(kind: .movie)
        public static let wholeSeries = DownloadScope(kind: .series)
        public static func season(_ number: Int) -> DownloadScope {
            DownloadScope(kind: .season, seasonNumber: number)
        }
        public static func episode(season: Int, number: Int) -> DownloadScope {
            DownloadScope(kind: .episode, seasonNumber: season, episodeNumbers: [number])
        }
        public static func episodes(season: Int, numbers: [Int]) -> DownloadScope {
            DownloadScope(kind: .episode, seasonNumber: season, episodeNumbers: numbers)
        }
    }

    /// What *would* be downloaded, costed — shown on a confirm sheet. Single-use and
    /// expiring: confirming twice is a 409, and a size quoted an hour ago is not a size
    /// worth committing disk to.
    public struct DownloadPlan: Decodable, Sendable, Equatable, Identifiable {
        public let planId: String
        public let ref: String
        public let title: String
        public let subtitle: String?
        public let type: String
        public let year: Int?
        public let posterURLString: String?
        public let scope: DownloadScope
        public let episodeCount: Int
        public let estimatedBytes: Int64
        public let quality: String?
        public let candidateCount: Int
        /// Already-in-library, a simulated engine, an enormous series — shown verbatim.
        public let warnings: [String]
        public let inLibrary: LibraryPresence?
        public let engine: String
        public let expiresAt: Double

        public var id: String { planId }
        public var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
        public var isSimulated: Bool { engine == "stub" }

        private enum CodingKeys: String, CodingKey {
            case planId, ref, title, subtitle, type, year, scope, episodeCount
            case estimatedBytes, quality, candidateCount, warnings, inLibrary, engine, expiresAt
            case posterURLString = "posterURL"
        }
    }

    /// A row in the download centre.
    public struct DownloadJob: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let ref: String
        public let title: String
        public let subtitle: String?
        public let posterURLString: String?
        public let scope: DownloadScope
        public let state: State
        public let progress: Double
        public let bytesTotal: Int64
        public let bytesDownloaded: Int64
        public let speedBytesPerSecond: Int64
        public let etaSeconds: Int?
        public let seeds: Int?
        public let peers: Int?
        public let message: String?
        public let engine: String
        public let landedItemIds: [String]
        public let createdAt: Double
        public let updatedAt: Double
        public let finishedAt: Double?
        public let isActive: Bool

        /// Decoded with an `unknown` fallback so a server that grows a state cannot make
        /// the whole download centre fail to decode.
        public enum State: String, Decodable, Sendable, Equatable {
            case searching, queued, downloading, paused, importing, landed, failed, cancelled
            case unknown

            public init(from decoder: any Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = State(rawValue: raw) ?? .unknown
            }

            public var isTerminal: Bool {
                switch self {
                case .landed, .failed, .cancelled: return true
                default: return false
                }
            }

            /// Whether a percentage is meaningful yet. "Searching" has no denominator.
            public var showsProgress: Bool {
                switch self {
                case .downloading, .paused, .importing, .landed: return true
                default: return false
                }
            }
        }

        public var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
        public var isSimulated: Bool { engine == "stub" }
        public var canPause: Bool { state == .downloading }
        public var canResume: Bool { state == .paused }

        private enum CodingKeys: String, CodingKey {
            case id, ref, title, subtitle, scope, state, progress, bytesTotal, bytesDownloaded
            case speedBytesPerSecond, etaSeconds, seeds, peers, message, engine
            case landedItemIds, createdAt, updatedAt, finishedAt, isActive
            case posterURLString = "posterURL"
        }
    }

    public struct DownloadList: Decodable, Sendable, Equatable {
        public let jobs: [DownloadJob]
        public let activeCount: Int
        public let engine: String
        /// False for a member — they may watch the centre but not start or cancel.
        public let canManage: Bool
    }

    // MARK: - Release search

    /// What to search the trackers for. Mirrors the server's own list; a category the
    /// server does not name in its capabilities is not offered.
    public enum ReleaseCategory: String, CaseIterable, Sendable, Equatable, Hashable {
        case all, movies, tv, anime

        public var label: String {
            switch self {
            case .all: return "Everything"
            case .movies: return "Movies"
            case .tv: return "TV"
            case .anime: return "Anime"
            }
        }
    }

    /// One release a tracker offers — a row on the Find-a-release screen.
    ///
    /// `fileCountExact` is the honest half of `fileCount`: only one tracker reports a real
    /// count, and for the others it is guessed from an episode range in the release name,
    /// so it is rendered as an approximation. A row that shows a guessed count as exact
    /// is lying about how many episodes are in the pack.
    public struct Release: Decodable, Sendable, Equatable, Identifiable {
        public let name: String
        public let infoHash: String
        public let magnet: String
        public let sizeBytes: Int64
        public let seeders: Int
        public let leechers: Int
        public let fileCount: Int
        public let fileCountExact: Bool
        public let quality: String
        public let qualityTier: Int
        public let category: String
        public let provider: String
        public let sourceId: String
        public let score: [Int]

        public var id: String { infoHash }

        /// "12 files", "≈12 files", or nil when nothing is known.
        public var fileCountLabel: String? {
            guard fileCount > 0 else { return nil }
            let noun = fileCount == 1 ? "file" : "files"
            return fileCountExact ? "\(fileCount) \(noun)" : "≈\(fileCount) \(noun)"
        }

        /// Three bands at the thresholds the server's own page colours by. A release
        /// nobody is seeding is not a release; the row says so before anyone waits on it.
        public enum SeedHealth: Sendable, Equatable {
            case healthy, thin, dead
        }

        public var seedHealth: SeedHealth {
            if seeders >= 50 { return .healthy }
            if seeders >= 5 { return .thin }
            return .dead
        }
    }

    /// How one tracker answered. A tracker that failed contributes no rows and says so
    /// here, so the screen can name what was down instead of quietly showing fewer rows.
    public struct ReleaseSource: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let ok: Bool
        public let rows: Int
        public let tookMs: Int
        /// The failure's class name when `ok` is false — "ReadTimeout", "ConnectError".
        public let detail: String?
    }

    /// Whether the library already has something by the searched name. Checked once per
    /// query, not per row, and only ever a warning.
    public struct ReleaseLibraryMatch: Decodable, Sendable, Equatable {
        public let present: Bool
        public let jellyfinItemId: String?
    }

    /// The answer to one search: ranked rows, how each tracker did, and whether the
    /// query names something already owned.
    public struct ReleaseSearch: Decodable, Sendable, Equatable {
        public let query: String
        /// What was actually searched for — a leading `~` is stripped and forces anime.
        public let normalized: String
        public let category: String
        public let results: [Release]
        public let sources: [ReleaseSource]
        public let cached: Bool
        public let tookMs: Int
        public let inLibrary: ReleaseLibraryMatch?

        public var failedSources: [ReleaseSource] { sources.filter { !$0.ok } }
        public var isAlreadyInLibrary: Bool { inLibrary?.present ?? false }
    }

    // MARK: - Library overrides

    /// A library's NSFW / anime classification, held by the server so every device in the
    /// house agrees. The client keeps its local `UserDefaults` store as the fallback for a
    /// plain Jellyfin, which has no opinion about either.
    public struct LibraryOverride: Codable, Sendable, Equatable, Identifiable {
        public let libraryId: String
        public let displayName: String?
        public let isNSFW: Bool
        public let isAnime: Bool

        public var id: String { libraryId }

        public init(libraryId: String, displayName: String? = nil,
                    isNSFW: Bool, isAnime: Bool) {
            self.libraryId = libraryId
            self.displayName = displayName
            self.isNSFW = isNSFW
            self.isAnime = isAnime
        }
    }

    // MARK: - Envelopes

    struct CategoriesResponse: Decodable, Sendable {
        let categories: [DiscoverCategory]
    }

    struct CatalogResponse: Decodable, Sendable {
        let items: [DiscoverItem]
    }

    struct OverridesResponse: Decodable, Sendable {
        let overrides: [LibraryOverride]
    }

    struct PlanRequest: Encodable, Sendable {
        let ref: String
        let scope: DownloadScope
    }

    struct ConfirmRequest: Encodable, Sendable {
        let planId: String
    }
}
