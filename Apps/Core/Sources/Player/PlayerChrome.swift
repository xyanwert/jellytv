import SwiftUI
import JellyTVKit

/// Focusable fields across the whole chrome — one `@FocusState` shared by
/// every subview via `@FocusState.Binding` so the tvOS focus engine treats
/// the chrome as a single spatial layout, not per-component islands.
enum PlayerFocusField: Hashable {
    case back, night, tags
    /// The opinions, above the transport.
    case dislike, favorite
    /// The transport circles, left to right.
    case back30, playPause, forward30, forwardMinute
    /// The foot, left to right.
    case previous, scenes, next
    /// "Skip intro" / "Skip credits" — bottom-right, and the only field here
    /// that can be focused while the chrome is hidden.
    case skipSegment
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

/// Owns the chrome's auto-hide countdown — 2s on iOS/iPadOS, **3s on tvOS**.
///
/// **Why tvOS keeps the longer grace period.** A shared pass shortened this
/// from 3s to 2s on every platform at once, tuned for a touchscreen a few
/// inches from the thumb that just tapped it — re-tapping to check the clock
/// or a tag costs nothing there. On a TV the same countdown starts the
/// instant a D-pad press lands, but *reading* what it revealed — the
/// position readout, a chip that just got added — happens from a couch, with
/// a remote that takes real aim to bring the chrome back if it vanishes
/// mid-read. 2s routinely cuts that read short in a way a touchscreen's 2s
/// doesn't. tvOS keeps the pre-existing 3s here — nothing about this round's
/// change suggested 3s was ever wrong for the living room, only that 2s is.
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

    #if os(tvOS)
    nonisolated static let defaultSeconds = 3
    #else
    nonisolated static let defaultSeconds = 2
    #endif

