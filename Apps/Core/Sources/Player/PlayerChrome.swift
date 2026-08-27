import SwiftUI
import JellyTVKit

/// Focusable fields across the whole chrome — one `@FocusState` shared by
/// every subview via `@FocusState.Binding` so the tvOS focus engine treats
/// the chrome as a single spatial layout, not per-component islands.
enum PlayerFocusField: Hashable {
    case back, night, repeatOne, playPause, favorite, next, dislike
    case transport(Int)
    case failureRetry, failureSkip, failureClose
}

extension View {
    /// tvOS-only `.focused()`. **Never bind focus on iOS here**: inside the
    /// player's `.fullScreenCover`, a live `@FocusState` binding has been
    /// observed to stop touch events reaching SwiftUI `Button`s in this view
    /// — see `PlayerChrome.onAppear`, which already stopped *seeding* focus
    /// on iOS for that reason. The `.focused()` modifiers themselves were
    /// still live, leaving the same hazard in place. There's no pointer or
    /// remote driving focus on iPad anyway — the chrome is entirely
    /// touch-driven — so compiling these out costs nothing.
    ///
    /// (Not the cause of the "chrome never reappears" bug, which bisected to
    /// the invisible `Button` in `tapCatcher`. Removed as a live hazard, not
    /// as that fix.)
    @ViewBuilder
    func remoteFocus(_ binding: FocusState<PlayerFocusField?>.Binding,
                     equals value: PlayerFocusField) -> some View {
        #if os(tvOS)
        focused(binding, equals: value)
        #else
        self
        #endif
    }
}

/// Owns the chrome's 3-second auto-hide countdown.
///
/// A reference type held in `@State` rather than a bare `@State
/// Task<Void, Never>?` because `armIdleTimer()` runs from escaping closures
/// (`.onAppear`, button actions), each holding its own copy of the
/// `PlayerChrome` struct. Writing `@State` through a stale copy works;
/// *reading* the previous `Task` back out of one does not — so
/// `idleTask?.cancel()` could miss, leaving several timers armed at once and
/// letting a leftover one hide the chrome moments after a tap revealed it.
/// Cancellation through a shared reference always hits the live task, and
/// `@MainActor` keeps the `visible` write off the concurrent pool (it was
/// previously running on whatever thread the detached `Task` landed on).
@MainActor
final class ChromeIdleTimer {
    private var task: Task<Void, Never>?
    private let interval: Duration

    init(seconds: Int = 3) {
        self.interval = .seconds(seconds)
    }

