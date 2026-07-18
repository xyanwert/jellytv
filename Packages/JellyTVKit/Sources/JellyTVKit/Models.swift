import Foundation

extension JellyfinAPI.JellyfinItem {

    public func toContinueWatchingItem(libraryCategory: MetaCategory?, imageBaseURL: URL? = nil) -> ContinueWatchingItem? {
        guard let name else { return nil }
        let progress = playbackProgress()
        let episodeLabel: String
        if type == "Episode", let indexNumber {
            let seasonPart = parentIndexNumber.map { "S\($0)" } ?? ""
            episodeLabel = "\(seasonPart) · E\(indexNumber) — \"\(name)\""
        } else if type == "Movie" {
            episodeLabel = "Movie"
        } else {
            episodeLabel = name
        }

        return ContinueWatchingItem(
            id: id,
            title: seriesName ?? name,
            episodeLabel: episodeLabel,
            remaining: remainingTimeString(),
            progress: progress,
            image: primaryImageURLString(imageBaseURL),
            artwork: artworkGradient(libraryCategory: libraryCategory)
        )
    }

    public func toMediaItem(libraryCategory: MetaCategory?, imageBaseURL: URL? = nil) -> MediaItem {
        let genrePart = genres?.first ?? ""
        let meta: String
        switch type {
        case "Movie": meta = genrePart.isEmpty ? "Movie" : "Movie · \(genrePart)"
        case "Series": meta = genrePart.isEmpty ? "Series" : "Series · \(genrePart)"
        default: meta = type ?? "Item"
        }

        return MediaItem(
            id: id,
            title: name ?? "Unknown",
            meta: meta,
            image: primaryImageURLString(imageBaseURL),
            artwork: artworkGradient(libraryCategory: libraryCategory),
            rating: communityRating,
            year: productionYear.map(String.init),
            certification: officialRating,
            synopsis: overview,
            // A wide, high-resolution image for full-bleed use (the Movies
            // library's selected-item backdrop): the real Backdrop when the
            // item has one, else a high-res Primary — not the 500px poster
            // `image` carries for the grid tiles.
            backdropImage: backdropImageURLString(imageBaseURL, maxWidth: 1920)
        )
    }

    public func toHeroFeature(libraryCategory: MetaCategory?, imageBaseURL: URL? = nil) -> HeroFeature {
        let isEpisode = type == "Episode"
        let episodeLabel: String
        if isEpisode, let indexNumber {
            let seasonPart = parentIndexNumber.map { "S\($0)" } ?? ""
            let episodeName = name ?? ""
            episodeLabel = "\(seasonPart) · E\(indexNumber) — \"\(episodeName)\""
        } else {
            episodeLabel = ""
        }

        let resumeLabel: String
        if isEpisode, let indexNumber {
            resumeLabel = "Resume · E\(indexNumber)"
        } else if let userData, let ticks = userData.playbackPositionTicks, ticks > 0 {
            resumeLabel = "Resume"
        } else {
            resumeLabel = "Play"
        }

        // The real certification (TV-MA, R, …) doesn't mean much for adult
        // content, and Jellyfin metadata providers rarely tag it usefully
        // there anyway — swap in a category-appropriate label instead.
        let certification: String
        switch libraryCategory {
        case .hentai: certification = "HENTAI"
        case .porn: certification = "XXX"
        default: certification = officialRating ?? ""
        }

        return HeroFeature(
            id: id,
            image: backdropImageURLString(imageBaseURL) ?? "",
            eyebrow: genres?.first.map { "Featured · \($0)" } ?? "Featured",
            title: name ?? "Unknown",
            certification: certification,
            year: productionYear.map(String.init) ?? "",
            genre: genres?.joined(separator: " ") ?? "",
            episode: episodeLabel,
            qualityBadge: "",
            synopsis: overview ?? "",
            resumeLabel: resumeLabel,
            artwork: artworkGradient(libraryCategory: libraryCategory)
        )
    }

