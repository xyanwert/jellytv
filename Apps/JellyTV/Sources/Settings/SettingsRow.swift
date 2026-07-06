import SwiftUI
import JellyTVKit

/// Focus highlight for panel rows: a subtle background wash (no scale).
struct SettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }
    private struct Row: View {
        @Environment(\.isFocused) private var focused: Bool
        let configuration: ButtonStyle.Configuration
        var body: some View {
            configuration.label
                .background(Palette.text(focused ? 0.10 : 0.0))
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// An account-panel row: icon tile, label + description, optional value, chevron.
struct SettingsRow: View {
    let entry: SettingsEntry
    let value: String?
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 22) {
                IconTile(systemName: Self.icon(for: entry.kind), color: iconColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.label)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text(entry.subtitle)
                        .font(Typography.font(18, .medium))
                        .foregroundStyle(Palette.text(0.48))
                }
                Spacer(minLength: 12)
                if let value, !value.isEmpty {
                    Text(value)
                        .font(Typography.font(20, .semibold))
                        .foregroundStyle(entry.kind == .server ? Palette.connected : Palette.text(0.4))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.text(0.35))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
    }

    static func icon(for kind: SettingsEntry.Kind) -> String {
        switch kind {
        case .profile: return "person.fill"
        case .settings: return "gearshape.fill"
        case .theme: return "moon.stars.fill"
        case .server: return "server.rack"
        }
    }
}
