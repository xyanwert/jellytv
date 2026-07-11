import SwiftUI
import JellyTVKit

/// Shared pieces for Settings detail panes: a divider-separated row (label +
/// description + trailing control), a segmented picker, and a toggle switch —
/// matching the two-pane design's row style (not the old panel's card rows).
struct DetailRow<Trailing: View>: View {
    let label: String
    let description: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(Typography.font(24, .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text(description)
                    .font(Typography.font(17, .medium))
                    .foregroundStyle(Palette.text(0.5))
            }
            Spacer(minLength: 20)
            trailing()
        }
        .padding(.vertical, 26)
    }
}

struct DetailDivider: View {
    var body: some View {
        Rectangle().fill(Palette.text(0.1)).frame(height: 1)
    }
}

/// A row of focusable option pills; the active option gets a white fill.
struct SegmentedControl: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 5) {
            ForEach(options, id: \.self) { option in
                let active = option == selection
                Button { selection = option } label: {
                    Text(option)
                        .font(Typography.font(16, .bold))
                        .foregroundStyle(active ? Palette.screen : Palette.text(0.65))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(active ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 8))
            }
        }
        .padding(5)
        .background(Palette.text(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
    }
}

/// A focusable pill toggle switch, accent-filled when on.
struct ToggleSwitch: View {
    @Binding var isOn: Bool
    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? theme.accent : Palette.text(0.14))
                .frame(width: 56, height: 32)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 26, height: 26).padding(3)
                }
        }
        .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 999, outline: false))
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