    /// A full `Movie` from a detail-fetched item (cast, ratings, tagline,
    /// studios, real director, IMDb id). `externalRatings`/`awards` stay nil
    /// here — they're merged in later from OMDb.
    public func toMovie(libraryCategory: MetaCategory?, imageBaseURL: URL? = nil,
                        moreLikeThis: [MediaItem] = []) -> Movie {
        let cast = castMembers(imageBaseURL: imageBaseURL)
        let studioNames = (studios ?? []).compactMap(\.name)
        let genrePart = genres?.first ?? ""
        return Movie(
            id: id,
            title: name ?? "Unknown",
            studioLine: studioNames.first.map { "Feature Film // \($0)" } ?? "Feature Film",
            rating: communityRating.map { String(format: "%.1f", $0) } ?? "",
            certification: officialRating ?? "",
            runtime: runTimeTicks.map(formatTicks) ?? "",
            director: (people ?? []).first { $0.type == "Director" }?.name ?? "",
            year: productionYear.map(String.init) ?? "",
            genreLabel: "Movies / \(genrePart.isEmpty ? "Film" : genrePart)",
            synopsis: overview ?? "",
            keyArt: backdropImageURLString(imageBaseURL, maxWidth: 1920),
            artwork: artworkGradient(libraryCategory: libraryCategory),
            resumeLabel: name ?? "",
            resumeProgress: playbackProgress(),
            resumeRemaining: remainingTimeString(),
            starring: cast.map(\.name).joined(separator: ", "),
            audioLine: "",
            moreLikeThis: moreLikeThis,
            cast: cast,
            tagline: taglines?.first,
            studios: studioNames,
            communityRating: communityRating,
            criticRating: criticRating,
            imdbId: providerIds?["Imdb"]
        )
    }

    /// Enriches an existing `Show` (which already carries its sample/real
    /// seasons) with real cast, ratings, tagline, studios, and IMDb id from a
    /// detail-fetched item. Season/episode data is out of this mapper's scope.
    public func enrich(_ base: Show, imageBaseURL: URL? = nil) -> Show {
        var show = base
        show.cast = castMembers(imageBaseURL: imageBaseURL)
        show.tagline = taglines?.first
        show.studios = (studios ?? []).compactMap(\.name)
        show.communityRating = communityRating
        show.criticRating = criticRating
        show.imdbId = providerIds?["Imdb"]
        if let overview, !overview.isEmpty { show.synopsis = overview }
        return show
    }

    /// Actors from `people` (billing order), capped, with headshot URLs.
    private func castMembers(imageBaseURL: URL?) -> [CastMember] {
        (people ?? [])
            .filter { $0.type == "Actor" }
            .prefix(12)
            .enumerated()
            .map { index, person in
                CastMember(
                    id: person.id ?? "\(index)",
                    name: person.name ?? "Unknown",
                    role: person.role,
                    imageURL: personImageURLString(person, base: imageBaseURL),
                    isLead: index == 0
                )
            }
    }

    /// Headshot URL for a person (`/Items/{personId}/Images/Primary`), or nil.
    private func personImageURLString(_ person: JellyfinAPI.JellyfinPerson, base: URL?) -> String? {
        guard let base, let pid = person.id, let tag = person.primaryImageTag else { return nil }
        return JellyfinAPI.imageURL(baseURL: base, itemId: pid, imageType: "Primary",
                                    tag: tag, maxWidth: 240)?.absoluteString
    }

    private func playbackProgress() -> Double {
        guard let userData, let pos = userData.playbackPositionTicks, pos > 0,
              let total = runTimeTicks, total > 0 else { return 0 }
        return min(1.0, Double(pos) / Double(total))
    }

    private func playbackProgressFormatted() -> String {
        let pct = Int(playbackProgress() * 100)
        return "\(pct)%"
    }

    private func remainingTimeString() -> String {
        guard let userData, let pos = userData.playbackPositionTicks, pos > 0,
              let total = runTimeTicks, total > 0 else {
            if let total = runTimeTicks, total > 0 {
                return formatTicks(total)
            }
            return ""
        }
        let remainingTicks = total - pos
        return formatTicks(remainingTicks)
    }

    private func formatTicks(_ ticks: Int64) -> String {
        let totalSeconds = Double(ticks) / 10_000_000
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }

    private func imageTag(for type: String) -> String? {
        imageTags?[type]
    }

    /// Absolute Primary-image URL (poster / episode still), or nil without a
    /// base URL or tag. Views detect the `http` prefix to load it remotely.
    private func primaryImageURLString(_ base: URL?) -> String? {
        guard let base, let tag = imageTags?["Primary"] else { return nil }
        return JellyfinAPI.imageURL(baseURL: base, itemId: id, imageType: "Primary",
                                    tag: tag, maxWidth: 500)?.absoluteString
    }

