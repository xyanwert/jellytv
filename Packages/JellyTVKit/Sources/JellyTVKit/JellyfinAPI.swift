import Foundation

/// Data-transfer types and helpers for the Jellyfin REST API.
///
/// Jellyfin (ASP.NET) serialises JSON in **PascalCase** (`ServerName`, `AccessToken`,
/// `Id`…), so every model maps its keys explicitly. A missing map silently fails
/// to decode — and in the auth path that turns a *valid* login into a rejected
/// one — which is exactly the class of bug these types (and their tests) exist to
/// prevent.
public enum JellyfinAPI {

    /// `GET /System/Info/Public` — unauthenticated reachability + identity.
    public struct PublicSystemInfo: Decodable, Equatable, Sendable {
        public let serverName: String?
        public let version: String?
        public let id: String?
        public let productName: String?

        enum CodingKeys: String, CodingKey {
            case serverName = "ServerName"
            case version = "Version"
            case id = "Id"
            case productName = "ProductName"
        }

        public init(serverName: String?, version: String?, id: String?, productName: String? = nil) {
            self.serverName = serverName
            self.version = version
            self.id = id
            self.productName = productName
        }

        /// True when the payload actually looks like a Jellyfin server.
        public var looksLikeJellyfin: Bool { id != nil || serverName != nil }
    }

    /// `POST /Users/AuthenticateByName` result.
    public struct AuthenticationResult: Decodable, Equatable, Sendable {
        public let accessToken: String
        public let user: User

        enum CodingKeys: String, CodingKey {
            case accessToken = "AccessToken"
            case user = "User"
        }

        public var userId: String { user.id }
    }

