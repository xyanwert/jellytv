import SwiftUI
import JellyTVKit

/// A Continue Watching card (280×140): artwork, title, accent progress bar,
/// circular remaining indicator, and an episode label beneath.
struct ContinueCard: View {
    let item: ContinueWatchingItem
    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    item.artwork.gradient
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)

                    Text(item.title)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 2)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 26)

                    // remaining pie
                    Circle()
                        .trim(from: 0, to: 1 - item.progress)
                        .stroke(theme.accent, lineWidth: 3)
                        .background(Circle().fill(.black.opacity(0.35)))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                        .padding(.trailing, 12)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                    // progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Palette.text(0.18))
                            Rectangle().fill(theme.accent).frame(width: geo.size.width * item.progress)
                        }
                    }
                    .frame(height: 6)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(width: 280, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(item.episodeLabel)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text(0.55))
                    .padding(.horizontal, 2)
            }
            .frame(width: 280)
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))
    }
}

/// A Recommended poster card (168×248): artwork, title overlay, meta beneath.
struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        Button {} label: {
            VStack(spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    item.artwork.gradient
                    LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                    Text(item.title)
                        .font(Typography.font(19, .heavy))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 2)
                        .padding(14)
                }
                .frame(width: 168, height: 248)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(item.meta)
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(Palette.text(0.55))
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 168)
        }
        .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 14))
    }
}
