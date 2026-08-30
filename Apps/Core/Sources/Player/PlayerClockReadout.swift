import SwiftUI

/// `00:27/01:17` — elapsed over total, in the technical readout voice.
///
/// This is what replaced the progress bar. A bar invites dragging, and a
/// dragged bar is the single easiest way to lose your place in a film by
/// accident; two numbers can be read and cannot be knocked. Elapsed is bright
/// and total is dim, so the eye lands on the half that changes.
struct PlayerClockReadout: View {
    let currentTime: Double
    let duration: Double

    var body: some View {
        HStack(spacing: 0) {
            Text(formatPlayerClock(currentTime, matching: duration))
                .foregroundStyle(Palette.text(0.95))
            Text("/")
                .foregroundStyle(Palette.text(0.3))
                .padding(.horizontal, 10)
            Text(formatPlayerClock(duration, matching: duration))
                .foregroundStyle(Palette.text(0.48))
        }
        .font(Mono.font(34, .bold))
        // The seconds digit changes 60 times a minute; without this the
        // readout re-lays-out on every tick and the numbers shimmy.
        .monospacedDigit()
        .tracking(1.5)
        // Display only — every seek in this chrome is a discrete circle.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(Int(currentTime / 60)) minutes in of \(Int(duration / 60)) minutes"
        )
    }
}