    /// Absolute Backdrop-image URL for the hero still — falls back to a parent
    /// (series) backdrop for episodes, then to the item's poster (at the same
    /// requested width, not the small grid-poster size).
    private func backdropImageURLString(_ base: URL?, maxWidth: Int = 1280) -> String? {
        guard let base else { return nil }
        if let tag = backdropImageTags?.first {
            return JellyfinAPI.imageURL(baseURL: base, itemId: id, imageType: "Backdrop",
                                        tag: tag, index: 0, maxWidth: maxWidth)?.absoluteString
        }
        if let pid = parentBackdropItemId, let tag = parentBackdropImageTags?.first {
            return JellyfinAPI.imageURL(baseURL: base, itemId: pid, imageType: "Backdrop",
                                        tag: tag, index: 0, maxWidth: maxWidth)?.absoluteString
        }
        if let tag = imageTags?["Primary"] {
            return JellyfinAPI.imageURL(baseURL: base, itemId: id, imageType: "Primary",
                                        tag: tag, maxWidth: maxWidth)?.absoluteString
        }
        return nil
    }

    private func artworkGradient(libraryCategory: MetaCategory?) -> Artwork {
        let hash = id.hashValue
        let hue = Double(abs(hash) % 360)
        let hue2 = Double(abs(hash / 7) % 360)
        return Artwork.gradient(l: 0.44, c: 0.11, hue: hue, hue2: hue2)
    }
}

extension JellyfinAPI.JellyfinUserView {
    public func toLibrary(classifier: (String?, String) -> MetaCategory?) -> Library? {
        guard let category = classifier(collectionType, name) else { return nil }
        return Library(
            id: id,
            name: name,
            isAdult: category.isNSFW,
            itemCount: ""
        )
    }
}

/// A poster/tile item (movie or series entry).
public struct MediaItem: Equatable, Sendable, Hashable, Identifiable {
    /// Whether the item is a single video or a collection — drives which detail
    /// screen it opens.
    public enum Kind: String, Sendable { case movie, series }

    public let id: String
    public var title: String
    /// Secondary line, e.g. "Movie · Thriller".
    public var meta: String
    /// Optional artwork image asset name; falls back to `artwork` gradient.
    public var image: String?
    public var artwork: Artwork
    /// Community/critic rating (0–10), when the server has one.
    public var rating: Double?
    /// Production year, e.g. "2026".
    public var year: String?
    /// Certification, e.g. "PG-13".
    public var certification: String?
    /// Plot overview, when the server has one.
    public var synopsis: String?
    /// A wide, high-resolution image for full-bleed use (e.g. the Movies
    /// library's selected-item backdrop) — distinct from `image`, which is a
    /// small poster sized for grid tiles.
    public var backdropImage: String?

    public init(id: String, title: String, meta: String, image: String? = nil, artwork: Artwork,
                rating: Double? = nil, year: String? = nil, certification: String? = nil,
                synopsis: String? = nil, backdropImage: String? = nil) {
        self.id = id
        self.title = title
        self.meta = meta
        self.image = image
        self.artwork = artwork
        self.rating = rating
        self.year = year
        self.certification = certification
        self.synopsis = synopsis
        self.backdropImage = backdropImage
    }

    /// Movie vs series, derived from the metadata line ("Movie · …" → movie).
    public var kind: Kind {
        meta.lowercased().hasPrefix("movie") ? .movie : .series
    }
}

/// A user library shown as a chip in the Home libraries row and as a row in the
/// rail's Libraries submenu.
public struct Library: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var isAdult: Bool
    /// Display-ready item count, e.g. `"428"` or `"1.2k"`.
    public var itemCount: String

    public init(id: String, name: String, isAdult: Bool = false, itemCount: String) {
        self.id = id
        self.name = name
        self.isAdult = isAdult
        self.itemCount = itemCount
    }
}

/// A featured hero slide. The Home hero rotates through a list of these.
public struct HeroFeature: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var image: String          // backdrop asset name
    public var eyebrow: String        // "Featured · New Season"
    public var title: String          // "The Deep Signal"
    public var certification: String  // "TV-MA"
    public var year: String           // "2026"
    public var genre: String          // "Sci-Fi Drama"
    public var episode: String        // "S3 · E4 — “Trench”"
    public var qualityBadge: String   // "4K HDR"
    public var synopsis: String
    public var resumeLabel: String    // "Resume · E4"
    public var artwork: Artwork

    public init(id: String, image: String, eyebrow: String, title: String,
                certification: String, year: String, genre: String, episode: String,
                qualityBadge: String, synopsis: String, resumeLabel: String, artwork: Artwork) {
        self.id = id
        self.image = image
        self.eyebrow = eyebrow
        self.title = title
        self.certification = certification
        self.year = year
        self.genre = genre
        self.episode = episode
        self.qualityBadge = qualityBadge
        self.synopsis = synopsis
        self.resumeLabel = resumeLabel
        self.artwork = artwork
    }
}

