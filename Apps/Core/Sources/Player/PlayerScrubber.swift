import SwiftUI

/// Pure display — elapsed/duration mono readout + a filled track with a
/// handle. Seeking happens via the discrete ±10s/±30s/±1min tiles in
/// `PlayerTransportStrip`, not by dragging this (tvOS has no drag gesture
/// here; v1's scrub-by-drag was iOS-only and explicitly unfinished).
struct PlayerScrubber: View {
    let currentTime: Double
    let duration: Double
    let accent: Color

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 20) {
            Text(formatPlayerTime(currentTime))
                .font(Mono.font(18, .bold))
                .foregroundStyle(Palette.text(0.85))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.text(0.18))
                    Capsule()
                        .fill(accent)
                        .frame(width: geo.size.width * progress)
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: accent.opacity(0.4), radius: 4)
                        .overlay(Circle().stroke(accent.opacity(0.4), lineWidth: 4).padding(-4))
                        .offset(x: geo.size.width * progress - 10)
                }
            }
            .frame(height: 8)

            Text(formatPlayerTime(duration))
                .font(Mono.font(18, .bold))
                .foregroundStyle(Palette.text(0.5))
        }
        .allowsHitTesting(false)
    }
}
