import Foundation
import AVFoundation
import Observation
import JellyTVKit

/// High-level playback state surfaced to the chrome. KVO-bridged from
/// `AVPlayerItem.status`.
enum PlayerPhase: Sendable, Equatable {
    case idle
    /// Resolving PlaybackInfo / loading the asset.
    case loading
    /// AVPlayerItem is `.readyToPlay`. Playback may be paused or running.
    case ready
    /// Playback finished naturally (no next item / repeat-one off).
    case ended
    /// Unrecoverable error on the current item, after fallback + re-resolve
    /// were exhausted.
    case failed(message: String)
}

/// Owns the single `AVPlayer` and every playback robustness mechanism —
/// resolve → direct/HLS fallback → resume-seek → progress reporting →
/// teardown. `PlayerController` is the only thing chrome talks to; it reads
/// through to this engine.
///
/// **Lifecycle rule**: keep this in a `@State` on `PlayerView`, built once in
/// `.task { if engine == nil { ... } }`. SwiftUI rebuilds tear playback down
/// otherwise. Ported from `/Users/xyan/code/jelly-tv-ios`'s `PlayerEngine`,
/// trimmed of NowPlayingCenter/PiP/AudioSession/MediaSelection/MediaSegments
/// and series-expansion (this app's `AppState` pre-builds flat `PlayableItem`
/// queues, unlike v1's `JfItem`-based engine-side expansion).
@Observable @MainActor
final class PlayerEngine {

    // MARK: - Observable state

    private(set) var phase: PlayerPhase = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying: Bool = false
    /// True when AVPlayer reports the buffer empty or not likely to keep up
    /// while playback is otherwise running — drives a small inline spinner
    /// during mid-playback rebuffering instead of a silently frozen frame.
    private(set) var isBuffering: Bool = false
    private(set) var currentItem: PlayableItem?
    /// The media source the server actually negotiated for this item. Kept
    /// because trickplay sheets are addressed per media source — it was
    /// previously computed during `wireUp` and thrown away.
    private(set) var currentMediaSourceId: String?
    /// Scene thumbnails. Lives here so its sheet cache outlives any one
    /// opening of the panel.
    let trickplayClient: TrickplayClient
    private(set) var isFavorite: Bool = false
    private(set) var repeatOne: Bool = false
    private(set) var queue: [PlayableItem] = []
    private(set) var queueIndex: Int = 0

    var hasNext: Bool { queueIndex + 1 < queue.count }
    var hasPrevious: Bool { queueIndex > 0 }
    var queuePositionLabel: String? {
        guard queue.count > 1 else { return nil }
        return "\(queueIndex + 1)/\(queue.count)"
    }

    /// The underlying AVPlayer. `PlayerLayerView` hosts it via `AVPlayerLayer`.
    let avPlayer = AVPlayer()

    // MARK: - Deps

    private let client: JellyfinClient
    private let userId: String
    private let resolver: PlaybackInfoResolver

    /// Bumped on each `setItem` call — aborts late callbacks from a
    /// superseded load.
    private let generation = Generation()

    /// Tracks consecutive load failures across the queue. Resets on first
    /// successful play.
    private var failureStreak = 0
    private static let failureLimit = 3

    /// Per-item re-resolve attempt counter — capped at 1 so a durably broken
    /// server doesn't storm PlaybackInfo requests.
    private var reresolveAttemptsForCurrentItem = 0
    private static let reresolveLimitPerItem = 1

    /// Sliding window of recent HTTP 5xx error-log timestamps. AVPlayer can
    /// stay `.readyToPlay` while every segment fetch 500s (half-dead
    /// transcoder) — this is the only signal that catches that case.
    private var recentHTTPServerErrors: [Date] = []
    private static let httpErrorBurstThreshold = 3
    private static let httpErrorWindow: TimeInterval = 5

    private var timeObserverToken: Any?
    private var endObserver: (any NSObjectProtocol)?
    private var errorLogObserver: (any NSObjectProtocol)?
    private var statusObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var bufferKeepUpObservation: NSKeyValueObservation?

    private weak var currentPlayerItem: AVPlayerItem?
    private var progressReporter: ProgressReporter?

