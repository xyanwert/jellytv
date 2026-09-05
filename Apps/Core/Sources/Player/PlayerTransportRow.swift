import SwiftUI
import JellyTVKit

/// The transport circles, one row, biggest in the middle:
///
///     ↺30  ·  play/pause  ·  ↻30  ·  ↻1min
///
/// Nothing is written under them — the glyph is the label. That is what buys
/// full-size targets in one row rather than three plus a strip of seven small
/// tiles, and it is the whole point of this chrome: the two things you
/// actually do (pause, and go back because you missed a line) are enormous and
/// dead centre, and everything reachable is reachable without aiming.
///
/// **Start-over went.** It was the fifth circle, on the left, and it is the
/// one control here whose accidental press costs you the entire film — a
/// hazard sitting in the same row as the two most-mashed buttons in the app.
/// ↺30 held down gets you back to the beginning the slow, recoverable way.
///
/// Every one of these routes through `PlayerController.jump`, which
/// accumulates a burst of taps into a single seek — these are the most
/// mashable targets in the app, and before that gate existed a fast tap train
/// both swallowed taps and fired one frame-accurate seek per tap at a
/// possibly-transcoding server. See that method for the full reasoning.
///
/// The minute-ahead circle is deliberately smaller than the ±30s pair — it is
/// the one you reach for least — and it is the only one carrying colour,
/// because it is the one control here you have to *pick out* of a row. Blue
/// rather than the accent so it reads as a different kind of thing, not a
/// second play button.
struct PlayerTransportRow: View {
    let controller: PlayerController
    let accent: Color
    let onInteract: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    /// Set when a long press on the play button has just fired, so the tap
    /// that arrives when the finger lifts doesn't immediately undo it.
    ///
    /// A timestamp rather than a plain flag on purpose: a long press whose
    /// finger then slides off the button never produces that trailing tap, and
    /// a bare flag would sit armed and swallow the *next* real press. This one
    /// expires on its own.
    @State private var longPressedAt: Date?

    /// Same blue the old seek strip used for its ±30s tiles, kept so the
    /// chrome's palette didn't gain a colour on the way to losing controls.
    private let blue = Color(OKLCH(l: 0.62, c: 0.16, h: 245))

    // iPad's 25% reduction off tvOS's "reads from across the room" numbers
    // (see that reasoning above) carries the same way to iPhone's *portrait*
    // screens — Setup, Home, the library grids — since that's still a
    // tablet-or-phone-sized panel held in the hand either way. The *player*
    // is the one screen phone runs in **landscape**, on a screen noticeably
    // smaller than an iPad's, so it gets its own smaller scale rather than
    // inheriting iPad's — see `Main.dc.html`'s 76/104/76pt circles.
    #if os(iOS)
    private var isPhone: Bool { DeviceClass.current == .phone }
    private enum Size {
        /// Minute-ahead: secondary, but still far past the 88pt floor this
        /// chrome holds itself to.
        static let edge: CGFloat = 114
        static let jump: CGFloat = 142.5
        static let play: CGFloat = 186
        static let gap: CGFloat = 33
    }
    private enum PhoneSize {
        static let jump: CGFloat = 76
        static let play: CGFloat = 104
        static let gap: CGFloat = 26
    }
    private var jump: CGFloat { isPhone ? PhoneSize.jump : Size.jump }
    private var play: CGFloat { isPhone ? PhoneSize.play : Size.play }
    private var gap: CGFloat { isPhone ? PhoneSize.gap : Size.gap }
    private var jumpGlyphSize: CGFloat { isPhone ? 30 : 55.5 }
    private static let minuteGlyphSize: CGFloat = 42
    private var repeatGlyphSize: CGFloat { isPhone ? 35 : 63 }
    private var playGlyphSize: CGFloat { isPhone ? 39 : 69 }
    private var playIconOffset: CGFloat { isPhone ? 2.5 : 4.5 }
    private var repeatRingWidth: CGFloat { isPhone ? 2 : 3.75 }
    private var plainRingWidth: CGFloat { isPhone ? 1.5 : 2.25 }
    #else
    private enum Size {
        /// Minute-ahead: secondary, but still far past the 88pt floor this
        /// chrome holds itself to.
        static let edge: CGFloat = 152
        static let jump: CGFloat = 190
        static let play: CGFloat = 248
        static let gap: CGFloat = 44
    }
    private let jump: CGFloat = Size.jump
    private let play: CGFloat = Size.play
    private let gap: CGFloat = Size.gap
    private let jumpGlyphSize: CGFloat = 74
    private static let minuteGlyphSize: CGFloat = 56
    private let repeatGlyphSize: CGFloat = 84
    private let playGlyphSize: CGFloat = 92
    private let playIconOffset: CGFloat = 6
    private let repeatRingWidth: CGFloat = 5
    private let plainRingWidth: CGFloat = 3
    #endif

    var body: some View {
        #if os(iOS)
        if isPhone {
            phoneRow
        } else {
            standardRow
        }
        #else
        standardRow
        #endif
    }

