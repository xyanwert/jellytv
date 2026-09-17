import SwiftUI
import JellyTVKit

#if os(tvOS)
/// What a D-pad press does while the chrome is hidden, shown for a beat.
///
/// With the controls away, the remote's four edges are the four things you do
/// most (`PlayerChrome.handleMove`): Up likes, Left and Right jump thirty
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

    var body: some View {
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
                Image(systemName: delta < 0 ? "gobackward.30" : "goforward.30")
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
