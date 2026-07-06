import SwiftUI
import JellyTVKit

/// The featured hero block: eyebrow, title, meta line, synopsis, actions, pager.
struct HeroView: View {
    let hero: HeroFeature
    var resumeFocus: FocusState<HomeFocus?>.Binding

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // eyebrow
            HStack(spacing: 14) {
                Rectangle().fill(theme.accent).frame(width: 34, height: 2)
                Text(hero.eyebrow.uppercased())
                    .font(Typography.eyebrow)
                    .tracking(2.6)
                    .foregroundStyle(theme.accent)
            }

            Text(hero.title)
                .font(Typography.heroTitle)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)

            metaLine

            Text(hero.synopsis)
                .font(Typography.body)
                .foregroundStyle(Palette.text(0.72))
                .lineSpacing(6)
                .frame(maxWidth: 760, alignment: .leading)

            actions
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
        .frame(maxWidth: 900, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaLine: some View {
        HStack(spacing: 14) {
            badge(hero.certification)
            Text(hero.year).foregroundStyle(Palette.text(0.65))
            dot
            Text(hero.genre).foregroundStyle(Palette.text(0.65))
            dot
            Text(hero.episode).foregroundStyle(Palette.text(0.65))
            dot
            badge(hero.qualityBadge)
        }
        .font(Typography.font(20, .medium))
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button {} label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.fill").font(.system(size: 22))
                    Text(hero.resumeLabel)
                }
                .font(Typography.button)
                .foregroundStyle(Palette.screen)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))
            .focused(resumeFocus, equals: .heroResume)

            Button {} label: {
                Text("Details")
                    .font(Typography.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Palette.text(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))

            Button {} label: {
                Image(systemName: "plus").font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Palette.text(0.85))
                    .frame(width: 58, height: 58)
                    .background(Palette.text(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))

            pager.padding(.leading, 22)
        }
        .padding(.top, 6)
    }

    private var pager: some View {
        HStack(spacing: 10) {
            ForEach(0..<hero.pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == hero.activePage ? theme.accent : Palette.text(0.22))
                    .frame(width: i == hero.activePage ? 110 : 12, height: 12)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(Typography.font(17, .heavy))
            .foregroundStyle(Palette.text(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.text(0.3), lineWidth: 1.5))
    }

    private var dot: some View { Text("·").foregroundStyle(Palette.text(0.4)) }
}
