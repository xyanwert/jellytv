import SwiftUI
import JellyTVKit

/// Sort chips shared by the Movies and Shows library screens. Each maps to a
/// real Jellyfin `sortBy`/`sortOrder` pair — picking a chip re-fetches the
/// library in that order rather than just re-arranging local state.
enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case az = "A–Z"
    case topRated = "Top Rated"

    var id: String { rawValue }

    var query: (sortBy: String, sortOrder: String) {
        switch self {
        case .newest: return ("DateCreated", "Descending")
        case .az: return ("SortName", "Ascending")
        case .topRated: return ("CommunityRating", "Descending")
        }
    }
}

/// The genre tail of a `MediaItem.meta` line ("Movie · Thriller" → "Thriller").
extension MediaItem {
    var genre: String {
        guard meta.contains("·") else { return "" }
        return meta.split(separator: "·").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}

/// A single filter/sort chip, shared by both library screens' filter bars.
struct LibraryFilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.font(17, .bold))
                .foregroundStyle(isOn ? .white : Palette.text(0.7))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(isOn ? theme.accent : Palette.text(0.06), in: Capsule())
                .overlay(Capsule().stroke(isOn ? .clear : Palette.text(0.14), lineWidth: 1.5))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 999))
    }
}

/// The focused item's full-screen backdrop — pinned to the top, behind the
/// rail/content, scrimmed for legibility and alpha-masked at the bottom so it
/// dissolves into the page over the first poster row. Shared by the Movies and
/// Shows library screens; sits behind the header, filters, and the selected-
/// item band so the image reads across the whole top of the screen.
struct SelectedBackdrop: View {
    let item: MediaItem

    /// How far down the screen the backdrop reaches before it has fully faded
    /// out — tall enough to cover the header, filters, the text band, and the
    /// top of the first poster row.
    private static let height: CGFloat = 900
    /// Shift the image content up so it sits a little higher than dead-center —
    /// the top of the art rides above the screen edge (roughly y = -100).
    private static let imageShift: CGFloat = -100

    /// The high-resolution wide image (real Backdrop when present), falling
    /// back to the poster if that's all the item has.
    private var imageURL: String? { item.backdropImage ?? item.image }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                heroImage(width: geo.size.width)
                    .opacity(0.9)
                // A softly-blurred copy of the image, shown only across the
                // top (behind the header/filters) and fading to the sharp
                // image below — takes the visual busyness out from under the
                // header without blurring the whole backdrop.
                heroImage(width: geo.size.width, blur: 18)
                    .opacity(0.9)
                    .mask(topBlur)
                scrims
            }
            .frame(width: geo.size.width, height: Self.height, alignment: .top)
            .mask(bottomFade)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .id(item.id)
        .transition(.opacity)
    }

    /// The backdrop rendered into a 1.5× box then clipped back to the frame —
    /// the same 50% zoom `HomeView.heroImage` applies, so the backdrop reads
    /// bigger/closer without changing its footprint. The image content is
    /// shifted up by `imageShift`; the blur (when set) is applied on the
    /// oversized box before clipping so it doesn't bleed transparent edges.
    private func heroImage(width: CGFloat, blur: CGFloat = 0) -> some View {
        backdrop
            .frame(width: width * 1.5, height: Self.height * 1.5)
            .blur(radius: blur)
            .offset(y: Self.imageShift)
            .frame(width: width, height: Self.height)
            .clipped()
    }

    @ViewBuilder private var backdrop: some View {
        if let art = imageURL, art.hasPrefix("http"), let url = URL(string: art) {
            JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
        } else if let art = imageURL {
            Image(art).resizable().scaledToFill()
        } else {
            item.artwork.gradient
        }
    }

    /// Mask for the blurred copy: opaque across the top (behind the header and
    /// filters), fading to clear so the sharp image shows below.
    private var topBlur: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.10),
                .init(color: .clear, location: 0.24),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// The darkening scrims from `HomeView.heroScrims`: a left→right scrim so
    /// the title/synopsis stay legible over the art, a top darkening so the
    /// header controls read over it, and a pre-darkening toward black at the
    /// bottom *before* the alpha mask cuts it away — that pre-darkening is what
    /// makes the image dissolve into the page rather than read as a hard cut.
    private var scrims: some View {
        Color.clear
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0.0),
                        .init(color: .black.opacity(0.35), location: 0.35),
                        .init(color: .black.opacity(0.10), location: 0.70),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.5), location: 0.0),
                        .init(color: .black.opacity(0.28), location: 0.07),
                        .init(color: .clear, location: 0.18),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.62),
                        .init(color: .black.opacity(0.5), location: 0.85),
                        .init(color: .black.opacity(0.9), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
    }

    /// Fades the bottom of the backdrop to transparent so it blends into the
    /// content below — several stops (rather than one straight ramp) so the
    /// falloff eases out gently, the same treatment as `HomeView.heroBottomFade`.
    /// The top stays fully opaque (it's at the screen edge, behind the header).
    private var bottomFade: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.68),
                .init(color: .white.opacity(0.7), location: 0.78),
                .init(color: .white.opacity(0.3), location: 0.87),
                .init(color: .white.opacity(0.08), location: 0.94),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// A single poster in a library grid (design 4a): artwork, a real ★ rating
/// badge when the server has one, and a title/year/genre caption. Shared by
/// the Movies and Shows library screens — purely presentational, driven by
/// the generic `MediaItem`.
struct LibraryPosterCard: View {
    let item: MediaItem
    var onSelect: () -> Void = {}

    private var isRemote: Bool { item.image?.hasPrefix("http") == true }
    private var dominant: Color {
        if let name = item.image, !isRemote { return DominantColor.of(name, fallback: Color(item.artwork.top)) }
        return Color(item.artwork.top)
    }

    private var caption: String {
        [item.year, item.genre].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                artwork
                LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.82)],
                               startPoint: .center, endPoint: .bottom)

                if let rating = item.rating {
                    Text("★ " + String(format: "%.1f", rating))
                        .font(Typography.font(13, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(12)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(Typography.font(19, .heavy))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.6), radius: 10, y: 2)
                    if !caption.isEmpty {
                        Text(caption)
                            .font(Mono.font(13, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.text(0.72))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.1))
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
