import SwiftUI
import JellyTVKit

/// Home top bar: logo + `jelly·tv` wordmark, centered nav pill, clock, and a
/// focusable profile avatar that opens Settings.
struct TopBar: View {
    let tabs: [String]
    @Binding var activeTab: Int
    let profile: UserProfile
    let onOpenSettings: () -> Void

    @EnvironmentObject private var theme: Theme

    var body: some View {
        HStack(alignment: .center) {
            // logo + wordmark
            HStack(spacing: 18) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 52, height: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 6)
                wordmark
            }

            Spacer()
            NavPill(tabs: tabs, active: $activeTab)
            Spacer()

            // clock + avatar
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
        .padding(.horizontal, 80)
        .padding(.top, 28)
    }

    private var wordmark: some View {
        (Text("jelly")
            + Text("·").foregroundColor(theme.accent)
            + Text("tv"))
            .font(Typography.wordmark)
            .foregroundStyle(Palette.textPrimary)
    }
}
