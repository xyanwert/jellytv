import SwiftUI
import JellyTVKit
#if canImport(UIKit)
import UIKit
#endif

/// Owns Night mode end to end: the locked chrome, the dimmed and de-blued
/// picture, the sleep timer and the wind-down that carries the sound to zero
/// before it fires.
///
/// It lives beside the chrome rather than inside `PlayerEngine` because none
/// of it is playback machinery — it drives the chrome, the display and the
/// app's output gain, and reaches playback only to pause it and to ride the
/// volume down. For that it talks to `PlayerController` and only
/// `PlayerController`, same contract the chrome itself follows.
///
/// **The lock is the point.** Night mode exists so an iPad can be held (or
/// dropped) while falling asleep without a stray touch stopping the episode,
/// so engaging it locks the chrome immediately; only a deliberate press-and-
/// hold opens it. An opened lock is temporary — everything else about Night
/// mode stays on, and the lock closes itself again after
/// `relockSeconds` unless the user actually switches Night mode off.
@Observable @MainActor
final class NightModeController {
    enum Phase {
        /// Night mode is off; the display, the sound and the chrome are the
        /// user's own again.
        case off
        /// Running: locked (or briefly opened), timer counting down.
        case running
        /// The timer ran out. Playback is paused and the lock stays open —
        /// waking up to a screen you can't get into would be the one failure
        /// mode worse than a stray touch.
        case ended
    }

    private(set) var phase: Phase = .off
    private(set) var isLocked = false
    /// Seconds left on the sleep timer.
    private(set) var remaining: Double = 0
    /// Seconds until an opened lock closes itself, or nil when nothing is
    /// pending (locked already, or ended).
    private(set) var relockRemaining: Double?

    /// 0…1 across the final `SleepTimer.fadeFraction` of the timer. Drives
    /// both the volume ramp and the picture's fade, so the room dims and
    /// quietens as one thing rather than two.
    private(set) var windDown: Double = 0

    var isOn: Bool { phase != .off }

    /// How long an opened lock stays open with nothing touching it.
    static let relockSeconds: Double = 15
    /// How long a press has to be held to open the lock.
    static let unlockHoldSeconds: Double = 1.2

    private weak var player: PlayerController?
    private var timer: Task<Void, Never>?
    private var brightnessRamp: Task<Void, Never>?
    private var deadline: Date?
    private var relockAt: Date?
    private var totalSeconds: Double = SleepTimer.default.seconds
    private var fadeSeconds: Double = SleepTimer.default.fadeSeconds
    /// The app's own output gain before the wind-down touched it, and the
    /// display brightness before Night mode dimmed it — both handed back
    /// whenever Night mode ends, however it ends.
    private var restoreVolume: Float = 1
    private var restoreBrightness: CGFloat?
    /// Quarter of the wind-down last reported to `PlayerDiagnostics` — the
    /// ramp is otherwise invisible in a screenshot and inaudible on a
    /// simulator, so it says so in the log.
    private var windDownLogged = -1

    /// Called once by the chrome — the controller isn't available when
    /// `@State` builds this object.
    func attach(_ player: PlayerController) {
        self.player = player
    }

    // MARK: - Engage / release

    func toggle(sleepTimer: SleepTimer) {
        isOn ? disable() : enable(sleepTimer)
    }

    func enable(_ sleepTimer: SleepTimer, locked: Bool = true) {
        engage(seconds: sleepTimer.seconds, fade: sleepTimer.fadeSeconds, locked: locked)
    }

    private func engage(seconds: Double, fade: Double, locked: Bool) {
        guard phase == .off else { return }
        totalSeconds = seconds
        fadeSeconds = fade
        deadline = Date().addingTimeInterval(seconds)
        remaining = seconds
        windDown = 0
        windDownLogged = -1
        // A volume of zero here means a previous run was torn down mid-fade;
        // never adopt that as the level to restore to.
        let current = player?.volume ?? 1
        restoreVolume = current > 0.01 ? current : 1
        phase = .running
        isLocked = locked
        relockAt = locked ? nil : Date().addingTimeInterval(Self.relockSeconds)
        dimDisplay()
        startTicking()
        PlayerDiagnostics.log("night: on — \(Int(seconds))s, fade \(Int(fade))s, locked=\(locked)")
    }

    /// Turn Night mode off and give everything back. `immediate` skips the
    /// brightness ramp for teardown, where this object may not outlive it.
    func disable(immediate: Bool = false) {
        guard phase != .off else { return }
        PlayerDiagnostics.log("night: off")
        timer?.cancel(); timer = nil
        deadline = nil
        relockAt = nil
        relockRemaining = nil
        phase = .off
        isLocked = false
        windDown = 0
        remaining = 0
        player?.setVolume(restoreVolume)
        restoreDisplay(immediate: immediate)
    }

    // MARK: - The lock

    func unlock() {
        guard phase == .running, isLocked else { return }
        PlayerDiagnostics.log("night: lock opened")
        isLocked = false
        noteInteraction()
    }

