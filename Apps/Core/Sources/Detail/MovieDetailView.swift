import SwiftUI
import JellyTVKit

/// Focusable fields on the Movie detail.
private enum MovieField: Hashable {
    case resume, play, poster(String)
}

/// The Movie detail: a full-screen "editorial dossier" for a single video —
/// its own left spine, a title block with a spec sheet and synopsis, a
/// framed key-art panel with a resume card, a "More Like This" poster row,
/// and a bottom bar of Play/Trailer/audio/subtitle/add controls, over an
/// atmospheric backdrop of the movie's art.
///
/// tvOS follows design 1b (the "signal dossier" — wide two-column layout,
/// cast row, floating resume card over the key art). iOS/iPad follows the
/// dedicated design 1b-iPad instead: no cast row, a boxed (not full-bleed)
/// key art panel with the resume card stacked below it, a combined
/// Rating+certification spec cell, and a "Starring" credit line in place of
/// cast avatars — a deliberately different, purpose-built layout for the
/// narrower iPad canvas, not just a resized tvOS one.
struct MovieDetailView: View {
    let initialMovie: Movie
    let onDismiss: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: MovieField?
    /// Live Jellyfin + OMDb detail; replaces the initial (often sample-derived)
    /// movie once it resolves. All `movie.*` reads below go through `movie`.
    @State private var detail: Movie?
    #if os(iOS)
    /// The poster's dominant colour, extracted once the art is in hand — the
    /// one-sheet layout takes every accent on the screen from it.
    @State private var posterTint: Color?
    #endif

    init(movie: Movie, onDismiss: @escaping () -> Void) {
        self.initialMovie = movie
        self.onDismiss = onDismiss
    }

    private var movie: Movie { detail ?? initialMovie }

