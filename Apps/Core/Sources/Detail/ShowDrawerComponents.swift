import SwiftUI
import JellyTVKit

// Shared iPad/tvOS chrome for the Show screen's "signal drawer" layout: a
// full-bleed unblurred backdrop and the right-hand episode drawer's rows.
// Originally iPad-only; tvOS adopted the identical composition (backdrop +
// episode drawer) rather than its earlier blurred-wallpaper-plus-inline-
// episode-strip layout — see `ShowView.padTVBody`.

/// The Show screen's backdrop: the show's own art at **full bleed and
/// deliberately unblurred** — unlike `DetailBackground` (still used by the
/// Movie dossier on both platforms), which renders a blurred wallpaper.
///
/// Legibility comes entirely from scrims, not from softening the picture: a
/// flat veil knocks the whole image back a notch, a wide left ramp holds the
/// title/spec/synopsis column, and top/bottom ramps protect the tech readout
/// and the control row. The ramp reaches well past the text column so the art
/// dissolves into the page instead of ending on a visible edge — same
/// reasoning as `DetailRightBackdrop`'s mask, one layer simpler because
/// there's no alpha cut-off to hide.
struct ShowFullBackdrop: View {
    let image: String?
    let artwork: Artwork

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.page
                art
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                Palette.page.opacity(Self.veilOpacity)
                leftRamp
                topScrim
                bottomScrim
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var art: some View {
        if let image, image.hasPrefix("http"), let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: artwork.gradient)
        } else if let image {
            Image(image).resizable().scaledToFill()
        } else {
            artwork.gradient
        }
    }

    // tvOS darkens far harder than iPad. Its hero puts a title, a metadata
    // line, three lines of synopsis and a button row on the left ~45% of a
    // 1920pt frame, then a whole episode shelf and cast row *below* the art —
    // and on a bright key art (a daylit cartoon, a white-costume still) the
    // iPad stops left white type sitting on yellow and cast names dissolving
    // into a shirt. So: the text column's whole width stays under ≥0.85, and
    // everything below ~60% of the height is effectively the page colour, so
    // the shelf sits on a real surface rather than on the picture. iPad keeps
    // its lighter treatment — its column is narrower and its drawer has its
    // own translucent backing.
    #if os(tvOS)
    private static let veilOpacity: Double = 0.30
    private static let leftStops: [Gradient.Stop] = [
        .init(color: Palette.page, location: 0.0),
        .init(color: Palette.page.opacity(0.98), location: 0.30),
        .init(color: Palette.page.opacity(0.90), location: 0.42),
        .init(color: Palette.page.opacity(0.70), location: 0.54),
        .init(color: Palette.page.opacity(0.40), location: 0.66),
        .init(color: Palette.page.opacity(0.12), location: 0.78),
        .init(color: .clear, location: 0.90),
    ]
    private static let bottomStops: [Gradient.Stop] = [
        .init(color: .clear, location: 0.36),
        .init(color: Palette.page.opacity(0.50), location: 0.50),
        .init(color: Palette.page.opacity(0.88), location: 0.64),
        .init(color: Palette.page, location: 0.76),
    ]
    #else
    private static let veilOpacity: Double = 0.22
    private static let leftStops: [Gradient.Stop] = [
        .init(color: Palette.page, location: 0.0),
        .init(color: Palette.page.opacity(0.96), location: 0.18),
        .init(color: Palette.page.opacity(0.88), location: 0.34),
        .init(color: Palette.page.opacity(0.68), location: 0.48),
        .init(color: Palette.page.opacity(0.34), location: 0.60),
        .init(color: Palette.page.opacity(0.08), location: 0.72),
        .init(color: .clear, location: 0.84),
    ]
    private static let bottomStops: [Gradient.Stop] = [
        .init(color: .clear, location: 0.68),
        .init(color: Palette.page.opacity(0.45), location: 0.86),
        .init(color: Palette.page.opacity(0.92), location: 1.0),
    ]
    #endif

    private var leftRamp: some View {
        LinearGradient(stops: Self.leftStops, startPoint: .leading, endPoint: .trailing)
    }

    private var topScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.page.opacity(0.78), location: 0.0),
                .init(color: Palette.page.opacity(0.28), location: 0.07),
                .init(color: .clear, location: 0.15),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var bottomScrim: some View {
        LinearGradient(stops: Self.bottomStops, startPoint: .top, endPoint: .bottom)
    }
}

