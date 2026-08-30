import SwiftUI
import JellyTVKit

/// The five circles, one row, biggest in the middle:
///
///     ⏮ start over  ·  ↺30  ·  play/pause  ·  ↻30  ·  ↻1min
///
/// Nothing is written under them — the glyph is the label. That is what buys
/// five full-size targets in one row rather than three plus a strip of seven
/// small tiles, and it is the whole point of this chrome: the two things you
/// actually do (pause, and go back because you missed a line) are enormous
/// and dead centre, and everything reachable is reachable without aiming.
///
/// Every one of these routes through `PlayerController.jump`, which
/// accumulates a burst of taps into a single seek — these are the most
/// mashable targets in the app, and before that gate existed a fast tap train
/// both swallowed taps and fired one frame-accurate seek per tap at a
/// possibly-transcoding server. See that method for the full reasoning.
///
/// The outer pair is deliberately smaller than the ±30s pair — they are the
/// ones you reach for less often — and only the minute-ahead circle carries
/// colour, because it is the one control here you have to *pick out* of a
/// row. Blue rather than the accent so it reads as a different kind of
/// thing, not a second play button.
struct PlayerTransportRow: View {
    let controller: PlayerController
    let accent: Color
    let onInteract: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    /// Same blue the old seek strip used for its ±30s tiles, kept so the
    /// chrome's palette didn't gain a colour on the way to losing controls.
    private let blue = Color(OKLCH(l: 0.62, c: 0.16, h: 245))

    private enum Size {
        /// Start-over and minute-ahead: secondary, but still far past the
        /// 88pt floor this chrome holds itself to.
        static let edge: CGFloat = 152
        static let jump: CGFloat = 190
        static let play: CGFloat = 248
        static let gap: CGFloat = 44
    }

    var body: some View {
        HStack(spacing: Size.gap) {
            circle(
                field: .restart, diameter: Size.edge, glyph: "backward.end.fill", glyphSize: 52,
                fill: .black.opacity(0.44), stroke: Palette.text(0.16), tint: Palette.text(0.88),
                label: "Start over from the beginning"
            ) {
                controller.jump(to: 0)
            }

            circle(
                field: .back30, diameter: Size.jump, glyph: "gobackward.30", glyphSize: 74,
                fill: .black.opacity(0.52), stroke: Palette.text(0.20), tint: .white,
                label: "30 seconds back"
            ) {
                controller.jump(by: -30)
            }

            playCircle

            circle(
                field: .forward30, diameter: Size.jump, glyph: "goforward.30", glyphSize: 74,
                fill: .black.opacity(0.52), stroke: Palette.text(0.20), tint: .white,
                label: "30 seconds ahead"
            ) {
                controller.jump(by: 30)
            }

            circle(
                field: .forwardMinute, diameter: Size.edge, glyph: "goforward.60", glyphSize: 56,
                fill: blue, stroke: .clear, tint: .white, glow: blue,
                label: "One minute ahead"
            ) {
                controller.jump(by: 60)
            }
        }
    }

    @ViewBuilder
    private func circle(field: PlayerFocusField, diameter: CGFloat, glyph: String,
                        glyphSize: CGFloat, fill: Color, stroke: Color, tint: Color,
                        glow: Color? = nil, label: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            onInteract()
            action()
        } label: {
            Image(systemName: glyph)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: diameter, height: diameter)
                .background(fill, in: Circle())
                .overlay(Circle().stroke(stroke, lineWidth: 1))
                .shadow(color: (glow ?? .black).opacity(glow == nil ? 0.42 : 0.45),
                        radius: glow == nil ? 26 : 30, y: 10)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: diameter / 2))
        .remoteFocus($focus, equals: field)
        .accessibilityLabel(label)
    }

    /// The one control that changes shape with state — and the chrome's only
    /// loading indicator, so a slow queue-advance doesn't leave the user
    /// staring at a still frame wondering whether anything is happening.
    private var playCircle: some View {
        Button {
            onInteract()
            controller.togglePlay()
        } label: {
            ZStack {
                Circle().fill(accent)
                if controller.isLoading {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 92, weight: .bold))
                        .foregroundStyle(.white)
                        // Optical centring: a triangle's mass sits left of its
                        // bounding box, a pair of bars is already centred.
                        .offset(x: controller.isPlaying ? 0 : 6)
                }
            }
            .frame(width: Size.play, height: Size.play)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .overlay(Circle().stroke(accent.opacity(0.45), lineWidth: 3))
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: Size.play / 2))
        .remoteFocus($focus, equals: .playPause)
        .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
    }
}