    init(seconds: Double = Double(ChromeIdleTimer.defaultSeconds)) {
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

/// Full custom chrome, matching the "Grandma menu" design (canvas artboard
/// A): BACK plus the item's logo and tags top-left, AirPlay and Night
/// top-right, the two opinions over four transport circles over a `27:00 /
/// 55:16` readout in the middle, and SCENES + NEXT in the bottom-right.
///
/// **What this replaced, and why.** The original chrome carried thirteen
/// controls in four clusters: a repeat toggle beside play, a right-hand rail
/// of favourite/next/dislike, a progress bar, and a seven-tile seek strip
/// (±10s / ±30s / ±1min around SCENES). The brief was that it should be
/// usable without aiming or reading, so:
///
/// - the **progress bar went** — it invited dragging, and a dragged bar is
///   the easiest way to lose your place by accident (`PlayerClockReadout`);
/// - the **seek strip collapsed** from seven tiles to two circles, ±30s,
///   joined by one-minute-ahead (`PlayerTransportRow`);
/// - **captions survive only where the glyph doesn't carry it** — BACK,
///   SCENES and NEXT. Everything in the middle of the screen is glyph alone,
///   which is what buys targets that size.
///
/// A second pass then moved the two opinions out of the foot and up under the
/// play button (`PlayerOpinionRow`), dropped **start-over** — one press,
/// whole film gone, sitting next to the most-mashed button in the app — and
/// gave the foot the queue instead of the heart — PREV and NEXT flanking
/// SCENES. Repeat-one came back as a *long press* on the play button rather
/// than as a sixth circle.
///
/// **All chrome talks to `PlayerController` and only `PlayerController`** —
/// see that type's doc comment for the contract.
///
/// Owns auto-hide (2s idle on iOS/iPadOS, 3s on tvOS — see `ChromeIdleTimer`
/// — never while paused, re-armed by any D-pad nudge or control tap) and
/// hosts Night mode: while the lock is on, the chrome
/// isn't rendered at all and `NightLockOverlay` has every touch — see
/// `NightModeController` for the rest of that behaviour.
///
/// **Appearing and disappearing is a 300ms cross-fade, never a hard cut** —
/// every `visible` write goes through `withAnimation(Self.fadeAnimation)`
/// (or the equivalent in a `.onChange`/timer callback), and the chrome's own
/// content carries `.transition(.opacity)` so SwiftUI actually has something
/// to animate between when the `if visible` branch flips.
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
    /// **Local to the chrome, deliberately.** Opening scenes pauses playback,
    /// and `onChange(of: controller.isPlaying)` below forces `visible = true`
    /// whenever playback stops — so if this lived in `PlayerView` and drove
    /// the shared `visible` binding, opening the panel would summon the chrome
    /// underneath it. Keeping it here lets the whole chrome subtree be gated
    /// on `!scenesOpen`, which makes that write harmless.
    @State private var scenesOpen = false
    /// Same reasoning as `scenesOpen` — and the same gate, since the tags
    /// panel pauses playback too.
    @State private var tagsOpen = false
    /// The tag the "stamped" confirmation is currently showing, or nil when
    /// none is up. See `applyTagAndClose`.
    @State private var stampedTag: String?
    @State private var sonarPulse = false
    #if os(tvOS)
    /// The receipt for a D-pad press made with the chrome hidden — see
    /// `handleMove` and `PlayerGlance`. Cleared by its own timer, or the
    /// moment the chrome comes up (the chrome shows the same state for real).
    @State private var glance: PlayerGlance.Kind?
    @State private var glanceTimer = ChromeIdleTimer(seconds: 1.4)
    #endif

    /// Shared duration for every chrome show/hide — see the type's own doc
    /// comment. 300ms reads as quick without being a flash-cut; long enough
    /// to actually register as a fade at a glance.
    private static let fadeAnimation: Animation = .easeInOut(duration: 0.3)

    private var accent: Color { theme.accent }

    private var isFailed: Bool {
        if case .failed = controller.phase { return true }
        return false
    }

    /// Where the skip button sits in from the bottom-right corner. Generous
    /// on tvOS for the overscan margin every other edge control here already
    /// respects, tighter on a tablet, tighter still on a phone in landscape
    /// where the corner is also where the home indicator lives.
    private var skipButtonInset: (horizontal: CGFloat, vertical: CGFloat) {
        #if os(tvOS)
        return (88, 76)
        #else
        return DeviceClass.current == .phone ? (28, 22) : (46, 40)
        #endif
    }

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

            if visible && !night.isLocked && !scenesOpen && !tagsOpen {
                // Grouped so the whole cluster shares one `.transition` —
                // without this wrapper, `.transition(.opacity)` would need
                // repeating on every top-level piece below (or SwiftUI has
                // nothing to cross-fade between when `visible` flips).
                Group {
                    #if os(iOS)
                    // tvOS shows the chrome on Down and hides it on Menu
                    // (`handleMove` / `handleMenuPress`) or idle-timeout.
                    // Touch has no such buttons, so tapping the empty video
                    // area toggles chrome visibility instead — lowest z-order
                    // so it sits behind every real control and only catches
                    // taps that miss them.
                    tapCatcher(action: toggleVisible)
                    #endif

                    // Legibility scrims, top and bottom. The chrome used to sit
                    // on raw picture, which is where its contrast went the moment
                    // a scene was bright — and this version leans harder on white
                    // type and thin strokes than the one it replaced, so it needs
                    // them more. Behind everything, and never hit-testable.
                    legibilityScrims

                    sonarMotif

                    #if os(iOS)
                    if DeviceClass.current == .phone {
                        phoneChromeColumn
                    } else {
                        standardChromeColumn
                    }
                    #else
                    standardChromeColumn
                    #endif

                    if case .failed(let message) = controller.phase {
                        PlayerFailureOverlay(
                            message: message, hasNext: controller.hasNext, accent: accent,
                            onRetry: { interact(); Task { await controller.retryCurrentItem() } },
                            onSkip: { interact(); Task { await controller.skipCurrentItem() } },
                            onClose: onClose,
                            focus: $focus
                        )
                        #if os(tvOS)
                        // The remote lands on Retry the moment the overlay
                        // exists, however it got here — a failure mid-chrome,
                        // one that arrives while the chrome is hidden, or the
                        // `=failed` fixture starting in this state. Without it
                        // focus stays on whatever was under the overlay
                        // (verified: the play circle kept its ring, and Retry
                        // had none) and Select presses a button nobody can see.
                        .onAppear { focus = .failureRetry }
                        #endif
                    }
                }
                .transition(.opacity)
            } else if !scenesOpen && !tagsOpen {
                hiddenCatcher
                    .transition(.opacity)
                #if os(tvOS)
                if let glance, !night.isLocked {
                    PlayerGlance(kind: glance, controller: controller, accent: accent)
                        .transition(.opacity)
                }
                #endif
            }

            if scenesOpen {
                PlayerScenesPanel(controller: controller, accent: accent,
                                  onDismiss: closeScenes)
                    .transition(.opacity)
            }

            if tagsOpen {
                PlayerTagsPanel(controller: controller, accent: accent,
                                onDismiss: closeTags, onTagApplied: applyTagAndClose)
                    .transition(.opacity)
            }

            // Above everything else that's currently up (chrome is already
            // gone by the time this shows — see `applyTagAndClose`), and
            // never hit-testable — it's a receipt, not a control.
            if let stampedTag {
                PlayerTagStamp(tag: stampedTag, accent: accent)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // **Outside the `if visible` branch**, which is the whole point:
            // the theme starts, the button appears over the picture, one
            // press and you're past it. Summoning the chrome first would make
            // it slower than the ⏩ circle it exists to replace.
            //
            // Still suppressed by everything that owns the screen — the scene
            // grid, the tag panel, a playback failure, and the Night lock,
            // under which nothing may act unseen.
            if let segment = controller.activeSegment,
               !night.isLocked, !scenesOpen, !tagsOpen, !isFailed {
                PlayerSkipButton(segment: segment, accent: accent,
                                 onSkip: { interact(); controller.skipActiveSegment() },
                                 focus: $focus)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomTrailing)
                    .padding(.trailing, skipButtonInset.horizontal)
                    .padding(.bottom, skipButtonInset.vertical)
            }

            // Last in the stack on purpose: while the lock is on it takes
            // every touch on the screen, including the ones that would
            // otherwise reach the hidden catcher underneath.
            if night.isLocked {
                NightLockOverlay(
                    remainingLabel: SleepTimer.remainingLabel(night.remaining),
                    onUnlock: { withAnimation(.easeOut(duration: 0.25)) { night.unlock() } },
                    // The same press as the chrome's thumbs-down: flag it, move on.
                    // The lock stays on — that is the point of doing it from here.
                    onDislike: { Task { await controller.dislikeAndAdvance() } }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.9), value: night.isOn)
        .animation(Self.fadeAnimation, value: controller.activeSegment)
        #if os(tvOS)
        .onChange(of: controller.activeSegment) { previous, current in
            // The button arrives already focused, so skipping is one Select
            // press rather than a hunt with the D-pad — the convention every
            // TV app that has this button follows. Only while the chrome is
            // hidden: with the controls up, yanking focus off play/pause
            // mid-film is the more annoying of the two failures.
            if current != nil, previous == nil, !visible, !night.isLocked {
                focus = .skipSegment
            } else if current != nil, previous != nil, current != previous,
                      focus == .skipSegment {
                // Intro straight into a recap, or the segment list arriving
                // late and replacing what was there: keep the focus on the
                // button rather than letting it fall to the catcher.
                focus = .skipSegment
            } else if current == nil, focus == .skipSegment {
                // Hand focus back rather than leaving it on a view that no
                // longer exists: with the chrome hidden the invisible catcher
                // is the only focusable thing left, and Menu needs *something*
                // focused for `.onExitCommand` to reach `handleMenuPress`.
                focus = nil
            }
        }
        #endif
        .onChange(of: visible) { _, v in
            PlayerDiagnostics.log("chrome: visible -> \(v)")
            #if os(tvOS)
            // **Every reveal lands on play/pause, not just the first.** The
            // `.onAppear` seed below runs once; after the idle timer hides the
            // chrome, focus moves to the invisible `hiddenCatcher`, and when a
            // D-pad nudge brings the controls back SwiftUI has to pick a new
            // home for it — which turned out to be BACK, the first focusable
            // in layout order and the one button here that ends playback.
            // Confirmed on the simulator: hide → Down → BACK glowing. For a
            // chrome whose premise is "press without aiming", a stray Select
            // after a reveal must pause, never exit. A failed item gets its
            // Retry — agreeing with the overlay's own `onAppear` seed rather
            // than racing it; skipped while the scenes/tags panel owns the
            // screen.
            if v, !scenesOpen, !tagsOpen {
                focus = isFailed ? .failureRetry : .playPause
            }
            // The chrome now shows the heart and the clock for real.
            if v { glanceTimer.cancel(); glance = nil }
            #endif
        }
        .onAppear {
            PlayerDiagnostics.log("chrome: onAppear visible=\(visible)")
            withAnimation(.easeOut(duration: 4).repeatForever(autoreverses: false)) { sonarPulse = true }
            // tvOS-only: seeding `@FocusState` gives the remote's directional
            // pad something focused at launch. On iPadOS, driving this same
            // `@FocusState` inside a `.fullScreenCover` silently breaks touch
            // delivery for every button in this view (confirmed on-device —
            // taps stopped reaching any SwiftUI `Button` here, chrome/hidden-
            // catcher included, the instant this ran unconditionally).
            #if os(tvOS)
            // A segment can already be active on the very first frame — the
            // `=skip` fixture, or resuming into an episode's credits. The
            // `onChange` above never fires for a value that was there from
            // the start, so the button would render unfocused and take two
            // presses instead of one.
            if controller.activeSegment != nil, !visible, !night.isLocked {
                focus = .skipSegment
            } else {
                focus = .playPause
            }
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
                withAnimation(Self.fadeAnimation) { visible = true }
                armIdleTimer()
            }
        }
        #if os(tvOS)
        // **The remote, with the chrome hidden, is four commands and Menu**
        // — see `handleMove` and `handleMenuPress`. Both fire here because
        // something in this view is always focused: the invisible catcher
        // while the chrome is away, a control while it's up, the badge under
        // the Night lock. They fire *at all* only because `JellyTV`'s
        // `RootView` presents the player as a same-`ZStack` overlay — inside
        // a `.fullScreenCover`, tvOS dismissed the cover on Menu before any
        // handler ran (verified with the chrome up and focus on the play
        // circle: no log line, straight to Home).
        .onMoveCommand(perform: handleMove)
        .onExitCommand(perform: handleMenuPress)
        #endif
        .onChange(of: controller.isPlaying) { _, playing in
            if playing {
                armIdleTimer()
            } else if !controller.isLoading {
                // The `isLoading` guard is the whole fix for "auto-advance
                // pops the chrome up": `setItem` (queue advance, retry, the
                // engine's own end-of-item skip) always dips `isPlaying`
                // false while it resolves the next item, whether a person
                // asked for that or the queue just moved on by itself. Only
                // a *paused-while-not-loading* transition is a real "the
                // user stopped playback" moment worth revealing the chrome
                // for — the video quietly becoming the next one is not.
                idleTimer.cancel()
                withAnimation(Self.fadeAnimation) { visible = true }
            }
        }
    }

    /// iPad/tvOS: one column, top to bottom — header, the circles centred in
    /// whatever is left, the foot. The circles take the slack, so they stay
    /// centred whether or not the item has tags. What is playing hangs off
    /// the bottom-right corner as an overlay rather than living in the
    /// column — see `PlayerIdentityMark`.
    private var standardChromeColumn: some View {
        VStack(spacing: 0) {
            PlayerTopBar(
                item: controller.currentItem,
                tags: controller.currentTags,
                accent: accent,
                night: night,
                onBack: onClose,
                onToggleNight: toggleNight,
                onEditTags: appState.canEditItemMetadata == false ? nil : openTags,
                focus: $focus
            )

            Spacer(minLength: 24)

            VStack(spacing: 34) {
                // One cluster: the opinions sit close enough to the
                // circles to read as belonging to the same block, and
                // far enough from the clock that the clock still reads
                // as a caption for the transport rather than for them.
                VStack(spacing: 20) {
                    PlayerOpinionRow(
                        controller: controller, accent: accent,
                        onInteract: interact, focus: $focus
                    )
                    PlayerTransportRow(
                        controller: controller, accent: accent,
                        onInteract: interact, focus: $focus
                    )
                }
                PlayerClockReadout(
                    // `displayTime`, not `currentTime`: while a burst
                    // of jump taps is settling this shows where they
                    // are heading, so the number moves on the tap
                    // rather than on the seek.
                    currentTime: controller.displayTime,
                    duration: controller.duration
                )
            }

            Spacer(minLength: 24)

            PlayerFootActions(
                controller: controller, accent: accent,
                onInteract: interact, onOpenScenes: openScenes, focus: $focus
            )
        }
        .padding(.top, 44)
        .padding(.bottom, 44)
        .padding(.horizontal, 56)
        // Diagonally opposite BACK, clear of the centred foot row,
        // and inert — it names the thing playing, it isn't a control.
        //
        // **It yields that corner to the skip button.** The mark is here
        // precisely because nobody needs to act on it, which is also what
        // makes it the thing to drop when something actionable needs the same
        // space for a minute. Stacking them instead was tried and is worse:
        // the button lands on top of the title and the episode line reads
        // through it.
        .overlay(alignment: .bottomTrailing) {
            if controller.activeSegment == nil {
                PlayerIdentityMark(item: controller.currentItem)
                    .padding(.trailing, 56)
                    .padding(.bottom, 44)
                    .transition(.opacity)
            }
        }
    }

    /// **Phone: "thumb rails," not a centred column.** `Main.dc.html` — the
    /// two things you actually *do* (the transport + clock) sit on the
    /// screen's own centre axis, same idea as iPad/tvOS; what's different is
    /// everything else moves to wherever a thumb already rests when a phone
    /// is held in two hands, landscape: the opinions to the bottom-left
    /// (where the left thumb sits), SCENES/NEXT to the bottom-right (where
    /// the right thumb sits) — not stacked in one centred column, which on
    /// a phone-sized landscape screen would put every control at arm's
    /// length from both thumbs at once instead of under one of them.
    ///
    /// **Cut outright, not shrunk:** the +1min circle (`PlayerTransportRow`
    /// already drops it for phone), PREV (`PlayerFootActions` already drops
    /// it for phone), and the corner identity mark — a phone's landscape
    /// player canvas doesn't have a fourth corner to spare on something
    /// nobody acts on, and BACK plus the title already say what's playing.
    private var phoneChromeColumn: some View {
        ZStack {
            VStack(spacing: 0) {
                PlayerTopBar(
                    item: controller.currentItem,
                    tags: controller.currentTags,
                    accent: accent,
                    night: night,
                    onBack: onClose,
                    onToggleNight: toggleNight,
                    onEditTags: appState.canEditItemMetadata == false ? nil : openTags,
                    focus: $focus
                )

                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    PlayerTransportRow(
                        controller: controller, accent: accent,
                        onInteract: interact, focus: $focus
                    )
                    PlayerClockReadout(
                        currentTime: controller.displayTime,
                        duration: controller.duration
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .padding(.bottom, 18)
            .padding(.horizontal, 20)

            PlayerOpinionRow(
                controller: controller, accent: accent,
                onInteract: interact, focus: $focus
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 20)
            .padding(.bottom, 18)

            PlayerFootActions(
                controller: controller, accent: accent,
                onInteract: interact, onOpenScenes: openScenes, focus: $focus
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 20)
            .padding(.bottom, 18)
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

    /// Scenes is its own surface: the chrome goes away entirely while it is
    /// up, and the auto-hide has nothing to hide, so the timer stops.
    private func openScenes() {
        onOpenScenes()
        idleTimer.cancel()
        withAnimation(.easeInOut(duration: 0.22)) { scenesOpen = true }
    }

    private func closeScenes() {
        withAnimation(.easeInOut(duration: 0.22)) { scenesOpen = false }
        interact()
    }

    /// Same bracket as scenes: the panel owns the screen, so the chrome's
    /// auto-hide has nothing to hide and stops until it closes.
    private func openTags() {
        idleTimer.cancel()
        withAnimation(.easeInOut(duration: 0.22)) { tagsOpen = true }
    }

    /// Leaving tags — however you leave (BACK, or a completed add — see
    /// `applyTagAndClose`) — returns straight to the hidden, playing video
    /// rather than re-summoning the chrome underneath it. Tagging is a quick
    /// aside mid-film, not a reason to stop and look at the controls again.
    private func closeTags() {
        withAnimation(.easeInOut(duration: 0.22)) { tagsOpen = false }
        idleTimer.cancel()
        withAnimation(Self.fadeAnimation) { visible = false }
    }

    /// One tag, one interaction: applying it from the panel (an existing
    /// suggestion, or a typed-and-added new one) closes the panel in the same
    /// beat and drops a quick "stamped" confirmation over the video, rather
    /// than leaving the panel open for more edits or bringing the chrome back
    /// to show the result. See `PlayerTagsPanel`'s own doc comment for why
    /// this only fires on an add, never a remove.
    private func applyTagAndClose(_ tag: String) {
        closeTags()
        withAnimation(.easeOut(duration: 0.15)) { stampedTag = tag }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { stampedTag = nil }
        }
    }

    private func interact() {
        PlayerDiagnostics.log("chrome: interact — reveal")
        withAnimation(Self.fadeAnimation) { visible = true }
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
            withAnimation(Self.fadeAnimation) { visible = false }
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
            withAnimation(Self.fadeAnimation) { visible = false }
        } else {
            interact()
        }
    }
    #endif

    #if os(tvOS)
    /// **Menu is "put that away", and only with nothing left to put away is
    /// it "leave".** Back out of whichever full-screen panel is on top first
    /// (tags and scenes both live in this view and have no handler of their
    /// own), then hide the chrome, and only from a hidden chrome leave the
    /// player — the same press the BACK pill makes. A failed item has no
    /// picture to hide the chrome over, so Menu leaves from there directly.
    /// Under the Night lock the press is inert, like every other press: the
    /// lock exists so a hand on the remote in the dark changes nothing.
    private func handleMenuPress() {
        if night.isLocked {
            PlayerDiagnostics.log("chrome: menu — locked, ignored")
        } else if tagsOpen {
            closeTags()
        } else if scenesOpen {
            closeScenes()
        } else if visible && !isFailed {
            PlayerDiagnostics.log("chrome: menu — hide")
            idleTimer.cancel()
            withAnimation(Self.fadeAnimation) { visible = false }
        } else {
            PlayerDiagnostics.log("chrome: menu — leave")
            onClose()
        }
    }

    /// **With the chrome hidden, the D-pad's four edges are the four things
    /// you do most**: Up likes, Left and Right jump thirty seconds, Down
    /// brings the controls. Each of the first three leaves a `PlayerGlance`
    /// so the press is seen to land. With the chrome up, the focus engine
    /// walks the controls as it always has and this only keeps the idle
    /// timer honest — plus `nudgeFocusIfStuck`, for the press it drops.
    /// Under the Night lock the overlay's two controls own the arrows.
    private func handleMove(_ direction: MoveCommandDirection) {
        if night.isLocked { return }
        if scenesOpen || tagsOpen || visible {
            interact()
            if visible, !scenesOpen, !tagsOpen { nudgeFocusIfStuck(direction) }
            return
        }
        switch direction {
        case .up:
            PlayerDiagnostics.log("chrome: hidden ↑ — like")
            night.noteInteraction()
            Task { await controller.toggleFavorite() }
            showGlance(.favorite)
        case .left, .right:
            let delta: Double = direction == .left ? -30 : 30
            PlayerDiagnostics.log("chrome: hidden \(direction == .left ? "←" : "→") — \(Int(delta))s")
            night.noteInteraction()
            controller.jump(by: delta)
            showGlance(.seek(delta))
        case .down:
            interact()
        @unknown default:
            interact()
        }
    }

    private func showGlance(_ kind: PlayerGlance.Kind) {
        withAnimation(.easeOut(duration: 0.15)) { glance = kind }
        glanceTimer.arm {
            withAnimation(.easeOut(duration: 0.35)) { glance = nil }
        }
    }

    /// The chrome is four centred rows — top bar, opinions, transport, foot —
    /// and the focus engine finds its way between them by geometry alone,
    /// which is what "stuck between the top buttons and the bottom ones" on
    /// the real box says it sometimes doesn't. So a moment after every Up or
    /// Down with the chrome up, check whether focus actually moved; if the
    /// engine left it where it was, put it on the next row by hand. When the
    /// engine does its job this never runs (the simulator walks all four rows
    /// cleanly); when it doesn't, the press still lands.
    private func nudgeFocusIfStuck(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down, let before = focus else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard visible, !scenesOpen, !tagsOpen, focus == before,
                  let target = fallbackFocus(from: before, direction) else { return }
            PlayerDiagnostics.log("chrome: focus stuck on \(before) — nudged to \(target)")
            focus = target
        }
    }

    private func fallbackFocus(from field: PlayerFocusField,
                               _ direction: MoveCommandDirection) -> PlayerFocusField? {
        let canEditTags = appState.canEditItemMetadata != false
        switch (direction, field) {
        case (.down, .back), (.down, .tags), (.down, .night):
            return .playPause
        case (.down, .dislike), (.down, .favorite):
            return .playPause
        case (.down, .back30), (.down, .playPause), (.down, .forward30), (.down, .forwardMinute):
            return .scenes
        case (.up, .previous), (.up, .scenes), (.up, .next):
            return .playPause
        case (.up, .back30):
            return .dislike
        case (.up, .playPause), (.up, .forward30), (.up, .forwardMinute):
            return .favorite
        case (.up, .dislike), (.up, .favorite):
            return canEditTags ? .tags : .back
        default:
            return nil
        }
    }
    #endif

    private func armIdleTimer() {
        idleTimer.arm {
            if controller.isPlaying {
                PlayerDiagnostics.log("chrome: idle timeout — hide")
                withAnimation(Self.fadeAnimation) { visible = false }
            }
        }
    }

    /// A top and bottom darkening pass, each fading to nothing well before
    /// the middle so the picture itself stays untouched where the eye
    /// actually is.
    ///
    /// **The two heights below are not cosmetic — they set the chrome's own
    /// size.** A SwiftUI `ZStack`'s reported size is the union of its
    /// children's ideal sizes, and this view's two `.frame(height:)` gradients
    /// are fixed regardless of what the parent actually proposes. Sized for
    /// tvOS/iPad's tall canvas (a landscape iPad is 800pt+ tall, tvOS far
    /// more), their combined 760pt used to be the *only* size on the books —
    /// no `DeviceClass` branch at all — even though the phone player runs
    /// this exact chrome in **landscape** on a screen only ~400pt tall. The
    /// instant this view mounted (it's only present while the chrome is
    /// `visible`, not in the hidden tap-catcher state), it forced the whole
    /// enclosing chrome — and `PlayerLayerView`, its sibling in `PlayerView`'s
    /// own `ZStack` — to be proposed a ~760pt-tall box instead of the real
    /// ~400pt one. Every edge-anchored control (`PlayerTopBar`, the opinions,
    /// SCENES/NEXT) shifted off-screen above/below a box nearly twice the
    /// physical height, while the vertically-centred transport row — the only
    /// piece whose position is symmetric `Spacer()`s rather than a screen
    /// edge — stayed exactly where it belonged, reading as "half the chrome
    /// is just missing." The `PlayerLayerView` sibling being resized into
    /// that same oversized, more-portrait-shaped box at the same moment is
    /// what read as "the video zooms in" the instant the chrome appeared.
    /// Confirmed by bisection: disabling this view alone (nothing else) made
    /// both symptoms disappear.
    private var legibilityScrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.86), .black.opacity(0.42), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Self.topScrimHeight)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.clear, .black.opacity(0.46), .black.opacity(0.90)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Self.bottomScrimHeight)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    #if os(iOS)
    private static var topScrimHeight: CGFloat { DeviceClass.current == .phone ? 110 : 340 }
    private static var bottomScrimHeight: CGFloat { DeviceClass.current == .phone ? 130 : 420 }
    #else
    private static let topScrimHeight: CGFloat = 340
    private static let bottomScrimHeight: CGFloat = 420
    #endif

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
