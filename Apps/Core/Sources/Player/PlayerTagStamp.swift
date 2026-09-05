import SwiftUI

/// The confirmation that flashes over the video the instant a tag is applied
/// from `PlayerTagsPanel` — see `PlayerChrome.applyTagAndClose`, which
/// dismisses the panel in the same beat this appears. It exists because that
/// dismissal is otherwise silent: the one piece of UI that showed the result
/// (the panel itself) is gone, and the chrome it used to reveal underneath
/// deliberately doesn't come back for this — so without a stamp, adding a tag
/// mid-film would have no visible effect at all.
///
/// A literal stamp motion — arrives oversized and rotated, snaps to rest with
/// a quick spring, holds just long enough to read, then fades. Never
/// hit-testable; it is a receipt, not a control.
struct PlayerTagStamp: View {
    let tag: String
    let accent: Color

    @State private var settled = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "tag.fill")
                .font(.system(size: 22, weight: .bold))
            Text(tag)
                .font(Typography.font(24, .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .background(accent, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1.5))
        .shadow(color: accent.opacity(0.55), radius: 26, y: 10)
        .scaleEffect(settled ? 1 : 1.5)
        .rotationEffect(.degrees(settled ? 0 : -10))
        .opacity(settled ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                settled = true
            }
        }
    }
}
