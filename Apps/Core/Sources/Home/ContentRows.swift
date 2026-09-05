import SwiftUI
import JellyTVKit

/// Continue Watching row.
struct ContinueWatchingRow: View {
    let items: [ContinueWatchingItem]
    var firstCardFocus: FocusState<HomeFocus?>.Binding?
    var firstCardTag: HomeFocus?
    /// Resumes directly into the player — no intermediate detail screen.
    var onSelect: (ContinueWatchingItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                // .top — without this, HStack centers each card by its total
                // height (image + caption), so a card whose episode label
                // wraps to 2 lines ends up taller than its neighbors and its
                // artwork shifts upward to stay vertically centered.
                HStack(alignment: .top, spacing: DeviceClass.current == .phone ? 12 : 20) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ContinueCard(
                            item: item,
                            focus: index == 0 ? firstCardFocus : nil,
                            focusTag: index == 0 ? firstCardTag : nil,
                            onSelect: { onSelect(item) }
                        )
                    }
                }
                .padding(.horizontal, DeviceClass.current == .phone ? 20 : 56)
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
            #if os(tvOS)
            // Without this, Left/Right at the row's edge lets the focus
            // engine search the whole screen for the geometrically-nearest
            // focusable view and jump there instead of stopping at this
            // row's own edge — see `ShowView.seasonSelector`'s identical
            // reasoning.
            .focusSection()
            #endif
        }
    }
}

/// Recommended for You poster row. Selecting a poster opens its Show view.
struct RecommendedRow: View {
    let items: [MediaItem]
    /// Optional focus binding so the first poster can be targeted (e.g.
    /// default focus when there's no hero and no Continue Watching item to
    /// land on instead) — same pattern as `ContinueWatchingRow`.
    var firstCardFocus: FocusState<HomeFocus?>.Binding?
    var firstCardTag: HomeFocus?
    var onSelect: (MediaItem) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Recommended for You")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DeviceClass.current == .phone ? 12 : 20) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PosterCard(
                            item: item,
                            focus: index == 0 ? firstCardFocus : nil,
                            focusTag: index == 0 ? firstCardTag : nil,
                            onSelect: { onSelect(item) }
                        )
                    }
                }
                .padding(.horizontal, DeviceClass.current == .phone ? 20 : 56)
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }
}

/// Placeholder for the not-yet-built nav destinations.
struct ComingSoon: View {
    let title: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(Palette.text(0.5))
            Text("\(title) — coming soon")
                .font(Typography.section)
                .foregroundStyle(Palette.text(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 640)
    }
}
