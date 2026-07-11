import SwiftUI
import JellyTVKit

/// The Home content area's readout row: a breadcrumb-style eyebrow on the left,
/// a clock and a focusable profile avatar on the right. The wordmark/logo and
/// primary navigation now live in the rail (`NavRail`), not here.
struct TopBar: View {
    let profile: UserProfile
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text("HOME // FEATURED")
                .font(Typography.font(15, .heavy))
                .tracking(2.6)
                .foregroundStyle(Palette.text(0.5))

            Spacer()

            HStack(spacing: 24) {
                Text("9:41 PM")
                    .font(Typography.font(21, .medium))
                    .foregroundStyle(Palette.text(0.5))
                Button(action: onOpenSettings) {
                    Avatar(initial: profile.initial, size: 48)
                        .overlay(Circle().stroke(Color(hex: "#FFF3F3"), lineWidth: 4))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.12, cornerRadius: 999))
            }
        }
        .padding(.horizontal, 56)
        .padding(.top, 28)
    }
}