/// An in-progress item in the Continue Watching row.
public struct ContinueWatchingItem: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var episodeLabel: String   // "S3 · E4 — Trench" or "Movie"
    public var remaining: String      // "31 min"
    /// Watched fraction, 0...1.
    public var progress: Double
    /// Optional artwork image asset name; falls back to `artwork` gradient.
    public var image: String?
    public var artwork: Artwork

    public init(id: String, title: String, episodeLabel: String, remaining: String,
                progress: Double, image: String? = nil, artwork: Artwork) {
        self.id = id
        self.title = title
        self.episodeLabel = episodeLabel
        self.remaining = remaining
        self.progress = progress
        self.image = image
        self.artwork = artwork
    }
}

/// The signed-in user shown in the top bar and Settings panel.
public struct UserProfile: Equatable, Sendable, Hashable {
    public var name: String     // "Marina"
    public var email: String    // "marina@home.local"
    public var role: String     // "Administrator"

    public init(name: String, email: String, role: String) {
        self.name = name
        self.email = email
        self.role = role
    }

    /// First character, used for the avatar.
    public var initial: String { String(name.prefix(1)) }
}

/// The connected Jellyfin server, shown in the Settings → Server row.
public struct ServerStatus: Equatable, Sendable, Hashable {
    public var name: String     // "reef.local"
    public var version: String  // "v10.9.2"
    public var isConnected: Bool

    public init(name: String, version: String, isConnected: Bool) {
        self.name = name
        self.version = version
        self.isConnected = isConnected
    }
}

/// A category row in the Settings screen's category list.
public struct SettingsCategory: Equatable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case playback, subtitles, audio, home, appearance, parental, metadata, server, account, about
    }

    public var kind: Kind
    public var label: String
    public var description: String

    public var id: String { kind.rawValue }

    public init(kind: Kind, label: String, description: String) {
        self.kind = kind
        self.label = label
        self.description = description
    }
}

/// A toggle row in the Settings Playback detail pane.
public struct PlaybackToggle: Equatable, Sendable, Hashable, Identifiable {
    public var id: String { label }
    public var label: String
    public var description: String
    public var isOnByDefault: Bool

    public init(label: String, description: String, isOnByDefault: Bool) {
        self.label = label
        self.description = description
        self.isOnByDefault = isOnByDefault
    }
}

/// One episode in a season's strip on the Show view.
public struct Episode: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var number: Int
    public var title: String
    public var runtime: String        // "49m"
    public var isCurrent: Bool        // the resume/NOW episode
    public var image: String?         // artwork asset name; falls back to `artwork`
    public var artwork: Artwork

    public init(id: String, number: Int, title: String, runtime: String,
                isCurrent: Bool = false, image: String? = nil, artwork: Artwork) {
        self.id = id
        self.number = number
        self.title = title
        self.runtime = runtime
        self.isCurrent = isCurrent
        self.image = image
        self.artwork = artwork
    }

    /// Zero-padded episode number, e.g. "04".
    public var numberLabel: String { String(format: "%02d", number) }
}

/// A season of a show: a named group of episodes.
public struct Season: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var number: Int
    public var name: String            // "Season 3" / "Specials"
    public var episodes: [Episode]

    public init(id: String, number: Int, name: String, episodes: [Episode]) {
        self.id = id
        self.number = number
        self.name = name
        self.episodes = episodes
    }

    /// Short segmented-control label, e.g. "S03" / "SPECIALS".
    public var shortLabel: String { number == 0 ? "SPECIALS" : String(format: "S%02d", number) }
}

/// A cast/crew member with an optional headshot. `imageURL` is a remote
/// Jellyfin person image; when nil the UI shows a monogram of `initials`.
public struct CastMember: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var role: String?        // character name, for actors
    public var imageURL: String?    // headshot URL; falls back to a monogram
    public var isLead: Bool

    public init(id: String, name: String, role: String? = nil,
                imageURL: String? = nil, isLead: Bool = false) {
        self.id = id
        self.name = name
        self.role = role
        self.imageURL = imageURL
        self.isLead = isLead
    }

    /// Up-to-two-letter monogram for the headshot fallback.
    public var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? (parts.last?.first).map(String.init) ?? "" : ""
        return (first + last).uppercased()
    }
}

