import Foundation
import AVFoundation
import UIKit
import Observation
import JellyTVKit

/// Mediator between `PlayerEngine` and chrome. **All chrome talks to this
/// controller and only this controller** — it owns mash-protection for
/// queue navigation and favorite round-trips so a fast tap train can't race
/// the network, and the local (non-Jellyfin) dislike flag.
///
/// Ported from `/Users/xyan/code/jelly-tv-ios`'s `PlayerController`, trimmed
/// of the persisted-prefs read-through (`autoAdvance`/`autoSkipIntros` — no
/// such settings in this app) and the SwiftData-backed dislike counter
/// (replaced with a local `UserDefaults` boolean per the confirmed scope:
/// Favorite is real Jellyfin state, Dislike has no server equivalent).
@Observable @MainActor
final class PlayerController {
    private let engine: PlayerEngine

    /// 250ms leading-edge coalesce: the first next/previous tap fires
    /// immediately, subsequent taps within the window are dropped.
    private var queueCoalesceUntil: Date = .distantPast
    /// Re-entrancy guard — blocks a second advance while the first's
    /// `setItem` is still in flight (catches mash the time-based gate above
    /// can't, since network latency can outlast the coalesce window).
    private var queueChangeInFlight = false
    private static let mashCoalesceSeconds: TimeInterval = 0.25

    private var favoriteChangeInFlight = false

    /// Tags the user has changed during this playback session, keyed by item
    /// id. The queue's `PlayableItem`s were built before the player opened
    /// and never change, so without this a tag applied mid-film would keep
    /// showing the old chips until the next launch.
    private var editedTags: [String: [String]] = [:]

    /// Where a burst of jump taps is heading. Non-nil only while a burst is
    /// settling; see `jump(by:)`.
    private(set) var pendingSeekTarget: Double?
    private var seekCommitTask: Task<Void, Never>?
    private var seekInFlight = false
    /// How long after the last jump tap the accumulated seek commits.
    /// Comfortably longer than a double-tap, comfortably shorter than the
    /// seek itself — a single tap is not perceptibly delayed by it.
    private static let seekCoalesceSeconds: Duration = .milliseconds(280)

    private static let dislikedIdsKey = "jelly:player.dislikedItemIds"

    init(engine: PlayerEngine) {
        self.engine = engine
    }

    // MARK: - State (read-through to engine)

    var currentItem: PlayableItem? { engine.currentItem }
    var phase: PlayerPhase { engine.phase }
    var isPlaying: Bool { engine.isPlaying }
    /// True while the engine is resolving/wiring the current item — drives
    /// the chrome's loading state (center button → spinner).
    var isLoading: Bool {
        if case .loading = engine.phase { return true } else { return false }
    }
    var currentTime: Double { engine.currentTime }
    var duration: Double { engine.duration }
    var isBuffering: Bool { engine.isBuffering }
    var isFavorite: Bool { engine.isFavorite }
    var repeatOne: Bool { engine.repeatOne }
    var hasNext: Bool { engine.hasNext }
    var hasPrevious: Bool { engine.hasPrevious }
    var queuePositionLabel: String? { engine.queuePositionLabel }
    /// Exposed only so `PlayerLayerView` can attach — chrome should not
    /// reach in here for playback actions, use the methods below.
    var avPlayer: AVPlayer { engine.avPlayer }

    /// **Which item's tags the chrome is showing — and therefore editing.**
    ///
    /// For an episode that is the *series*, not the episode: Jellyfin puts
    /// tags on the show and virtually never on an episode, so every episode
    /// `PlayableItem` in this app is built carrying its series' tags (see
    /// `AppState.seriesIdentity`). Editing anywhere else would mean the chips
    /// you can see and the chips you can change are two different lists —
    /// tag an episode and the row wouldn't move, while the show's tags would
    /// silently get copied onto it. A film or a home video owns its own.
    var tagTargetId: String? {
        guard let item = currentItem else { return nil }
        return item.seriesId ?? item.id
    }

    /// True when the above resolved to the series rather than the item, so
    /// the panel can say "this show" instead of "this video".
    var tagsBelongToSeries: Bool { currentItem?.seriesId != nil }

    /// The tags the chrome should draw: whatever the user has just set, else
    /// whatever the item was queued with.
    var currentTags: [String] {
        guard let id = tagTargetId else { return [] }
        return editedTags[id] ?? currentItem?.tags ?? []
    }

