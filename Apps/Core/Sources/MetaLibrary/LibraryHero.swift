import SwiftUI
import JellyTVKit

#if os(tvOS)
/// What the library hero needs to know about the focused title — one flat
/// value built from a `Movie` or a `Show`, so the hero itself never has to
/// know which kind of screen it is on.
struct LibraryHeroContent: Equatable {
    let id: String
    var title: String
    var logoURL: String?
    var rating: Double?
    var certification: String?
    var years: String?
    /// "2h 9m" for a film, "3 seasons" for a series — whichever answers
    /// "how much of my evening is this".
    var length: String?
    var genre: String?
    var synopsis: String
    var cast: [String]
    /// "Directed by …" for a film; the network for a series.
    var byline: String?
    var externalRatings: ExternalRatings?
    var awards: MovieAwards?
    /// True until the selection's detail fetch has landed — the people line
    /// stays an empty slot rather than showing a spinner for a sentence.
    var isLoading: Bool

    /// **Everything the list already knows comes from the list item, not the
    /// `Movie`/`Show`.** The bare `Movie`/`Show` a library screen holds before
    /// the detail fetch lands is `SampleCatalog.movie(for:)`/`.show(for:)`,
    /// which fills every field the item lacks from the *demo template* — a
    /// show with no community rating came back as "★ 8.9", no certification
    /// as "TV-MA", no overview as the demo synopsis, no genre as "Sci-Fi
    /// Drama". The old band rendered those straight (Derry Girls wore the
    /// demo's 8.9 for as long as anyone looked). Rating, certification, year,
    /// genre and synopsis are the same server fields the list fetch already
    /// requested, so they are read from the item; the `Movie`/`Show` supplies
    /// only what the list cannot — cast, runtime, director, seasons, network,
    /// external ratings, awards — and those arrive real or not at all.
    static func movie(_ movie: Movie, item: MediaItem, isLoading: Bool) -> LibraryHeroContent {
        LibraryHeroContent(
            id: item.id,
            title: item.title,
            logoURL: item.logoImage ?? movie.logoArt,
            rating: item.rating ?? movie.communityRating,
            certification: item.certification,
            years: item.year,
            length: movie.runtime,
            genre: nonEmpty(item.genre),
            synopsis: item.synopsis ?? "",
            cast: movie.cast.map(\.name),
            byline: movie.director.isEmpty ? nil : "Directed by \(movie.director)",
            externalRatings: movie.externalRatings,
            awards: movie.awards,
            isLoading: isLoading
        )
    }

