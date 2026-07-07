import SwiftUI
import JellyTVKit

/// Horizontal pill timer for the hero carousel. One pill per slide; the active
/// pill is wider, starts full, and drains left→right over the rotation interval
/// (after a brief hold-full lead-in) as a visible countdown to the next
/// auto-advance. A status read-out — not part of the focus engine.
struct HeroPillTimer: View {
    let count: Int
    let activeIndex: Int
    let slideStartTime: Date
    let interval: Double

    @EnvironmentObject private var theme: Theme

    /// Hold the active pill full for this long before it starts draining, so
    /// the "full then drain" reads correctly.
    private let leadIn: Double = 0.5

    var body: some View {
        if count > 1 {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let elapsed = context.date.timeIntervalSince(slideStartTime)
                let drain = max(0.1, interval - leadIn)
                let progress = max(0, min(1, (elapsed - leadIn) / drain))

                HStack(spacing: 8) {
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
                    HStack(spacing: 0) {
                        // Clear region grows from the leading edge as the timer
                        // runs, draining the visible accent left→right.
                        Color.clear.frame(width: isActive ? proxy.size.width * progress : 0)
                        Color.white
                    }
                }
            )
            .overlay {
                if isActive {
                    Capsule().strokeBorder(theme.accent, lineWidth: 1)
                }
            }
            .frame(width: isActive ? 92 : 14, height: 10)
    }
}
