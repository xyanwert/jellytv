import SwiftUI
import JellyTVKit

/// Focusable fields on the Movie detail.
private enum MovieField: Hashable {
    case resume, play, poster(String)
}

/// The Movie detail (design 1b): a full-screen "editorial dossier" for a single
/// video — its own left spine, a title block with a spec sheet and synopsis, a
/// framed key-art panel with a floating resume card, a "More Like This" poster
/// row, and a bottom bar of cast credits + Play/Trailer/audio/subtitle/add
/// controls, over an atmospheric backdrop of the movie's art.
struct MovieDetailView: View {
    let movie: Movie
    let onDismiss: () -> Void

    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: MovieField?

    var body: some View {
        ZStack {
            DetailBackground(image: movie.keyArt, artwork: movie.artwork)
            HStack(spacing: 0) {
                DetailSpine(genreLabel: movie.genreLabel, markerTop: "FILM",
                            markerBottom: "001", onBack: onDismiss)
                content
            }
            .ignoresSafeArea()
        }
        .background(Color(hex: "#070A10").ignoresSafeArea())
        .defaultFocus($focus, .resume)
        .onExitCommand(perform: onDismiss)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); DetailTechReadout(status: "READY TO PLAY", tech: "4K · HDR · ATMOS") }

            HStack(alignment: .top, spacing: 40) {
                titleBlock
                Spacer(minLength: 0)
                KeyArtPanel(image: movie.keyArt, artwork: movie.artwork) {
                    ResumeCard(title: movie.resumeLabel, remaining: movie.resumeRemaining,
                               progress: movie.resumeProgress)
                        .focused($focus, equals: .resume)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 20)

            moreLikeThis

            Spacer(minLength: 18)

            bottomBar
        }
        .padding(.init(top: 46, leading: 64, bottom: 40, trailing: 64))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(movie.studioLine.uppercased())
                .font(Typography.font(16, .heavy)).tracking(4).foregroundStyle(theme.accent)
                .padding(.bottom, 18)

            Text(movie.title)
                .font(Typography.font(88, .black)).foregroundStyle(Palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.5).lineSpacing(-8)

            SpecSheet {
                SpecCell(label: "Rating") { SpecRating(rating: movie.rating, certification: movie.certification) }
            } topRight: {
                SpecCell(label: "Runtime") { SpecValue(movie.runtime) }
            } bottomLeft: {
                SpecCell(label: "Director") { SpecValue(movie.director) }
            } bottomRight: {
                SpecCell(label: "Year") { SpecValue(movie.year) }
            }
            .padding(.top, 26)

            Text(movie.synopsis)
                .font(Typography.font(21, .regular)).foregroundStyle(Palette.text(0.74))
                .lineSpacing(7).frame(maxWidth: 580, alignment: .leading)
                .padding(.top, 24)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var moreLikeThis: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("MORE LIKE THIS")
                    .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.5))
                Spacer()
                Text("SWIPE ▸").font(Typography.font(14, .semibold)).tracking(1).foregroundStyle(Palette.text(0.32))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(movie.moreLikeThis) { item in
                        MoreLikeThisCard(item: item).focused($focus, equals: .poster(item.id))
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 24) {
            HStack(spacing: 44) {
                credit(label: "Starring", value: movie.starring)
                credit(label: "Audio", value: movie.audioLine)
            }
            Spacer()
            controls
        }
        .padding(.top, 24)
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.1)).frame(height: 1) }
    }

    private func credit(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Typography.font(12, .heavy)).tracking(1.5).foregroundStyle(Palette.text(0.4))
            Text(value).font(Typography.font(17, .semibold)).foregroundStyle(Palette.text(0.85))
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {} label: {
                HStack(spacing: 11) {
                    Image(systemName: "play.fill").font(.system(size: 20))
                    Text("Play")
                }
                .font(Typography.font(20, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 34).padding(.vertical, 15)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 13))
            .focused($focus, equals: .play)

            DetailPill(label: "Trailer")
            DetailPill(icon: "speaker.wave.2.fill", label: "EN·5.1")
            DetailPill(icon: "captions.bubble", label: "CC·OFF")

            Button {} label: {
                Image(systemName: "plus").font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Palette.text(0.85))
                    .frame(width: 52, height: 52)
                    .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 13))
        }
    }
}