/// External aggregator ratings (from OMDb) — distinct from Jellyfin's own
/// community/critic numbers so the UI can prefer these when available.
public struct ExternalRatings: Equatable, Sendable, Hashable {
    public var imdbRating: Double?      // 0–10
    public var rottenTomatoes: Int?     // 0–100 (%)
    public var metacritic: Int?         // 0–100

    public init(imdbRating: Double? = nil, rottenTomatoes: Int? = nil, metacritic: Int? = nil) {
        self.imdbRating = imdbRating
        self.rottenTomatoes = rottenTomatoes
        self.metacritic = metacritic
    }

    public var isEmpty: Bool { imdbRating == nil && rottenTomatoes == nil && metacritic == nil }
}

/// Awards summary, parsed from OMDb's free-text "Awards" field.
public struct MovieAwards: Equatable, Sendable, Hashable {
    public var oscarsWon: Int
    public var oscarNominations: Int
    public var wins: Int
    public var nominations: Int
    public var summary: String          // the raw OMDb string, for a tooltip/detail

    public init(oscarsWon: Int = 0, oscarNominations: Int = 0, wins: Int = 0,
                nominations: Int = 0, summary: String = "") {
        self.oscarsWon = oscarsWon
        self.oscarNominations = oscarNominations
        self.wins = wins
        self.nominations = nominations
        self.summary = summary
    }

    /// A short headline badge for the dossier, or nil when there's nothing
    /// worth calling out.
    public var badge: String? {
        if oscarsWon > 0 { return oscarsWon == 1 ? "★ ACADEMY AWARD WINNER" : "★ \(oscarsWon) OSCARS" }
        if oscarNominations > 0 { return oscarNominations == 1 ? "★ OSCAR NOMINEE" : "★ \(oscarNominations) OSCAR NOMS" }
        if wins > 0 { return "\(wins) WIN\(wins == 1 ? "" : "S")" }
        return nil
    }