    /// Record a tag edit for display. **Does not write to Jellyfin** — the
    /// server round-trip is `AppState.setTags(_:forItem:)`, which owns the
    /// client; this is the optimistic half, and its caller is expected to
    /// call again with the old value if the write fails.
    func setTagsLocally(_ tags: [String], for itemId: String) {
        editedTags[itemId] = tags
    }

    /// Local-only "not interested" flag — Jellyfin has no dislike endpoint,
    /// so this never leaves the device.
    var isDisliked: Bool {
        guard let id = currentItem?.id else { return false }
        return Self.dislikedIds().contains(id)
    }

    // MARK: - Actions — transport

    func play() { engine.play() }
    func pause() { engine.pause() }
    func togglePlay() { engine.togglePlay() }

    /// App-level output gain (0…1). Owned by `NightModeController`, which
    /// captures the level on the way in and restores it on the way out — no
    /// other caller should be moving it.
    var volume: Float { engine.volume }
    func setVolume(_ value: Float) { engine.volume = value }

    /// What the position readout should show: where a settling burst of taps
    /// is *heading*, or the real position when nothing is pending.
    ///
    /// This is what makes the coalesce below invisible. The number moves the
    /// instant a circle is pressed, even though the picture follows a beat
    /// later — press +30s four times and the readout counts up by two
    /// minutes immediately, which is the feedback that stops someone pressing
    /// again to check whether it worked.
    var displayTime: Double { pendingSeekTarget ?? engine.currentTime }

    /// Nudge the position by `delta` seconds. **Safe to mash.**
    ///
    /// Each tap adds to a running target and re-arms a short timer; the burst
    /// commits as exactly one seek when the tapping stops. Two things this
    /// fixes, both of which are live in the shipping code today:
    ///
    /// 1. **Taps used to be swallowed.** The old version computed its target
    ///    from `currentTime` read at tap time, and every tap spawned its own
    ///    `Task`. Taps landing before the first `await avPlayer.seek` resolved
    ///    all read the *same* stale position, so three fast taps on +30s
    ///    produced one +30s jump rather than +90s — which reads as the button
    ///    not registering. Accumulating onto `pendingSeekTarget` instead of
    ///    re-reading the clock makes every tap count.
    /// 2. **N precise seeks became one.** Each `seek` was frame-accurate
    ///    (`tolerance .zero`) and, on a transcoded HLS stream, can restart the
    ///    server-side transcode. A burst of those is how playback ends up
    ///    wedged rather than merely late.
    ///
    /// v1 (`/Users/xyan/code/jelly-tv-ios`) never gated seeks either — its
    /// seek strip only carried `.disabled(isLoading)`, which guards
    /// item-resolve latency, not this. What it did leave behind is the
    /// principle, in its own port plan: *"Coalesce + busy gate solves mash,
    /// debounce alone does not."* Hence the in-flight guard as well as the
    /// timer, and the same 250ms-ish window `next()`/`previous()` already use.
    func jump(by delta: Double) {
        let base = pendingSeekTarget ?? engine.currentTime
        pendingSeekTarget = clampToItem(base + delta)
        scheduleSeekCommit()
    }

    /// Jump to an absolute position from a *mashable* control — the coalesced
    /// counterpart to `seek(to:)`. Cancels any accumulated nudge rather than
    /// fighting it, then commits on the same timer, so a burst is one seek.
    ///
    /// No control calls this today: its one caller was the chrome's
    /// start-over circle, which was cut for being a whole-film mistake one
    /// press away from the seek buttons.
    func jump(to seconds: Double) {
        pendingSeekTarget = clampToItem(seconds)
        scheduleSeekCommit()
    }

    /// Direct, uncoalesced seek — for callers that already know their exact
    /// target and are not driven by a mashable control (a scenes thumbnail,
    /// a resume position). Cancels any pending nudge so the two can't race.
    func seek(to seconds: Double) async {
        seekCommitTask?.cancel()
        seekCommitTask = nil
        pendingSeekTarget = nil
        await engine.seek(to: seconds)
    }

    private func scheduleSeekCommit() {
        seekCommitTask?.cancel()
        seekCommitTask = Task { @MainActor [self] in
            try? await Task.sleep(for: Self.seekCoalesceSeconds)
            guard !Task.isCancelled else { return }
            await commitPendingSeek()
        }
    }

