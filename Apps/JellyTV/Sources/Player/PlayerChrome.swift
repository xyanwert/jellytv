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

/// Full custom chrome, matching the "Jelly-tv Player" design: top bar,
/// center repeat + play, right-rail favorite/next/dislike, scrubber, bottom
/// seek strip. **All chrome talks to `PlayerController` and only
/// `PlayerController`** — see that type's doc comment for the contract.
///
/// Owns auto-hide (3s idle on tvOS, never while paused, re-armed by any
/// D-pad nudge or control tap). The Night toggle only flips its own button
/// state for now — the actual dim/warm treatment is deferred, not wired up.
struct PlayerChrome: View {
    let controller: PlayerController
    @Binding var visible: Bool
    let onClose: () -> Void
    let onOpenScenes: () -> Void

    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: PlayerFocusField?
    @State private var nightMode = false
    @State private var idleTask: Task<Void, Never>?
    @State private var sonarPulse = false

    private var accent: Color { theme.accent }

    var body: some View {
        ZStack {
            if visible {
                sonarMotif

                VStack {
                    PlayerTopBar(
                        item: controller.currentItem,
                        queuePositionLabel: controller.queuePositionLabel,
                        accent: accent,
                        nightMode: nightMode,
                        onBack: onClose,
                        onToggleNight: { interact(); nightMode.toggle() },
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
        }
        .onAppear {
            withAnimation(.easeOut(duration: 4).repeatForever(autoreverses: false)) { sonarPulse = true }
            focus = .playPause
            armIdleTimer()
        }
        .onMoveCommand { _ in interact() }
        .onChange(of: controller.isPlaying) { _, playing in
            if playing {
                armIdleTimer()
            } else {
                idleTask?.cancel()
                visible = true
            }
        }
    }

    /// Full-screen invisible button so a Select press while the chrome is
    /// hidden reveals it again instead of doing nothing (nothing else is
    /// focusable once the chrome's own buttons are gone).
    ///
    /// **Not `.buttonStyle(.plain)`** — on tvOS a focused plain-style button
    /// still paints the system's default white focus card, which here
    /// covers nearly the whole video (this button fills the screen). A
    /// custom style that renders nothing but `configuration.label` sidesteps
    /// that system chrome entirely, same rationale as `FocusScaleStyle`
    /// elsewhere in this app never using `.plain`/`.automatic`.
    private var hiddenCatcher: some View {
        Button(action: interact) {
            Color.clear
        }
        .buttonStyle(InvisibleButtonStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func interact() {
        visible = true
        armIdleTimer()
    }

    private func armIdleTimer() {
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if controller.isPlaying {
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
private struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