/// One episode in the drawer's vertical list: a thumb carrying its number and
/// runtime as chips, the title beside it, and — for the episode actually in
/// progress — an accent progress bar across the thumb, its remaining time
/// under the title, and a filled play disc.
///
/// A list row rather than a card in a scrolling strip: the whole season fits
/// the drawer's height, so no title has to truncate and nothing scrolls
/// sideways to be reached.
struct DrawerEpisodeRow: View {
    let episode: Episode
    var action: () -> Void = {}

    @EnvironmentObject private var theme: Theme

    private var isRemote: Bool { episode.image?.hasPrefix("http") == true }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                thumb
                // Number and runtime live on the thumb, so the whole text
                // column is the title's — two lines of it before anything
                // truncates.
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(Typography.font(16, .bold))
                        .foregroundStyle(episode.isCurrent ? Palette.textPrimary : Palette.text(0.86))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // The in-progress episode also carries what's left of it —
                    // this row is the only place the Show screen still
                    // surfaces resume state now that the resume card is gone.
                    if episode.isCurrent, !episode.resumeRemaining.isEmpty {
                        Text(episode.resumeRemaining)
                            .font(Mono.font(11, .bold))
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                playDisc
            }
            .padding(8)
            // Without this the row's padding (and the gap left of the play
            // disc) isn't hit-testable — a plain `.clear` background gives a
            // touch nothing to land on, same trap as an invisible Button.
            .contentShape(Rectangle())
            .background(episode.isCurrent ? theme.accent.opacity(0.10) : .clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(episode.isCurrent ? theme.accent.opacity(0.45) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(FocusScaleStyle(scale: 1.02, cornerRadius: 12))
    }

    private var thumb: some View {
        ZStack(alignment: .bottom) {
            artwork
                .frame(width: 124, height: 70)
                .clipped()
            // Chips sit on the picture, so the picture has to be darkened
            // under them — same treatment as the tvOS `EpisodeCard`.
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
            if episode.isCurrent, episode.resumeProgress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Palette.text(0.18))
                        Rectangle().fill(theme.accent)
                            .frame(width: geo.size.width * episode.resumeProgress)
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(width: 124, height: 70)
        .overlay(alignment: .topLeading) { numberBadge }
        .overlay(alignment: .bottomTrailing) { runtimeLabel }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.text(0.08), lineWidth: 1)
        )
    }

    private var numberBadge: some View {
        Text("E\(episode.numberLabel)")
            .font(Mono.font(10, .bold))
            .foregroundStyle(episode.isCurrent ? .white : Palette.text(0.9))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(episode.isCurrent ? theme.accent : .black.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(5)
    }

    /// Chipped like the number badge rather than set straight on the picture:
    /// at this size the gradient alone doesn't hold it over a bright still
    /// (a daylit or animated frame swallowed "52m" whole).
    private var runtimeLabel: some View {
        Text(episode.runtime)
            .font(Mono.font(10, .bold))
            .foregroundStyle(Palette.text(0.9))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.trailing, 5)
            // Clears the resume bar on the episode that has one.
            .padding(.bottom, episode.isCurrent && episode.resumeProgress > 0 ? 7 : 5)
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

    private var playDisc: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(episode.isCurrent ? .white : Palette.text(0.8))
            .frame(width: 30, height: 30)
            .background(episode.isCurrent ? theme.accent : Palette.text(0.10), in: Circle())
            .overlay(Circle().stroke(episode.isCurrent ? .clear : Palette.text(0.16), lineWidth: 1))
    }
}
