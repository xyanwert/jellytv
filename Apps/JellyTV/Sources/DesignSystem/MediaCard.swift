import SwiftUI
import JellyTVKit

/// A Continue Watching card (280×140): the preview image tinted with a gradient
/// of its dominant color and a solid border in that same color, plus title,
/// accent progress bar, and a circular remaining indicator.
struct ContinueCard: View {
    let item: ContinueWatchingItem
    @EnvironmentObject private var theme: Theme

    private var dominant: Color {
        if let name = item.image { return DominantColor.of(name, fallback: Color(item.artwork.top)) }
        return Color(item.artwork.top)
    }

    var body: some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    artwork

                    Text(item.title)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 2)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 26)

                    // remaining pie
                    Circle()
                        .trim(from: 0, to: 1 - item.progress)
                        .stroke(theme.accent, lineWidth: 3)
                        .background(Circle().fill(.black.opacity(0.4)))
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
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(dominant, lineWidth: 3)
                )

                Text(item.episodeLabel)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text(0.55))
                    .padding(.horizontal, 2)
            }
            .frame(width: 280)
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 14))
    }

    @ViewBuilder private var artwork: some View {
        if let name = item.image {
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
/// title; the tvOS focus outline handles the focused state.
struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        Button {} label: {
            VStack(spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    if let name = item.image {
                        Image(name).resizable().scaledToFill()
                    } else {
                        item.artwork.gradient
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
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
