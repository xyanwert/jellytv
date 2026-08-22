import SwiftUI
import JellyTVKit

/// Vertical pill timer for the hero carousel, sitting on the hero's right edge
/// (vertically centered). One pill per slide; the active pill is tall, starts
/// full, and drains top→bottom over the rotation interval (after a brief
/// hold-full lead-in) as a countdown to the next auto-advance. A status
/// read-out — not part of the focus engine.
struct HeroPillTimer: View {
    let count: Int
    let activeIndex: Int
    let slideStartTime: Date
    let interval: Double

    @EnvironmentObject private var theme: Theme

    /// Hold the active pill full for this long before it starts draining.
    private let leadIn: Double = 0.5

    var body: some View {
        if count > 1 {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(slideStartTime)
                let drain = max(0.1, interval - leadIn)
                let progress = max(0, min(1, (elapsed - leadIn) / drain))

                VStack(spacing: 8) {
                    ForEach(0..<count, id: \.self) { i in
                        pill(isActive: i == activeIndex, progress: progress)
                    }
                }
                // Animate ONLY the pill morph on index change; the drain mask
                // is recomputed per frame by TimelineView and never tweened.
                .animation(.smooth(duration: 0.5), value: activeIndex)
            }
            .focusable(false)
        }
    }

    private func pill(isActive: Bool, progress: Double) -> some View {
        Capsule()
            .fill(theme.accent)
            .mask(
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        // Clear region grows from the top as the timer runs,
                        // draining the visible accent top→bottom.
                        Color.clear.frame(height: isActive ? proxy.size.height * progress : 0)
                        Color.white
                    }
                }
            )
            .overlay {
                if isActive {
                    Capsule().strokeBorder(theme.accent, lineWidth: 1)
                }
            }
            .frame(width: 10, height: isActive ? 92 : 14)
    }
}
