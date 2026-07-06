import SwiftUI
import JellyTVKit

/// Horizontally-centered libraries chip row.
struct LibraryChipsRow: View {
    let libraries: [Library]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(libraries) { LibraryChip(library: $0) }
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)   // center the chip group
    }
}

/// Continue Watching row.
struct ContinueWatchingRow: View {
    let items: [ContinueWatchingItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(items) { ContinueCard(item: $0) }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
    }
}

/// Recommended for You poster row.
struct RecommendedRow: View {
    let items: [MediaItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Recommended for You")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(items) { PosterCard(item: $0) }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
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
