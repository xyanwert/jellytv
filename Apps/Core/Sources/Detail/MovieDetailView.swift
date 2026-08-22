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
                #if os(iOS)
                contentIOS
                #else
                content
                #endif
            }
            .ignoresSafeArea()
        }
        .background(Color(hex: "#070A10").ignoresSafeArea())
        .defaultFocus($focus, .resume)
        .task { await loadDetail() }
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

    // MARK: - iOS/iPad (design 1b-iPad)

    #if os(iOS)
    private static let rightColumnWidth: CGFloat = 452

    private var contentIOS: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(movie.studioLine.uppercased())
                    .font(Typography.font(13, .heavy)).tracking(3).foregroundStyle(theme.accent)
                Spacer()
                DetailTechReadout(status: "READY TO PLAY", tech: "4K · HDR · ATMOS")
            }

            // Both columns' content has a fixed natural height (a poster
            // panel, a spec sheet, a few lines of synopsis) that doesn't
            // grow with the screen, but the row between the top bar and
            // bottom bar does — a big iPad Pro 13" leaves far more of it
            // than an iPad mini. Centering the two-column block vertically
            // (an equal-height Spacer on each side, rather than one fixed
            // gap that only happened to look right on one specific device)
            // spreads that leftover evenly instead of dumping it all in one
            // spot, so the layout holds up across the whole iPad size range.
            Spacer(minLength: 12)

            HStack(alignment: .top, spacing: 40) {
                titleBlockIOS
                rightColumnIOS
            }

            Spacer(minLength: 12)

            bottomBarIOS
        }
        .padding(.init(top: 22, leading: 40, bottom: 22, trailing: 40))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var titleBlockIOS: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(movie.title)
                .font(Typography.font(58, .black)).foregroundStyle(Palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.5).lineSpacing(-4)

            SpecSheet {
                SpecCell(label: "Rating") { SpecRating(rating: movie.rating, certification: movie.certification) }
            } topRight: {
                SpecCell(label: "Runtime") { SpecValue(movie.runtime.isEmpty ? "—" : movie.runtime) }
            } bottomLeft: {
                SpecCell(label: "Director") { SpecValue(movie.director.isEmpty ? "—" : movie.director) }
            } bottomRight: {
                SpecCell(label: "Year") { SpecValue(movie.year.isEmpty ? "—" : movie.year) }
            }
            .padding(.top, 18)
            // Sitting in a VStack that's given a tall `.frame(maxHeight:
            // .infinity)` (below, so the trailing Spacer can push the
            // Starring/Audio credits toward the bottom) proposes far more
            // height than this spec sheet needs — `SpecSheet`'s divider
            // `Rectangle()` (no explicit height, so it fills whatever it's
            // given) stretches to fill it, leaving huge gaps between rows.
            // `.fixedSize` pins this view to its own ideal height regardless
            // of how much its parent offers it (see `MoreLikeThisCard`'s
            // isolated-clip fix for the same class of stretch bug).
            .fixedSize(horizontal: false, vertical: true)

            Text(movie.synopsis)
                .font(Typography.font(17, .regular)).foregroundStyle(Palette.text(0.74))
                .lineSpacing(6)
                .lineLimit(6)
                .padding(.top, 16)

            // The design pins this row to the bottom of the column via a
            // bare `flex: 1` spacer — on its 820pt-tall mockup canvas that's
            // a modest gap, but the real iPad's much taller column turns the
            // same spacer into a disproportionate void. A fixed gap instead
            // keeps the credits reading as "right after the synopsis" at
            // any device height.
            HStack(spacing: 40) {
                if !movie.starring.isEmpty {
                    credit(label: "Starring", value: movie.starring)
                }
                if !movie.audioLine.isEmpty {
                    credit(label: "Audio", value: movie.audioLine)
                }
            }
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var rightColumnIOS: some View {
        VStack(alignment: .leading, spacing: 22) {
            keyArtPanelIOS
            ResumeCard(title: movie.resumeLabel, remaining: movie.resumeRemaining,
                       progress: movie.resumeProgress, width: Self.rightColumnWidth, action: play)
                .focused($focus, equals: .resume)
            moreLikeThisIOS
        }
        .frame(width: Self.rightColumnWidth, alignment: .leading)
    }

    private var keyArtPanelIOS: some View {
        artworkIOS
            .frame(width: Self.rightColumnWidth, height: 258)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
            .overlay(alignment: .topLeading) { cornerTickIOS(topLeading: true) }
            .overlay(alignment: .bottomTrailing) { cornerTickIOS(topLeading: false) }
            .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
    }

    @ViewBuilder private var artworkIOS: some View {
        if let image = movie.keyArt, image.hasPrefix("http"), let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: movie.artwork.gradient)
        } else if let image = movie.keyArt {
            Image(image).resizable().scaledToFill()
        } else {
            movie.artwork.gradient
        }
    }

    private func cornerTickIOS(topLeading: Bool) -> some View {
        Path { p in
            if topLeading {
                p.move(to: CGPoint(x: 0, y: 22)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 22, y: 0))
            } else {
                p.move(to: CGPoint(x: 0, y: 22)); p.addLine(to: CGPoint(x: 22, y: 22)); p.addLine(to: CGPoint(x: 22, y: 0))
            }
        }
        .stroke(theme.accent, lineWidth: 2)
        .frame(width: 22, height: 22)
        .offset(x: topLeading ? -7 : 7, y: topLeading ? -7 : 7)
    }

    private var moreLikeThisIOS: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MORE LIKE THIS")
                .font(Typography.font(13, .heavy)).tracking(2).foregroundStyle(Palette.text(0.5))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 11) {
                    ForEach(movie.moreLikeThis) { item in
                        MoreLikeThisCard(item: item, size: CGSize(width: 78, height: 116),
                                          titleFontSize: 12, contentPadding: 8)
                            .focused($focus, equals: .poster(item.id))
                    }
                }
                .padding(.vertical, 6)
            }
            .horizontalEdgeFade(width: 20)
        }
    }

    private var bottomBarIOS: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 11) {
                    Image(systemName: "play.fill").font(.system(size: 18))
                    Text("Play")
                }
                .font(Typography.font(19, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 30).padding(.vertical, 13)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 14))
            .focused($focus, equals: .play)

            DetailPill(label: "Trailer")

            Spacer()

            DetailPill(icon: "speaker.wave.2.fill", label: "EN·5.1")
            DetailPill(icon: "captions.bubble", label: "CC·OFF")

            Button {} label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Palette.text(0.85))
                    .frame(width: 46, height: 46)
                    .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 14))
        }
        .padding(.top, 18)
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.1)).frame(height: 1) }
    }
    #endif
}
