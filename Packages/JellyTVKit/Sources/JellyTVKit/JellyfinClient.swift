import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// Richer than a raw `URLError` — lets callers (the stale-session detector,
/// a future re-login flow) branch on the exact failure instead of guessing
/// from an HTTP-status-as-URLError-code hack.
public enum JellyfinRequestError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case server(status: Int, body: String)
    case decoding(underlying: String)
}

public struct JellyfinClient: Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let deviceId: String
    private let clientName: String
    private let clientVersion: String
    private let session: URLSession

    public init(baseURL: URL, apiKey: String, deviceId: String,
                clientName: String = "JellyTV", clientVersion: String = "1.0.0",
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.deviceId = deviceId
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.session = session
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
    /// taglines, studios, provider IDs, season count (`ChildCount`, Series
    /// only). Used to enrich the detail/dossier surfaces on demand (never for
    /// the whole library list).
    ///
    /// `ProductionLocations` is deliberately in the fields string: Jellyfin
    /// only returns `CriticRating` when it's requested alongside — omitting it
    /// silently drops the critic score.
    public func fetchItemDetail(userId: String, itemId: String) async throws -> JellyfinAPI.JellyfinItem {
        let fields = "Overview,Genres,OfficialRating,CommunityRating,CriticRating,RunTimeTicks,"
            + "PremiereDate,People,Studios,Taglines,ProductionLocations,ProviderIds,ChildCount,"
            + "Status,EndDate,BackdropImageTags,ParentBackdropImageTags"
        let query = [URLQueryItem(name: "fields", value: fields)]
        guard let url = buildURL(path: "/Users/\(userId)/Items/\(itemId)", query: query) else {
            throw URLError(.badURL)
        }
        return try await request(url: url)
    }

    /// A series' seasons (lightweight — id/name/index/episode count only).
    /// Episodes are fetched separately, per selected season, on demand.
    public func fetchSeasons(userId: String, seriesId: String) async throws -> [JellyfinAPI.JellyfinItem] {
        let query = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "fields", value: "ChildCount"),
        ]
        guard let url = buildURL(path: "/Shows/\(seriesId)/Seasons", query: query) else {
            throw URLError(.badURL)
        }
        let response: JellyfinAPI.ItemsResponse<JellyfinAPI.JellyfinItem> = try await request(url: url)
        return response.items
    }

    /// One season's episodes — thumbnail, runtime, and per-user watch progress.
    public func fetchEpisodes(userId: String, seriesId: String, seasonId: String) async throws -> [JellyfinAPI.JellyfinItem] {
        let query = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "seasonId", value: seasonId),
            URLQueryItem(name: "fields", value: "Overview,RunTimeTicks,UserData,ImageTags"),
        ]
        guard let url = buildURL(path: "/Shows/\(seriesId)/Episodes", query: query) else {
            throw URLError(.badURL)
        }
        let response: JellyfinAPI.ItemsResponse<JellyfinAPI.JellyfinItem> = try await request(url: url)
        return response.items
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

    // MARK: - Playback

    /// Negotiates DirectPlay vs. DirectStream vs. Transcode for one item.
    /// Response's `mediaSources.first` + `playSessionId` feed the stream URL
    /// builders below.
    public func fetchPlaybackInfo(userId: String, itemId: String,
                                  deviceProfile: JellyfinAPI.DeviceProfile = .tvOS) async throws -> JellyfinAPI.PlaybackInfoResponse {
        guard let url = buildURL(path: "/Items/\(itemId)/PlaybackInfo",
                                  query: [URLQueryItem(name: "userId", value: userId)]) else {
            throw JellyfinRequestError.invalidURL
        }
        let bodyData = try JSONEncoder().encode(JellyfinAPI.PlaybackInfoRequest(userId: userId, deviceProfile: deviceProfile))
        return try await request(url: url, method: .post, bodyData: bodyData)
    }

    public func reportPlaybackStart(_ report: JellyfinAPI.PlaybackStartReport) async throws {
        guard let url = buildURL(path: "/Sessions/Playing", query: nil) else { throw JellyfinRequestError.invalidURL }
        try await requestVoid(url: url, method: .post, bodyData: try JSONEncoder().encode(report))
    }

    /// The one POST path that's safe to retry — a double-posted progress
    /// tick is a no-op on Jellyfin. `/Sessions/Playing`/`Stopped` are not
    /// (see `shouldRetry`) since a duplicate creates a ghost session.
    public func reportPlaybackProgress(_ report: JellyfinAPI.PlaybackProgressReport) async throws {
        guard let url = buildURL(path: "/Sessions/Playing/Progress", query: nil) else { throw JellyfinRequestError.invalidURL }
        try await requestVoid(url: url, method: .post, bodyData: try JSONEncoder().encode(report))
    }

    public func reportPlaybackStop(_ report: JellyfinAPI.PlaybackStopReport) async throws {
        guard let url = buildURL(path: "/Sessions/Playing/Stopped", query: nil) else { throw JellyfinRequestError.invalidURL }
        try await requestVoid(url: url, method: .post, bodyData: try JSONEncoder().encode(report))
    }

    public func setFavorite(userId: String, itemId: String) async throws {
        guard let url = buildURL(path: "/Users/\(userId)/FavoriteItems/\(itemId)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        try await requestVoid(url: url, method: .post)
    }

    public func clearFavorite(userId: String, itemId: String) async throws {
        guard let url = buildURL(path: "/Users/\(userId)/FavoriteItems/\(itemId)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        try await requestVoid(url: url, method: .delete)
    }

    /// Direct-play URL — only meaningful when the resolved `MediaSource`
    /// reports `canDirectPlayNatively`.
    public func directStreamURL(itemId: String, mediaSourceId: String) -> URL? {
        buildURL(path: "/Videos/\(itemId)/stream", query: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
            URLQueryItem(name: "deviceId", value: deviceId),
            URLQueryItem(name: "api_key", value: apiKey),
        ])
    }

    /// HLS manifest URL — always available; Jellyfin transcodes if needed.
    /// `enableAdaptiveBitrateStreaming=false` deliberately pins Jellyfin to a
    /// single variant — AVPlayer's HLS ABR doesn't pair well with Jellyfin's
    /// on-demand transcode (the player requests segments faster than ffmpeg
    /// produces them across variants).
    ///
    /// **`videoBitRate`/`audioBitRate` are not optional tuning knobs — leaving
    /// them off silently breaks video.** Jellyfin derives the master
    /// playlist's declared `BANDWIDTH` from *these*, not from
    /// `maxStreamingBitrate`. With no `videoBitRate` it emits
    /// `BANDWIDTH=256000` and downscales the picture to match that invented
    /// ceiling, while ffmpeg writes segments far larger than 256 kbps.
    /// AVPlayer enforces the declaration, fails the variant with
    /// `CoreMediaErrorDomain -12318` ("Segment exceeds specified bandwidth
    /// for variant"), and — because `enableAdaptiveBitrateStreaming=false`
    /// leaves no other variant to fall back to — drops the video track while
    /// happily continuing the audio. That is the "sound but no picture" bug.
    ///
    /// `profile`/`level` are pinned for the same class of reason: without
    /// them Jellyfin advertises `CODECS="avc1.424029"` (Baseline @ 4.1, not
    /// even a legal pairing) regardless of what ffmpeg actually encodes, and
    /// AVPlayer refuses a video track whose real bitstream contradicts the
    /// declared codec string.
    ///
    /// Video is pinned to `h264` rather than also offering `hevc` — Jellyfin
    /// would *copy* an HEVC source into the MPEG-TS segments, and
    /// AVFoundation only decodes HEVC from fMP4 segments, which is the same
    /// black-picture symptom by a different route. Likewise `flac`/`opus`
    /// are dropped from the audio list: neither is playable inside MPEG-TS
    /// on Apple platforms.
    public func hlsManifestURL(itemId: String, mediaSourceId: String, playSessionId: String,
                                videoCodec: String = "h264",
                                audioCodec: String = "aac,mp3,ac3,eac3",
                                videoBitRate: Int = 20_000_000,
                                audioBitRate: Int = 384_000) -> URL? {
        buildURL(path: "/Videos/\(itemId)/master.m3u8", query: [
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
            URLQueryItem(name: "playSessionId", value: playSessionId),
            URLQueryItem(name: "deviceId", value: deviceId),
            URLQueryItem(name: "videoCodec", value: videoCodec),
            URLQueryItem(name: "audioCodec", value: audioCodec),
            URLQueryItem(name: "segmentContainer", value: "ts"),
            URLQueryItem(name: "enableAdaptiveBitrateStreaming", value: "false"),
            URLQueryItem(name: "videoBitRate", value: String(videoBitRate)),
            URLQueryItem(name: "audioBitRate", value: String(audioBitRate)),
            URLQueryItem(name: "profile", value: "high"),
            URLQueryItem(name: "level", value: "41"),
            URLQueryItem(name: "transcodingMaxAudioChannels", value: "6"),
            URLQueryItem(name: "api_key", value: apiKey),
        ])
    }

    /// The `MediaBrowser Token="…"` header string, for callers outside this
    /// module that need to attach it directly (an `AVURLAsset`'s HTTP header
    /// options — belt-and-suspenders alongside the `api_key` query param, in
    /// case a platform strips custom headers on HLS segment sub-requests).
    public var authorizationHeader: String { authHeader }

    // MARK: - Transport (retry/backoff + decode)

    private static let maxAttempts = 3
    private static let perAttemptTimeout: TimeInterval = 15

    private func request<T: Decodable & Sendable>(url: URL) async throws -> T {
        let (data, _) = try await send(url: url, method: .get, bodyData: nil)
        return try decode(T.self, from: data)
    }

    private func request<T: Decodable & Sendable>(url: URL, method: HTTPMethod, bodyData: Data) async throws -> T {
        let (data, _) = try await send(url: url, method: method, bodyData: bodyData)
        return try decode(T.self, from: data)
    }

    private func requestVoid(url: URL, method: HTTPMethod, bodyData: Data? = nil) async throws {
        _ = try await send(url: url, method: method, bodyData: bodyData)
    }

    /// Capped exponential backoff (250ms → 1s → 2s), 3 attempts total.
    /// GET/PUT/DELETE retried on transient failures; POST only for the
    /// idempotent progress-report path (see `shouldRetry`); 401 never retried.
    private func send(url: URL, method: HTTPMethod, bodyData: Data?) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var backoffNs: UInt64 = 250_000_000
        while true {
            attempt += 1
            do {
                return try await sendOnce(url: url, method: method, bodyData: bodyData)
            } catch {
                let isLast = attempt >= Self.maxAttempts
                guard !isLast, shouldRetry(method: method, url: url, error: error) else { throw error }
                try? await Task.sleep(nanoseconds: backoffNs)
                backoffNs = min(backoffNs * 4, 2_000_000_000)
            }
        }
    }

    private func sendOnce(url: URL, method: HTTPMethod, bodyData: Data?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.perAttemptTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JellyfinRequestError.invalidResponse }
        if http.statusCode == 401 { throw JellyfinRequestError.unauthorized }
        if http.statusCode >= 400 {
            throw JellyfinRequestError.server(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }

    /// GET/PUT/DELETE are idempotent by contract — always safe to retry on a
    /// transient failure. POST is only safe for `/Sessions/Playing/Progress`
    /// (a double-posted tick is a no-op); `/Sessions/Playing` and
    /// `/Sessions/Playing/Stopped` are excluded — a duplicate creates a
    /// ghost session server-side.
    private func shouldRetry(method: HTTPMethod, url: URL, error: Error) -> Bool {
        if case JellyfinRequestError.unauthorized = error { return false }
        if case JellyfinRequestError.server(let status, _) = error {
            switch status {
            case 408, 429, 500, 502, 503, 504: break
            default: return false
            }
        } else if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed,
                 .cannotConnectToHost, .cannotFindHost: break
            default: return false
            }
        }
        switch method {
        case .get, .put, .delete: return true
        case .post: return url.path.hasSuffix("/Sessions/Playing/Progress")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw JellyfinRequestError.decoding(underlying: String(describing: error))
        }
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
