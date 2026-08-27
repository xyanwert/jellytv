import SwiftUI
import JellyTVKit

/// Night mode's own small palette — the amber the Night toggle already wears,
/// named once so the veil, the lock and the button can't drift apart.
enum NightPalette {
    static let amber = Color(OKLCH(l: 0.55, c: 0.13, h: 55))
    static let amberBright = Color(OKLCH(l: 0.62, c: 0.14, h: 55))
    /// Ink dark enough to read on a filled amber pill.
    static let ink = Color(hex: "#1A0E02")
    /// The filter itself: a warm wash multiplied into the picture. Multiply
    /// is what actually *removes* blue — laying a warm colour over the video
    /// at normal blend only lifts the blacks and greys the whole image out.
    static let warm = Color(red: 1.0, green: 0.62, blue: 0.26)
}

/// The picture treatment: blue pulled out of the video and the whole frame
/// taken down, deepening as the sleep timer winds down so the room darkens
/// and quietens as one movement.
///
/// The display's own brightness goes to its minimum alongside this (see
/// `NightModeController.dimDisplay`) — that alone can't cut blue, and this
/// alone can't get an iPad dark enough for a dark room, so Night mode does
/// both.
struct NightVeil: View {
    let windDown: Double
    let ended: Bool

    var body: some View {
        ZStack {
            NightPalette.warm
                .blendMode(.multiply)
                .opacity(0.62)
            Color.black.opacity(0.28 + windDown * 0.50 + (ended ? 0.14 : 0))
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// What Night mode puts between a sleeping viewer and the controls: a
/// full-screen catcher that swallows every touch, and a badge that says why.
///
/// A tap does nothing but bring the badge back — that's the whole feature, an
/// accidental touch has to be *inert*. Only a press held for
/// `NightModeController.unlockHoldSeconds` opens the lock, and the ring fills
/// while it's held so the gesture teaches itself.
struct NightLockOverlay: View {
    let remainingLabel: String
    let onUnlock: () -> Void

    /// The badge fades away on its own so the screen can go properly dark;
    /// any touch wakes it. `wake` is bumped rather than reset so each touch
    /// restarts the countdown.
    @State private var badgeShown = true
    @State private var wake = 0
    @State private var holdProgress: Double = 0

    private static let badgeSeconds: Double = 4

    var body: some View {
        ZStack {
            catcher
            badge
                .opacity(badgeShown ? 1 : 0)
                .animation(.easeInOut(duration: 0.45), value: badgeShown)
                .allowsHitTesting(false)
        }
        .task(id: wake) {
            badgeShown = true
            try? await Task.sleep(for: .seconds(Self.badgeSeconds))
            guard !Task.isCancelled else { return }
            badgeShown = false
        }
    }

    /// Swallows everything. On iOS this must not be a `Button` — an invisible
    /// one silently eats direct touches (see `PlayerChrome.tapCatcher`); on
    /// tvOS it must be one, since only a focusable view can receive a Select
    /// press at all.
    @ViewBuilder
    private var catcher: some View {
        #if os(tvOS)
        Button {
            wake += 1
        } label: {
            Color.clear
        }
        .buttonStyle(InvisibleButtonStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: NightModeController.unlockHoldSeconds) {
            onUnlock()
        } onPressingChanged: { pressing in
            press(pressing)
        }
        #else
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { wake += 1 }
            .onLongPressGesture(minimumDuration: NightModeController.unlockHoldSeconds) {
                onUnlock()
            } onPressingChanged: { pressing in
                press(pressing)
            }
            .ignoresSafeArea()
        #endif
    }

    private func press(_ pressing: Bool) {
        if pressing { wake += 1 }
        withAnimation(.linear(duration: pressing ? NightModeController.unlockHoldSeconds : 0.25)) {
            holdProgress = pressing ? 1 : 0
        }
    }

    private var badge: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(NightPalette.amberBright)
                .neonGlow(NightPalette.amber, intensity: 0.55)

            Text("NIGHT MODE")
                .font(Mono.font(12, .bold)).tracking(3)
                .foregroundStyle(NightPalette.amberBright.opacity(0.75))

            Text(remainingLabel)
                .font(Typography.font(36, .black))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()

            holdTrack

            Text("HOLD TO UNLOCK")
                .font(Mono.font(11, .bold)).tracking(2)
                .foregroundStyle(Palette.text(0.45))
        }
        .padding(.horizontal, 46)
        .padding(.vertical, 32)
        .frame(width: 320)
        .background(Palette.page.opacity(0.72), in: shape)
        .overlay { NeonTube(shape: shape, accent: NightPalette.amber, intensity: 0.5) }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    /// Fills across the hold. Present at rest as a hairline so the badge
    /// doesn't jump a row taller the moment a finger lands on it.
    private var holdTrack: some View {
        Capsule()
            .fill(Palette.text(0.14))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(NightPalette.amberBright)
                        .frame(width: geo.size.width * holdProgress)
                        .neonGlow(NightPalette.amber, intensity: 0.6)
                }
            }
            .frame(height: 3)
    }
}
