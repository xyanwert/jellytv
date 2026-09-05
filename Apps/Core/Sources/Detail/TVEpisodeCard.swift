import SwiftUI
import JellyTVKit

/// One episode in the tvOS Show screen's horizontal episode shelf: a wide
/// 16:9 still (runtime chip, and — for the episode actually in progress — an
/// accent progress bar and ring), the numbered title, two lines of the
/// episode's own overview, and a remaining-time readout.
///
/// A big card in a sideways shelf rather than a row in a vertical list: that
/// is the native tvOS idiom (Netflix / Apple TV / Disney+ / Max all shelve
/// episodes), it keeps the still large enough to recognise from the couch,
/// and Left/Right through a season is the gesture a remote is built for. The
/// vertical list it replaced stretched one line of text across 1250pt, so its
/// focus ring read as an enormous empty rectangle.
struct TVEpisodeCard: View {
    let episode: Episode
    var action: () -> Void = {}

    @EnvironmentObject private var theme: Theme

    static let thumbWidth: CGFloat = 320
    static let thumbHeight: CGFloat = 180
    /// Thumb + caption block, for the shelf's loading state to reserve the
    /// same footprint so nothing reflows when a season's episodes land.
    static let height: CGFloat = 286

    private var isRemote: Bool { episode.image?.hasPrefix("http") == true }

    private var dominant: Color {
        if let name = episode.image, !isRemote { return DominantColor.of(name, fallback: Color(episode.artwork.top)) }
        return Color(episode.artwork.top)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                thumb

                Text("\(episode.number). \(episode.title)")
                    .font(Typography.font(21, .heavy))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                // Reserves both lines even when the server has no overview,
                // so cards in a row keep one baseline for the runtime below.
                Text(episode.overview ?? "")
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(Palette.text(0.58))
                    .lineSpacing(3)
                    .lineLimit(2, reservesSpace: true)

                HStack(spacing: 8) {
                    Text(episode.runtime)
                    if episode.isCurrent, !episode.resumeRemaining.isEmpty {
                        Text("·").foregroundStyle(Palette.text(0.3))
                        Text(episode.resumeRemaining).foregroundStyle(theme.accent)
                    }
                }
                .font(Mono.font(13, .bold))
                .tracking(0.5)
                .foregroundStyle(Palette.text(0.45))
            }
            .frame(width: Self.thumbWidth, alignment: .leading)
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.08))
    }

    private var thumb: some View {
        ZStack(alignment: .bottom) {
            artwork
                .frame(width: Self.thumbWidth, height: Self.thumbHeight)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.5)],
                           startPoint: .center, endPoint: .bottom)
            if episode.isCurrent, episode.resumeProgress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Palette.text(0.22))
                        Rectangle().fill(theme.accent)
                            .frame(width: geo.size.width * episode.resumeProgress)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(width: Self.thumbWidth, height: Self.thumbHeight)
        .overlay(alignment: .bottomTrailing) {
            Text(episode.runtime)
                .font(Mono.font(12, .bold))
                .foregroundStyle(Palette.text(0.9))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(.trailing, 8)
                .padding(.bottom, episode.isCurrent && episode.resumeProgress > 0 ? 12 : 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(episode.isCurrent ? theme.accent : Palette.text(0.08),
                        lineWidth: episode.isCurrent ? 2 : 1)
        )
    }

    @ViewBuilder private var artwork: some View {
        if let image = episode.image, isRemote, let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: episode.artwork.gradient)
        } else if let name = episode.image {
            Image(name).resizable().scaledToFill()
        } else {
            episode.artwork.gradient
        }
    }
}
