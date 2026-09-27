import SwiftUI
import JellyTVKit

/// "Skip intro" / "Skip credits" — the one control in this player that
/// appears without being asked for.
///
/// **Why it breaks the centred-column rule.** Every other control here lives
/// in one column down the middle of the screen, because those are things you
/// go looking for and the middle is where the eye and the thumb already are.
/// This one is the opposite: it seeks *you*, arriving unbidden over a playing
/// picture and leaving a minute later. Putting it in that column would mean
/// dropping a live target under the play button — the most-mashed surface in
/// the app — where a press meant for pause would jump the film instead. The
/// corner is also simply where a decade of streaming apps have taught people
/// to look for it, and this is not the control to be inventive with.
///
/// **It is drawn outside the chrome's `if visible` branch on purpose.** The
/// premise of the feature is that the theme starts, the button appears, one
/// press and you're past it — needing to summon the chrome first would make
/// it slower than pressing ⏩ twice, which is the thing it replaces.
///
/// Whether it appears at all is `PlayerController.activeSegment`, which is
/// nil unless the server actually marked a sequence *and* the viewer left
/// "Skip intros" on. Nothing here detects anything; see `MediaSegment`.
struct PlayerSkipButton: View {
    let segment: MediaSegment
    let accent: Color
    let onSkip: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    @EnvironmentObject private var theme: Theme

    private var isPhone: Bool {
        #if os(iOS)
        DeviceClass.current == .phone
        #else
        false
        #endif
    }

    #if os(tvOS)
    private let height: CGFloat = 76
    private let radius: CGFloat = 16
    private let labelSize: CGFloat = 26
    private let glyphSize: CGFloat = 24
    private let padding: CGFloat = 34
    #else
    private var height: CGFloat { isPhone ? 46 : 58 }
    private var radius: CGFloat { isPhone ? 12 : 14 }
    private var labelSize: CGFloat { isPhone ? 15 : 19 }
    private var glyphSize: CGFloat { isPhone ? 13 : 16 }
    private var padding: CGFloat { isPhone ? 18 : 26 }
    #endif

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// Deliberately quiet: a solid accent slab in the corner of a playing
    /// picture is a distraction for the whole minute it sits there, and most
    /// of the time it will be ignored. Dark glass with a hairline reads
    /// clearly over any scene without competing with the film.
    private var label: some View {
        HStack(spacing: 10) {
            Text(segment.kind.actionLabel)
                .font(Typography.font(labelSize, .semibold))
            Image(systemName: "forward.end.fill")
                .font(.system(size: glyphSize, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, padding)
        .frame(height: height)
        .background(.black.opacity(0.62), in: shape)
        .overlay(shape.stroke(Palette.text(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }

    /// A real `Button` on both platforms.
    ///
    /// The iOS-eats-touches hazard `PlayerChrome.tapCatcher` documents does
    /// **not** apply here, and the distinction is the whole of it: that one
    /// is a `Button` whose label is `Color.clear` under a style that draws
    /// nothing, so there is no shape for a touch to land on. This one paints
    /// a real filled capsule, and `.contentShape(shape)` states the hit area
    /// explicitly rather than leaving it to be inferred — belt to that
    /// braces. Keeping it a `Button` is also what keeps it a button to
    /// VoiceOver, which `.onTapGesture` would quietly cost.
    var body: some View {
        if theme.isPoster {
            Button(action: onSkip) { posterLabel.contentShape(Capsule()) }
                .buttonStyle(StickerButtonStyle(cornerRadius: posterHeight / 2, lift: PosterPlayerSize.lift * 1.6,
                                                focusScale: 1.08))
                .remoteFocus($focus, equals: .skipSegment)
                .transition(.posterSlap)
        } else {
            Button(action: onSkip) { label.contentShape(shape) }
            #if os(tvOS)
                .buttonStyle(FocusScaleStyle(cornerRadius: radius))
            #else
                .buttonStyle(.plain)
            #endif
                .remoteFocus($focus, equals: .skipSegment)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    // MARK: - Poster Mode

    private var posterHeight: CGFloat { DeviceClass.current == .tv ? 118 : (isPhone ? 52 : 72) }

    /// The white arrow pill: SKIP INTRO in the display face, the ink disc
    /// with the skip glyph at its end. It arrives with the sticker slap —
    /// one small layer, and the thing on screen that most needs noticing.
    private var posterLabel: some View {
        let h = posterHeight
        return HStack(spacing: h * 0.26) {
            Text(segment.kind.actionLabel.uppercased())
                .font(Display.font(h * 0.46))
                .tracking(1)
                .lineLimit(1)
                .fixedSize()
            Image(systemName: "forward.end.fill")
                .font(.system(size: h * 0.3, weight: .black))
                .foregroundStyle(.white)
                .frame(width: h * 0.75, height: h * 0.75)
                .background(Palette.posterInk, in: Circle())
        }
        .foregroundStyle(Palette.posterInk)
        .padding(.leading, h * 0.38)
        .padding(.trailing, h * 0.125)
        .frame(height: h)
        .background(.white, in: Capsule())
    }
}