    init(client: JellyfinClient, userId: String) {
        self.client = client
        self.userId = userId
        // No audio-session setup here: on iOS the app already claims
        // `.playback`/`.moviePlayback` once at launch in `RemoteApp.init`, and
        // it owns that session for the whole process. Re-activating it per
        // engine is redundant, and deactivating it on teardown would tear
        // down the app-wide session behind `RemoteApp`'s back. tvOS has no
        // equivalent knob to set.
        self.resolver = PlaybackInfoResolver(client: client, userId: userId)
        self.trickplayClient = TrickplayClient(client: client, userId: userId)
    }

    // MARK: - Public API

    /// Load a request (single item or queue) and start playback at the
    /// request's `startIndex`.
    func play(_ request: PlaybackRequest) async {
        guard !request.items.isEmpty else { return }
        queue = request.items
        queueIndex = max(0, min(request.startIndex, request.items.count - 1))
        await setItem(queue[queueIndex])
    }

    @discardableResult
    func advanceQueue() async -> Bool {
        let nextIdx = queueIndex + 1
        guard nextIdx < queue.count else { return false }
        queueIndex = nextIdx
        await setItem(queue[nextIdx])
        return true
    }

    @discardableResult
    func regressQueue() async -> Bool {
        let prev = queueIndex - 1
        guard prev >= 0 else { return false }
        queueIndex = prev
        await setItem(queue[prev])
        return true
    }

    /// User-initiated retry — clears every safety brake so explicit intent
    /// overrides the auto-skip cap.
    func retryCurrentItem() async {
        guard let item = currentItem else { return }
        failureStreak = 0
        await setItem(item)
    }

    func toggleRepeatOne() {
        repeatOne.toggle()
    }

    /// Real Jellyfin endpoint — optimistic update, reverted on failure.
    func toggleFavorite() async {
        guard let item = currentItem else { return }
        let newValue = !isFavorite
        isFavorite = newValue
        do {
            if newValue {
                try await client.setFavorite(userId: userId, itemId: item.id)
            } else {
                try await client.clearFavorite(userId: userId, itemId: item.id)
            }
        } catch {
            isFavorite = !newValue
        }
    }

    func play() {
        avPlayer.play()
        isPlaying = true
    }