    /// **No phantom slot, and no +1min circle.** iPad/tvOS hold an empty
    /// slot where start-over used to sit so the asymmetric +1min circle
    /// doesn't pull play off-centre; phone drops +1min entirely (task brief:
    /// "cut on phone: the +1min circle, PREV, and the corner identity
    /// mark"), so three circles are already symmetric on their own — no
    /// counterweight needed. Matches `Main.dc.html`'s centre exactly:
    /// ↺30 · play/pause · ↻30 at 76/104/76pt with 26pt gaps.
    private var phoneRow: some View {
        HStack(spacing: gap) {
            circle(
                field: .back30, diameter: jump, glyph: "gobackward.30", glyphSize: jumpGlyphSize,
                fill: .black.opacity(0.52), stroke: Palette.text(0.20), tint: .white,
                label: "30 seconds back"
            ) {
                controller.jump(by: -30)
            }

            playCircle

            circle(
                field: .forward30, diameter: jump, glyph: "goforward.30", glyphSize: jumpGlyphSize,
                fill: .black.opacity(0.52), stroke: Palette.text(0.20), tint: .white,
                label: "30 seconds ahead"
            ) {
                controller.jump(by: 30)
            }
        }
    }

    private var standardRow: some View {
        HStack(spacing: gap) {
            // **A phantom slot where start-over used to be.** The row is
            // centred on screen, so simply deleting the fifth circle left the
            // play button ~96pt left of centre — and "the button you press
            // most is dead centre, reachable without aiming" is the whole
            // premise of this chrome, not a detail of it. Holding the empty
            // width keeps play centred, keeps the opinions above it centred
            // too, and costs nothing but air on the left.
            Color.clear.frame(width: Size.edge, height: 1)

            circle(
                field: .back30, diameter: jump, glyph: "gobackward.30", glyphSize: jumpGlyphSize,
                fill: .black.opacity(0.52), stroke: Palette.text(0.20), tint: .white,
                label: "30 seconds back"
            ) {
                controller.jump(by: -30)
            }

            playCircle

            circle(
                field: .forward30, diameter: jump, glyph: "goforward.30", glyphSize: jumpGlyphSize,
                fill: .black.opacity(0.52), stroke: Palette.text(0.20), tint: .white,
                label: "30 seconds ahead"
            ) {
                controller.jump(by: 30)
            }

            circle(
                field: .forwardMinute, diameter: Size.edge, glyph: "goforward.60", glyphSize: Self.minuteGlyphSize,
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
    ///
    /// **Hold it to repeat this one.** Repeat-one had no control at all after
    /// the thirteen-button chrome was cut; rather than spend a sixth circle on
    /// something you want perhaps once a night, it lives on a long press of
    /// the button that is already impossible to miss. The circle then *shows*
    /// it — `repeat.1` and a bright ring, not a badge tucked in a corner —
    /// because a playback mode you can't see is a playback mode you can't
    /// escape. One ordinary tap turns it off again.
    ///
    /// The cost, stated plainly: while repeat is on, that tap spends itself
    /// clearing the mode rather than pausing. Pausing is a second tap. That is
    /// the trade for having exactly one thing written on the button at a time.
    private var playCircle: some View {
        let repeating = controller.repeatOne
        return Button {
            onInteract()
            // Swallow the tap that a long press leaves behind on finger-up.
            if let at = longPressedAt, Date().timeIntervalSince(at) < 1 {
                longPressedAt = nil
                return
            }
            if repeating {
                controller.toggleRepeatOne()
            } else {
                controller.togglePlay()
            }
        } label: {
            ZStack {
                Circle().fill(accent)
                if controller.isLoading {
                    ProgressView().controlSize(.large).tint(.white)
                } else if repeating {
                    Image(systemName: "repeat.1")
                        .font(.system(size: repeatGlyphSize, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: playGlyphSize, weight: .bold))
                        .foregroundStyle(.white)
                        // Optical centring: a triangle's mass sits left of its
                        // bounding box, a pair of bars is already centred.
                        .offset(x: controller.isPlaying ? 0 : playIconOffset)
                }
            }
            .frame(width: play, height: play)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .overlay(Circle().stroke(repeating ? .white : accent.opacity(0.45),
                                     lineWidth: repeating ? repeatRingWidth : plainRingWidth))
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: play / 2))
        // Simultaneous, not `.onLongPressGesture`: the latter would replace
        // the button's own tap handling, and the tap is what this control is
        // mainly for.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                longPressedAt = Date()
                onInteract()
                if !controller.repeatOne { controller.toggleRepeatOne() }
            }
        )
        .remoteFocus($focus, equals: .playPause)
        .accessibilityLabel(repeating ? "Repeating this one — tap to stop repeating"
                                      : (controller.isPlaying ? "Pause" : "Play"))
        .accessibilityHint(repeating ? "" : "Press and hold to repeat this one")
    }
}
