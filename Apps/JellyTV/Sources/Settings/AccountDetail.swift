import SwiftUI
import JellyTVKit

/// Settings → Account: profile, sign out, and the personalization pickers that
/// don't have a dedicated category in the design (accent theme, hero
/// transition/rotation) — see design.md's category-mapping decision.
struct AccountDetail: View {
    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Account")

            profileRow
            DetailDivider()

            DetailRow(label: "Theme", description: "Appearance & accent color") {
                AccentSwatchPicker(selection: $theme.option)
            }
            DetailDivider()

            DetailRow(label: "Transition", description: "Hero backdrop animation") {
                SegmentedControl(
                    options: HeroTransitionStyle.allCases.map(\.label),
                    selection: Binding(
                        get: { theme.transitionStyle.label },
                        set: { label in
                            if let match = HeroTransitionStyle.allCases.first(where: { $0.label == label }) {
                                theme.transitionStyle = match
                            }
                        }
                    )
                )
            }
            DetailDivider()

            DetailRow(label: "Rotation", description: "Hero auto-advance interval") {
                SegmentedControl(
                    options: HeroRotation.allCases.map(\.label),
                    selection: Binding(
                        get: { theme.rotationInterval.label },
                        set: { label in
                            if let match = HeroRotation.allCases.first(where: { $0.label == label }) {
                                theme.rotationInterval = match
                            }
                        }
                    )
                )
            }
            DetailDivider()

            signOutRow

            Spacer(minLength: 0)
        }
    }

    private var profileRow: some View {
        HStack(spacing: 20) {
            Avatar(initial: SampleCatalog.profile.initial, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(SampleCatalog.profile.name)
                    .font(Typography.font(24, .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(SampleCatalog.profile.email) · \(SampleCatalog.profile.role)")
                    .font(Typography.font(17, .medium))
                    .foregroundStyle(Palette.text(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 26)
    }

    private var signOutRow: some View {
        Button {} label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(FocusScaleStyle(scale: 1.0, cornerRadius: 0, outline: false))
    }
}

/// Four color swatches; the selected accent gets a white ring.
private struct AccentSwatchPicker: View {
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
                .buttonStyle(FocusScaleStyle(scale: 1.15, cornerRadius: 999, outline: false))
            }
        }
    }
}