    func pause() {
        avPlayer.pause()
        isPlaying = false
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    /// The app's own output gain, 0…1 — distinct from the system volume the
    /// hardware buttons move, which no app may touch. Night mode's wind-down
    /// rides on this and hands it back when it's done.
    var volume: Float {
        get { avPlayer.volume }
        set { avPlayer.volume = max(0, min(1, newValue)) }
    }

    func seek(to seconds: Double) async {
        let target = max(0, min(duration > 0 ? duration : seconds, seconds))
        let cm = CMTime(seconds: target, preferredTimescale: 600)
        await avPlayer.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        // Reflect the new position immediately — otherwise the chrome shows
        // the pre-seek time until the next periodic observer tick.
        currentTime = target
    }

    func seekRelative(_ delta: Double) async {
        await seek(to: currentTime + delta)
    }

    /// Resolve and start playing the given item. Safe to call repeatedly —
    /// each call supersedes the in-flight load.
    func setItem(_ item: PlayableItem) async {
        let token = generation.next()
        phase = .loading
        currentItem = item
        isFavorite = item.isFavorite
        isPlaying = false
        reresolveAttemptsForCurrentItem = 0

        // Capture the outgoing item's position BEFORE tearing down
        // observers, so `/Sessions/Playing/Stopped` carries an accurate
        // position instead of 0 — otherwise every queue advance wrecks the
        // Continue Watching shelf for the item we just left.
        let outgoingTicks = ticksFrom(seconds: currentTime)
        tearDownObservers()
        await progressReporter?.reportStop(positionTicks: outgoingTicks)
        progressReporter = nil

        do {
            let resolved = try await resolver.resolve(itemId: item.id)
            if generation.isCancelled(token) { return }
            PlayerDiagnostics.logResolved(resolved, item: item)
            if PlayerDiagnostics.isEnabled, resolved.directURL == nil {
                Task { await PlayerDiagnostics.dumpPlaylists(masterURL: resolved.hlsURL, authHeader: resolved.authHeader) }
            }
            await wireUp(resolved: resolved, item: item, token: token)
            failureStreak = 0
        } catch {
            PlayerDiagnostics.log("resolve FAILED for \"\(item.title)\": \(error)")
            failureStreak += 1
            phase = .failed(message: failureMessage(for: error))
            // Item-level resolve failure inside a multi-item queue →
            // auto-skip so one broken episode doesn't strand the user.
            if shouldAutoSkipAfterFailure(error: error) {
                _ = await advanceQueue()
            }
        }
    }

    /// Final teardown. Posts `/Sessions/Playing/Stopped`, removes observers.
    func teardown() async {
        let positionTicks = ticksFrom(seconds: currentTime)
        await progressReporter?.reportStop(positionTicks: positionTicks)
        progressReporter = nil
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        tearDownObservers()
        phase = .idle
        isPlaying = false
        isBuffering = false
        currentItem = nil
    }

    // MARK: - Failure handling

    private func shouldAutoSkipAfterFailure(error: Error) -> Bool {
        guard queueIndex + 1 < queue.count else { return false }
        guard failureStreak < Self.failureLimit else { return false }
        if let infoError = error as? PlaybackInfoError {
            return infoError.isItemLevel
        }
        return true
    }

    private func failureMessage(for error: Error) -> String {
        if let info = error as? PlaybackInfoError {
            return info.errorDescription ?? "Playback failed."
        }
        if case JellyfinRequestError.server(let status, _) = error {
            return "Playback failed — the server returned HTTP \(status)."
        }
        if case JellyfinRequestError.unauthorized = error {
            return "Playback failed — not authorized."
        }
        return "Playback failed — the connection was lost."
    }

    /// Append a timestamp to the HTTP-5xx burst window and, if it exceeds
    /// the threshold, escalate by re-resolving the current item with a
    /// fresh `playSessionId`. Fired from the error-log observer whenever a
    /// segment fetch returns HTTP 5xx.
    private func noteHTTPServerError() {
        let now = Date()
        recentHTTPServerErrors.append(now)
        let cutoff = now.addingTimeInterval(-Self.httpErrorWindow)
        recentHTTPServerErrors.removeAll { $0 < cutoff }

        guard recentHTTPServerErrors.count >= Self.httpErrorBurstThreshold else { return }
        guard let item = currentItem else { return }
        recentHTTPServerErrors.removeAll()

        guard reresolveAttemptsForCurrentItem < Self.reresolveLimitPerItem else {
            phase = .failed(message: "Playback failed — the server returned repeated 500 errors and a fresh session didn't recover.")
            isPlaying = false
            if queueIndex + 1 < queue.count, failureStreak < Self.failureLimit {
                failureStreak += 1
                Task { await advanceQueue() }
            }
            return
        }
        reresolveAttemptsForCurrentItem += 1
        Task { await setItemReresolving(item) }
    }

    /// Reload the same item via a fresh PlaybackInfo round-trip while
    /// preserving the per-item re-resolve budget counter.
    private func setItemReresolving(_ item: PlayableItem) async {
        let savedBudget = reresolveAttemptsForCurrentItem
        await setItem(item)
        reresolveAttemptsForCurrentItem = savedBudget
    }

    // MARK: - Wire-up

    private func wireUp(resolved: ResolvedPlayback, item: PlayableItem, token: Int) async {
        currentMediaSourceId = resolved.mediaSourceId
        let primary = resolved.directURL ?? resolved.hlsURL
        let fallback: URL? = resolved.directURL != nil ? resolved.hlsURL : nil

        let asset = makeAsset(url: primary, authHeader: resolved.authHeader)
        let playerItem = AVPlayerItem(asset: asset)
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        attachObservers(to: playerItem, resolved: resolved, fallback: fallback, token: token)
        avPlayer.replaceCurrentItem(with: playerItem)

        let reporter = ProgressReporter(
            client: client,
            itemId: item.id,
            playSessionId: resolved.playSessionId,
            mediaSourceId: resolved.mediaSourceId
        )
        // Stale-session recovery: N consecutive 404s on the progress POST
        // means Jellyfin forgot our playSessionId (idle past server
        // timeout) — re-resolve for a fresh one before a segment fetch
        // 404s and wedges playback.
        reporter.onStaleSessionDetected = { [weak self] in
            guard let self else { return }
            // Within ~30s of natural end-of-video, the server may have
            // already closed the session. Re-resolving here would bump the
            // generation token and cancel the about-to-fire end-of-video
            // handler, silently breaking auto-advance — let it run instead.
            let nearEnd = self.duration > 0 && self.currentTime >= self.duration - 30
            if nearEnd { return }
            guard let curItem = self.currentItem,
                  self.reresolveAttemptsForCurrentItem < Self.reresolveLimitPerItem else { return }
            self.reresolveAttemptsForCurrentItem += 1
            Task { @MainActor in
                await self.setItemReresolving(curItem)
            }
        }
        await reporter.reportStart(positionTicks: item.resumePositionTicks)

        // 4Hz tick — smooth enough for the scrubber; the actual Jellyfin
        // POST is independently throttled to 10s inside ProgressReporter.
        timeObserverToken = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { [weak self, weak reporter] _ in
            Task { @MainActor in
                guard let self, let reporter else { return }
                self.currentTime = self.avPlayer.currentTime().seconds
                let positionTicks = self.ticksFrom(seconds: self.currentTime)
                await reporter.reportProgressIfDue(positionTicks: positionTicks, isPaused: !self.isPlaying)
            }
        }
        progressReporter = reporter

        // Load-timeout watchdog. AVPlayerItem.status can stick on `.unknown`
        // indefinitely (DNS hiccup, hung transcoder, empty segment store) —
        // without this the user sees the spinner forever with no recourse.
        Task { [token, weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self else { return }
            guard !self.generation.isCancelled(token) else { return }
            if case .loading = self.phase {
                self.phase = .failed(message: "Playback load timed out — the server didn't deliver a playable manifest.")
                self.isPlaying = false
                if self.queueIndex + 1 < self.queue.count, self.failureStreak < Self.failureLimit {
                    self.failureStreak += 1
                    Task { await self.advanceQueue() }
                }
            }
        }
    }

    /// Registers every per-item observer on `playerItem`.
    ///
    /// Shared by the initial wire-up and the direct→HLS fallback swap. The
    /// fallback used to re-register only `statusObservation`, leaving the
    /// end-of-video, error-log and buffer observers still watching the
    /// *failed* item — so any file that fell back to HLS (in a Jellyfin
    /// library, most of them) played fine but never fired
    /// `AVPlayerItemDidPlayToEndTime`, and therefore never auto-advanced the
    /// queue or reached `.ended`.
    private func attachObservers(to playerItem: AVPlayerItem, resolved: ResolvedPlayback,
                                 fallback: URL?, token: Int) {
        // Keep ~30s of forward buffer so range requests batch into longer
        // chunks on a fast LAN — the framework default is tuned for cellular.
        playerItem.preferredForwardBufferDuration = 30
        currentPlayerItem = playerItem
        tearDownItemObservers()

        // `[.initial, .new]` — without `.initial`, a status transition that
        // AVPlayer performs synchronously inside `replaceCurrentItem` can be
        // missed if the KVO edge coalesces before the observer registers.
        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] kvoItem, _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.generation.isCancelled(token) else { return }
                await self.handleStatus(item: kvoItem, resolved: resolved, fallback: fallback, token: token)
            }
        }

