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

    /// Decoded sheets, keyed by URL, with a plain LRU. A 22-minute episode at
    /// the default 10s interval is ~132 frames across ~2 sheets, so a couple
    /// of dozen is generous for a session while still bounding memory.
    private var tileCache: [URL: UIImage] = [:]
    private var tileOrder: [URL] = []
    private static let maxCachedTiles = 24

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
                return nil
            }
            Self.log.notice("resolve: width=\(pick.widthKey, privacy: .public) interval=\(pick.info.interval)ms")
            return pick
        } catch {
            Self.log.warning("resolve failed: \(String(describing: error), privacy: .public)")
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
        let globalIndex = Int(max(0, timeSeconds * 1000) / Double(info.interval))
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

    private func fetchSheet(_ url: URL) async -> UIImage? {
        if let cached = tileCache[url] {
            touch(url)
            return cached
        }
        if let existing = inFlight[url] {
            return await existing.value
        }
        let task = Task<UIImage?, Never> {
            let started = Date()
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    Self.log.warning("sheet HTTP \(http.statusCode) in \(ms)ms")
                    return nil
                }
                guard let image = UIImage(data: data) else {
                    Self.log.warning("sheet decode failed (\(data.count) bytes)")
                    return nil
                }
                Self.log.notice("sheet fetched: \(data.count) bytes in \(ms)ms")
                return image
            } catch {
                Self.log.warning("sheet fetch failed: \(error.localizedDescription, privacy: .public)")
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
        tileCache[url] = image
        tileOrder.removeAll { $0 == url }
        tileOrder.append(url)
        while tileOrder.count > Self.maxCachedTiles {
            tileCache.removeValue(forKey: tileOrder.removeFirst())
        }
    }

    private func touch(_ url: URL) {
        tileOrder.removeAll { $0 == url }
        tileOrder.append(url)
    }

    /// Drop everything. The sheet URLs carry an `api_key`, but the *decoded*
    /// images have no auth boundary of their own — so they're wiped explicitly
    /// whenever credentials change rather than left to the LRU.
    func reset() {
        for (_, task) in inFlight { task.cancel() }
        inFlight.removeAll()
        tileCache.removeAll()
        tileOrder.removeAll()
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
