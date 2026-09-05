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
    /// Details opens the hero's own screen — the film's, or for an episode
    /// the show's. It was an empty `Button {}` for a long time: the second
    /// most prominent control on the screen, and the only one that did
    /// nothing.
    var onDetails: () -> Void = {}

    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState
    /// Optimistic favourite state until the server answers — see
    /// `toggleFavorite`. Reset per slide.
    @State private var favoriteOverride: Bool?

    // tvOS's hero text zone was sized for a 1080pt-tall canvas with room to
    // spare below it for Continue Watching/Recommended. An iPad landscape
    // window is much shorter, so this whole block (title font/box, synopsis
    // box, inter-line spacing) is scaled down for iOS rather than eating
    // most of the screen — see `HomeView.backdropHeight`'s matching note.
    #if os(iOS)
    private static let textBlockSpacing: CGFloat = 8
    private static let titleFontSize: CGFloat = 52
    private static let titleBoxHeight: CGFloat = 116
    private static let synopsisFontSize: CGFloat = 18
    private static let synopsisBoxHeight: CGFloat = 58
    private static let actionsRowGap: CGFloat = 10
    #else
    private static let textBlockSpacing: CGFloat = 13
    private static let titleFontSize: CGFloat = 78
    private static let titleBoxHeight: CGFloat = 190
    private static let synopsisFontSize: CGFloat = 21
    private static let synopsisBoxHeight: CGFloat = 84
    private static let actionsRowGap: CGFloat = 20
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            textBlock
                .id(hero.id)
                // Match the backdrop's departure duration so the title/synopsis
                // don't jump to the next slide while the old backdrop is still
                // crumbling away — text and image reveal together.
                .transition(.opacity.animation(.easeInOut(duration: theme.transitionStyle.duration)))
            Spacer().frame(height: Self.actionsRowGap)
            actionsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: hero.id) { _, _ in favoriteOverride = nil }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: Self.textBlockSpacing) {
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
                    .font(Typography.font(Self.titleFontSize, .black))
                    .tracking(-2)
                    .foregroundStyle(Palette.textPrimary)
                if let secondLine = Self.titleLines(hero.title).1 {
                    Text(secondLine)
                        .font(Typography.font(Self.titleFontSize, .black))
                        .tracking(-2)
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            .frame(height: Self.titleBoxHeight, alignment: .bottomLeading)

            metaLine

            // Fixed 3-line reserve: missing descriptions leave the space empty
            // rather than pulling the buttons up.
            Text(hero.synopsis.isEmpty ? " " : hero.synopsis)
                .font(Typography.font(Self.synopsisFontSize, .medium))
                .foregroundStyle(hero.synopsis.isEmpty ? .clear : Palette.text(0.7))
                .lineSpacing(6)
                .lineLimit(3)
                .frame(maxWidth: 900, alignment: .topLeading)
                .frame(height: Self.synopsisBoxHeight, alignment: .topLeading)
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

    #if os(iOS)
    @ViewBuilder
    private var actionsRow: some View {
        if DeviceClass.current == .phone {
            // **iPad's row doesn't survive a phone width — it wraps a
            // button's own label, not just the row.** Resume's 220pt
            // `minWidth` plus "Details" plus a 56pt "+" square add up to
            // more than a phone's content width; an `HStack` that runs out
            // of room doesn't clip its overflow, it *shrinks the proposed
            // width it hands each child* — and a plain `Text` given less
            // width than one character wraps instead of truncating, which
            // is how "Details" turned into a very tall, apparently-empty
            // grey box (each wrapped line a sliver a pixel or two tall).
            // Phone gets Resume full-width on its own row — it's the button
            // meant to need no aiming — with Details/Favorite as a compact
            // pair underneath.
            VStack(spacing: 10) {
                resumeButton(fullWidth: true)
                HStack(spacing: 10) {
                    detailsButton(fullWidth: true)
                    favoriteButton
                }
            }
            .padding(.top, 4)
        } else {
            HStack(spacing: 16) {
                resumeButton(fullWidth: false)
                detailsButton(fullWidth: false)
                favoriteButton
            }
            .padding(.top, 4)
        }
    }
    #else
    private var actionsRow: some View {
        HStack(spacing: 16) {
            resumeButton(fullWidth: false)
            detailsButton(fullWidth: false)
            favoriteButton
        }
        .padding(.top, 4)
        // Without this, Left at Resume (leftmost) or Right at the favorite
        // square (rightmost) lets the focus engine search the whole screen
        // for the geometrically-nearest focusable view and jump there — the
        // same "selection just vanished" failure `ShowView.seasonSelector`
        // documents. Up/Down still cross normally into/out of Continue
        // Watching below and TopBar above.
        .focusSection()
    }
    #endif

    /// Resume — accent-filled with a soft glow (design 3a). `fullWidth` is
    /// the phone-only stacked layout's own row; iPad/tvOS keep the fixed
    /// `minWidth` that reads as "the widest of the three, but not the whole
    /// row" alongside Details and the favorite square.
    private func resumeButton(fullWidth: Bool) -> some View {
        Button(action: resume) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill").font(.system(size: 20))
                Text(hero.resumeLabel)
            }
            .font(Typography.button)
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .frame(minWidth: fullWidth ? nil : 220)   // ~50% wider than Details on iPad/tvOS
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            // The lit-tube treatment the detail screens' primary actions
            // wear. iPad/phone only: tvOS already has LEDRing on focus, and
            // two glows on one control fight each other.
            #if os(iOS)
            .overlay { NeonTube(shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                accent: theme.accent, intensity: 0.7) }
            #endif
            .shadow(color: theme.accent.opacity(0.45), radius: 20, y: 6)
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))
        .focused(resumeFocus, equals: .heroResume)
    }

    private func detailsButton(fullWidth: Bool) -> some View {
        Button(action: onDetails) {
            Text("Details")
                .font(Typography.button)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))
        .focused($detailsFocused)
        // The film's page zooms out of this button — see `ZoomTransition`.
        .zoomOrigin(detailsFocused)
    }

    @FocusState private var detailsFocused: Bool

    /// A heart, not a plus: it favourites the item on the server (the same
    /// `setFavorite`/`clearFavorite` the show page and the player use), and a
    /// "+" promised a list this app doesn't have. Filled in the accent while
    /// the item is a favourite; optimistic, reverted if the server refuses.
    private var favoriteButton: some View {
        let on = effectiveIsFavorite
        return Button(action: toggleFavorite) {
            Image(systemName: on ? "heart.fill" : "heart").font(.system(size: 22, weight: .semibold))
                .foregroundStyle(on ? theme.accent : Palette.text(0.85))
                .frame(width: 56, height: 56)
                .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(on ? theme.accent.opacity(0.5) : Palette.text(0.14), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))
        .accessibilityLabel(on ? "Remove from favourites" : "Add to favourites")
    }

    private var effectiveIsFavorite: Bool { favoriteOverride ?? hero.isFavorite }

    private func toggleFavorite() {
        guard let client = appState.jellyfinClient else { return }
        let newValue = !effectiveIsFavorite
        favoriteOverride = newValue
        Task {
            do {
                if newValue {
                    try await client.setFavorite(userId: appState.currentUserId, itemId: hero.id)
                } else {
                    try await client.clearFavorite(userId: appState.currentUserId, itemId: hero.id)
                }
            } catch {
                favoriteOverride = !newValue
            }
        }
    }

    private func resume() {
        Task {
            guard let request = await appState.resumeRequest(for: hero) else { return }
            appState.requestPlayback(request)
        }
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
            // Twelve redraws a second, not sixty: a 44pt pill draining over
            // 5–30 seconds moves well under a point per frame either way, and
            // `.animation` alone kept this row invalidating every frame for
            // the whole time Home was on screen — a constant tax on the same
            // GPU the crumble has to share.
            TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in
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
