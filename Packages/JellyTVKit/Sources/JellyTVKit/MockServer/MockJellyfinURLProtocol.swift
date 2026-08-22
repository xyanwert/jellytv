import Foundation

/// A `URLProtocol` that answers Jellyfin's REST API with real,
/// TMDB/AniList-sourced data from `MockCatalogLoader` — registered globally
/// only when `JT_MOCK_SERVER` is set (see `MockJellyfinServer.start()`).
/// `canInit` matches only requests to the mock's own loopback port; anything
/// else (including the image pass-through fetches this class itself makes)
/// falls through to real networking untouched.
public final class MockJellyfinURLProtocol: URLProtocol {
    static var mockPort: UInt16?

    private var imageProxyTask: Task<Void, Never>?

    public override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, url.scheme == "http", url.host == "127.0.0.1",
              let port = mockPort, url.port == Int(port) else { return false }
        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        guard let url = request.url else { fail(); return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let segments = url.path.split(separator: "/").map(String.init)
        let method = request.httpMethod ?? "GET"

        func q(_ name: String) -> String? { query.first { $0.name == name }?.value }

        // Images: a live pass-through fetch to the real TMDB/AniList CDN URL.
        if segments.count >= 4, segments[0] == "Items", segments[2] == "Images" {
            proxyImage(itemId: segments[1], type: segments[3],
                       index: segments.count >= 5 ? Int(segments[4]) : nil)
            return
        }

        if segments == ["System", "Info", "Public"] {
            respondJSON(MockCatalogLoader.shared.systemInfoJSON())
            return
        }
        if segments == ["UserViews"] {
            respondJSON(MockCatalogLoader.shared.userViewsJSON())
            return
        }
        if segments == ["Items"] {
            respondJSON(MockCatalogLoader.shared.itemsJSON(
                parentId: q("parentId"), includeItemTypes: q("includeItemTypes"),
                filters: q("filters"), sortBy: q("sortBy"), sortOrder: q("sortOrder"),
                limit: q("limit").flatMap(Int.init)))
            return
        }
        if segments.count == 4, segments[0] == "Users", segments[2] == "Items" {
            if let json = MockCatalogLoader.shared.itemDetailJSON(itemId: segments[3]) {
                respondJSON(json)
            } else {
                respondNotFound()
            }
            return
        }
        if segments.count == 3, segments[0] == "Shows", segments[2] == "Seasons" {
            respondJSON(MockCatalogLoader.shared.seasonsJSON(seriesId: segments[1]))
            return
        }
        if segments.count == 3, segments[0] == "Shows", segments[2] == "Episodes" {
            respondJSON(MockCatalogLoader.shared.episodesJSON(seriesId: segments[1], seasonId: q("seasonId")))
            return
        }
        if segments.count == 3, segments[0] == "Items", segments[2] == "PlaybackInfo" {
            respondJSON(MockCatalogLoader.shared.playbackInfoJSON(itemId: segments[1]))
            return
        }
        if segments.first == "Sessions" {
            respondEmptyOK()
            return
        }
        if segments.count == 4, segments[0] == "Users", segments[2] == "FavoriteItems",
           method == "POST" || method == "DELETE" {
            respondEmptyOK()
            return
        }

        respondNotFound()
    }

    public override func stopLoading() {
        imageProxyTask?.cancel()
    }

    // MARK: - Response helpers

    private func respondJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { fail(); return }
        respond(data: data, contentType: "application/json", status: 200)
    }

    private func respondEmptyOK() {
        respond(data: Data(), contentType: "application/json", status: 200)
    }

    private func respondNotFound() {
        respond(data: Data(), contentType: "application/json", status: 404)
    }

    private func respond(data: Data, contentType: String, status: Int) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                              headerFields: ["Content-Type": contentType]) else {
            fail()
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func fail() {
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
    }

    /// A live fetch (via a plain, non-mock `URLSession`) to the real external
    /// TMDB/AniList CDN URL recorded for this item/type — `canInit` only
    /// matches the mock's own loopback host/port, so this never recurses.
    private func proxyImage(itemId: String, type: String, index: Int?) {
        guard let target = MockCatalogLoader.shared.imageURL(itemId: itemId, type: type, index: index) else {
            respondNotFound()
            return
        }
        imageProxyTask = Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: target)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    respondNotFound()
                    return
                }
                respond(data: data, contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "image/jpeg", status: 200)
            } catch {
                respondNotFound()
            }
        }
    }
}

/// Starts the dev-only mock Jellyfin server: registers the `URLProtocol`
/// above globally (covers `JellyfinClient`'s JSON calls and
/// `JellyfinAsyncImage`'s plain `AsyncImage` loads — both are `URLSession`
/// traffic) and boots the tiny real loopback listener for video-stream
/// routes. Idempotent — safe to call more than once.
public enum MockJellyfinServer {
    private static var registered = false

    public static func start() async -> URL {
        if !registered {
            URLProtocol.registerClass(MockJellyfinURLProtocol.self)
            registered = true
        }
        let port = await MockVideoRedirectServer.shared.start()
        MockJellyfinURLProtocol.mockPort = port
        return URL(string: "http://127.0.0.1:\(port)")!
    }
}
