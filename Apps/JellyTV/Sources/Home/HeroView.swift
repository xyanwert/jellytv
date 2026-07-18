import SwiftUI
import JellyTVKit

/// The featured hero's LEFT column in the split layout (design 3a): mono eyebrow,
/// oversized title, meta badges, synopsis, and the action buttons. The rotation
/// dots live in `TopBar` instead (top center of the screen). The framed still
/// on the right is rendered by `HomeView` so it can carry the crumble
/// transition. Text crossfades per slide; actions keep focus.
struct HeroView: View {
    let hero: HeroFeature
    var resumeFocus: FocusState<HomeFocus?>.Binding

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            textBlock
                .id(hero.id)
                // Match the backdrop's departure duration so the title/synopsis
                // don't jump to the next slide while the old backdrop is still
                // crumbling away — text and image reveal together.
                .transition(.opacity.animation(.easeInOut(duration: theme.transitionStyle.duration)))
            Spacer().frame(height: 20)
            actionsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(hero.eyebrow.uppercased())
                .font(Mono.font(15, .bold))
                .tracking(3.4)
                .foregroundStyle(theme.accent)

            // Reserve two lines so the title box height never changes.
            // The design's poster-style title is always two dramatic lines
            // (e.g. "The Deep" / "Signal") rather than one line that happens
            // to wrap, so we force a break at a balanced word boundary
            // instead of relying on width to wrap it — a short title like
            // "X: The Movie" would otherwise just sit on one line. Two
            // separate `Text` views (rather than one `Text` with an embedded
            // "\n") because a single Text combined with negative `.tracking`
            // collapsed the manual line break and truncated to one line.
            VStack(alignment: .leading, spacing: -8) {
                Text(Self.titleLines(hero.title).0)
                    .font(Typography.font(78, .black))
                    .tracking(-2)
                    .foregroundStyle(Palette.textPrimary)
                if let secondLine = Self.titleLines(hero.title).1 {
                    Text(secondLine)
                        .font(Typography.font(78, .black))
                        .tracking(-2)
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            .frame(height: 190, alignment: .bottomLeading)

            metaLine

            // Fixed 3-line reserve: missing descriptions leave the space empty
            // rather than pulling the buttons up.
            Text(hero.synopsis.isEmpty ? " " : hero.synopsis)
                .font(Typography.font(21, .medium))
                .foregroundStyle(hero.synopsis.isEmpty ? .clear : Palette.text(0.7))
                .lineSpacing(6)
                .lineLimit(3)
                .frame(maxWidth: 900, alignment: .topLeading)
                .frame(height: 84, alignment: .topLeading)
        }
    }

    /// Splits `title` into two lines at whichever word boundary lands
    /// closest to the midpoint (by character count), so titles of any
    /// length read as a balanced two-line poster title. Single-word titles
    /// can't be split without breaking the word, so those return `nil` for
    /// the second line and stay one line.
    private static func titleLines(_ title: String) -> (String, String?) {
        let words = title.split(separator: " ")
        guard words.count > 1 else { return (title, nil) }

        var cumulative: [Int] = [0]
        for word in words { cumulative.append(cumulative.last! + word.count + 1) }
        let total = cumulative.last!

        var bestIndex = 1
        var bestDistance = Int.max
        for i in 1..<words.count {
            let distance = abs(cumulative[i] - total / 2)
            if distance < bestDistance { bestDistance = distance; bestIndex = i }
        }

        let firstLine = words[..<bestIndex].joined(separator: " ")
        let secondLine = words[bestIndex...].joined(separator: " ")
        return (firstLine, secondLine)
    }

    private var metaLine: some View {
        HStack(spacing: 12) {
            badge(hero.certification.isEmpty ? " " : hero.certification,
                  visible: !hero.certification.isEmpty)
            Text(hero.year.isEmpty ? " " : hero.year)
                .foregroundStyle(hero.year.isEmpty ? .clear : Palette.text(0.62))
            dot
            Text(hero.genre.isEmpty ? " " : hero.genre)
                .foregroundStyle(hero.genre.isEmpty ? .clear : Palette.text(0.62))
                .lineLimit(1)
            if !hero.episode.isEmpty {
                dot
                Text(hero.episode).foregroundStyle(Palette.text(0.62)).lineLimit(1)
            }
            badge(hero.qualityBadge.isEmpty ? " " : hero.qualityBadge,
                  visible: !hero.qualityBadge.isEmpty)
        }
        .font(Typography.font(19, .medium))
    }

    private var actionsRow: some View {
        HStack(spacing: 16) {
            // Resume — accent-filled with a soft glow (design 3a).
            Button {} label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill").font(.system(size: 20))
                    Text(hero.resumeLabel)
                }
                .font(Typography.button)
                .foregroundStyle(.white)
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .frame(minWidth: 220)   // ~50% wider than the Details button
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: theme.accent.opacity(0.45), radius: 20, y: 6)
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))
            .focused(resumeFocus, equals: .heroResume)

            Button {} label: {
                Text("Details")
                    .font(Typography.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))

            Button {} label: {
                Image(systemName: "plus").font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Palette.text(0.85))
                    .frame(width: 56, height: 56)
                    .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))
        }
        .padding(.top, 4)
    }

    private func badge(_ text: String, visible: Bool = true) -> some View {
        Text(text)
            .font(Typography.font(15, .heavy))
            .foregroundStyle(visible ? Palette.text(0.8) : .clear)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(visible ? Palette.text(0.3) : .clear, lineWidth: 1.5))
    }

    private var dot: some View { Text("·").foregroundStyle(Palette.text(0.4)) }
}

/// Horizontal rotation dots for the hero (design 3a): one per slide, the active
/// one a wider pill that fills with the accent over the rotation interval.
struct HeroDotsRow: View {
    let count: Int
    let activeIndex: Int
    let slideStartTime: Date
    let interval: Double

    @EnvironmentObject private var theme: Theme
    private let leadIn: Double = 0.5

    var body: some View {
        if count > 1 {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(slideStartTime)
                let drain = max(0.1, interval - leadIn)
                let progress = max(0, min(1, (elapsed - leadIn) / drain))
                HStack(spacing: 9) {
                    ForEach(0..<count, id: \.self) { i in
                        dot(isActive: i == activeIndex, progress: progress)
                    }
                }
                .animation(.smooth(duration: 0.5), value: activeIndex)
            }
            .focusable(false)
        }
    }

    private func dot(isActive: Bool, progress: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.22))
            if isActive {
                GeometryReader { proxy in
                    Capsule().fill(theme.accent).frame(width: proxy.size.width * progress)
                }
            }
        }
        .frame(width: isActive ? 44 : 10, height: 10)
    }
}
