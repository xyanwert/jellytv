import SwiftUI
import JellyTVKit

/// A Continue Watching card (280×140): the preview image tinted with a gradient
/// of its dominant color and a solid border in that same color, plus title,
/// accent progress bar, and a circular remaining indicator. Focus is shown by
/// growth + a dominant-color glow (see `CardFocusStyle`), not a white ring.
struct ContinueCard: View {
    let item: ContinueWatchingItem
    /// Optional focus binding so a specific card can be targeted (e.g. default focus).
    var focus: FocusState<HomeFocus?>.Binding?
    var focusTag: HomeFocus?
    /// Resumes directly into the player — no intermediate detail screen.
    var onSelect: () -> Void = {}

    @EnvironmentObject private var theme: Theme
    // Dominant color of the actual downloaded artwork (remote images only —
    // it can't be known until the pixels are in hand). Until it resolves,
    // `dominant` falls back to the artwork gradient's top color.
    @State private var remoteDominant: Color?

    init(item: ContinueWatchingItem,
         focus: FocusState<HomeFocus?>.Binding? = nil,
         focusTag: HomeFocus? = nil,
         onSelect: @escaping () -> Void = {}) {
        self.item = item
        self.focus = focus
        self.focusTag = focusTag
        self.onSelect = onSelect
    }

    private var isRemote: Bool { item.image?.hasPrefix("http") == true }
    private var dominant: Color {
        if isRemote { return remoteDominant ?? Color(item.artwork.top) }
        if let name = item.image { return DominantColor.of(name, fallback: Color(item.artwork.top)) }
        return Color(item.artwork.top)
    }

    var body: some View {
        let card = Button(action: onSelect) { label }
            .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.16))
            .task(id: item.image) {
                guard isRemote, let image = item.image, let url = URL(string: image) else { return }
                remoteDominant = await DominantColor.of(url: url, fallback: Color(item.artwork.top))
            }
        if let focus, let focusTag {
            card.focused(focus, equals: focusTag)
        } else {
            card
        }
    }

    /// 280×140 with a 6pt dominant-color border on iPad/tvOS; a phone column
    /// shrinks this to `Home.dc.html`'s 206×116 with a thinner 2pt border —
    /// a 6pt border at that size would eat a visible chunk of a much smaller
    /// card's own artwork.
    private var isPhone: Bool { DeviceClass.current == .phone }
    private var cardWidth: CGFloat { isPhone ? 206 : 280 }
    private var cardHeight: CGFloat { isPhone ? 116 : 140 }
    private var borderWidth: CGFloat { isPhone ? 2 : 6 }
    private var titleFont: Font { isPhone ? Typography.font(14, .heavy) : Typography.cardTitle }
    private var captionFont: Font { isPhone ? Typography.font(12, .semibold) : Typography.caption }

    private var label: some View {
        VStack(alignment: .leading, spacing: isPhone ? 7 : 10) {
            ZStack(alignment: .bottomLeading) {
                artwork

                Text(item.title)
                    .font(titleFont)
                    .foregroundStyle(Palette.textPrimary)
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 2)
                    .padding(.horizontal, isPhone ? 11 : 18)
                    .padding(.bottom, isPhone ? 13 : 26)

                // Remaining-time pie: iPad/tvOS only. `Home.dc.html`'s phone
                // card drops it — at 206×116 there isn't room for a second
                // indicator alongside the title without crowding it, and the
                // bottom progress bar already answers "how far in".
                if !isPhone {
                    Circle()
                        .trim(from: 0, to: 1 - item.progress)
                        .stroke(theme.accent, lineWidth: 3)
                        .background(Circle().fill(.black.opacity(0.4)))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                        .padding(.trailing, 12)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                // progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Palette.text(0.18))
                        Rectangle().fill(theme.accent).frame(width: geo.size.width * item.progress)
                    }
                }
                .frame(height: isPhone ? 4 : 6)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(dominant, lineWidth: borderWidth)
            )

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(item.episodeLabel)
                    .font(captionFont)
                    .foregroundStyle(Palette.text(0.55))
                    .lineLimit(1)
                // The real equivalent of `Home.dc.html`'s "31:04" readout —
                // `item.remaining` ("31 min") is the actual data this app
                // has; a clock-format position isn't, so this doesn't invent
                // one just to match the mockup's exact string shape.
                if isPhone, !item.remaining.isEmpty {
                    Text(item.remaining)
                        .font(Mono.font(11, .bold))
                        .foregroundStyle(Palette.text(0.32))
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(width: cardWidth)
    }

    @ViewBuilder private var artwork: some View {
        if let image = item.image, isRemote, let url = URL(string: image) {
            ZStack {
                JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
                LinearGradient(colors: [.clear, .clear, .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)   // bottom scrim for the title
            }
            .compositingGroup()
        } else if let name = item.image {
            ZStack {
                Image(name).resizable().scaledToFill()
                dominant.opacity(0.38).blendMode(.color)          // duotone tint toward the dominant color
                LinearGradient(                                    // gradient color mix + bottom scrim for the title
                    colors: [dominant.opacity(0.30), .clear, .black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .compositingGroup()
        } else {
            item.artwork.gradient
        }
    }
}

/// A Recommended poster card (168×248): preview image with a bottom scrim and
/// title; focus grows the card and glows in its dominant color. Selecting it
/// opens the Show view via `onSelect`.
struct PosterCard: View {
    let item: MediaItem
    /// Optional focus binding so a specific card can be targeted (e.g.
    /// default focus) — same pattern as `ContinueCard`.
    var focus: FocusState<HomeFocus?>.Binding?
    var focusTag: HomeFocus?
    var onSelect: () -> Void = {}

    private var isRemote: Bool { item.image?.hasPrefix("http") == true }
    private var dominant: Color {
        if let name = item.image, !isRemote { return DominantColor.of(name, fallback: Color(item.artwork.top)) }
        return Color(item.artwork.top)
    }

    /// 168×248 on iPad/tvOS; `Home.dc.html`'s phone Recommended row is
    /// noticeably smaller (104×154) — two-and-a-bit cards visible at once
    /// instead of one, which reads more like a shelf you skim than a single
    /// poster you examine.
    private var isPhone: Bool { DeviceClass.current == .phone }
    private var cardWidth: CGFloat { isPhone ? 104 : 168 }
    private var cardHeight: CGFloat { isPhone ? 154 : 248 }

    var body: some View {
        let card = Button(action: onSelect) {
            VStack(spacing: isPhone ? 6 : 10) {
                ZStack(alignment: .bottomLeading) {
                    if let image = item.image, isRemote, let url = URL(string: image) {
                        JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
                    } else if let name = item.image {
                        Image(name).resizable().scaledToFill()
                    } else {
                        item.artwork.gradient
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    Text(item.title)
                        .font(Typography.font(isPhone ? 13 : 19, .heavy))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 2)
                        .padding(isPhone ? 9 : 14)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(item.meta)
                    .font(Typography.font(isPhone ? 11 : 16, .medium))
                    .foregroundStyle(Palette.text(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: cardWidth)
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.18))
        .focused($isFocusedCard)
        // The page a poster opens zooms out of that poster — see `ZoomTransition`.
        .zoomOrigin(isFocusedCard)
        if let focus, let focusTag {
            card.focused(focus, equals: focusTag)
        } else {
            card
        }
    }

    @FocusState private var isFocusedCard: Bool
}
