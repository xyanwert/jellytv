import Foundation

/// Posts to Jellyfin's `/Sessions/Playing/*` endpoints on behalf of the
/// player engine. Caller-driven: the engine's periodic time observer calls
/// `reportProgressIfDue` on every tick; the reporter throttles the actual
/// network POST to once per 10s.
@MainActor
public final class ProgressReporter {
    private let client: JellyfinClient
    private let itemId: String
    private let playSessionId: String
    private let mediaSourceId: String
    private let throttle = Throttle(interval: 10)

    /// Fired when the reporter suspects the server-side session is gone
    /// (consecutive 404s on the progress POST — most commonly the server's
    /// idle timeout expiring). The engine wires this to a re-resolve so
    /// playback recovers without the user noticing.
    public var onStaleSessionDetected: (@MainActor () -> Void)?

    private var consecutive404s = 0
    private static let staleSessionLimit = 3
    private var didFireStaleCallback = false

    public init(client: JellyfinClient, itemId: String, playSessionId: String, mediaSourceId: String) {
        self.client = client
        self.itemId = itemId
        self.playSessionId = playSessionId
        self.mediaSourceId = mediaSourceId
    }

    /// Fire once on item mount.
    public func reportStart(positionTicks: Int64?) async {
        try? await client.reportPlaybackStart(.init(
            itemId: itemId, mediaSourceId: mediaSourceId, playSessionId: playSessionId, positionTicks: positionTicks
        ))
    }

    /// Called from the engine's periodic time observer; skips the network
    /// POST if fewer than 10s have elapsed since the last one.
    public func reportProgressIfDue(positionTicks: Int64, isPaused: Bool) async {
        var fired = false
        throttle.fire { fired = true }
        guard fired else { return }
        do {
            try await client.reportPlaybackProgress(.init(
                itemId: itemId, mediaSourceId: mediaSourceId, playSessionId: playSessionId,
                positionTicks: positionTicks, isPaused: isPaused
            ))
            if consecutive404s > 0 || didFireStaleCallback {
                consecutive404s = 0
                didFireStaleCallback = false
            }
        } catch {
            // Stale-session detection: Jellyfin 404s the progress POST once
            // it's forgotten our playSessionId. After N consecutive 404s,
            // fire the callback so the engine can re-resolve for a fresh one.
            if case JellyfinRequestError.server(let status, _) = error, status == 404 {
                consecutive404s += 1
                if consecutive404s >= Self.staleSessionLimit, !didFireStaleCallback {
                    didFireStaleCallback = true
                    onStaleSessionDetected?()
                }
            }
        }
    }

    /// Final stop — fires once on teardown/dismiss.
    public func reportStop(positionTicks: Int64?) async {
        try? await client.reportPlaybackStop(.init(
            itemId: itemId, mediaSourceId: mediaSourceId, playSessionId: playSessionId, positionTicks: positionTicks
        ))
    }
}
