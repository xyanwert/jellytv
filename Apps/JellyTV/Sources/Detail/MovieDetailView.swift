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
    let initialMovie: Movie
    let onDismiss: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: MovieField?
    /// Live Jellyfin + OMDb detail; replaces the initial (often sample-derived)
    /// movie once it resolves. All `movie.*` reads below go through `movie`.
    @State private var detail: Movie?

    init(movie: Movie, onDismiss: @escaping () -> Void) {
        self.initialMovie = movie
        self.onDismiss = onDismiss
    }

    private var movie: Movie { detail ?? initialMovie }

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
        .task { await loadDetail() }
        .onExitCommand(perform: onDismiss)
    }

    /// Fetches full detail (cast, ratings, tagline, director) then merges OMDb
    /// awards/RT. No-ops gracefully before the server is up (keeps the initial).
    private func loadDetail() async {
        guard var m = await appState.movieDetail(for: initialMovie.id) else { return }
        m.moreLikeThis = initialMovie.moreLikeThis   // keep the row we were opened with
        detail = m
        if let enrichment = await appState.omdbEnrichment(imdbId: m.imdbId) {
            m.externalRatings = enrichment.ratings
            m.awards = enrichment.awards
            detail = m
        }
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

            Spacer(minLength: 14)

            if !movie.cast.isEmpty {
                castRow
                Spacer(minLength: 14)
            }

            moreLikeThis

            Spacer(minLength: 14)

            bottomBar
        }
        .padding(.init(top: 46, leading: 64, bottom: 40, trailing: 64))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(movie.studioLine.uppercased())
                .font(Typography.font(16, .heavy)).tracking(4).foregroundStyle(theme.accent)
                .padding(.bottom, movie.tagline == nil ? 18 : 6)

            if let tagline = movie.tagline, !tagline.isEmpty {
                Text("“\(tagline)”")
                    .font(Typography.font(20, .medium)).italic()
                    .foregroundStyle(Palette.text(0.6))
                    .lineLimit(2)
                    .padding(.bottom, 14)
            }

            Text(movie.title)
                .font(Typography.font(88, .black)).foregroundStyle(Palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.5).lineSpacing(-8)

            HStack(spacing: 12) {
                RatingChips(imdb: imdbRating, rottenTomatoes: rottenTomatoes, metacritic: metacritic)
                if movie.awards?.academyAwardsLabel != nil { AwardsBadge(awards: movie.awards) }
            }
            .padding(.top, 20)

            SpecSheet {
                SpecCell(label: "Director") { SpecValue(movie.director.isEmpty ? "—" : movie.director) }
            } topRight: {
                SpecCell(label: "Runtime") { SpecValue(movie.runtime.isEmpty ? "—" : movie.runtime) }
            } bottomLeft: {
                SpecCell(label: "Studio") { SpecValue(movie.studios.first ?? "—") }
            } bottomRight: {
                SpecCell(label: "Year") { SpecValue(movie.year.isEmpty ? "—" : movie.year) }
            }
            .padding(.top, 22)

            Text(movie.synopsis)
                .font(Typography.font(21, .regular)).foregroundStyle(Palette.text(0.74))
                .lineSpacing(7).frame(maxWidth: 580, alignment: .leading)
                .lineLimit(3)
                .padding(.top, 20)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var imdbRating: Double? { movie.externalRatings?.imdbRating ?? movie.communityRating }
    private var rottenTomatoes: Int? { movie.externalRatings?.rottenTomatoes ?? movie.criticRating.map { Int($0) } }
    private var metacritic: Int? { movie.externalRatings?.metacritic }

    private var castRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CAST")
                .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.5))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(movie.cast) { member in
                        CastAvatar(member: member, size: 72)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
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
                if !movie.studios.isEmpty {
                    credit(label: "Studio", value: movie.studios.prefix(2).joined(separator: ", "))
                }
                if !movie.audioLine.isEmpty {
                    credit(label: "Audio", value: movie.audioLine)
                }
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