    /// The busy gate. A commit that lands while the previous seek is still
    /// resolving re-arms the timer instead of stacking a second
    /// `avPlayer.seek` on top of the first — the accumulated target is not
    /// lost, it just waits its turn.
    private func commitPendingSeek() async {
        guard let target = pendingSeekTarget else { return }
        guard !seekInFlight else {
            scheduleSeekCommit()
            return
        }
        seekInFlight = true
        // Cleared *before* awaiting, so taps arriving during the seek start a
        // fresh burst from the committed position rather than re-adding to a
        // target that is already being applied.
        pendingSeekTarget = nil
        await engine.seek(to: target)
        seekInFlight = false
    }

    private func clampToItem(_ seconds: Double) -> Double {
        let duration = engine.duration
        guard duration > 0 else { return max(0, seconds) }
        // Never park exactly on the end: that trips end-of-item handling and
        // auto-advances, which is not what "+1 min" near the credits means.
        return min(max(0, seconds), max(0, duration - 1))
    }

    // MARK: - Actions — queue traversal

    @discardableResult
    func next() async -> Bool {
        guard passesMashGate() else { return false }
        queueChangeInFlight = true
        defer { queueChangeInFlight = false }
        return await engine.advanceQueue()
    }

    @discardableResult
    func previous() async -> Bool {
        guard passesMashGate() else { return false }
        queueChangeInFlight = true
        defer { queueChangeInFlight = false }
        return await engine.regressQueue()
    }

    /// User-initiated retry from the failure overlay — bypasses the mash
    /// gate (a deliberate Retry tap isn't the mash-protection spam case).
    func retryCurrentItem() async {
        await engine.retryCurrentItem()
    }

    /// User-initiated skip from the failure overlay — distinct from
    /// `next()` only in that it can fire once the engine's own auto-advance
    /// has already capped out.
    @discardableResult
    func skipCurrentItem() async -> Bool {
        await engine.advanceQueue()
    }

    /// True when a new next/previous is allowed to fire.
    private func passesMashGate() -> Bool {
        if queueChangeInFlight { return false }
        let now = Date()
        guard now >= queueCoalesceUntil else { return false }
        queueCoalesceUntil = now.addingTimeInterval(Self.mashCoalesceSeconds)
        return true
    }

    // MARK: - Scenes (trickplay)

    /// The media source trickplay sheets are addressed against.
    var currentMediaSourceId: String? { engine.currentMediaSourceId }

    /// The current item's trickplay geometry, or nil when the server has none
    /// — which is the gate the scenes panel uses to decide whether it can
    /// offer anything at all.
    func resolveTrickplay() async -> (widthKey: String, info: JellyfinAPI.TrickplayInfo)? {
        guard let itemId = currentItem?.id else { return nil }
        return await engine.trickplayClient.resolve(itemId: itemId,
                                                    mediaSourceId: engine.currentMediaSourceId)
    }

    /// One scene thumbnail. Nil for anything missing, so a cell stays empty
    /// rather than showing the wrong frame.
    func trickplayThumbnail(at seconds: Double, widthKey: String,
                            info: JellyfinAPI.TrickplayInfo) async -> UIImage? {
        guard let itemId = currentItem?.id,
              let mediaSourceId = engine.currentMediaSourceId else { return nil }
        return await engine.trickplayClient.thumbnail(
            forSeconds: seconds, itemId: itemId, widthKey: widthKey,
            info: info, mediaSourceId: mediaSourceId
        )
    }

    // MARK: - Actions — favorite / dislike / repeat

    /// Real Jellyfin endpoint round-trip. Mash-protected: drops re-entrant
    /// taps while a round-trip is in flight, since the engine's optimistic
    /// local state can't be safely updated by overlapping calls.
    @discardableResult
    func toggleFavorite() async -> Bool {
        guard !favoriteChangeInFlight else { return false }
        favoriteChangeInFlight = true
        defer { favoriteChangeInFlight = false }
        await engine.toggleFavorite()
        return true
    }

    /// Local-only toggle. Mirrors the mutual exclusivity a Jellyfin-native
    /// dislike would have with favorite, even though this half never
    /// reaches the server.
    func toggleDislike() {
        guard let id = currentItem?.id else { return }
        var ids = Self.dislikedIds()
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
            if isFavorite {
                Task { await engine.toggleFavorite() }
            }
        }
        UserDefaults.standard.set(Array(ids), forKey: Self.dislikedIdsKey)
    }

    func toggleRepeatOne() { engine.toggleRepeatOne() }

    private static func dislikedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dislikedIdsKey) ?? [])
    }
}