    static func show(_ show: Show, item: MediaItem, isLoading: Bool) -> LibraryHeroContent {
        LibraryHeroContent(
            id: item.id,
            title: item.title,
            logoURL: item.logoImage ?? show.logoArt,
            rating: item.rating ?? show.communityRating,
            certification: item.certification,
            // The detail's real air-year range ("2018 – 2022") once it has
            // landed; the list's single production year before that.
            years: isLoading ? item.year : nonEmpty(show.years) ?? item.year,
            length: show.seasonCount.map { "\($0) season\($0 == 1 ? "" : "s")" },
            genre: nonEmpty(item.genre),
            synopsis: item.synopsis ?? "",
            cast: show.cast.map(\.name),
            byline: show.network?.name ?? show.studios.first,
            externalRatings: show.externalRatings,
            awards: show.awards,
            isLoading: isLoading
        )
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

/// The focused title, laid over the backdrop the way a commercial TV app's
/// browse screen does it: logo art (or the title in type), one line of facts,
/// a short synopsis, and who is in it — text over the picture, no boxes.
///
/// **What it replaced, and why.** The library screens used to carry a
/// "SIGNAL DOSSIER / DECODED" panel here — a bordered card with critics and
/// audience stat boxes and a two-column grid of 42pt cast portraits, sitting
/// on top of the very art it was meant to showcase, with a "SCANNING" state
/// while it loaded and a `SELECTED // NOW IN YOUR LIBRARY` eyebrow over the
/// title. Every one of those was chrome describing chrome. A viewer on a sofa
/// wants the picture, the name, a line of facts and a line of people; Apple
/// TV, Netflix and Disney+ all landed on that same answer.
///
/// **Fixed height, bottom-aligned.** The block hugs the top of the poster grid
/// so the eye reads hero → posters in one drop, and the art above it is left
/// alone. It holds one size across loading / sparse / rich states — a title
/// with no logo, an item with no synopsis, cast not yet fetched — so the grid
/// under it never moves. The "panels don't jump" rule, applied to a paragraph.
///
/// **The logo is the title where the server has one.** `MediaItem.logoImage`
/// arrives with the list, so a logo'd title never renders in type first and
/// then swaps; the slot simply stays empty for the beat the image takes. Only
/// a title *without* logo art is set in type, and only a failed logo load
/// falls back to it.
struct LibraryHero: View {
    let content: LibraryHeroContent
    var accent: Color
    /// "Starring" for live action; "Voice cast" where the names are seiyuu.
    var castLabel: String = "Starring"

    static let height: CGFloat = 340
    /// One slot for every logo, whatever its proportions, so a wide wordmark
    /// and a square badge leave the meta line in the same place.
    private static let logoSlotHeight: CGFloat = 124
    private static let logoMaxWidth: CGFloat = 520
    private static let textWidth: CGFloat = 960

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleBlock
            metaRow
            Text(content.synopsis)
                .font(Typography.font(20, .medium))
                .foregroundStyle(Palette.text(0.74))
                .lineLimit(3)
                .lineSpacing(5)
                .frame(maxWidth: Self.textWidth, alignment: .leading)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 2)
            peopleLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height, alignment: .bottomLeading)
        .libraryContentMargin()
        .animation(.easeOut(duration: 0.25), value: content.isLoading)
        .id(content.id)
        .transition(.opacity)
    }

    // MARK: - Title

    @ViewBuilder private var titleBlock: some View {
        if let logo = content.logoURL, let url = URL(string: logo) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: Self.logoMaxWidth, maxHeight: Self.logoSlotHeight,
                               alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.65), radius: 18, y: 4)
                        .accessibilityLabel(content.title)
                case .failure:
                    titleText
                default:
                    Color.clear
                }
            }
            .frame(height: Self.logoSlotHeight, alignment: .bottomLeading)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(content.title)
            .font(Typography.font(60, .black))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .lineSpacing(-4)
            .frame(maxWidth: Self.textWidth, alignment: .leading)
            .shadow(color: .black.opacity(0.55), radius: 14, y: 2)
    }

    // MARK: - Facts

    /// Year · genre · length, then the critic scores and an Oscar badge where
    /// they exist. One line, one typeface, separators instead of boxes.
    private var metaRow: some View {
        HStack(spacing: 14) {
            if let rating = content.rating ?? content.externalRatings?.imdbRating {
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").font(.system(size: 15, weight: .bold))
                    Text(String(format: "%.1f", rating))
                }
                .fontWeight(.heavy)
                .foregroundStyle(accent)
            }
            if let cert = content.certification, !cert.isEmpty {
                Text(cert)
                    .font(Typography.font(15, .bold))
                    .foregroundStyle(Palette.text(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Palette.text(0.35), lineWidth: 1.5))
            }
            if !facts.isEmpty {
                Text(facts.joined(separator: "  ·  "))
                    .lineLimit(1)
            }
            if let rt = content.externalRatings?.rottenTomatoes {
                score(icon: "circle.fill", tint: Self.freshness(rt), text: "\(rt)%")
            }
            if let mc = content.externalRatings?.metacritic {
                score(icon: "square.fill", tint: Self.freshness(mc), text: "\(mc)")
            }
            AwardsBadge(awards: content.awards)
        }
        .font(Typography.font(19, .semibold))
        .foregroundStyle(Palette.text(0.72))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 1)
        .frame(height: 34)
    }

    private var facts: [String] {
        [content.years, content.genre, content.length]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    private func score(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
            Text(text)
        }
    }

    /// Green (fresh) ≥ 75, amber ≥ 60, else red — the usual critic-score tiers.
    private static func freshness(_ score: Int) -> Color {
        if score >= 75 { return Color(hex: "#3FBF8F") }
        if score >= 60 { return Color(hex: "#E8B44A") }
        return Color(hex: "#E8544A")
    }

    // MARK: - People

    /// "Starring A, B, C  ·  Directed by D". An empty slot while the detail is
    /// still in flight, so the block keeps its height and the grid stays put.
    @ViewBuilder private var peopleLine: some View {
        if content.isLoading || (content.cast.isEmpty && content.byline == nil) {
            Color.clear.frame(height: 24)
        } else {
            HStack(spacing: 0) {
                if !content.cast.isEmpty {
                    Text("\(castLabel)  ").foregroundStyle(Palette.text(0.45))
                    + Text(content.cast.prefix(4).joined(separator: ", ")).foregroundStyle(Palette.text(0.85))
                }
                if let byline = content.byline, !byline.isEmpty {
                    if !content.cast.isEmpty {
                        Text("   ·   ").foregroundStyle(Palette.text(0.35))
                    }
                    Text(byline).foregroundStyle(Palette.text(0.62))
                }
            }
            .font(Typography.font(18, .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Self.textWidth, alignment: .leading)
            .frame(height: 24)
            .shadow(color: .black.opacity(0.5), radius: 8, y: 1)
            .transition(.opacity)
        }
    }
}
#endif