    /// Parses OMDb's Awards string, e.g. "Won 2 Oscars. 15 wins & 30
    /// nominations total" or "Nominated for 3 Oscars. 5 wins & 12 nominations".
    /// Returns nil when there's nothing quantifiable to show.
    public static func parse(_ awards: String?) -> MovieAwards? {
        guard let awards, !awards.isEmpty, awards != "N/A" else { return nil }
        func firstInt(_ pattern: String) -> Int {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
            let range = NSRange(awards.startIndex..., in: awards)
            guard let m = re.firstMatch(in: awards, range: range), m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: awards) else { return 0 }
            return Int(awards[r]) ?? 0
        }
        let oscarsWon = firstInt(#"Won (\d+) Oscar"#)
        let oscarNoms = firstInt(#"Nominated for (\d+) Oscar"#)
        let wins = firstInt(#"(\d+) win"#)
        let noms = firstInt(#"(\d+) nomination"#)
        if oscarsWon == 0 && oscarNoms == 0 && wins == 0 && noms == 0 { return nil }
        return MovieAwards(oscarsWon: oscarsWon, oscarNominations: oscarNoms,
                           wins: wins, nominations: noms, summary: awards)
    }
}

/// A collection (series) shown on the Show view: spec-sheet metadata, a resume
/// point, and its seasons/episodes.
public struct Show: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var studioLine: String      // "Series 003 // Benthic Pictures"
    public var rating: String          // "8.9"
    public var certification: String   // "TV-MA"
    public var runSummary: String      // "3 seasons · 24 ep"
    public var createdBy: String       // "Mara Ellingsen"
    public var years: String           // "2023 – 2026"
    public var genreLabel: String      // spine text, "TV Shows / Sci-Fi Drama"
    public var techLine: String        // "4K · HDR · ATMOS"
    public var synopsis: String
    public var keyArt: String?         // artwork asset name; falls back to `artwork`
    public var artwork: Artwork
    public var resumeEpisodeLabel: String  // "S3 · E4 — Trench"
    public var resumeProgress: Double       // 0...1
    public var resumeRemaining: String      // "31:04 LEFT · 62%"
    public var seasons: [Season]
    // Enrichment (Jellyfin detail + OMDb) — all optional/defaulted so existing
    // call sites keep compiling.
    public var cast: [CastMember]
    public var tagline: String?
    public var studios: [String]
    public var communityRating: Double?     // IMDb-style 0–10
    public var criticRating: Double?        // Rotten Tomatoes-style 0–100
    public var imdbId: String?
    public var externalRatings: ExternalRatings?
    public var awards: MovieAwards?

    public init(id: String, title: String, studioLine: String, rating: String,
                certification: String, runSummary: String, createdBy: String,
                years: String, genreLabel: String, techLine: String, synopsis: String,
                keyArt: String? = nil, artwork: Artwork,
                resumeEpisodeLabel: String, resumeProgress: Double,
                resumeRemaining: String, seasons: [Season],
                cast: [CastMember] = [], tagline: String? = nil, studios: [String] = [],
                communityRating: Double? = nil, criticRating: Double? = nil,
                imdbId: String? = nil, externalRatings: ExternalRatings? = nil,
                awards: MovieAwards? = nil) {
        self.id = id
        self.title = title
        self.studioLine = studioLine
        self.rating = rating
        self.certification = certification
        self.runSummary = runSummary
        self.createdBy = createdBy
        self.years = years
        self.genreLabel = genreLabel
        self.techLine = techLine
        self.synopsis = synopsis
        self.keyArt = keyArt
        self.artwork = artwork
        self.resumeEpisodeLabel = resumeEpisodeLabel
        self.resumeProgress = resumeProgress
        self.resumeRemaining = resumeRemaining
        self.seasons = seasons
        self.cast = cast
        self.tagline = tagline
        self.studios = studios
        self.communityRating = communityRating
        self.criticRating = criticRating
        self.imdbId = imdbId
        self.externalRatings = externalRatings
        self.awards = awards
    }

    /// Index of the season containing the current/resume episode (or the last).
    public var currentSeasonIndex: Int {
        seasons.firstIndex { $0.episodes.contains(where: \.isCurrent) } ?? max(0, seasons.count - 1)
    }
}

/// A single-video title (feature film) shown on the Movie detail screen.
public struct Movie: Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var studioLine: String      // "Feature Film // Benthic Pictures"
    public var rating: String          // "8.6"
    public var certification: String   // "PG-13"
    public var runtime: String         // "2h 14m"
    public var director: String        // "Mara Ellingsen"
    public var year: String            // "2026"
    public var genreLabel: String      // spine text, "Movies / Thriller"
    public var synopsis: String
    public var keyArt: String?
    public var artwork: Artwork
    public var resumeLabel: String     // "Undertow"
    public var resumeProgress: Double
    public var resumeRemaining: String // "1:40:12 LEFT · 26%"
    public var starring: String        // "Ines Duval, Theo Marsh"
    public var audioLine: String       // "EN · FR · 12 subtitles"
    public var moreLikeThis: [MediaItem]
    // Enrichment (Jellyfin detail + OMDb) — all optional/defaulted so existing
    // call sites keep compiling.
    public var cast: [CastMember]
    public var tagline: String?
    public var studios: [String]
    public var communityRating: Double?     // IMDb-style 0–10
    public var criticRating: Double?        // Rotten Tomatoes-style 0–100
    public var imdbId: String?
    public var externalRatings: ExternalRatings?
    public var awards: MovieAwards?

    public init(id: String, title: String, studioLine: String, rating: String,
                certification: String, runtime: String, director: String, year: String,
                genreLabel: String, synopsis: String, keyArt: String? = nil, artwork: Artwork,
                resumeLabel: String, resumeProgress: Double, resumeRemaining: String,
                starring: String, audioLine: String, moreLikeThis: [MediaItem],
                cast: [CastMember] = [], tagline: String? = nil, studios: [String] = [],
                communityRating: Double? = nil, criticRating: Double? = nil,
                imdbId: String? = nil, externalRatings: ExternalRatings? = nil,
                awards: MovieAwards? = nil) {
        self.id = id
        self.title = title
        self.studioLine = studioLine
        self.rating = rating
        self.certification = certification
        self.runtime = runtime
        self.director = director
        self.year = year
        self.genreLabel = genreLabel
        self.synopsis = synopsis
        self.keyArt = keyArt
        self.artwork = artwork
        self.resumeLabel = resumeLabel
        self.resumeProgress = resumeProgress
        self.resumeRemaining = resumeRemaining
        self.starring = starring
        self.audioLine = audioLine
        self.moreLikeThis = moreLikeThis
        self.cast = cast
        self.tagline = tagline
        self.studios = studios
        self.communityRating = communityRating
        self.criticRating = criticRating
        self.imdbId = imdbId
        self.externalRatings = externalRatings
        self.awards = awards
    }
}
