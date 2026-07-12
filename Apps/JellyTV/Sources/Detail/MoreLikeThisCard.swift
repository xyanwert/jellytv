import SwiftUI
import JellyTVKit

/// A portrait poster (128×190) in the Movie detail's "More Like This" row.
struct MoreLikeThisCard: View {
    let item: MediaItem

    private var dominant: Color {
        if let name = item.image { return DominantColor.of(name, fallback: Color(item.artwork.top)) }
        return Color(item.artwork.top)
    }

    var body: some View {
        Button {} label: {
            ZStack(alignment: .bottomLeading) {
                artwork
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                Text(item.title)
                    .font(Typography.font(15, .heavy))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    .padding(11)
            }
            .frame(width: 128, height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.14))
    }

    @ViewBuilder private var artwork: some View {
        if let name = item.image {
            Image(name).resizable().scaledToFill()
        } else {
            item.artwork.gradient
        }
    }
}
