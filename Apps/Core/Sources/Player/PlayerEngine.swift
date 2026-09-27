import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import UIKit
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
    /// Intro/credits markers for the current item, as the *server's* segment
    /// providers reported them. Empty for everything nobody has analysed,
    /// which is most of a library — every consumer must degrade to "no
    /// button" rather than treating emptiness as a failure.
    private(set) var segments: [MediaSegment] = []
    /// The segment the playhead is inside right now, if it is one this app
    /// offers to skip. Recomputed on the 4Hz tick; nil the rest of the time.
    private(set) var activeSegment: MediaSegment?
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
    private var progressReporter: PlaybackProgressReporter?

    /// The picture is parked (rate 0, `isPlaying` untouched) under a skip's
    /// fast-forward — see `skipHolding`. Any real play/pause, a new item or
    /// a teardown clears it, so a hold can never outlive the tape.
    private var heldForSkip = false
    /// How long `skipHolding` waits for the landing to become playable
    /// before giving the picture back regardless. Well past any seek that
    /// is going to succeed; a stalled one is the viewer's to notice.
    private static let heldSkipTimeout: TimeInterval = 10

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
        heldForSkip = false
        avPlayer.play()
        isPlaying = true
        reportNow()
    }

    func pause() {
        heldForSkip = false
        avPlayer.pause()
        isPlaying = false
        reportNow()
    }

    /// Tells the server *now* rather than at the next ten-second tick. A paired phone
    /// reads this session's `PlayState` to draw its remote; left to the throttle, a
    /// pause pressed there would show the clock still running for up to ten seconds
    /// and get pressed again.
    private func reportNow() {
        // Only once the item is actually up. The resume seek runs *before* the first
        // `play()`, and reporting it said "paused" a few milliseconds ahead of the
        // "playing" that followed — two posts racing, and a paired phone's glyph read
        // whichever landed last (verified: paused, for the ten seconds until the next
        // periodic report).
        guard let progressReporter, case .ready = phase else { return }
        let ticks = ticksFrom(seconds: currentTime)
        let paused = !isPlaying
        Task { await progressReporter.reportNow(positionTicks: ticks, isPaused: paused) }
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
        // the pre-seek time until the next periodic observer tick. The same
        // goes for the skip on offer: a seek that lands inside an intro (a
        // scenes tile, a resume) should show the button now, not a tick later.
        currentTime = target
        if !heldForSkip {
            activeSegment = MediaSegments.skippable(at: target, in: segments)
        }
        reportNow()
    }

    func seekRelative(_ delta: Double) async {
        await seek(to: currentTime + delta)
    }

    /// Jump to the end of a segment the viewer asked to skip.
    ///
    /// Lands a hair *before* the end rather than exactly on it: `seek(to:)`
    /// already clamps to `duration`, but an end-credits segment that runs to
    /// the last frame would otherwise park the playhead on end-of-item and
    /// auto-advance — so "skip the credits" would silently start the next
    /// episode instead of showing them the last shot.
    func skip(_ segment: MediaSegment) async {
        // Clear immediately so the button cannot be pressed twice while the
        // seek settles; the next tick recomputes it anyway.
        activeSegment = nil
        await seek(to: skipTarget(for: segment))
    }

    /// Where a skip of `segment` lands: its end, or a second short of the
    /// item's end (see `skip`).
    func skipTarget(for segment: MediaSegment) -> Double {
        max(0, duration > 0 ? min(segment.endSeconds, duration - 1) : segment.endSeconds)
    }

    /// What `skipHolding` hands back: how it ended, and — when the player
    /// gave one up — the frame it is parked on.
    struct HeldSkip {
        let outcome: HeldSkipOutcome
        /// The decoded frame at the landing, for the tape to park on: exact
        /// where a trickplay tile is up to five seconds off (and, on a cut
        /// to black, a different shot altogether), so the fade onto the live
        /// picture is seamless. Nil when the player vended nothing in time.
        let landingFrame: UIImage?
    }

    /// How a held skip ended — what the chrome logs, and whether it should
    /// still play its tape out.
    enum HeldSkipOutcome: String, Sendable {
        /// The landing is loaded and will play the moment the hold is released.
        case ready
        /// Nothing arrived within `heldSkipTimeout`; the hold is released anyway.
        case timedOut
        /// Something else took the player first — a real pause, a new item,
        /// a teardown — and there is nothing left to release.
        case abandoned
    }

    /// A skip with the picture **held** while it happens — the version the
    /// chrome plays its fast-forward over.
    ///
    /// The plain `skip` seeks with the player running, and what a seek looks
    /// like is a black picture until the frame at the new position exists:
    /// measured at 1.5–11 s on a direct-played MKV in the simulator (the
    /// layer flushes on the seek, the demuxer walks to the new cluster), and
    /// as long as ffmpeg takes to restart on an HLS transcode. The one-second
    /// tape used to end on its own clock and hand the viewer that black.
    ///
    /// So this parks the player at rate 0 — `isPlaying` stays true, because
    /// this is not the viewer pausing and the chrome must not treat it as
    /// one — seeks, prerolls the pipeline at the landing, and waits until
    /// the item reports it can keep up there. It returns *without*
    /// resuming: the chrome finishes the tape and calls `releaseHold()` as
    /// it fades, so the first live frame is the one the tape settled on and
    /// the show simply continues.
    func skipHolding(_ segment: MediaSegment) async -> HeldSkip {
        let target = skipTarget(for: segment)
        activeSegment = nil
        guard let item = currentPlayerItem, case .ready = phase, isPlaying else {
            await seek(to: target)
            return HeldSkip(outcome: .abandoned, landingFrame: nil)
        }
        heldForSkip = true
        avPlayer.pause()
        let started = Date.now
        await seek(to: target)
        PlayerDiagnostics.log("skip: seek landed after \(Self.elapsedLabel(started))")
        guard heldForSkip, avPlayer.currentItem === item else { return HeldSkip(outcome: .abandoned, landingFrame: nil) }
        // Prime the pipeline at the landing while still parked, so the
        // release plays at once instead of decoding its way in.
        let primed = await avPlayer.preroll(atRate: 1)
        PlayerDiagnostics.log("skip: preroll \(primed ? "done" : "declined") after \(Self.elapsedLabel(started))")
        // Then the buffer: the seek can return before the landing can play.
        // Timed from here, not from the press — a slow seek is the player's
        // to finish, and only the wait after it is bounded.
        let landed = Date.now
        var outcome = HeldSkipOutcome.timedOut
        while Date.now.timeIntervalSince(landed) < Self.heldSkipTimeout {
            guard heldForSkip, isPlaying, avPlayer.currentItem === item, case .ready = phase else {
                return HeldSkip(outcome: .abandoned, landingFrame: nil)
            }
            if item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull {
                PlayerDiagnostics.log("skip: landing buffered after \(Self.elapsedLabel(started))")
                outcome = .ready
                break
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        if outcome == .timedOut {
            PlayerDiagnostics.log("skip: landing not buffered after \(Self.elapsedLabel(started)) — releasing anyway")
        }
        let frame = await landingFrame(of: item)
        PlayerDiagnostics.log(frame.map { "skip: landing frame \(Int($0.size.width))x\(Int($0.size.height)) after \(Self.elapsedLabel(started))" }
            ?? "skip: no landing frame from the player — the tape keeps its trickplay still")
        return HeldSkip(outcome: outcome, landingFrame: frame)
    }

    /// The frame the parked player has decoded at the landing, if it will
    /// give one up within `seconds` — through a video output attached for
    /// just that long. BGRA is asked for so an HDR source arrives already
    /// mapped for display. Nothing here is required: nil leaves the tape on
    /// its trickplay tile.
    private func landingFrame(of item: AVPlayerItem, within seconds: Double = 0.8) async -> UIImage? {
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        defer { item.remove(output) }
        let started = Date.now
        while Date.now.timeIntervalSince(started) < seconds {
            guard heldForSkip, avPlayer.currentItem === item else { return nil }
            let now = avPlayer.currentTime()
            if output.hasNewPixelBuffer(forItemTime: now),
               let buffer = output.copyPixelBuffer(forItemTime: now, itemTimeForDisplay: nil) {
                let image = CIImage(cvPixelBuffer: buffer)
                // The simulator's decoder vends black for its first seconds
                // after a seek (the same black its layer shows), and a black
                // still is worse than the trickplay tile it would replace.
                guard !Self.isEssentiallyBlack(image) else {
                    PlayerDiagnostics.log("skip: the player's landing frame is black — keeping the trickplay tile")
                    return nil
                }
                guard let cg = Self.frameContext.createCGImage(image, from: image.extent) else { return nil }
                return UIImage(cgImage: cg)
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return nil
    }

    private static let frameContext = CIContext(options: [.cacheIntermediates: false])

    /// One averaged pixel: under ~4% in every channel is a black frame.
    private static func isEssentiallyBlack(_ image: CIImage) -> Bool {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let averaged = filter.outputImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        frameContext.render(averaged, toBitmap: &pixel, rowBytes: 4,
                            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return max(pixel[0], pixel[1], pixel[2]) < 10
    }

    /// Let a held skip's picture run. A no-op unless a hold is in place,
    /// and never a `play()` over a viewer's own pause.
    func releaseHold() {
        guard heldForSkip else { return }
        heldForSkip = false
        if isPlaying { avPlayer.play() }
    }

    /// After `releaseHold`: true once the player is really running past
    /// `target` — rate 1 and the clock advancing — so the tape fades onto a
    /// moving picture rather than a black one. Bounded, and over at once if
    /// something else takes the player (a pause, a new item).
    ///
    /// **The simulator keeps a black picture for ~6 s after any seek while
    /// every observable says it is playing** — `videoRect`, `isReadyForDisplay`,
    /// the timebase, the buffer flags, even an `AVPlayerItemVideoOutput`
    /// vending frames — measured across five runs, on the iPad simulator as
    /// well; a real device presents as soon as the clock runs. Nothing in
    /// AVFoundation exposes when the layer catches up, so on the simulator
    /// the tape is simply held that much longer, which is the only way to
    /// judge the feature there without the black it is meant to cover.
    func awaitPicture(past target: Double, timeout: TimeInterval = 10) async -> Bool {
        let started = Date.now
        while Date.now.timeIntervalSince(started) < timeout {
            guard isPlaying, case .ready = phase, avPlayer.currentItem != nil else { return false }
            if avPlayer.timeControlStatus == .playing, avPlayer.currentTime().seconds > target + 0.08 {
                PlayerDiagnostics.log("skip: clock running after \(Self.elapsedLabel(started))")
                #if targetEnvironment(simulator)
                try? await Task.sleep(for: .seconds(Self.simulatorLayerLag))
                #endif
                return true
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        PlayerDiagnostics.log("skip: clock not running within \(Int(timeout))s — giving up the tape anyway")
        return false
    }

    #if targetEnvironment(simulator)
    /// See `awaitPicture`. 5.4–6.5 s measured; nothing to tune against on a device.
    private static let simulatorLayerLag: TimeInterval = 6.5
    #endif

    private static func elapsedLabel(_ since: Date) -> String {
        String(format: "%.2fs", Date.now.timeIntervalSince(since))
    }

    /// Ask the server what it knows about this item's intro and credits.
    ///
    /// Deliberately not awaited by `setItem`: this is a second endpoint, and
    /// nothing about starting playback should wait on it. A server with no
    /// segment provider answers an empty list in about a millisecond, an
    /// older one 404s, and either way the player behaves exactly as it did
    /// before this existed.
    private func loadSegments(for item: PlayableItem, token: Int) {
        // **Episodes only** — TV shows and anime series. Skip intro / credits
        // is a between-episodes convenience; a film's opening titles and
        // end credits are part of the film, and a home video has neither.
        // Asking only for episodes also keeps Night mode's auto-skip off
        // them. An episode is anything with a series.
        guard item.seriesId != nil else {
            PlayerDiagnostics.log("segments [\(item.title)] skipped: not an episode")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let runtime = item.runtimeTicks.map { Double($0) / 10_000_000 }
            let found = (try? await self.client.fetchMediaSegments(
                itemId: item.id, runtimeSeconds: runtime)) ?? []
            // Two guards, not one: the generation token catches a superseded
            // load, and the id catches the same item being re-entered.
            guard !self.generation.isCancelled(token),
                  self.currentItem?.id == item.id else { return }
            self.segments = found
            PlayerDiagnostics.log("segments [\(item.title)] \(found.count): "
                + found.map { "\($0.kind.rawValue) \(Int($0.startSeconds))-\(Int($0.endSeconds))s" }
                    .joined(separator: ", "))
        }
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
        heldForSkip = false
        // Clear before the fetch, never after: a queue advance must not leave
        // the outgoing episode's intro markers pointing into the new one.
        segments = []
        activeSegment = nil
        loadSegments(for: item, token: token)

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
        let token = generation.latest
        await progressReporter?.reportStop(positionTicks: positionTicks)
        // A new item loaded while that stop was in flight (`PlayerView` swapping its
        // request into a live engine) owns the player now; destroying it here would be
        // the dead-player bug by another route.
        guard !generation.isCancelled(token) else { return }
        progressReporter = nil
        heldForSkip = false
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

        let reporter = PlaybackProgressReporter(
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
        // POST is independently throttled to 10s inside PlaybackProgressReporter.
        timeObserverToken = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { [weak self, weak reporter] _ in
            Task { @MainActor in
                guard let self, let reporter else { return }
                self.currentTime = self.avPlayer.currentTime().seconds
                // The only recurring position callback in the app, so it is
                // also what decides whether a "Skip intro" is on offer. Pure
                // arithmetic over an array that is almost always empty or two
                // items long — cheaper than the `currentTime` assignment above.
                // Not while a held skip is moving the playhead: the tick between
                // the park and the seek landing still reads the old position, and
                // re-arming the segment there put the button back over the tape.
                if !self.heldForSkip {
                    self.activeSegment = MediaSegments.skippable(at: self.currentTime, in: self.segments)
                }
                // Not while loading: the observer's first tick lands before the first
                // `play()`, and "paused" is not what a still-buffering item is.
                guard case .ready = self.phase else { return }
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
                     failureMessage: String? = nil,
                     segments: [MediaSegment] = []) {
        self.currentItem = item
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.isFavorite = isFavorite
        self.queue = queue
        self.queueIndex = queueIndex
        self.phase = failureMessage.map { .failed(message: $0) } ?? .ready
        self.segments = segments
        // The fixture has no periodic observer to recompute this, so it is
        // resolved once here — through the same function the live tick uses,
        // so a screenshot can't show a button the real player wouldn't.
        self.activeSegment = MediaSegments.skippable(at: currentTime, in: segments)
    }
}