    var body: some View {
        ZStack {
            #if os(iOS)
            PosterBloom(image: posterImage, artwork: movie.artwork, tint: tint)
            #else
            DetailBackground(image: movie.keyArt, artwork: movie.artwork)
            #endif
            HStack(spacing: 0) {
                #if os(iOS)
                DetailSpine(genreLabel: movie.genreLabel, markerTop: "FILM",
                            markerBottom: "001", onBack: onDismiss, accent: tint)
                contentIOS
                #else
                DetailSpine(genreLabel: movie.genreLabel, markerTop: "FILM",
                            markerBottom: "001", onBack: onDismiss)
                content
                #endif
            }
            .ignoresSafeArea()
        }
        .background(Color(hex: "#070A10").ignoresSafeArea())
        .defaultFocus($focus, .resume)
        .task { await loadDetail() }
        #if os(iOS)
        .task(id: posterImage) { await loadPosterTint() }
        #endif
        #if os(tvOS)
        .onExitCommand(perform: onDismiss)
        #endif
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

    private func play() {
        appState.requestPlayback(.single(movie.asPlayableItem()))
    }

    private func credit(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Typography.font(12, .heavy)).tracking(1.5).foregroundStyle(Palette.text(0.4))
            Text(value).font(Typography.font(17, .semibold)).foregroundStyle(Palette.text(0.85))
        }
    }

    // MARK: - tvOS (design 1b)

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); DetailTechReadout(status: "READY TO PLAY", tech: "4K · HDR · ATMOS") }

            HStack(alignment: .top, spacing: 40) {
                titleBlock
                Spacer(minLength: 0)
                KeyArtPanel(image: movie.keyArt, artwork: movie.artwork) {
                    ResumeCard(title: movie.resumeLabel, remaining: movie.resumeRemaining,
                               progress: movie.resumeProgress, action: play)
                        .focused($focus, equals: .resume)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 8)

            if !movie.cast.isEmpty {
                castRow
                Spacer(minLength: 8)
            }

            moreLikeThis

            Spacer(minLength: 8)

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
                .font(Typography.font(78, .black)).foregroundStyle(Palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.5).lineSpacing(-6)

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
                        CastAvatar(member: member, size: 60)
                    }
                }
                .padding(.vertical, 4)
            }
            .horizontalEdgeFade()
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
            .horizontalEdgeFade()
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
        .padding(.top, 18)
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.1)).frame(height: 1) }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 11) {
                    Image(systemName: "play.fill").font(.system(size: 20))
                    Text("Play")
                }
                .font(Typography.font(20, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 34).padding(.vertical, 12)
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
                    .frame(width: 46, height: 46)
                    .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 13))
        }
    }

    // MARK: - iOS/iPad (design 1b-onesheet)

    #if os(iOS)
    /// The poster (Jellyfin `Primary`), falling back to the landscape backdrop
    /// on an item that has no poster — cropped to 2:3 rather than left blank.
    private var posterImage: String? { movie.posterArt ?? movie.keyArt }

    /// Every accent on this screen: the poster's dominant colour, or the app
    /// accent until (or unless) the extraction lands.
    private var tint: Color { posterTint ?? theme.accent }

    private func loadPosterTint() async {
        guard let image = posterImage else { return }
        if image.hasPrefix("http"), let url = URL(string: image) {
            posterTint = await DominantColor.of(url: url, fallback: theme.accent)
        } else {
            posterTint = DominantColor.of(image, fallback: theme.accent)
        }
    }

    /// The poster is the tallest thing on the screen, so it — not the text —
    /// is what has to give when the device is shorter. Everything else on the
    /// screen has a fixed height, so subtracting that from what we're given
    /// leaves the poster's; the 2:3 width follows from it.
    private func posterHeight(in size: CGSize) -> CGFloat {
        let chrome: CGFloat = movie.cast.isEmpty ? 174 : 336
        return max(300, min(645, size.height - chrome))
    }

    private var contentIOS: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                HStack { Spacer(); DetailTechReadout(status: "READY TO PLAY", tech: "4K · HDR · ATMOS") }

                // Both columns are sized explicitly. Left to negotiate it
                // themselves inside a GeometryReader, the text column takes
                // its ideal (single-line) width from the synopsis and runs
                // straight off the right edge of the screen, trailing padding
                // and all.
                let posterH = posterHeight(in: geo.size)
                let posterW = OneSheetPoster.width(for: posterH)
                let infoW = max(340, geo.size.width - 128 - posterW - 56)
                HStack(alignment: .top, spacing: 56) {
                    OneSheetPoster(image: posterImage, artwork: movie.artwork, height: posterH)
                    oneSheetInfo(height: posterH, width: infoW)
                }
                .padding(.top, 34)

                if !movie.cast.isEmpty {
                    Spacer(minLength: 20)
                    CastBand(cast: movie.cast)
                }
            }
            .padding(.init(top: 44, leading: 64, bottom: 40, trailing: 64))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The text column, held to the poster's exact height so its controls line
    /// up with the poster's bottom edge instead of floating mid-air.
    private func oneSheetInfo(height: CGFloat, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(movie.studioLine.uppercased())
                .font(Typography.font(15, .heavy)).tracking(4)
                .foregroundStyle(tint)
                .lineLimit(1)

            if let tagline = movie.tagline, !tagline.isEmpty {
                Text("\u{201C}\(tagline)\u{201D}")
                    .font(Typography.font(20, .medium)).italic()
                    .foregroundStyle(Palette.text(0.62))
                    .lineLimit(2)
                    .padding(.top, 12)
            }

            Text(movie.title)
                .font(Typography.font(88, .black)).foregroundStyle(Palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.42).lineSpacing(-12)
                .padding(.top, 8)

            HStack(spacing: 10) {
                RatingChips(imdb: imdbRating, rottenTomatoes: rottenTomatoes, metacritic: metacritic)
                if movie.awards?.academyAwardsLabel != nil { AwardsBadge(awards: movie.awards) }
            }
            .padding(.top, 24)

            HairlineRail {
                RailCell(label: "Rating", first: true) { ratingValue }
            } second: {
                RailCell(label: "Runtime") { railValue(movie.runtime) }
            } third: {
                RailCell(label: "Director") { railValue(movie.director) }
            } fourth: {
                RailCell(label: "Year") { railValue(movie.year) }
            }
            .padding(.top, 26)

            Text(movie.synopsis)
                .font(Typography.font(20, .regular)).foregroundStyle(Palette.text(0.74))
                .lineSpacing(7).lineLimit(4)
                .padding(.top, 22)

            Spacer(minLength: 24)

            actionsIOS
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private var ratingValue: some View {
        HStack(spacing: 8) {
            Text("\u{2605}").foregroundStyle(tint)
            Text(movie.rating.isEmpty ? "\u{2014}" : movie.rating)
            if !movie.certification.isEmpty {
                Text(movie.certification)
                    .font(Typography.font(15, .semibold))
                    .foregroundStyle(Palette.text(0.42))
            }
        }
        .font(Typography.font(20, .heavy))
        .foregroundStyle(Palette.textPrimary)
    }

    private func railValue(_ text: String) -> some View {
        Text(text.isEmpty ? "\u{2014}" : text)
            .font(Typography.font(20, .bold))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// "RESUME · 1:40:12" once there is progress to resume from, otherwise a
    /// plain Play — the remaining time comes off the item, never invented.
    private var playLabel: String {
        guard movie.resumeProgress > 0 else { return "PLAY" }
        let time = movie.resumeRemaining.split(separator: " ").first.map(String.init) ?? ""
        return time.isEmpty ? "RESUME" : "RESUME \u{00B7} \(time)"
    }

    private var actionsIOS: some View {
        HStack(spacing: 12) {
            OneSheetPlayButton(label: playLabel, progress: movie.resumeProgress,
                               tint: tint, action: play)
                .focused($focus, equals: .play)

            DetailPill(label: "Trailer", compact: true)
            DetailPill(icon: "speaker.wave.2.fill", label: "EN\u{00B7}5.1", compact: true)
            DetailPill(icon: "captions.bubble", label: "CC\u{00B7}OFF", compact: true)

            // Still the empty stub it has always been on both detail screens —
            // left in place pending a decision on what it should do.
            Button {} label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Palette.text(0.85))
                    .frame(width: 46, height: 46)
                    .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 14))

            Spacer(minLength: 0)
        }
    }
    #endif
}
