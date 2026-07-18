import Foundation

public struct JellyfinClient: Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let deviceId: String
    private let clientName: String
    private let clientVersion: String

    public init(baseURL: URL, apiKey: String, deviceId: String,
                clientName: String = "JellyTV", clientVersion: String = "1.0.0") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.deviceId = deviceId
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    private var authHeader: String {
        JellyfinAPI.authorizationHeader(
            token: apiKey,
            client: clientName,
            device: clientName,
            deviceId: deviceId,
            version: clientVersion
        )
    }

    public func fetchUserViews(userId: String) async throws -> [JellyfinAPI.JellyfinUserView] {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "userId", value: userId)]
        guard let url = buildURL(path: "/UserViews", query: components.queryItems) else {
            throw URLError(.badURL)
        }
        let response: JellyfinAPI.ItemsResponse<JellyfinAPI.JellyfinUserView> = try await request(url: url)
        return response.items
    }

    public func fetchItems(
        userId: String,
        parentId: String? = nil,
        includeItemTypes: String? = nil,
        filters: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        limit: Int? = nil,
        fields: String? = "UserData,PrimaryImageAspectRatio,Overview,Genres,OfficialRating,PremiereDate,SeriesName,SeriesId,IndexNumber,ParentIndexNumber,BackdropImageTags,ParentBackdropImageTags"
    ) async throws -> [JellyfinAPI.JellyfinItem] {
        var queryItems = [URLQueryItem(name: "userId", value: userId)]
        if let v = parentId { queryItems.append(URLQueryItem(name: "parentId", value: v)) }
        queryItems.append(URLQueryItem(name: "recursive", value: "true"))
        if let v = includeItemTypes { queryItems.append(URLQueryItem(name: "includeItemTypes", value: v)) }
        if let v = filters { queryItems.append(URLQueryItem(name: "filters", value: v)) }
        if let v = sortBy { queryItems.append(URLQueryItem(name: "sortBy", value: v)) }
        if let v = sortOrder { queryItems.append(URLQueryItem(name: "sortOrder", value: v)) }
        if let v = limit { queryItems.append(URLQueryItem(name: "limit", value: String(v))) }
        if let v = fields { queryItems.append(URLQueryItem(name: "fields", value: v)) }

        guard let url = buildURL(path: "/Items", query: queryItems) else {
            throw URLError(.badURL)
        }
        let response: JellyfinAPI.ItemsResponse<JellyfinAPI.JellyfinItem> = try await request(url: url)
        return response.items
    }

    /// Full metadata for a single item — cast (`People`), critic rating,
    /// taglines, studios, provider IDs. Used to enrich the detail/dossier
    /// surfaces on demand (never for the whole library list).
    ///
    /// `ProductionLocations` is deliberately in the fields string: Jellyfin
    /// only returns `CriticRating` when it's requested alongside — omitting it
    /// silently drops the critic score.
    public func fetchItemDetail(userId: String, itemId: String) async throws -> JellyfinAPI.JellyfinItem {
        let fields = "Overview,Genres,OfficialRating,CommunityRating,CriticRating,RunTimeTicks,"
            + "PremiereDate,People,Studios,Taglines,ProductionLocations,ProviderIds,"
            + "BackdropImageTags,ParentBackdropImageTags"
        let query = [URLQueryItem(name: "fields", value: fields)]
        guard let url = buildURL(path: "/Users/\(userId)/Items/\(itemId)", query: query) else {
            throw URLError(.badURL)
        }
        return try await request(url: url)
    }

    public func imageURL(itemId: String, type: String, tag: String? = nil,
                          maxWidth: Int? = nil, maxHeight: Int? = nil,
                          quality: Int = 90) -> URL? {
        var components = URLComponents()
        var items: [URLQueryItem] = []
        if let tag { items.append(URLQueryItem(name: "tag", value: tag)) }
        if let maxWidth { items.append(URLQueryItem(name: "maxWidth", value: String(maxWidth))) }
        if let maxHeight { items.append(URLQueryItem(name: "maxHeight", value: String(maxHeight))) }
        items.append(URLQueryItem(name: "quality", value: String(quality)))
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        components.queryItems = items
        guard let url = buildURL(path: "/Items/\(itemId)/Images/\(type)",
                                  query: components.queryItems) else { return nil }
        return url
    }

    private func request<T: Decodable & Sendable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard httpResponse.statusCode == 200 else {
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func buildURL(path: String, query: [URLQueryItem]?) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            return nil
        }
        components.path = (components.path as NSString).appendingPathComponent(path)
        if let query, !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        return components.url
    }
}
