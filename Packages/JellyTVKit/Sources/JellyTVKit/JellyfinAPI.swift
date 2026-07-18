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
    public struct JellyfinItem: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String?
        public let type: String?
        public let overview: String?
        public let genres: [String]?
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

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case type = "Type"
            case overview = "Overview"
            case genres = "Genres"
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
            case productionLocations = "ProductionLocations"
        }

        public init(id: String, name: String? = nil, type: String? = nil,
                    overview: String? = nil, genres: [String]? = nil,
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
                    studios: [JellyfinNamedItem]? = nil, productionLocations: [String]? = nil) {
            self.id = id
            self.name = name
            self.type = type
            self.overview = overview
            self.genres = genres
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
