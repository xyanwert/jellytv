import Foundation

/// The resolved playback URLs + session info for one item, derived from
/// `POST /Items/{id}/PlaybackInfo`. The player tries `directURL` first and
/// falls back to `hlsURL` if AVPlayer can't decode the container.
///
/// Both URLs already carry `?api_key=...`, so even if the platform strips
/// the `Authorization` header on HLS segment sub-requests, the request
/// still authenticates. The engine attaches the header too — belt-and-suspenders.
public struct ResolvedPlayback: Sendable {
    public let itemId: String
    public let playSessionId: String
    public let mediaSourceId: String
    /// Present only when the resolved media source can be played natively.
    public let directURL: URL?
    /// Always present — Jellyfin transcodes to this if direct play isn't possible.
    public let hlsURL: URL
    public let mediaSource: JellyfinAPI.MediaSource
    /// The auth header to attach to the `AVURLAsset` for header-based auth.
    public let authHeader: String
}

public enum PlaybackInfoError: Error, LocalizedError, Sendable {
    case noMediaSource
    case serverErrorCode(String)

    public var errorDescription: String? {
        switch self {
        case .noMediaSource:
            return "Jellyfin reports no playable media for this item — the file may have moved or been deleted."
        case .serverErrorCode(let code):
            return "Jellyfin can't play this item (\(code))."
        }
    }

    /// Both cases here are per-item — safe for the caller to skip to the
    /// next queue entry rather than stopping playback entirely.
    public var isItemLevel: Bool { true }
}

/// Resolves one item to a `ResolvedPlayback`. Pure — no AVFoundation, no
/// player state — so the URL composition and direct-vs-HLS decision are
/// unit-testable without a device or a live server.
public struct PlaybackInfoResolver: Sendable {
    let client: JellyfinClient
    let userId: String

    public init(client: JellyfinClient, userId: String) {
        self.client = client
        self.userId = userId
    }

    public func resolve(itemId: String) async throws -> ResolvedPlayback {
        let response = try await client.fetchPlaybackInfo(userId: userId, itemId: itemId)

        if let code = response.errorCode, !code.isEmpty {
            throw PlaybackInfoError.serverErrorCode(code)
        }
        guard let mediaSource = response.mediaSources.first else {
            throw PlaybackInfoError.noMediaSource
        }
        // PlaySessionId is required for healthy items; undefined behavior if
        // it's missing alongside a populated mediaSources array — refuse to play.
        guard let playSessionId = response.playSessionId, !playSessionId.isEmpty else {
            throw PlaybackInfoError.noMediaSource
        }
        guard let hlsURL = client.hlsManifestURL(itemId: itemId, mediaSourceId: mediaSource.id,
                                                  playSessionId: playSessionId) else {
            throw PlaybackInfoError.noMediaSource
        }
        let directURL: URL? = mediaSource.canDirectPlayNatively
            ? client.directStreamURL(itemId: itemId, mediaSourceId: mediaSource.id)
            : nil

        return ResolvedPlayback(
            itemId: itemId,
            playSessionId: playSessionId,
            mediaSourceId: mediaSource.id,
            directURL: directURL,
            hlsURL: hlsURL,
            mediaSource: mediaSource,
            authHeader: client.authorizationHeader
        )
    }
}
