import Foundation
import AVFoundation
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

    func seek(to seconds: Double) async {
        await engine.seek(to: seconds)
    }

    /// Skip forward (positive) or backward (negative) seconds — the ±10s/
    /// ±30s seek-strip buttons.
    func seekRelative(by delta: Double) async {
        await engine.seekRelative(delta)
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
