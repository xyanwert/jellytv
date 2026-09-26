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
    /// Jellyfin's next-up episode — tagged so the shelf says where to start.
    var isUpNext = false
    /// Position on the shelf, for Poster Mode's alternating resting tilt.
    var shelfIndex = 0
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
            if theme.isPoster { posterLabel } else { classicLabel }
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.08))
    }

    /// Poster Mode: the still in a white frame with the episode's number set
    /// big into its corner (the key visual's numbered strip), the title in the
    /// display face, a watched episode gone grey with a check — and the card
    /// leaning until the remote straightens it.
    private var posterLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumb
                .grayscale(episode.isPlayed ? 0.9 : 0)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 5))
                .overlay(alignment: .bottomLeading) {
                    Text(episode.numberLabel)
                        .font(Display.font(64))
                        .foregroundStyle(episode.isPlayed ? Palette.text(0.7) : Color.white)
                        .shadow(color: .black.opacity(0.7), radius: 10, y: 3)
                        .padding(.leading, 14)
                        .padding(.bottom, 2)
                }
                .overlay(alignment: .topLeading) { upNextSticker }
                .overlay(alignment: .topTrailing) {
                    if episode.isPlayed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Palette.posterInk, Palette.posterTeal)
                            .padding(10)
                    }
                }
            Text(episode.title.uppercased())
                .font(Display.font(27))
                .foregroundStyle(episode.isPlayed ? Palette.text(0.55) : Palette.textPrimary)
                .lineLimit(1)
            Text(episode.overview ?? "")
                .font(Typography.font(16, .medium))
                .foregroundStyle(Palette.text(0.58))
                .lineSpacing(3)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 8) {
                Text(episode.runtime)
                if episode.isCurrent, !episode.resumeRemaining.isEmpty {
                    Text("·").foregroundStyle(Palette.text(0.3))
                    Text(episode.resumeRemaining).foregroundStyle(Color(hex: "#F0525F"))
                }
            }
            .font(Mono.font(13, .bold))
            .foregroundStyle(Palette.text(0.45))
        }
        .frame(width: Self.thumbWidth, alignment: .leading)
        .posterTilt(index: shelfIndex, degrees: 1.6)
    }

    @ViewBuilder private var upNextSticker: some View {
        if isUpNext {
            Text("UP NEXT")
                .font(Display.font(18))
                .tracking(0.8)
                .foregroundStyle(Palette.posterInk)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(hex: "#F0525F"), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .rotationEffect(.degrees(-4))
                .padding(9)
        }
    }

    private var classicLabel: some View {
            VStack(alignment: .leading, spacing: 10) {
                thumb
                    .overlay(alignment: .topLeading) {
                        if isUpNext {
                            Text("UP NEXT")
                                .font(Display.font(18))
                                .tracking(0.8)
                                .foregroundStyle(Palette.posterInk)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(hex: "#F0525F"), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .rotationEffect(.degrees(-4))
                                .padding(9)
                        }
                    }

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
