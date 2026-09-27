import Foundation
import UIKit
import os
import JellyTVKit

/// Fetches and slices Jellyfin trickplay sprite sheets so the scenes panel can
/// show thumbnails without scrubbing the video.
///
/// **Why sheets rather than seeks.** Jellyfin pre-generates a grid of small
/// frames — sampled every `interval` ms — baked into a handful of big JPEGs. We
/// download one sheet (a few hundred KB for ~100 frames) and cut every
/// thumbnail out of it locally. The alternative, asking AVPlayer for a
/// frame-accurate seek per thumbnail, costs hundreds of milliseconds each: a
/// six-thumbnail page measured ~1.1s that way against ~80ms once a sheet is
/// cached.
///
/// Ported from `/Users/xyan/code/jelly-tv-ios`'s `Core/Jellyfin/TrickplayClient.swift`,
/// which arrived at this shape over a dozen commits. Three of its bugs are
/// designed out here rather than rediscovered — see `bestResolution` (the
/// two-level response), the note on `thumbnailCount` in `JellyfinAPI.TrickplayInfo`,
/// and `inFlight` (duplicate fetches).
actor TrickplayClient {
    private static let log = Logger(subsystem: "net.graficx.jellytv", category: "trickplay")

    private let client: JellyfinClient
    private let userId: String

    /// Decoded sheets, keyed by URL, LRU **bounded by decoded bytes**, not by
    /// count. A count was fine while every sheet was a 320px 10×10 grid
    /// (~30 MB decoded); a 640px set is heavier per frame, and twenty-four of
    /// anything that size is gigabytes on an Apple TV. The budget holds ~6–8
    /// sheets, each covering four to sixteen minutes of video.
    private var tileCache: [URL: UIImage] = [:]
    private var tileCost: [URL: Int] = [:]
    private var tileOrder: [URL] = []
    private var cachedBytes = 0
    private static let maxCachedBytes = 192 * 1024 * 1024

    /// **Fetch dedupe.** A fresh page of six cells that all miss the cache
    /// otherwise pulls the same sheet six times — six times the bandwidth, and
    /// only the last write survives. Joining an in-flight task collapses them.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init(client: JellyfinClient, userId: String) {
        self.client = client
        self.userId = userId
    }

    /// The best available trickplay geometry for an item, or nil when the
    /// server has none — which is a normal answer, not an error.
    func resolve(itemId: String, mediaSourceId: String?) async
        -> (widthKey: String, info: JellyfinAPI.TrickplayInfo)? {
        do {
            let trickplay = try await client.fetchTrickplayInfo(userId: userId, itemId: itemId)
            guard let pick = Self.bestResolution(trickplay, forMediaSourceId: mediaSourceId) else {
                Self.log.notice("resolve: no trickplay for item=\(itemId, privacy: .public)")
                PlayerDiagnostics.log("trickplay: none for item=\(itemId)")
                return nil
            }
            Self.log.notice("resolve: width=\(pick.widthKey, privacy: .public) interval=\(pick.info.interval)ms")
            PlayerDiagnostics.log("trickplay: width=\(pick.widthKey) \(pick.info.width)x\(pick.info.height) grid=\(pick.info.tileWidth)x\(pick.info.tileHeight) every \(pick.info.interval)ms")
            return pick
        } catch {
            Self.log.warning("resolve failed: \(String(describing: error), privacy: .public)")
            PlayerDiagnostics.log("trickplay: resolve failed \(error)")
            return nil
        }
    }

    /// **The response nests two levels** — media-source id, then width — and
    /// reading the media-source key as a width is a decode failure that
    /// presents as "this item has no trickplay" rather than as an error. Pick
    /// the exact media source when we know it, else whatever the server listed
    /// first; then take the widest resolution, sorting the keys numerically
    /// (they are strings: `"1280"` sorts before `"320"` lexically).
    private static func bestResolution(
        _ trickplay: [String: [String: JellyfinAPI.TrickplayInfo]]?,
        forMediaSourceId mediaSourceId: String?
    ) -> (widthKey: String, info: JellyfinAPI.TrickplayInfo)? {
        guard let outer = trickplay, !outer.isEmpty else { return nil }
        let resolutions: [String: JellyfinAPI.TrickplayInfo]? = {
            if let mediaSourceId, let exact = outer[mediaSourceId] { return exact }
            return outer.first?.value
        }()
        guard let resolutions, !resolutions.isEmpty else { return nil }
        return resolutions
            .sorted { (Int($0.key) ?? 0) > (Int($1.key) ?? 0) }
            .first
            .map { ($0.key, $0.value) }
    }

    /// One thumbnail for one moment. Nil whenever anything is missing — a
    /// sheet that 404s, a frame past the end of the grid, a decode failure —
    /// so the caller renders an empty cell rather than a wrong one.
    func thumbnail(forSeconds timeSeconds: Double, itemId: String, widthKey: String,
                   info: JellyfinAPI.TrickplayInfo, mediaSourceId: String) async -> UIImage? {
        let perSheet = info.thumbsPerTile
        guard perSheet > 0, info.interval > 0 else {
            Self.log.warning("degenerate geometry tile=\(info.tileWidth)x\(info.tileHeight) interval=\(info.interval)")
            return nil
        }
        guard let width = Int(widthKey) else {
            Self.log.warning("width key not numeric: '\(widthKey, privacy: .public)'")
            return nil
        }

        // Which frame, which sheet, and where in that sheet's grid.
        let globalIndex = Self.frameIndex(forSeconds: timeSeconds, interval: info.interval)
        let tileIndex = globalIndex / perSheet
        let inTile = globalIndex % perSheet
        let col = inTile % info.tileWidth
        let row = inTile / info.tileWidth

        guard let url = client.trickplayTileURL(itemId: itemId, width: width,
                                                tileIndex: tileIndex,
                                                mediaSourceId: mediaSourceId) else { return nil }
        guard let sheet = await fetchSheet(url) else { return nil }
        return crop(sheet: sheet, col: col, row: row,
                    frameWidth: info.width, frameHeight: info.height)
    }

    /// The frame *nearest* a moment, not the one before it. Frame `n` is the
    /// picture at `n × interval`; truncating showed 46:48 as the 46:40
    /// frame — eight seconds back and, in the case that caught it, the other
    /// side of a cut, so a jump preview promised a scene the jump didn't
    /// land in.
    static func frameIndex(forSeconds seconds: Double, interval: Int) -> Int {
        Int((max(0, seconds) * 1000 / Double(interval)).rounded())
    }

    private func fetchSheet(_ url: URL) async -> UIImage? {
        if let cached = tileCache[url] {
            touch(url)
            return cached
        }
        if let existing = inFlight[url] {
            return await existing.value
        }
        // The header, never `?api_key=`: Jellyfin 10.11 401s the query-string
        // token on this route (see `JellyfinClient.trickplayTileURL`).
        var request = URLRequest(url: url)
        request.setValue(client.authorizationHeader, forHTTPHeaderField: "Authorization")
        let task = Task<UIImage?, Never> { [request, url] in
            let started = Date()
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    Self.log.warning("sheet HTTP \(http.statusCode) in \(ms)ms")
                    PlayerDiagnostics.log("trickplay: sheet HTTP \(http.statusCode) \(url.path)")
                    return nil
                }
                // Decoded once, here, off the main actor. A plain
                // `UIImage(data:)` is lazily decoded, and every crop out of
                // it would pay for the whole sheet again.
                guard let raw = UIImage(data: data) else {
                    Self.log.warning("sheet decode failed (\(data.count) bytes)")
                    return nil
                }
                let image = raw.preparingForDisplay() ?? raw
                Self.log.notice("sheet fetched: \(data.count) bytes in \(ms)ms")
                PlayerDiagnostics.log("trickplay: sheet \(url.pathComponents.suffix(2).joined(separator: "/")) \(data.count / 1024) KB in \(ms)ms")
                return image
            } catch {
                Self.log.warning("sheet fetch failed: \(error.localizedDescription, privacy: .public)")
                PlayerDiagnostics.log("trickplay: sheet failed \(error.localizedDescription)")
                return nil
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight.removeValue(forKey: url)
        if let image { insert(url: url, image: image) }
        return image
    }

    private func insert(url: URL, image: UIImage) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        if let old = tileCost[url] { cachedBytes -= old }
        tileCache[url] = image
        tileCost[url] = cost
        cachedBytes += cost
        tileOrder.removeAll { $0 == url }
        tileOrder.append(url)
        // Always keep the sheet just inserted, however large.
        while cachedBytes > Self.maxCachedBytes, tileOrder.count > 1 {
            let evicted = tileOrder.removeFirst()
            tileCache.removeValue(forKey: evicted)
            cachedBytes -= tileCost.removeValue(forKey: evicted) ?? 0
        }
    }

    /// Warm the sheets behind a set of moments without cutting anything, so
    /// the page a viewer is about to swipe to is already here. Sheets already
    /// cached or in flight cost nothing (`fetchSheet` joins them).
    func prefetch(seconds: [Double], itemId: String, widthKey: String,
                  info: JellyfinAPI.TrickplayInfo, mediaSourceId: String) async {
        guard info.thumbsPerTile > 0, info.interval > 0, let width = Int(widthKey) else { return }
        let sheets = Set(seconds.map { Self.frameIndex(forSeconds: $0, interval: info.interval) / info.thumbsPerTile })
        for index in sheets.sorted() {
            guard let url = client.trickplayTileURL(itemId: itemId, width: width, tileIndex: index,
                                                    mediaSourceId: mediaSourceId) else { continue }
            _ = await fetchSheet(url)
        }
    }

    private func touch(_ url: URL) {
        tileOrder.removeAll { $0 == url }
        tileOrder.append(url)
    }

    /// Drop everything. The sheets were fetched with the signed-in user's
    /// token, but the *decoded* images have no auth boundary of their own —
    /// so they're wiped explicitly whenever credentials change rather than
    /// left to the LRU.
    func reset() {
        for (_, task) in inFlight { task.cancel() }
        inFlight.removeAll()
        tileCache.removeAll()
        tileCost.removeAll()
        tileOrder.removeAll()
        cachedBytes = 0
    }

    /// Clamped against the decoded bitmap's real bounds — the last sheet of an
    /// item is usually only partly filled, so the arithmetic can point past
    /// the edge of a perfectly valid image.
    private nonisolated func crop(sheet: UIImage, col: Int, row: Int,
                                  frameWidth: Int, frameHeight: Int) -> UIImage? {
        guard let cg = sheet.cgImage else { return nil }
        let rect = CGRect(x: col * frameWidth, y: row * frameHeight,
                          width: frameWidth, height: frameHeight)
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let clamped = rect.intersection(bounds)
        guard !clamped.isEmpty, let cropped = cg.cropping(to: clamped) else { return nil }
        return UIImage(cgImage: cropped, scale: sheet.scale, orientation: sheet.imageOrientation)
    }
}
