import SwiftUI

#if os(tvOS)
/// What the receiver has to say, on any screen: "Remote control on", a `DisplayMessage`
/// from a controlling app, and above all a phone's "👋 this is the TV I'm pointing at"
/// when two Apple TVs share a house and a name. Top centre, large, gone in four seconds
/// (`RemoteControl.notice` clears itself). Drawn by `RootView` and again inside the
/// player cover, which is its own window layer.
struct RemoteNoticeToast: View {
    @EnvironmentObject private var remote: RemoteControl
    @EnvironmentObject private var theme: Theme

    var body: some View {
        ZStack {
            if let notice = remote.notice {
                Text(notice)
                    .font(Typography.font(30, .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Palette.sheet.opacity(0.96))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(theme.accent.opacity(0.6), lineWidth: 2))
                    )
                    .shadow(color: theme.accent.opacity(0.35), radius: 30, y: 10)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 1100)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: remote.notice)
    }
}
#endif
