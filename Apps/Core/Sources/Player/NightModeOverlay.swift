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
/// full-screen catcher that swallows every touch, a badge that says why, and
/// beside the badge the one verdict you can still give — NOT FOR ME.
///
/// A tap does nothing but bring the badge back — that's the whole feature, an
/// accidental touch has to be *inert*. Only a press held for
/// `NightModeController.unlockHoldSeconds` opens the lock, and the ring fills
/// while it's held so the gesture teaches itself.
///
/// **The dislike button is the one deliberate exception to "inert".** Night
/// mode is for a queue playing itself through a dark room, and the thing you
/// most want to do from under the covers is skip the one you don't like —
/// without unlocking, finding the chrome and locking it again. So the button
/// sits next to the timer, does exactly what the chrome's thumbs-down does
/// (`PlayerController.dislikeAndAdvance`: save the flag, play the next), and
/// wakes the badge first if it had faded, so a press in the dark never acts on
/// something you can't see. On tvOS it is focusable — the badge is the other
/// focusable, and Left/Right walks between the two.
struct NightLockOverlay: View {
    let remainingLabel: String
    let onUnlock: () -> Void
    let onDislike: () -> Void

    /// The badge fades away on its own so the screen can go properly dark;
    /// any touch wakes it. `wake` is bumped rather than reset so each touch
    /// restarts the countdown.
    @State private var badgeShown = true
    @State private var wake = 0
    @State private var holdProgress: Double = 0
    #if os(tvOS)
    private enum Field: Hashable { case badge, dislike }
    @FocusState private var focused: Field?
    #endif

    private static let badgeSeconds: Double = 4

    var body: some View {
        ZStack {
            catcher
            HStack(alignment: .center, spacing: 22) {
                badgeControl
                dislikeButton
            }
            .opacity(badgeShown ? 1 : 0)
            .animation(.easeInOut(duration: 0.45), value: badgeShown)
        }
        .task(id: wake) {
            badgeShown = true
            try? await Task.sleep(for: .seconds(Self.badgeSeconds))
            guard !Task.isCancelled else { return }
            badgeShown = false
        }
        #if os(tvOS)
        .onAppear { focused = .badge }
        #endif
    }

    /// Swallows everything. On iOS this must not be a `Button` — an invisible
    /// one silently eats direct touches (see `PlayerChrome.tapCatcher`). On
    /// tvOS there is nothing to swallow (no touches) and a full-screen
    /// focusable would be a focus sink the dislike button could never be
    /// reached from — the *badge* is the focusable there (`badgeControl`).
    @ViewBuilder
    private var catcher: some View {
        #if os(iOS)
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
        #else
        Color.clear
        #endif
    }

    /// The badge — inert under a finger on iOS (the catcher beneath has the
    /// touches), the hold-to-unlock control itself under a remote on tvOS.
    @ViewBuilder
    private var badgeControl: some View {
        #if os(tvOS)
        Button {
            wake += 1
        } label: {
            badge
        }
        .buttonStyle(NightControlStyle(cornerRadius: 22))
        .focused($focused, equals: .badge)
        .onLongPressGesture(minimumDuration: NightModeController.unlockHoldSeconds) {
            onUnlock()
        } onPressingChanged: { pressing in
            press(pressing)
        }
        .accessibilityLabel("Night mode, \(remainingLabel) left. Hold to unlock.")
        #else
        badge.allowsHitTesting(false)
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

    /// NOT FOR ME, in the badge's own amber so it reads as part of Night mode
    /// rather than a piece of the chrome that slipped through the lock.
    private var dislikeButton: some View {
        Button {
            // A press on a faded badge only wakes it — nothing here acts
            // unseen.
            let seen = badgeShown
            wake += 1
            guard seen else { return }
            onDislike()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "hand.thumbsdown.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(NightPalette.amberBright)
                    .frame(width: 84, height: 84)
                    .background(Palette.page.opacity(0.72), in: Circle())
                    .overlay(Circle().stroke(NightPalette.amber.opacity(0.7), lineWidth: 1))
                Text("NOT FOR ME")
                    .font(Mono.font(11, .bold)).tracking(2)
                    .foregroundStyle(NightPalette.amberBright.opacity(0.75))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .background(Palette.page.opacity(0.72), in: shape)
            .overlay { NeonTube(shape: shape, accent: NightPalette.amber, intensity: 0.35) }
        }
        .buttonStyle(NightControlStyle(cornerRadius: 22))
        #if os(tvOS)
        .focused($focused, equals: .dislike)
        #endif
        .accessibilityLabel("Not for me — skip to the next")
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

/// The lock's controls under a remote: the amber ring, not the theme's accent
/// — `FocusScaleStyle` would put a red LED around an amber card. Touch keeps
/// the plain press dip.
struct NightControlStyle: ButtonStyle {
    var cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct Content: View {
        #if os(tvOS)
        @Environment(\.isFocused) private var focused: Bool
        #endif
        let configuration: NightControlStyle.Configuration
        let cornerRadius: CGFloat

        var body: some View {
            #if os(tvOS)
            configuration.label
                .scaleEffect((focused ? 1.05 : 1) * (configuration.isPressed ? 0.96 : 1))
                .overlay {
                    if focused {
                        LEDRing(cornerRadius: cornerRadius + 4, accent: NightPalette.amberBright)
                            .padding(-4)
                            .transition(.opacity)
                    }
                }
                .shadow(color: NightPalette.amber.opacity(focused ? 0.55 : 0), radius: focused ? 34 : 0)
                .animation(.spring(response: 0.26, dampingFraction: 0.6), value: focused)
            #else
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            #endif
        }
    }
}
