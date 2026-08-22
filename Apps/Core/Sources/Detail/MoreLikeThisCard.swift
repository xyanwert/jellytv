import SwiftUI
import JellyTVKit

/// A portrait poster (116×172 by default — the tvOS dossier's size; the
/// iPad "More Like This" strip passes a smaller 78×116 per design 1b-iPad)
/// in the Movie detail's "More Like This" row.
struct MoreLikeThisCard: View {
    let item: MediaItem
    var size: CGSize = CGSize(width: 116, height: 172)
    // The iPad 78×116 strip (design 1b-iPad) needs a proportionally smaller
    // title treatment — at the default 15pt/11pt padding, that width wraps
    // ordinary titles mid-word.
    var titleFontSize: CGFloat = 15
    var contentPadding: CGFloat = 11

    private var isRemote: Bool { item.image?.hasPrefix("http") == true }
    private var dominant: Color {
        if let name = item.image, !isRemote { return DominantColor.of(name, fallback: Color(item.artwork.top)) }
        return Color(item.artwork.top)
    }

    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        Button {} label: {
            ZStack(alignment: .bottomLeading) {
                // Clipping a container that has a live `JellyfinAsyncImage`
                // (AsyncImage) anywhere inside it reproducibly corrupts *any*
                // sibling content in that same clipped subtree — a `Text`
                // drawn alongside the image loses ~20pt off its left edge,
                // regardless of whether the clip is `.clipShape` or
                // `.cornerRadius`, regardless of the scrim/shadow/edge-fade/
                // `.focused()` binding (all individually ruled out), and only
                // with a real remote image (never the local-asset/gradient
                // fallback). So `artwork` gets its own frame+clip in total
                // isolation, and `Text` sits in the *outer*, entirely
                // unclipped ZStack — outside that corrupted subtree.
                artwork
                    .frame(width: size.width, height: size.height)
                    .clipShape(cardShape)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .frame(width: size.width, height: size.height)
                    .clipShape(cardShape)
                Text(item.title)
                    .font(Typography.font(titleFontSize, .heavy))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    .padding(contentPadding)
            }
            .frame(width: size.width, height: size.height)
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.14))
    }

    @ViewBuilder private var artwork: some View {
        if let image = item.image, isRemote, let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
        } else if let name = item.image {
            Image(name).resizable().scaledToFill()
        } else {
            item.artwork.gradient
        }
    }
}
