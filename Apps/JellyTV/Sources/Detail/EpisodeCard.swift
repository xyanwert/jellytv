import SwiftUI
import JellyTVKit

/// An episode card in the Show view's season strip (236×133 thumb + title):
/// episode-number badge, runtime, a "NOW" marker + accent outline for the
/// current episode, and the dominant-color focus glow shared with other cards.
struct EpisodeCard: View {
    let episode: Episode

    @EnvironmentObject private var theme: Theme

    private var dominant: Color {
        if let name = episode.image { return DominantColor.of(name, fallback: Color(episode.artwork.top)) }
        return Color(episode.artwork.top)
    }

    var body: some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    artwork
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)

                    Text("E\(episode.numberLabel)")
                        .font(Typography.font(13, .heavy)).tracking(1)
                        .foregroundStyle(Palette.text(0.85))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)

                    Text(episode.runtime)
                        .font(Typography.font(13, .medium))
                        .foregroundStyle(Palette.text(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(12)

                    if episode.isCurrent {
                        Text("NOW")
                            .font(Typography.font(12, .heavy)).tracking(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(12)
                    }
                }
                .frame(width: 236, height: 133)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(episode.isCurrent ? theme.accent : .clear, lineWidth: 2)
                )

                Text(episode.title)
                    .font(Typography.font(18, .bold))
                    .foregroundStyle(episode.isCurrent ? Palette.textPrimary : Palette.text(0.75))
                    .lineLimit(1)
            }
            .frame(width: 236)
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.1))
    }

    @ViewBuilder private var artwork: some View {
        if let name = episode.image {
            ZStack {
                Image(name).resizable().scaledToFill()
                dominant.opacity(0.35).blendMode(.color)
            }
            .compositingGroup()
        } else {
            episode.artwork.gradient
        }
    }
}
