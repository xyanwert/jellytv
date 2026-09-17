import Foundation

/// Posts to Jellyfin's `/Sessions/Playing/*` endpoints on behalf of the
/// player engine. Caller-driven: the engine's periodic time observer calls
/// `reportProgressIfDue` on every tick; the reporter throttles the actual
/// network POST to once per 10s.
@MainActor
public final class PlaybackProgressReporter {
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
    /// Reports go out one after another, in the order they were asked for. A remote
    /// reads the *last* one the server received, and two in flight at once — a pause
    /// and the resume right behind it — can land in either order.
    private var chain: Task<Void, Never>?

    private func enqueue(_ post: @escaping @MainActor () async -> Void) async {
        let previous = chain
        let next = Task { @MainActor in
            await previous?.value
            await post()
        }
        chain = next
        await next.value
    }

    public init(client: JellyfinClient, itemId: String, playSessionId: String, mediaSourceId: String) {
        self.client = client
        self.itemId = itemId
        self.playSessionId = playSessionId
        self.mediaSourceId = mediaSourceId
    }

    /// Fire once on item mount. Through the chain like everything else: a start that
    /// overtook a still-in-flight stop for the previous item would be undone by it.
    public func reportStart(positionTicks: Int64?) async {
        await enqueue { [self] in
            try? await client.reportPlaybackStart(.init(
                itemId: itemId, mediaSourceId: mediaSourceId, playSessionId: playSessionId,
                positionTicks: positionTicks
            ))
        }
    }

    /// Called from the engine's periodic time observer; skips the network
    /// POST if fewer than 10s have elapsed since the last one.
    public func reportProgressIfDue(positionTicks: Int64, isPaused: Bool) async {
        var fired = false
        throttle.fire { fired = true }
        guard fired else { return }
        await enqueue { [self] in await postProgress(positionTicks: positionTicks, isPaused: isPaused) }
    }

    private func postProgress(positionTicks: Int64, isPaused: Bool) async {
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

    /// An immediate report, outside the throttle — for the moments a remote is watching
    /// for: pause, resume and seek. Left to the ten-second tick, a phone that just pressed
    /// pause would watch the TV's clock keep running for up to ten seconds and press again.
    public func reportNow(positionTicks: Int64, isPaused: Bool) async {
        await enqueue { [self] in await postProgress(positionTicks: positionTicks, isPaused: isPaused) }
    }

    /// Final stop — fires once on teardown/dismiss. Chained, so a progress post still in
    /// flight cannot land after it and resurrect a stopped session's "now playing".
    public func reportStop(positionTicks: Int64?) async {
        await enqueue { [self] in
            try? await client.reportPlaybackStop(.init(
                itemId: itemId, mediaSourceId: mediaSourceId, playSessionId: playSessionId,
                positionTicks: positionTicks
            ))
        }
    }
}
