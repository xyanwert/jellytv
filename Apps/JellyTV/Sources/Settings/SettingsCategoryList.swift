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

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(category.label)
                    .font(Typography.font(23, .bold))
                    .foregroundStyle(isActive ? Palette.textPrimary : Palette.text(0.75))
                Text(category.description)
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(isActive ? Palette.text(0.55) : Palette.text(0.35))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowFocusStyle(isActive: isActive))
    }
}