    func arm(_ hide: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor [interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Full custom chrome, matching the "Jelly-tv Player" design: top bar,
/// center repeat + play, right-rail favorite/next/dislike, scrubber, bottom
/// seek strip. **All chrome talks to `PlayerController` and only
/// `PlayerController`** — see that type's doc comment for the contract.
///
/// Owns auto-hide (3s idle on tvOS, never while paused, re-armed by any
/// D-pad nudge or control tap) and hosts Night mode: while the lock is on,
/// the chrome isn't rendered at all and `NightLockOverlay` has every touch —
/// see `NightModeController` for the rest of that behaviour.
struct PlayerChrome: View {
    let controller: PlayerController
    @Binding var visible: Bool
    let onClose: () -> Void
    let onOpenScenes: () -> Void

    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focus: PlayerFocusField?
    @State private var night = NightModeController()
    @State private var idleTimer = ChromeIdleTimer()
    @State private var sonarPulse = false

    private var accent: Color { theme.accent }

    /// Screenshot hook, inert unless set: `JT_NIGHT` / `RT_NIGHT` =
    /// `on` (engaged, lock open) | `locked` | `ending` (deep in the
    /// wind-down) | `ended` (the timer has fired) | `fast` (the whole thing
    /// for real, compressed into 90 seconds). Same convention as
    /// `JT_SHOW_PLAYER`.
    private static var nightSeed: String? {
        let env = ProcessInfo.processInfo.environment
        return env["JT_NIGHT"] ?? env["RT_NIGHT"]
    }

    var body: some View {
        ZStack {
            if night.isOn {
                NightVeil(windDown: night.windDown, ended: night.phase == .ended)
                    .transition(.opacity)
            }

            if visible && !night.isLocked {
                #if os(iOS)
                // tvOS reveals/hides chrome via the Menu button
                // (`PlayerView`'s `.onExitCommand`) and idle-timeout alone.
                // Touch has no such button, so tapping the empty video area
                // toggles chrome visibility instead — lowest z-order so it
                // sits behind every real control and only catches taps that
                // miss them.
                tapCatcher(action: toggleVisible)
                #endif

                sonarMotif

                VStack {
                    PlayerTopBar(
                        item: controller.currentItem,
                        queuePositionLabel: controller.queuePositionLabel,
                        accent: accent,
                        night: night,
                        onBack: onClose,
                        onToggleNight: toggleNight,
                        focus: $focus
                    )
                    Spacer()
                }
                .padding(.top, 44)
                .padding(.horizontal, 56)

                PlayerCenterControls(controller: controller, accent: accent, onInteract: interact, focus: $focus)

                HStack {
                    Spacer()
                    PlayerRightRail(controller: controller, accent: accent, onInteract: interact, focus: $focus)
                        .padding(.trailing, 44)
                }

                VStack {
                    Spacer()
                    VStack(spacing: 48) {
                        PlayerScrubber(currentTime: controller.currentTime, duration: controller.duration, accent: accent)
                        PlayerTransportStrip(
                            controller: controller, accent: accent,
                            onInteract: interact, onOpenScenes: onOpenScenes, focus: $focus
                        )
                    }
                }
                .padding(.bottom, 44)
                .padding(.horizontal, 56)

                if case .failed(let message) = controller.phase {
                    PlayerFailureOverlay(
                        message: message, hasNext: controller.hasNext, accent: accent,
                        onRetry: { interact(); Task { await controller.retryCurrentItem() } },
                        onSkip: { interact(); Task { await controller.skipCurrentItem() } },
                        onClose: onClose,
                        focus: $focus
                    )
                }
            } else {
                hiddenCatcher
            }

            // Last in the stack on purpose: while the lock is on it takes
            // every touch on the screen, including the ones that would
            // otherwise reach the hidden catcher underneath.
            if night.isLocked {
                NightLockOverlay(
                    remainingLabel: SleepTimer.remainingLabel(night.remaining),
                    onUnlock: { withAnimation(.easeOut(duration: 0.25)) { night.unlock() } }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.9), value: night.isOn)
        .onAppear {
            withAnimation(.easeOut(duration: 4).repeatForever(autoreverses: false)) { sonarPulse = true }
            // tvOS-only: seeding `@FocusState` gives the remote's directional
            // pad something focused at launch. On iPadOS, driving this same
            // `@FocusState` inside a `.fullScreenCover` silently breaks touch
            // delivery for every button in this view (confirmed on-device —
            // taps stopped reaching any SwiftUI `Button` here, chrome/hidden-
            // catcher included, the instant this ran unconditionally).
            #if os(tvOS)
            focus = .playPause
            #endif
            armIdleTimer()
            night.attach(controller)
            applyNightSeedIfNeeded()
        }
        .onDisappear {
            // Night mode holds the display's brightness down — hand it back
            // the moment the player leaves the screen, whatever the reason.
            night.disable(immediate: true)
        }
        .onChange(of: scenePhase) { _, phase in
            night.setForeground(phase == .active)
        }
        .onChange(of: night.isLocked) { _, locked in
            if locked {
                idleTimer.cancel()
            } else {
                visible = true
                armIdleTimer()
            }
        }
        #if os(tvOS)
        .onMoveCommand { _ in interact() }
        #endif
        .onChange(of: controller.isPlaying) { _, playing in
            if playing {
                armIdleTimer()
            } else {
                idleTimer.cancel()
                visible = true
            }
        }
    }

    /// Full-bleed invisible tap target, so an input while the chrome is
    /// hidden reveals it again instead of doing nothing (nothing else is
    /// interactive once the chrome's own controls are gone).
    private var hiddenCatcher: some View {
        tapCatcher(action: interact)
    }

    /// **The two platforms need genuinely different mechanisms here.**
    ///
    /// tvOS needs a real `Button`: there's no cursor, so the catcher has to
    /// be *focusable* for a Select press to land on it. It must not be
    /// `.buttonStyle(.plain)` though — a focused plain-style button still
    /// paints the system's white focus card, which on a full-screen button
    /// covers the whole video. `InvisibleButtonStyle` renders nothing but
    /// `configuration.label`, same rationale as `FocusScaleStyle` elsewhere
    /// never using `.plain`/`.automatic`.
    ///
    /// iOS must **not** use a `Button`. Verified by bisect with real HID
    /// touch injection: with a `Button` whose label is `Color.clear` and
    /// whose style draws no shape of its own, three consecutive taps on the
    /// hidden chrome produce *nothing* — the action never fires. Swap in
    /// `.contentShape(Rectangle())` + `.onTapGesture` and the same tap
    /// reveals the chrome every time.
    ///
    /// The trap is that such a `Button` still registers in the accessibility
    /// tree, so an accessibility press (`AXPress` — which is what AppleScript
    /// `click at` performs, and what most simulator scripting drives) invokes
    /// it happily. Only a direct touch hit-tests straight past it. Any
    /// "verification" of this control that isn't a real HID touch is
    /// therefore worthless — that false signal is what made this look fixed
    /// once already.
    @ViewBuilder
    private func tapCatcher(action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        Button(action: action) {
            Color.clear
        }
        .buttonStyle(InvisibleButtonStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        #else
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            // The chrome itself stays inside the safe area, but the catcher
            // has to cover the home-indicator strip and the display edges —
            // otherwise a tap near the bottom of the screen hits nothing.
            .ignoresSafeArea()
        #endif
    }

    private func interact() {
        PlayerDiagnostics.log("chrome: interact — reveal")
        visible = true
        armIdleTimer()
        // The re-lock counts idleness, so every deliberate touch pushes it
        // back out — the lock only closes on someone who has actually
        // stopped using the controls.
        night.noteInteraction()
    }

    /// Engaging Night mode locks the chrome straight away — that's the whole
    /// point of it — so put the controls away in the same movement.
    private func toggleNight() {
        interact()
        withAnimation(.easeInOut(duration: 0.4)) {
            night.toggle(sleepTimer: appState.sleepTimer)
        }
        if night.isLocked {
            idleTimer.cancel()
            visible = false
        }
    }

    private func applyNightSeedIfNeeded() {
        guard let seed = Self.nightSeed else { return }
        switch seed {
        case "on": night.enable(appState.sleepTimer, locked: false)
        case "locked": night.enable(appState.sleepTimer, locked: true)
        case "ending", "ended": night.previewSeed(appState.sleepTimer, ended: seed == "ended")
        case "fast": night.previewFast(locked: false)
        default: break
        }
    }

    #if os(iOS)
    private func toggleVisible() {
        if visible {
            PlayerDiagnostics.log("chrome: tap — hide")
            idleTimer.cancel()
            visible = false
        } else {
            interact()
        }
    }
    #endif

    private func armIdleTimer() {
        idleTimer.arm {
            if controller.isPlaying {
                PlayerDiagnostics.log("chrome: idle timeout — hide")
                visible = false
            }
        }
    }

    /// Decorative concentric-ring motif, top-right — the same idiom as
    /// `DetailBackground.sonarRings`, reused here for visual continuity.
    private var sonarMotif: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(Color(hex: "#78B4DC").opacity(0.12 - Double(i) * 0.03), lineWidth: 1)
                    .frame(width: 620 - CGFloat(i) * 240, height: 620 - CGFloat(i) * 240)
            }
            Circle()
                .stroke(accent, lineWidth: 2)
                .frame(width: 200, height: 200)
                .scaleEffect(sonarPulse ? 2.2 : 0.6)
                .opacity(sonarPulse ? 0 : 0.5)
        }
        .frame(width: 620, height: 620)
        .position(x: 1720, y: 120)
        .allowsHitTesting(false)
    }
}

/// Renders only `configuration.label` — no system focus card, no dimming,
/// nothing layered on top. Used where a button must be genuinely invisible
/// even while focused (`hiddenCatcher`), which `.plain`/`.automatic` don't
/// guarantee on tvOS.
struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
