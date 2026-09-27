import SwiftUI

/// The next video is on its way: an hourglass turning over inside a disc of
/// the theme's colour, centre screen, while the queue's natural advance
/// resolves the next item (and after a credits skip's tape, which lands
/// there). Without it, the gap between one episode and the next is a black
/// screen that reads as the app having stalled.
///
/// The hourglass *flips* rather than spins — half a turn, a rest, half a
/// turn — the way a real one is turned over. One small layer on its own
/// clock; never hit-testable.
struct PlayerNextLoading: View {
    @EnvironmentObject private var theme: Theme

    private var diameter: CGFloat {
        switch DeviceClass.current {
        case .tv: return 150
        case .phone: return 72
        default: return 100
        }
    }

    /// One turn every 1.3s: 0.55s of turning, the rest resting.
    private static let period: Double = 1.3
    private static let turn: Double = 0.55

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let turns = (time / Self.period).rounded(.down)
            let phase = min(1, (time - turns * Self.period) / Self.turn)
            let eased = phase < 0.5 ? 2 * phase * phase : 1 - pow(-2 * phase + 2, 2) / 2
            let angle = 180 * (turns + eased)
            disc
                .overlay {
                    Image(systemName: "hourglass")
                        .font(.system(size: diameter * 0.42, weight: .bold))
                        .foregroundStyle(theme.isPoster ? Palette.posterInk : .white)
                        .rotationEffect(.degrees(angle))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading the next video")
    }

    @ViewBuilder
    private var disc: some View {
        if theme.isPoster {
            Circle()
                .fill(Palette.posterTeal)
                .overlay(Circle().strokeBorder(.white, lineWidth: max(4, diameter * 0.05)))
                .frame(width: diameter, height: diameter)
                .compositingGroup()
                .shadow(color: Palette.posterInk.opacity(0.9), radius: 0,
                        x: diameter * 0.05, y: diameter * 0.05)
        } else {
            Circle()
                .fill(theme.accent)
                .frame(width: diameter, height: diameter)
                .shadow(color: theme.accent.opacity(0.45), radius: diameter * 0.25)
        }
    }
}
