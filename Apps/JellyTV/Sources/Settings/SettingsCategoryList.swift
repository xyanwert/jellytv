import SwiftUI
import JellyTVKit

/// The Settings screen's left pane: category rows, the active one accent-tinted
/// with a left bar (same visual language as the rail's active nav icon).
struct SettingsCategoryList: View {
    let categories: [SettingsCategory]
    @Binding var selected: SettingsCategory.Kind
    var focus: FocusState<SettingsCategory.Kind?>.Binding

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYSTEM")
                .font(Typography.font(15, .heavy))
                .tracking(3)
                .foregroundStyle(theme.accent)
            Text("Settings")
                .font(Typography.font(52, .black))
                .foregroundStyle(Palette.textPrimary)
                .padding(.bottom, 20)

            ForEach(categories) { category in
                CategoryRow(category: category, isActive: category.kind == selected) {
                    selected = category.kind
                }
                .focused(focus, equals: category.kind)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 52)
        .frame(width: 420, alignment: .leading)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.text(0.08)).frame(width: 1)
        }
    }
}

private struct CategoryRow: View {
    let category: SettingsCategory
    let isActive: Bool
    let action: () -> Void

    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 4, height: 28)
                    .opacity(isActive ? 1 : 0)
                    .padding(.trailing, 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.label)
                        .font(Typography.font(23, .bold))
                        .foregroundStyle(isActive ? Palette.textPrimary : Palette.text(0.75))
                    Text(category.description)
                        .font(Typography.font(16, .medium))
                        .foregroundStyle(isActive ? Palette.text(0.55) : Palette.text(0.35))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(isActive ? Palette.text(0.06) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowFocusStyle())
    }
}

/// Focus highlight for full-width rows: a subtle background wash (no scale).
private struct SettingsRowFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }
    private struct Row: View {
        @Environment(\.isFocused) private var focused: Bool
        let configuration: ButtonStyle.Configuration
        var body: some View {
            configuration.label
                .background(Palette.text(focused ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
