import SwiftUI
import JellyTVKit

/// Focusable fields on the Show view.
private enum ShowField: Hashable {
    case resume
    case season(Int)
    case episode(String)
}

/// The Show view (design 2a): a full-screen "editorial dossier" for a
/// collection — its own left spine (not the main nav rail), a title block with
/// a spec sheet and synopsis, a framed key-art panel with a floating resume
/// card, an episode strip for the selected season, and a season selector +
/// control bar, over an atmospheric backdrop of the show's art.
struct ShowView: View {
    let initialShow: Show
    let onDismiss: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: ShowField?
    @State private var selectedSeason: Int
    /// Live Jellyfin + OMDb detail (cast, ratings, tagline, awards); keeps the
    /// initial show's seasons. All reads below go through `show`.
    @State private var detail: Show?

    init(show: Show, onDismiss: @escaping () -> Void) {
        self.initialShow = show
        self.onDismiss = onDismiss
        _selectedSeason = State(initialValue: show.currentSeasonIndex)
    }

    private var show: Show { detail ?? initialShow }
    private var season: Season { show.seasons[min(selectedSeason, show.seasons.count - 1)] }
    private var currentEpisode: Episode? { show.seasons.flatMap(\.episodes).first(where: \.isCurrent) }

    private var imdbRating: Double? { show.externalRatings?.imdbRating ?? show.communityRating }
    private var rottenTomatoes: Int? { show.externalRatings?.rottenTomatoes ?? show.criticRating.map { Int($0) } }
    private var metacritic: Int? { show.externalRatings?.metacritic }

    var body: some View {
        ZStack {
            DetailBackground(image: show.keyArt, artwork: show.artwork)
            HStack(spacing: 0) {
                DetailSpine(genreLabel: show.genreLabel, markerTop: "EP",
                            markerBottom: currentEpisode?.numberLabel ?? "—", onBack: onDismiss)
                content
            }
            .ignoresSafeArea()
        }
        .background(Color(hex: "#070A10").ignoresSafeArea())
        .defaultFocus($focus, .resume)
        .task { await loadDetail() }
        .onExitCommand(perform: onDismiss)
    }

    /// Enriches the show with live cast/ratings/tagline (keeps its seasons),
    /// then merges OMDb awards/RT. No-ops before the server is up.
    private func loadDetail() async {
        guard var s = await appState.enrichedShow(initialShow) else { return }
        detail = s
        if let enrichment = await appState.omdbEnrichment(imdbId: s.imdbId) {
            s.externalRatings = enrichment.ratings
            s.awards = enrichment.awards
            detail = s
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); DetailTechReadout(status: "SIGNAL ●●●●○", tech: show.techLine) }

            HStack(alignment: .top, spacing: 40) {
                titleBlock
                Spacer(minLength: 0)
                KeyArtPanel(image: show.keyArt, artwork: show.artwork) {
                    ResumeCard(title: show.resumeEpisodeLabel, remaining: show.resumeRemaining,
                               progress: show.resumeProgress)
                        .focused($focus, equals: .resume)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 14)

            if !show.cast.isEmpty {
                castRow
                Spacer(minLength: 14)
            }

            episodeStrip

            Spacer(minLength: 14)

            bottomBar
        }
        .padding(.init(top: 46, leading: 64, bottom: 40, trailing: 64))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(show.studioLine.uppercased())
                .font(Typography.font(16, .heavy)).tracking(4).foregroundStyle(theme.accent)
                .padding(.bottom, 18)

            if let tagline = show.tagline, !tagline.isEmpty {
                Text("“\(tagline)”")
                    .font(Typography.font(19, .medium)).italic()
                    .foregroundStyle(Palette.text(0.6))
                    .lineLimit(2)
                    .padding(.bottom, 10)
            }

            Text(show.title)
                .font(Typography.font(72, .black)).foregroundStyle(Palette.textPrimary)
                .lineLimit(3).minimumScaleFactor(0.5).lineSpacing(-6)

            HStack(spacing: 12) {
                RatingChips(imdb: imdbRating, rottenTomatoes: rottenTomatoes, metacritic: metacritic)
                if show.awards?.badge != nil { AwardsBadge(awards: show.awards) }
            }
            .padding(.top, 18)

            SpecSheet {
                SpecCell(label: "Run") { SpecValue(show.runSummary) }
            } topRight: {
                SpecCell(label: "Created by") { SpecValue(show.createdBy) }
            } bottomLeft: {
                SpecCell(label: "Studio") { SpecValue(show.studios.first ?? show.createdBy) }
            } bottomRight: {
                SpecCell(label: "Years") { SpecValue(show.years) }
            }
            .padding(.top, 24)

            Text(show.synopsis)
                .font(Typography.font(21, .regular)).foregroundStyle(Palette.text(0.72))
                .lineSpacing(6).frame(maxWidth: 560, alignment: .leading)
                .lineLimit(3)
                .padding(.top, 20)
        }
        .frame(maxWidth: 600, alignment: .leading)
    }

    private var castRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CAST")
                .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.5))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(show.cast) { member in
                        CastAvatar(member: member, size: 72)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var episodeStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(season.name.uppercased()) — \(season.episodes.count) EPISODES")
                    .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.5))
                Spacer()
                Text("SWIPE ▸").font(Typography.font(14, .semibold)).tracking(1).foregroundStyle(Palette.text(0.32))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(season.episodes) { ep in
                        EpisodeCard(episode: ep).focused($focus, equals: .episode(ep.id))
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 24) {
            seasonSelector
            Spacer()
            controls
        }
        .padding(.top, 24)
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.1)).frame(height: 1) }
    }

    private var seasonSelector: some View {
        HStack(spacing: 5) {
            ForEach(Array(show.seasons.enumerated()), id: \.element.id) { index, s in
                let active = index == selectedSeason
                Button { selectedSeason = index } label: {
                    Text(s.shortLabel)
                        .font(Typography.font(16, .bold)).tracking(1)
                        .foregroundStyle(active ? Palette.screen : Palette.text(0.6))
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(active ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 8))
                .focused($focus, equals: .season(index))
            }
        }
        .padding(5)
        .background(Palette.text(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {} label: {
                HStack(spacing: 11) {
                    Image(systemName: "shuffle").font(.system(size: 20, weight: .bold))
                    Text("Shuffle Play")
                }
                .font(Typography.font(20, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 30).padding(.vertical, 15)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 13))

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
