import SwiftUI
import JellyTVKit

/// The Settings account panel: a right-aligned panel over a dimmed Home.
/// Presented by the app shell (which blurs the Home behind it).
struct SettingsPanel: View {
    let onDismiss: () -> Void

    @EnvironmentObject private var theme: Theme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            panel
                .padding(.top, 60)
                .padding(.trailing, 80)
        }
        .onExitCommand(perform: onDismiss)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            divider
            ForEach(Array(SampleCatalog.settingsEntries.enumerated()), id: \.element.id) { _, entry in
                SettingsRow(
                    entry: entry,
                    value: value(for: entry),
                    iconColor: iconColor(for: entry.kind),
                    action: { onSelect(entry) }
                )
                divider
            }
            signOut
        }
        .frame(width: 620)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 90, y: 40)
    }

    private var header: some View {
        HStack(spacing: 20) {
            Avatar(initial: SampleCatalog.profile.initial, size: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(SampleCatalog.profile.name)
                    .font(Typography.font(26, .heavy))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(SampleCatalog.profile.email) · \(SampleCatalog.profile.role)")
                    .font(Typography.font(18, .medium))
                    .foregroundStyle(Palette.text(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(32)
    }

    private var signOut: some View {
        Button(action: onDismiss) {
            HStack(spacing: 22) {
                IconTile(systemName: "rectangle.portrait.and.arrow.right", color: theme.accent)
                Text("Sign Out")
                    .font(Typography.rowTitle)
                    .foregroundStyle(theme.accent)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
    }

    private var divider: some View {
        Rectangle().fill(Palette.text(0.06)).frame(height: 1)
    }

    private func onSelect(_ entry: SettingsEntry) {
        if entry.kind == .theme { theme.cycleAccent() }
    }

    private func value(for entry: SettingsEntry) -> String? {
        switch entry.kind {
        case .theme: return theme.appearanceValue
        case .server: return SampleCatalog.server.isConnected ? "Connected" : "Offline"
        case .profile: return entry.value
        case .settings: return nil
        }
    }

    private func iconColor(for kind: SettingsEntry.Kind) -> Color {
        switch kind {
        case .theme: return theme.accent
        case .server: return Palette.connected
        default: return Palette.text(0.85)
        }
    }
}
