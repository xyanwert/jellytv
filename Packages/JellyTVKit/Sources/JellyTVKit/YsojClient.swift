import Foundation

/// Talks to a YSOJ-server's extended surface (`/ysoj/*`) — Discover and downloads.
///
/// Deliberately a **separate client from `JellyfinClient`**, not more methods on it: this
/// speaks a different contract to a different set of handlers, and mixing them would make
/// it easy to call a YSOJ-only endpoint on a plain Jellyfin by accident. It borrows the
/// same base URL, token and auth-header shape, because a YSOJ server *is* the Jellyfin
/// endpoint as far as credentials go.
///
/// **How this degrades on a plain Jellyfin, which is the whole compatibility story:**
/// there is no such router there, so the request falls through to Jellyfin, which 404s.
/// `fetchCapabilities()` turns that 404 into `nil`, the app hides every Discover surface,
/// and nothing else in the app ever asks. No version check, no probe, no second protocol.
public struct YsojClient: Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let deviceId: String
    private let clientName: String
    private let clientVersion: String
    private let deviceName: String
    private let session: URLSession

    public init(baseURL: URL, apiKey: String, deviceId: String,
                clientName: String = "JellyTV", clientVersion: String = "1.0.0",
                deviceName: String? = nil,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.deviceId = deviceId
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.deviceName = deviceName ?? clientName
        self.session = session
    }

    private var authHeader: String {
        JellyfinAPI.authorizationHeader(
            token: apiKey, client: clientName, device: deviceName,
            deviceId: deviceId, version: clientVersion
        )
    }

    // MARK: - Capabilities

    /// The feature document, or `nil` when this server has no extended surface.
    ///
    /// Returns `nil` — never throws — for the two "this isn't a YSOJ server" answers, 404
    /// and 401, so a caller can write `if let caps = await ysoj.fetchCapabilities()`
    /// without a do/catch around what is a completely ordinary outcome. A genuine
    /// transport failure still throws, because "the network is down" and "this server
    /// doesn't do Discover" must not look the same: the first should be retried, the
    /// second is permanent.
    public func fetchCapabilities() async throws -> YsojAPI.Capabilities? {
        guard let url = buildURL(path: "/ysoj/capabilities", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        do {
            return try await request(url: url) as YsojAPI.Capabilities
        } catch JellyfinRequestError.server(let status, _) where status == 404 {
            return nil
        } catch JellyfinRequestError.unauthorized {
            return nil
        } catch JellyfinRequestError.decoding {
            // A plain Jellyfin can answer `/ysoj/capabilities` with its own error body
            // rather than a 404 depending on how it routes unknown paths. Undecodable is
            // the same conclusion: this server has nothing to offer here.
            return nil
        }
    }

    // MARK: - Discover

    public func fetchCategories() async throws -> [YsojAPI.DiscoverCategory] {
        guard let url = buildURL(path: "/ysoj/discover/categories", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        let response: YsojAPI.CategoriesResponse = try await request(url: url)
        return response.categories
    }

    public func fetchSources() async throws -> [YsojAPI.Capabilities.Source] {
        guard let url = buildURL(path: "/ysoj/discover/sources", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        let response: SourcesResponse = try await request(url: url)
        return response.sources
    }

    public func fetchCatalog(category: String, page: Int = 1) async throws -> [YsojAPI.DiscoverItem] {
        let query = [
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "page", value: String(page)),
        ]
        guard let url = buildURL(path: "/ysoj/discover/catalog", query: query) else {
            throw JellyfinRequestError.invalidURL
        }
        let response: YsojAPI.CatalogResponse = try await request(url: url)
        return response.items
    }

    public func search(query: String, page: Int = 1) async throws -> [YsojAPI.DiscoverItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let items = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "page", value: String(page)),
        ]
        guard let url = buildURL(path: "/ysoj/discover/search", query: items) else {
            throw JellyfinRequestError.invalidURL
        }
        let response: YsojAPI.CatalogResponse = try await request(url: url)
        return response.items
    }

    /// A ref is `source:type:id`. The colons are legal in a path segment and are passed
    /// through **unencoded on purpose**.
    ///
    /// Percent-encoding them here was a real bug: `buildURL` assigns to
    /// `URLComponents.path`, which takes a *decoded* path and re-encodes it on the way
    /// out — so a hand-encoded `%3A` went out as `%253A`, the server saw a ref containing
    /// a literal `%3A`, refused to parse it, and every detail page spun forever. Let
    /// `URLComponents` do the encoding exactly once. The server re-validates the ref on
    /// arrival regardless, which is what actually bounds what an id may contain.
    public func fetchDetail(ref: String) async throws -> YsojAPI.DiscoverDetail {
        guard let url = buildURL(path: "/ysoj/discover/item/\(ref)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        return try await request(url: url)
    }

    // MARK: - Downloads

    /// Step one of plan → confirm → apply. Costs the request and returns what *would*
    /// happen; nothing is started.
    public func planDownload(ref: String, scope: YsojAPI.DownloadScope,
                             target: YsojAPI.DownloadTarget? = nil) async throws -> YsojAPI.DownloadPlan {
        guard let url = buildURL(path: "/ysoj/downloads/plan", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        let body = try JSONEncoder().encode(
            YsojAPI.PlanRequest(ref: ref, scope: scope, target: target))
        return try await request(url: url, method: .post, bodyData: body)
    }

    /// Step two. Consumes the plan — a second call with the same id is a 409, by design.
    public func confirmDownload(planId: String) async throws -> YsojAPI.DownloadJob {
        guard let url = buildURL(path: "/ysoj/downloads/confirm", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        let body = try JSONEncoder().encode(YsojAPI.ConfirmRequest(planId: planId))
        return try await request(url: url, method: .post, bodyData: body)
    }

    public func fetchDownloads(activeOnly: Bool = false) async throws -> YsojAPI.DownloadList {
        let query = activeOnly ? [URLQueryItem(name: "activeOnly", value: "true")] : nil
        guard let url = buildURL(path: "/ysoj/downloads", query: query) else {
            throw JellyfinRequestError.invalidURL
        }
        return try await request(url: url)
    }

    public func pauseDownload(jobId: String) async throws -> YsojAPI.DownloadJob {
        try await jobAction(jobId: jobId, action: "pause")
    }

    public func resumeDownload(jobId: String) async throws -> YsojAPI.DownloadJob {
        try await jobAction(jobId: jobId, action: "resume")
    }

    private func jobAction(jobId: String, action: String) async throws -> YsojAPI.DownloadJob {
        guard let url = buildURL(path: "/ysoj/downloads/\(jobId)/\(action)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        return try await request(url: url, method: .post, bodyData: Data("{}".utf8))
    }

    /// Cancels a running job or forgets a finished one — the server decides which from the
    /// state, because that is how the row reads: one dismiss whose meaning depends on
    /// what it is dismissing.
    public func removeDownload(jobId: String) async throws {
        guard let url = buildURL(path: "/ysoj/downloads/\(jobId)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        _ = try await send(url: url, method: .delete, bodyData: nil)
    }

    // MARK: - Library overrides

    public func fetchLibraryOverrides() async throws -> [YsojAPI.LibraryOverride] {
        guard let url = buildURL(path: "/ysoj/library-overrides", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        let response: YsojAPI.OverridesResponse = try await request(url: url)
        return response.overrides
    }

    public func setLibraryOverride(
        libraryId: String, isNSFW: Bool, isAnime: Bool, displayName: String? = nil
    ) async throws -> YsojAPI.LibraryOverride {
        guard let url = buildURL(path: "/ysoj/library-overrides/\(libraryId)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        let override = YsojAPI.LibraryOverride(
            libraryId: libraryId, displayName: displayName, isNSFW: isNSFW, isAnime: isAnime
        )
        let body = try JSONEncoder().encode(override)
        return try await request(url: url, method: .put, bodyData: body)
    }

    // MARK: - LAN remote (pairing a phone to a TV)

    /// The TV starts looking for a remote. Re-post to keep looking: the same beacon comes
    /// back with a fresh expiry, so the overlay can keep polling the id it was given.
    public func openRemoteBeacon(deviceName: String) async throws -> YsojAPI.RemoteBeacon {
        guard let url = buildURL(path: "/ysoj/remote/beacon", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        let body = try JSONEncoder().encode(["deviceId": deviceId, "deviceName": deviceName])
        return try await request(url: url, method: .post, bodyData: body)
    }

    /// Did anyone answer yet?
    public func pollRemoteBeacon(id: String) async throws -> YsojAPI.RemoteBeacon {
        guard let url = buildURL(path: "/ysoj/remote/beacon/\(id)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        return try await request(url: url)
    }

    public func closeRemoteBeacon(id: String) async throws {
        guard let url = buildURL(path: "/ysoj/remote/beacon/\(id)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        _ = try await send(url: url, method: .delete, bodyData: nil)
    }

    /// The phone's poll: is a TV of mine looking for a remote? Already-paired TVs and
    /// this device itself are left out server-side.
    public func fetchRemoteBeacons() async throws -> [YsojAPI.RemoteBeacon] {
        guard let url = buildURL(path: "/ysoj/remote/beacons",
                                 query: [URLQueryItem(name: "deviceId", value: deviceId)]) else {
            throw JellyfinRequestError.invalidURL
        }
        let response: YsojAPI.RemoteBeaconsResponse = try await request(url: url)
        return response.beacons
    }

    /// Answer a beacon: this device becomes that TV's remote. A refusal arrives as
    /// `JellyfinRequestError.server(status:body:)` whose body carries the sentence to show.
    public func acceptRemotePairing(beaconId: String, deviceName: String) async throws -> YsojAPI.RemotePairing {
        guard let url = buildURL(path: "/ysoj/remote/pair", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        let body = try JSONEncoder().encode([
            "beaconId": beaconId, "deviceId": deviceId, "deviceName": deviceName,
        ])
        return try await request(url: url, method: .post, bodyData: body)
    }

    /// Every pairing this device is one side of — what both a phone and a TV restore
    /// from on launch.
    public func fetchRemotePairings() async throws -> [YsojAPI.RemotePairing] {
        guard let url = buildURL(path: "/ysoj/remote/pairings",
                                 query: [URLQueryItem(name: "deviceId", value: deviceId)]) else {
            throw JellyfinRequestError.invalidURL
        }
        let response: YsojAPI.RemotePairingsResponse = try await request(url: url)
        return response.pairings
    }

    /// Name a TV from the phone. The server puts the name on every pairing of that TV,
    /// so a second phone sees "Bedroom" too.
    public func renameRemotePairing(id: String, name: String) async throws -> YsojAPI.RemotePairing {
        guard let url = buildURL(path: "/ysoj/remote/pairings/\(id)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        let body = try JSONEncoder().encode(["tvName": name])
        return try await request(url: url, method: .patch, bodyData: body)
    }

    public func deleteRemotePairing(id: String) async throws {
        guard let url = buildURL(path: "/ysoj/remote/pairings/\(id)", query: nil) else {
            throw JellyfinRequestError.invalidURL
        }
        _ = try await send(url: url, method: .delete, bodyData: nil)
    }

    // MARK: - Transport

    private static let maxAttempts = 3
    private static let perAttemptTimeout: TimeInterval = 20

    private struct SourcesResponse: Decodable, Sendable {
        let sources: [YsojAPI.Capabilities.Source]
    }

    private func request<T: Decodable & Sendable>(url: URL) async throws -> T {
        let (data, _) = try await send(url: url, method: .get, bodyData: nil)
        return try decode(T.self, from: data)
    }

    private func request<T: Decodable & Sendable>(
        url: URL, method: HTTPMethod, bodyData: Data
    ) async throws -> T {
        let (data, _) = try await send(url: url, method: method, bodyData: bodyData)
        return try decode(T.self, from: data)
    }

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
                // Not `try?`: a shelf load cancelled by the next chip press must stop
                // here, not swallow the cancellation and fire two more requests.
                try await Task.sleep(nanoseconds: backoffNs)
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
            throw JellyfinRequestError.server(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return (data, http)
    }

    /// GETs are safe to retry. **`/downloads/confirm` never is** — not because a duplicate
    /// would start two downloads (the plan is single-use server-side, so it wouldn't), but
    /// because the retry would come back 409 and be reported to the user as a failure of
    /// a job that had in fact just started. `plan` is retried: a spare plan row expires on
    /// its own and starts nothing.
    private func shouldRetry(method: HTTPMethod, url: URL, error: Error) -> Bool {
        // Only what a second attempt could change: a transient status or a transport
        // failure. A body that failed to decode will fail to decode three times.
        switch error {
        case JellyfinRequestError.server(let status, _):
            guard [408, 429, 500, 502, 503, 504].contains(status) else { return false }
        case let urlErr as URLError:
            switch urlErr.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed,
                 .cannotConnectToHost, .cannotFindHost: break
            default: return false
            }
        default:
            return false
        }
        switch method {
        case .get, .put, .patch, .delete: return true
        case .post: return !url.path.hasSuffix("/downloads/confirm")
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
        Self.url(base: baseURL, path: path, query: query)
    }

    /// The one place a path becomes a URL, kept static so the encoding rule is testable:
    /// `path` is *decoded* — `URLComponents.path` percent-encodes on the way out, and a
    /// hand-encoded `%3A` went out as `%253A` once, which spun every detail page forever.
    static func url(base: URL, path: String, query: [URLQueryItem]?) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: true) else {
            return nil
        }
        components.path = (components.path as NSString).appendingPathComponent(path)
        if let query, !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        return components.url
    }
}
