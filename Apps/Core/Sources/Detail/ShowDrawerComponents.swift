#if os(iOS)
import SwiftUI
import JellyTVKit

// iPad-only chrome for the Show screen's "signal drawer" layout: a full-bleed
// unblurred backdrop, the right-hand episode drawer's rows, and the round
// shuffle-everything control that replaced the floating resume card.

/// The Show screen's backdrop on iPad: the show's own art at **full bleed and
/// deliberately unblurred** — unlike `DetailBackground` (still used by the
/// Movie dossier and by tvOS), which renders a blurred wallpaper.
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
                Palette.page.opacity(0.22)
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

    private var leftRamp: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.page, location: 0.0),
                .init(color: Palette.page.opacity(0.96), location: 0.18),
                .init(color: Palette.page.opacity(0.88), location: 0.34),
                .init(color: Palette.page.opacity(0.68), location: 0.48),
                .init(color: Palette.page.opacity(0.34), location: 0.60),
                .init(color: Palette.page.opacity(0.08), location: 0.72),
                .init(color: .clear, location: 0.84),
            ],
            startPoint: .leading, endPoint: .trailing
        )
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
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.68),
                .init(color: Palette.page.opacity(0.45), location: 0.86),
                .init(color: Palette.page.opacity(0.92), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
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

/// The Show screen's primary control: shuffle every episode of every season.
///
/// Deliberately unlabelled — it's the only large action on the screen, and
/// `AppState.shufflePlayRequest` already walks all seasons, so the button
/// needs no qualifier. Being wordless, it carries its own accessibility label.
struct ShufflePlayButton: View {
    var action: () -> Void = {}

    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "shuffle")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(theme.accent, in: Circle())
                // Same lit-tube treatment as the Movie transport bar, dialled
                // down for a small shape.
                .overlay { NeonTube(shape: Circle(), accent: theme.accent, intensity: 0.55) }
                .shadow(color: theme.accent.opacity(0.38), radius: 18, y: 10)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 38))
        .accessibilityLabel("Shuffle all episodes")
    }
}
#endif
