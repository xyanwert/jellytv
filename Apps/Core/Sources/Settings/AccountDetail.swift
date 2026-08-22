import SwiftUI
import JellyTVKit

/// Settings → Account: profile info and sign out. Theme/hero controls have
/// moved to their own categories (Appearance, Home).
struct AccountDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var server: ServerConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Account")

            profileRow
            DetailDivider()

            signOutRow

            Spacer(minLength: 0)
        }
    }

    private var profileRow: some View {
        HStack(spacing: 20) {
            Avatar(initial: profileInitial, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(profileName)
                    .font(Typography.font(24, .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text(profileEmail)
                    .font(Typography.font(17, .medium))
                    .foregroundStyle(Palette.text(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 26)
    }

    private var profileInitial: String {
        if let info = server.serverInfo {
            return String(info.userId.prefix(1))
        }
        return SampleCatalog.profile.initial
    }

    private var profileName: String {
        server.serverInfo != nil ? "User" : SampleCatalog.profile.name
    }

    private var profileEmail: String {
        if let info = server.serverInfo {
            return "Connected to \(info.name)"
        }
        return "\(SampleCatalog.profile.email) · \(SampleCatalog.profile.role)"
    }

    private var signOutRow: some View {
        Button {
            server.signOut()
        } label: {
            HStack {
                Text("Sign Out")
                    .font(Typography.font(24, .bold))
                    .foregroundStyle(theme.accent)
                Spacer(minLength: 0)
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowFocusStyle())
    }
}