        bufferEmptyObservation = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.generation.isCancelled(token) else { return }
                self.recomputeBufferingState()
            }
        }
        bufferKeepUpObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.generation.isCancelled(token) else { return }
                self.recomputeBufferingState()
            }
        }

        // AVPlayerItem error-log entries surface the real HTTP status from
        // segment fetches that `AVPlayerItem.error` collapses away.
        errorLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification,
            object: playerItem,
            queue: .main
        ) { [weak self, weak playerItem] _ in
            guard let entry = playerItem?.errorLog()?.events.last else { return }
            let code = entry.errorStatusCode
            PlayerDiagnostics.log("errorLog status=\(code) domain=\(entry.errorDomain) comment=\(entry.errorComment ?? "-")")
            let isServerError = code >= 500 || code == -16847 // kCMHTTPError, AVFoundation's HTTP-mapped variant
            if isServerError {
                Task { @MainActor in
                    self?.noteHTTPServerError()
                }
            }
        }

        // End-of-video: repeat-one wins, else auto-advance, else `.ended`.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.generation.isCancelled(token) else { return }
                if self.repeatOne {
                    await self.avPlayer.seek(to: .zero)
                    self.avPlayer.play()
                    return
                }
                let advanced = await self.advanceQueue()
                if advanced { return }
                self.phase = .ended
                self.isPlaying = false
            }
        }
    }

    private func handleStatus(item: AVPlayerItem, resolved: ResolvedPlayback, fallback: URL?, token: Int) async {
        switch item.status {
        case .readyToPlay:
            if PlayerDiagnostics.isEnabled {
                // Deferred a beat: an HLS item's `tracks` only populate once
                // the first segment is parsed, so sampling them the instant
                // status flips to `.readyToPlay` always reads as empty.
                Task { [weak item] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let item else { return }
                    PlayerDiagnostics.logTracks(of: item, label: fallback == nil ? "hls-or-final" : "direct")
                }
            }
            duration = item.duration.isNumeric ? item.duration.seconds : Double(currentItem?.runtimeTicks ?? 0) / 10_000_000
            if let resumeTicks = currentItem?.resumePositionTicks, resumeTicks > 0 {
                let resumeSeconds = Double(resumeTicks) / 10_000_000
                let total = duration
                // Skip the resume seek if we're essentially at the start
                // (fresh) or within 30s of the end (treat as completed).
                if resumeSeconds > 5 && (total <= 0 || resumeSeconds < total - 30) {
                    PlayerDiagnostics.log("resume seek → \(Int(resumeSeconds))s of \(Int(total))s")
                    await seek(to: resumeSeconds)
                }
            }
            phase = .ready
            failureStreak = 0
            play()
        case .failed:
            let underlying = item.error?.localizedDescription ?? "AVPlayerItem failed"
            PlayerDiagnostics.log("item FAILED (\(underlying)) — \(fallback != nil ? "falling back to HLS" : "no fallback left")")
            if let fallback {
                let asset = makeAsset(url: fallback, authHeader: resolved.authHeader)
                let nextItem = AVPlayerItem(asset: asset)
                attachObservers(to: nextItem, resolved: resolved, fallback: nil, token: token)
                avPlayer.replaceCurrentItem(with: nextItem)
            } else if let curItem = currentItem,
                      reresolveAttemptsForCurrentItem < Self.reresolveLimitPerItem {
                // Both primary and fallback exhausted, but we haven't tried
                // a fresh PlaybackInfo POST yet — recovers from an expired
                // session, a crashed transcoder, or a post-restart cleanup.
                reresolveAttemptsForCurrentItem += 1
                await setItemReresolving(curItem)
            } else {
                failureStreak += 1
                phase = .failed(message: underlying)
                isPlaying = false
                if queueIndex + 1 < queue.count, failureStreak < Self.failureLimit {
                    _ = await advanceQueue()
                }
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func makeAsset(url: URL, authHeader: String) -> AVURLAsset {
        // Belt-and-suspenders: the header rides on the manifest/segment
        // fetches where the platform honors it; the URL also carries
        // `?api_key=...` as a fallback.
        AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": authHeader]
        ])
    }

    private func tearDownObservers() {
        // The periodic time observer belongs to the *player*, not the item,
        // so it's removed only here (full teardown / item change) and never
        // on a direct→HLS swap, which replaces just the item.
        if let t = timeObserverToken {
            avPlayer.removeTimeObserver(t)
            timeObserverToken = nil
        }
        tearDownItemObservers()
    }

    private func tearDownItemObservers() {
        if let o = endObserver {
            NotificationCenter.default.removeObserver(o)
            endObserver = nil
        }
        if let o = errorLogObserver {
            NotificationCenter.default.removeObserver(o)
            errorLogObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        bufferKeepUpObservation?.invalidate()
        bufferKeepUpObservation = nil
    }

    // MARK: - Buffering state

    /// Collapses the two buffer KVOs into one boolean the chrome renders
    /// off of. A paused stream that's still filling its buffer isn't
    /// "buffering" from the user's point of view.
    private func recomputeBufferingState() {
        guard let item = currentPlayerItem, isPlaying else {
            if isBuffering { isBuffering = false }
            return
        }
        let stalled = item.isPlaybackBufferEmpty || !item.isPlaybackLikelyToKeepUp
        if stalled != isBuffering {
            isBuffering = stalled
        }
    }

    // MARK: - Ticks conversion

    /// Jellyfin positions are in 10,000,000ths of a second.
    private func ticksFrom(seconds: Double) -> Int64 {
        Int64(seconds * 10_000_000)
    }

    // MARK: - Debug fixture (JT_SHOW_PLAYER)

    /// Screenshot-only seam — lets `PlayerPreviewFixture` show `PlayerChrome`
    /// in a "ready, playing" state with no live `AVPlayer`/network resolve.
    /// Never called outside that debug harness.
    func previewSeed(item: PlayableItem, currentTime: Double, duration: Double,
                     isPlaying: Bool, isFavorite: Bool, queue: [PlayableItem], queueIndex: Int,
                     failureMessage: String? = nil) {
        self.currentItem = item
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.isFavorite = isFavorite
        self.queue = queue
        self.queueIndex = queueIndex
        self.phase = failureMessage.map { .failed(message: $0) } ?? .ready
    }
}