    /// A Jellyfin user, from `/Users` or nested in an auth result.
    public struct User: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
        }

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// `GET /Users/Me` — who the token belongs to, and what they may do.
    ///
    /// Only `IsAdministrator` is decoded, because only one question is being
    /// asked: **may this account edit item metadata?** Jellyfin gates
    /// `POST /Items/{id}` on `RequiresElevation`, so a non-admin user gets a
    /// 403 no matter how the request is shaped. Asking up front is what lets
    /// the UI say so instead of failing at the tap.
    public struct CurrentUser: Decodable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let isAdministrator: Bool

        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", policy = "Policy"
        }

        private struct Policy: Decodable {
            let isAdministrator: Bool?
            enum CodingKeys: String, CodingKey { case isAdministrator = "IsAdministrator" }
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            isAdministrator = (try c.decodeIfPresent(Policy.self, forKey: .policy))?.isAdministrator ?? false
        }

        public init(id: String, name: String, isAdministrator: Bool) {
            self.id = id
            self.name = name
            self.isAdministrator = isAdministrator
        }
    }

    /// `GET /Items/Filters` — the tag vocabulary actually in use under a
    /// parent. Shared shape with `/Items/Filters2`, which on 10.11.11 answers
    /// with an empty `Tags` array; see `JellyfinClient.fetchTagVocabulary`.
    ///
    /// There is no `/Tags` endpoint, whatever it looks like there should be:
    /// v1 assumed `/Tags?searchTerm=` existed and shipped a 404 (its commit
    /// `c838c0f`).
    public struct QueryFilters: Decodable, Equatable, Sendable {
        public let tags: [String]

        enum CodingKeys: String, CodingKey { case tags = "Tags" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        }

        public init(tags: [String]) { self.tags = tags }
    }

    /// Builds the `MediaBrowser` authorization header value sent on every request.
    /// `token` is empty for the initial `AuthenticateByName` call and set to the
    /// access token (or API key) afterwards.
    public static func authorizationHeader(token: String,
                                           client: String,
                                           device: String,
                                           deviceId: String,
                                           version: String) -> String {
        "MediaBrowser Token=\"\(token)\", Client=\"\(client)\", Device=\"\(device)\", DeviceId=\"\(deviceId)\", Version=\"\(version)\""
    }

    /// Absolute URL for an item's image. Jellyfin serves images unauthenticated,
    /// so this needs no token — `/Items/{id}/Images/{type}[/{index}]?tag=…`.
    public static func imageURL(baseURL: URL, itemId: String, imageType: String = "Primary",
                                tag: String? = nil, index: Int? = nil,
                                maxWidth: Int? = nil, maxHeight: Int? = nil, quality: Int = 90) -> URL? {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let base = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        let idxPart = index.map { "/\($0)" } ?? ""
        comps.path = base + "/Items/\(itemId)/Images/\(imageType)\(idxPart)"
        var q: [URLQueryItem] = [URLQueryItem(name: "quality", value: String(quality))]
        if let tag { q.append(URLQueryItem(name: "tag", value: tag)) }
        if let maxWidth { q.append(URLQueryItem(name: "maxWidth", value: String(maxWidth))) }
        if let maxHeight { q.append(URLQueryItem(name: "maxHeight", value: String(maxHeight))) }
        comps.queryItems = q
        return comps.url
    }

    // MARK: - Item DTOs

    /// Per-user playback state on an item (`UserData` in Jellyfin JSON).
    public struct JellyfinUserData: Decodable, Equatable, Sendable, Hashable {
        public let playbackPositionTicks: Int64?
        public let playCount: Int?
        public let played: Bool?
        public let isFavorite: Bool?
        public let lastPlayedDate: String?

        enum CodingKeys: String, CodingKey {
            case playbackPositionTicks = "PlaybackPositionTicks"
            case playCount = "PlayCount"
            case played = "Played"
            case isFavorite = "IsFavorite"
            case lastPlayedDate = "LastPlayedDate"
        }

        public init(playbackPositionTicks: Int64? = nil, playCount: Int? = nil,
                    played: Bool? = nil, isFavorite: Bool? = nil,
                    lastPlayedDate: String? = nil) {
            self.playbackPositionTicks = playbackPositionTicks
            self.playCount = playCount
            self.played = played
            self.isFavorite = isFavorite
            self.lastPlayedDate = lastPlayedDate
        }
    }

    /// A Jellyfin media item (Movie, Series, Episode, etc.) from `GET /Items`.
    /// One trickplay resolution's sprite-sheet geometry.
    ///
    /// **Trickplay** is Jellyfin's pre-generated scrubbing preview: for each
    /// item it bakes a grid of small frames, sampled every `interval` ms, into
    /// a few big JPEG "sheets". A client downloads one sheet and slices every
    /// thumbnail out of it locally — no per-frame network call and no
    /// AVPlayer seek, which is the difference between ~80ms and ~1.1s for a
    /// page of six previews.
    public struct TrickplayInfo: Decodable, Hashable, Sendable {
        /// One frame's pixel size inside the sheet.
        public let width: Int
        public let height: Int
        /// The sheet's grid, in frames.
        public let tileWidth: Int
        public let tileHeight: Int
        /// Milliseconds of video between consecutive frames.
        public let interval: Int
        /// Jellyfin's own count — **never gate rendering on this.** It counts
        /// only non-black frames, so an item whose opening is a fade can
        /// report `1` while the sheet holds a full valid grid.
        public let thumbnailCount: Int
        public let bandwidth: Int?

        enum CodingKeys: String, CodingKey {
            case width = "Width", height = "Height"
            case tileWidth = "TileWidth", tileHeight = "TileHeight"
            case interval = "Interval", thumbnailCount = "ThumbnailCount"
            case bandwidth = "Bandwidth"
        }

        /// Frames per sheet.
        public var thumbsPerTile: Int { tileWidth * tileHeight }
    }

    /// **The `Trickplay` field nests two levels**, media-source id then width:
    /// `{"Trickplay": {"<mediaSourceId>": {"320": {…}, "1280": {…}}}}`.
    /// Reading the media-source key as if it were a width is a decode failure
    /// that looks like "this item has no trickplay" rather than an error —
    /// v1 shipped that bug for a while before catching it.
    public struct TrickplayResponse: Decodable, Sendable {
        public let trickplay: [String: [String: TrickplayInfo]]?
        enum CodingKeys: String, CodingKey { case trickplay = "Trickplay" }
    }

    /// One chapter marker on an item (`Chapters` field). `imageTag` is set when
    /// the server has extracted a thumbnail for it — served from
    /// `/Items/{id}/Images/Chapter/{index}`.
    public struct JellyfinChapter: Decodable, Equatable, Sendable {
        public let name: String?
        public let startPositionTicks: Int64?
        public let imageTag: String?

        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case startPositionTicks = "StartPositionTicks"
            case imageTag = "ImageTag"
        }

        public init(name: String? = nil, startPositionTicks: Int64? = nil, imageTag: String? = nil) {
            self.name = name
            self.startPositionTicks = startPositionTicks
            self.imageTag = imageTag
        }
    }

    /// One stream of an item's primary media source (`MediaStreams` field);
    /// `type` is "Video", "Audio" or "Subtitle". What the movie page's facts
    /// row reads its "English 5.1 · Subs: EN, ES" from.
    public struct JellyfinMediaStream: Decodable, Equatable, Sendable {
        public let type: String?
        public let language: String?
        public let displayLanguage: String?
        public let displayTitle: String?
        public let channels: Int?
        public let channelLayout: String?
        public let isDefault: Bool?
        public let codec: String?

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case language = "Language"
            case displayLanguage = "DisplayLanguage"
            case displayTitle = "DisplayTitle"
            case channels = "Channels"
            case channelLayout = "ChannelLayout"
            case isDefault = "IsDefault"
            case codec = "Codec"
        }

        public init(type: String? = nil, language: String? = nil, displayLanguage: String? = nil,
                    displayTitle: String? = nil, channels: Int? = nil, channelLayout: String? = nil,
                    isDefault: Bool? = nil, codec: String? = nil) {
            self.type = type
            self.language = language
            self.displayLanguage = displayLanguage
            self.displayTitle = displayTitle
            self.channels = channels
            self.channelLayout = channelLayout
            self.isDefault = isDefault
            self.codec = codec
        }
    }

        public struct JellyfinItem: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String?
        public let type: String?
        public let overview: String?
        public let genres: [String]?
        // Free-form tags (distinct from Genres) — only returned when `Tags`
        // is explicitly requested via `fields`. A library like an anime/adult
        // collection typically carries many of these per item, which is what
        // the library screens' tag-chip search filters against.
        //
        // `var` alone among the fields: tags are the one thing this app
        // writes back (`JellyfinClient.setItemTags`), and a caller that has
        // just written them needs to bring its cached copies into step
        // without rebuilding a thirty-parameter init.
        public var tags: [String]?
        public let productionYear: Int?
        public let premiereDate: String?
        public let officialRating: String?
        public let communityRating: Double?
        public let runTimeTicks: Int64?
        public let seriesName: String?
        public let seriesId: String?
        public let seasonName: String?
        public let seasonId: String?
        public let indexNumber: Int?
        public let parentIndexNumber: Int?
        public let imageTags: [String: String]?
        public let backdropImageTags: [String]?
        public let parentBackdropItemId: String?
        public let parentBackdropImageTags: [String]?
        public let userData: JellyfinUserData?
        public let childCount: Int?
        public let recursiveItemCount: Int?
        public let locationType: String?
        // Rich metadata — only returned when explicitly requested via the
        // `fields` query param (see `JellyfinClient.fetchItemDetail`). Note:
        // `criticRating` only comes back when `ProductionLocations` is *also*
        // in the requested fields (a Jellyfin server quirk).
        public let people: [JellyfinPerson]?
        public let criticRating: Double?
        public let providerIds: [String: String]?
        public let taglines: [String]?
        public let studios: [JellyfinNamedItem]?
        public let productionLocations: [String]?
        // Series-only: "Continuing" or "Ended", and the end date once ended —
        // used to format a show's year range ("2023 – 2026" vs "2023 – Still On").
        public let status: String?
        public let endDate: String?
        // Detail-only (`fields=Chapters,MediaStreams,LocalTrailerCount`): the
        // movie page's scenes strip, its audio/subtitle facts, and whether a
        // trailer file exists that this app could actually play.
        public let chapters: [JellyfinChapter]?
        public let mediaStreams: [JellyfinMediaStream]?
        public let localTrailerCount: Int?
        // Home-video shelf data: the sprite-sheet geometry (`fields=Trickplay`,
        // nested media-source → width) so a card can page through frames
        // without a per-item fetch; the frame's pixel size, which tells a
        // portrait phone clip from a landscape one; and when the file was
        // added, distinct from `PremiereDate` (when it was shot).
        public let trickplay: [String: [String: TrickplayInfo]]?
        public let width: Int?
        public let height: Int?
        public let dateCreated: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case type = "Type"
            case overview = "Overview"
            case genres = "Genres"
            case tags = "Tags"
            case productionYear = "ProductionYear"
            case premiereDate = "PremiereDate"
            case officialRating = "OfficialRating"
            case communityRating = "CommunityRating"
            case runTimeTicks = "RunTimeTicks"
            case seriesName = "SeriesName"
            case seriesId = "SeriesId"
            case seasonName = "SeasonName"
            case seasonId = "SeasonId"
            case indexNumber = "IndexNumber"
            case parentIndexNumber = "ParentIndexNumber"
            case imageTags = "ImageTags"
            case backdropImageTags = "BackdropImageTags"
            case parentBackdropItemId = "ParentBackdropItemId"
            case parentBackdropImageTags = "ParentBackdropImageTags"
            case userData = "UserData"
            case childCount = "ChildCount"
            case recursiveItemCount = "RecursiveItemCount"
            case locationType = "LocationType"
            case people = "People"
            case criticRating = "CriticRating"
            case providerIds = "ProviderIds"
            case taglines = "Taglines"
            case studios = "Studios"
            case status = "Status"
            case endDate = "EndDate"
            case productionLocations = "ProductionLocations"
            case chapters = "Chapters"
            case mediaStreams = "MediaStreams"
            case localTrailerCount = "LocalTrailerCount"
            case trickplay = "Trickplay"
            case width = "Width"
            case height = "Height"
            case dateCreated = "DateCreated"
        }

        public init(id: String, name: String? = nil, type: String? = nil,
                    overview: String? = nil, genres: [String]? = nil,
                    tags: [String]? = nil,
                    productionYear: Int? = nil, premiereDate: String? = nil,
                    officialRating: String? = nil, communityRating: Double? = nil,
                    runTimeTicks: Int64? = nil, seriesName: String? = nil,
                    seriesId: String? = nil, seasonName: String? = nil,
                    seasonId: String? = nil, indexNumber: Int? = nil,
                    parentIndexNumber: Int? = nil, imageTags: [String: String]? = nil,
                    backdropImageTags: [String]? = nil,
                    parentBackdropItemId: String? = nil,
                    parentBackdropImageTags: [String]? = nil,
                    userData: JellyfinUserData? = nil, childCount: Int? = nil,
                    recursiveItemCount: Int? = nil, locationType: String? = nil,
                    people: [JellyfinPerson]? = nil, criticRating: Double? = nil,
                    providerIds: [String: String]? = nil, taglines: [String]? = nil,
                    studios: [JellyfinNamedItem]? = nil, productionLocations: [String]? = nil,
                    status: String? = nil, endDate: String? = nil,
                    chapters: [JellyfinChapter]? = nil, mediaStreams: [JellyfinMediaStream]? = nil,
                    localTrailerCount: Int? = nil,
                    trickplay: [String: [String: TrickplayInfo]]? = nil,
                    width: Int? = nil, height: Int? = nil, dateCreated: String? = nil) {
            self.id = id
            self.name = name
            self.type = type
            self.overview = overview
            self.genres = genres
            self.tags = tags
            self.productionYear = productionYear
            self.premiereDate = premiereDate
            self.officialRating = officialRating
            self.communityRating = communityRating
            self.runTimeTicks = runTimeTicks
            self.seriesName = seriesName
            self.seriesId = seriesId
            self.seasonName = seasonName
            self.seasonId = seasonId
            self.indexNumber = indexNumber
            self.parentIndexNumber = parentIndexNumber
            self.imageTags = imageTags
            self.backdropImageTags = backdropImageTags
            self.parentBackdropItemId = parentBackdropItemId
            self.parentBackdropImageTags = parentBackdropImageTags
            self.userData = userData
            self.childCount = childCount
            self.recursiveItemCount = recursiveItemCount
            self.locationType = locationType
            self.people = people
            self.criticRating = criticRating
            self.providerIds = providerIds
            self.taglines = taglines
            self.studios = studios
            self.productionLocations = productionLocations
            self.status = status
            self.endDate = endDate
            self.chapters = chapters
            self.mediaStreams = mediaStreams
            self.localTrailerCount = localTrailerCount
            self.trickplay = trickplay
            self.width = width
            self.height = height
            self.dateCreated = dateCreated
        }

        public var displayName: String { name ?? "Unknown" }
    }

    /// A cast/crew member on an item's `People` array. `type` is "Actor",
    /// "Director", "Writer", etc.; `role` is the character name (actors).
    public struct JellyfinPerson: Decodable, Equatable, Sendable, Identifiable {
        public let id: String?
        public let name: String?
        public let role: String?
        public let type: String?
        public let primaryImageTag: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case role = "Role"
            case type = "Type"
            case primaryImageTag = "PrimaryImageTag"
        }

        public init(id: String? = nil, name: String? = nil, role: String? = nil,
                    type: String? = nil, primaryImageTag: String? = nil) {
            self.id = id
            self.name = name
            self.role = role
            self.type = type
            self.primaryImageTag = primaryImageTag
        }
    }

    /// A named sub-entity on an item (studio, genre item, etc.).
    public struct JellyfinNamedItem: Decodable, Equatable, Sendable, Identifiable {
        public let id: String?
        public let name: String?
        public let imageTags: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case imageTags = "ImageTags"
        }

        public init(id: String? = nil, name: String? = nil, imageTags: [String: String]? = nil) {
            self.id = id
            self.name = name
            self.imageTags = imageTags
        }
    }

    /// A Jellyfin user library (view) from `GET /UserViews`.
    public struct JellyfinUserView: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let collectionType: String?
        public let imageTags: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case collectionType = "CollectionType"
            case imageTags = "ImageTags"
        }

        public init(id: String, name: String, collectionType: String? = nil,
                    imageTags: [String: String]? = nil) {
            self.id = id
            self.name = name
            self.collectionType = collectionType
            self.imageTags = imageTags
        }
    }

    /// Generic paged response wrapper for list endpoints (`/UserViews`, `/Items`, etc.).
    public struct ItemsResponse<T: Decodable & Sendable>: Decodable, Sendable {
        public let items: [T]
        public let totalRecordCount: Int?
        public let startIndex: Int?

        enum CodingKeys: String, CodingKey {
            case items = "Items"
            case totalRecordCount = "TotalRecordCount"
            case startIndex = "StartIndex"
        }

        public init(items: [T], totalRecordCount: Int? = nil, startIndex: Int? = nil) {
            self.items = items
            self.totalRecordCount = totalRecordCount
            self.startIndex = startIndex
        }
    }
}
