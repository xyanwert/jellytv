import SwiftUI
import JellyTVKit

/// What is playing, set in the bottom-right corner — the show's logo artwork
/// where the server has one, its title in type where it doesn't.
///
/// **It used to sit under BACK, and it was in the way.** The top-left column
/// is the only place tags can live (BACK anchors it, and the right side is
/// spoken for by AirPlay and Night), so a wordmark stacked above them capped
/// how many chips could be read at a glance on the exact screen where tags
/// are edited. Moving the mark diagonally opposite hands that whole width
/// back and costs nothing: identity is the one thing on this screen nobody
/// needs to *act* on, so it belongs in the corner furthest from the controls.
///
/// **Corner, not row.** It is `.allowsHitTesting(false)` decoration, and it is
/// capped narrow enough that it cannot reach the centred `PlayerFootActions`
/// row — the foot's tiles are the widest targets in the chrome and must not
/// have to share their line.
///
/// Rendering follows `PlayerTopBar`'s old rules unchanged: a bare
/// `AsyncImage` rather than `JellyfinAsyncImage` (a logo has to *fit*, not
/// fill, and its fallback is the title in type, never a coloured rectangle),
/// no spinner and no placeholder box while it loads, and nothing at all for
/// an item whose title is meaningless (`hidesTitle` — a home video's file
/// name).
struct PlayerIdentityMark: View {
    let item: PlayableItem?

    /// Narrow on purpose — see the note above about the foot row. iPad has
    /// roughly 280pt of clear space to the right of that row at its widest;
    /// tvOS has twice as much.
    #if os(iOS)
    private static let maxWidth: CGFloat = 240
    private static let maxHeight: CGFloat = 64
    private static let titleSize: CGFloat = 26
    private static let subtitleSize: CGFloat = 15
    #else
    private static let maxWidth: CGFloat = 380
    private static let maxHeight: CGFloat = 88
    private static let titleSize: CGFloat = 34
    private static let subtitleSize: CGFloat = 20
    #endif

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            content
            subtitle
        }
        .frame(maxWidth: Self.maxWidth, alignment: .trailing)
        .allowsHitTesting(false)
    }

    /// **Which episode this is** — `S2 · E6 — "Mirror Mirror"` under the
    /// show's logo or title. This closes a gap the chrome carried for a
    /// while: `PlayableItem.subtitle` was built for every episode and shown
    /// nowhere, which was fine when every queue was one season of a show you
    /// had just chosen, and not fine once Random shuffles a whole series —
    /// the logo said *what* was playing and nothing said *where in it*.
    /// Truncated from the tail so the season/episode numbers, the part that
    /// answers the question, are what survive a long title. Nothing for a
    /// movie (no subtitle) or a home video (`hidesTitle`).
    @ViewBuilder
    private var subtitle: some View {
        if item?.hidesTitle != true, let text = item?.subtitle, !text.isEmpty {
            Text(text)
                .font(Typography.font(Self.subtitleSize, .semibold))
                .foregroundStyle(Palette.text(0.62))
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        if item?.hidesTitle == true {
            EmptyView()
        } else if let logo = item?.logoURL, let url = URL(string: logo) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: Self.maxWidth, maxHeight: Self.maxHeight,
                               alignment: .trailing)
                        .shadow(color: .black.opacity(0.7), radius: 18, y: 2)
                        .accessibilityLabel(item?.title ?? "")
                default:
                    titleText
                }
            }
            .frame(height: Self.maxHeight, alignment: .trailing)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(item?.title ?? "")
            .font(Typography.font(Self.titleSize, .black))
            .foregroundStyle(Palette.text(0.9))
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.6), radius: 16, y: 2)
    }
}
