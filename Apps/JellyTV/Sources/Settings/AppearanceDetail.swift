import SwiftUI
import JellyTVKit

/// Settings → Appearance: accent color picker. The visual "theme" in this
/// single-accent design is just the four brand colors — no full-skin switcher
/// like v1's Jelly/Neon/TV themes.
struct AppearanceDetail: View {
    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Appearance")

            DetailRow(label: "Accent color", description: "Tint used for focus rings, highlights, and active states") {
                AccentSwatchPicker(selection: $theme.option)
            }
            DetailDivider()

            Spacer(minLength: 0)
        }
    }
}

/// Four color swatches; the selected accent gets a white ring.
struct AccentSwatchPicker: View {
    @Binding var selection: AccentOption

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AccentOption.allCases) { option in
                Button { selection = option } label: {
                    Circle()
                        .fill(Color(hex: option.hex))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(.white, lineWidth: option == selection ? 3 : 0))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.25, cornerRadius: 999, outline: false))
            }
        }
    }
}
