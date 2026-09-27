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

    @EnvironmentObject private var theme: Theme

    var body: some View {
        if theme.isPoster { poster } else { classic }
    }

    private var classic: some View {
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

    // MARK: - Poster Mode

    /// "27:00 / 55:16" in the display face, then what a viewer actually
    /// weighs up: how long is left, and the time it will end. The end time
    /// reads the wall clock once a minute (`TimelineView`), so it stays true
    /// while paused.
    private var poster: some View {
        let isPhone = DeviceClass.current == .phone
        return VStack(spacing: PosterPlayerSize.chip * 0.5) {
            HStack(alignment: .firstTextBaseline, spacing: PosterPlayerSize.clock * 0.18) {
                Text(formatPlayerClock(currentTime, matching: duration))
                    .font(Display.font(PosterPlayerSize.clock))
                    .foregroundStyle(.white)
                Text("/ \(formatPlayerClock(duration, matching: duration))")
                    .font(Display.font(PosterPlayerSize.clockTotal))
                    .foregroundStyle(Palette.text(0.5))
                if isPhone, let left = leftLabel { chip(left, color: Palette.posterTeal) }
            }
            .monospacedDigit()
            .shadow(color: Palette.posterInk.opacity(0.8), radius: 0, x: 3, y: 3)
            if !isPhone, let left = leftLabel {
                TimelineView(.everyMinute) { context in
                    HStack(spacing: PosterPlayerSize.chip * 0.55) {
                        chip(left, color: Palette.posterTeal)
                        chip("ENDS \(endsLabel(now: context.date))", color: Palette.text(0.75))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(currentTime / 60)) minutes in of \(Int(duration / 60)) minutes")
    }

    private var remaining: Double { max(0, duration - currentTime) }

    private var leftLabel: String? {
        guard duration > 0 else { return nil }
        return "\(formatPlayerClock(remaining, matching: duration)) LEFT"
    }

    private func endsLabel(now: Date) -> String {
        now.addingTimeInterval(remaining).formatted(date: .omitted, time: .shortened).uppercased()
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Mono.font(PosterPlayerSize.chip, .bold))
            .tracking(PosterPlayerSize.chip * 0.08)
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, PosterPlayerSize.chip * 0.55)
            .padding(.vertical, PosterPlayerSize.chip * 0.22)
            .background(Palette.posterInk, in: RoundedRectangle(cornerRadius: PosterPlayerSize.chip * 0.28, style: .continuous))
    }
}
