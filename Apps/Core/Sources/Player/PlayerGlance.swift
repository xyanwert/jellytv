import SwiftUI
import JellyTVKit

#if os(tvOS)
/// What a D-pad press does while the chrome is hidden, shown for a beat.
///
/// With the controls away, the remote's four edges are the four things you do
/// most (`PlayerChrome.handleMove`): Up likes, Left and Right jump (10 s, climbing under a run of presses)
/// seconds, Down brings the chrome. None of those has anything on screen to
/// press, so each one leaves a receipt — the heart as it now stands, or the
/// jump glyph over the clock, which moves on the press because it reads
/// `displayTime` (the seek's *target*), the same trick the readout in the
/// chrome uses. Without it a press with no visible answer gets pressed again.
///
/// Bottom-centre, where the readout sits when the chrome is up, and never a
/// control: it is drawn, not pressed.
struct PlayerGlance: View {
    enum Kind: Equatable {
        case favorite
        case seek(Double)
    }

    let kind: Kind
    let controller: PlayerController
    let accent: Color

    @EnvironmentObject private var theme: Theme

    var body: some View {
        if theme.isPoster { poster } else { classic }
    }

    /// Poster Mode: one sticker at the top centre — the glyph in a teal disc,
    /// the clock beside it (or LIKED) — tilted, with the hard ink shadow.
    private var poster: some View {
        VStack(spacing: 34) {
            posterSticker
            // The frame the jump lands on, under the sticker: the clock says
            // where, this says what — the same trickplay sheets as SCENES.
            if case .seek = kind {
                PlayerSceneFrame(controller: controller, time: controller.displayTime, width: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 70)
        .allowsHitTesting(false)
    }

    private var posterSticker: some View {
        HStack(spacing: 18) {
            switch kind {
            case .favorite:
                let on = controller.isFavorite
                Image(systemName: on ? "heart.fill" : "heart")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(on ? Color(hex: "#F0525F") : Palette.posterInk)
                    .frame(width: 84, height: 84)
                    .background(.white, in: Circle())
                Text(on ? "LIKED" : "LIKE REMOVED")
                    .font(Display.font(52))
            case .seek(let delta):
                VStack(spacing: 0) {
                    Image(systemName: delta < 0 ? "arrow.counterclockwise" : "arrow.clockwise")
                        .font(.system(size: 26, weight: .heavy))
                    Text(delta < 0 ? "-\(Int(-delta))" : "+\(Int(delta))")
                        .font(Display.font(24))
                }
                .foregroundStyle(Palette.posterInk)
                .frame(width: 84, height: 84)
                .background(Palette.posterTeal, in: Circle())
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(formatPlayerClock(controller.displayTime, matching: controller.duration))
                        .font(Display.font(64))
                    Text("/ \(formatPlayerClock(controller.duration, matching: controller.duration))")
                        .font(Display.font(34))
                        .foregroundStyle(Palette.text(0.5))
                }
                .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 32)
        .padding(.vertical, 12)
        .background(Palette.posterInk, in: Capsule())
        .overlay(Capsule().strokeBorder(.white, lineWidth: 5))
        .compositingGroup()
        .shadow(color: Palette.posterInk.opacity(0.6), radius: 0, x: 8, y: 8)
        .rotationEffect(.degrees(-2))
    }

    private var classic: some View {
        VStack(spacing: 18) {
            switch kind {
            case .favorite:
                let on = controller.isFavorite
                Image(systemName: on ? "heart.fill" : "heart")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(on ? .white : Palette.text(0.82))
                    .frame(width: 108, height: 108)
                    .background(on ? accent : .black.opacity(0.46), in: Circle())
                    .overlay(Circle().stroke(on ? accent : Palette.text(0.16), lineWidth: 1))
                    .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
                Text(on ? "LIKED" : "LIKE REMOVED")
                    .font(Mono.font(15, .bold))
                    .tracking(1.6)
                    .foregroundStyle(Palette.text(0.7))
            case .seek(let delta):
                PlayerSceneFrame(controller: controller, time: controller.displayTime, width: 480)
                Image(systemName: "\(delta < 0 ? "gobackward" : "goforward").\(Int(abs(delta)))")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 128, height: 128)
                    .background(.black.opacity(0.52), in: Circle())
                    .overlay(Circle().stroke(Palette.text(0.20), lineWidth: 1))
                    .shadow(color: .black.opacity(0.42), radius: 26, y: 10)
                PlayerClockReadout(currentTime: controller.displayTime,
                                   duration: controller.duration)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 132)
        .allowsHitTesting(false)
    }
}
#endif