    func lock() {
        guard phase == .running, !isLocked else { return }
        PlayerDiagnostics.log("night: re-locked")
        isLocked = true
        relockAt = nil
        relockRemaining = nil
    }

    /// Any deliberate touch on the open chrome pushes the re-lock back out —
    /// the countdown measures *idleness*, not time since unlocking.
    func noteInteraction() {
        guard phase == .running, !isLocked else { return }
        relockAt = Date().addingTimeInterval(Self.relockSeconds)
        relockRemaining = Self.relockSeconds
    }

    // MARK: - Scene

    /// The system keeps an app's brightness change after that app leaves the
    /// foreground, so hand the user's own level back whenever the player goes
    /// away and take it again when it comes back. Without this, swiping home
    /// mid-episode would leave the whole device dark.
    func setForeground(_ active: Bool) {
        guard phase != .off else { return }
        active ? dimDisplay() : restoreDisplay(immediate: true)
    }

    // MARK: - The countdown

    private func startTicking() {
        timer?.cancel()
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard phase == .running, let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)

        windDown = fadeSeconds > 0 ? min(1, max(0, 1 - remaining / fadeSeconds)) : 0
        player?.setVolume(restoreVolume * Float(1 - windDown))
        if windDown > 0, Int(windDown * 4) > windDownLogged {
            windDownLogged = Int(windDown * 4)
            PlayerDiagnostics.log(String(format: "night: wind-down %.0f%% — volume %.2f",
                                         windDown * 100, player?.volume ?? 0))
        }

        if let relockAt {
            // A paused player is a player someone is looking at — hold the
            // lock open, exactly as the chrome's own idle timer holds the
            // controls up. Nothing can pause while locked, so this only ever
            // follows a deliberate pause.
            if player?.isPlaying == false {
                self.relockAt = Date().addingTimeInterval(Self.relockSeconds)
                relockRemaining = Self.relockSeconds
            } else {
                relockRemaining = max(0, relockAt.timeIntervalSinceNow)
                if (relockRemaining ?? 0) <= 0 { lock() }
            }
        }

        if remaining <= 0 { finish() }
    }

    private func finish() {
        PlayerDiagnostics.log("night: sleep timer ended")
        timer?.cancel(); timer = nil
        deadline = nil
        relockAt = nil
        relockRemaining = nil
        phase = .ended
        isLocked = false
        windDown = 1
        player?.pause()
        // Hand the gain back now that it has done its job — a muted app
        // waiting silently for the next tap would be a trap.
        player?.setVolume(restoreVolume)
        PlayerDiagnostics.log(String(format: "night: paused, volume restored to %.2f", restoreVolume))
    }

    // MARK: - Debug fixture (JT_NIGHT / RT_NIGHT)

    /// Screenshot hook only: drops Night mode straight into its wind-down (or
    /// past the end of it) so those states can be captured without waiting
    /// out a real timer. Cancels the ticker, so nothing moves afterwards.
    func previewSeed(_ sleepTimer: SleepTimer, ended: Bool) {
        enable(sleepTimer, locked: false)
        timer?.cancel(); timer = nil
        if ended {
            phase = .ended
            windDown = 1
            remaining = 0
            relockRemaining = nil
            player?.pause()
        } else {
            windDown = 0.72
            remaining = sleepTimer.fadeSeconds * 0.28
        }
    }

    /// Runs a real, complete Night mode — lock, countdown, wind-down, stop —
    /// compressed into 90 seconds, so the end of the timer can be watched
    /// instead of taken on trust.
    func previewFast(locked: Bool) {
        engage(seconds: 90, fade: 90 * SleepTimer.fadeFraction, locked: locked)
    }

    // MARK: - Display

    private func dimDisplay() {
        #if os(iOS)
        guard let screen = Self.screen else { return }
        if restoreBrightness == nil { restoreBrightness = screen.brightness }
        ramp(screen, to: 0)
        #endif
    }

    private func restoreDisplay(immediate: Bool) {
        #if os(iOS)
        guard let screen = Self.screen, let level = restoreBrightness else { return }
        if phase == .off { restoreBrightness = nil }
        if immediate {
            brightnessRamp?.cancel()
            screen.brightness = level
        } else {
            ramp(screen, to: level)
        }
        #endif
    }

    #if os(iOS)
    /// Brightness has no animation of its own, so step it — a cut from full
    /// to black is a slap in a dark room.
    private func ramp(_ screen: UIScreen, to target: CGFloat) {
        brightnessRamp?.cancel()
        let from = screen.brightness
        guard abs(from - target) > 0.01 else { screen.brightness = target; return }
        brightnessRamp = Task { @MainActor in
            let steps = 30
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                screen.brightness = from + (target - from) * CGFloat(step) / CGFloat(steps)
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private static var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }?.screen ?? scenes.first?.screen
    }
    #endif
}
