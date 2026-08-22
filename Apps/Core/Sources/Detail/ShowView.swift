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
    /// Live Jellyfin + OMDb detail (cast, ratings, tagline, awards, real
    /// seasons/episodes). All reads below go through `show`.
    @State private var detail: Show?
    /// The season currently being fetched (its episodes are still empty) —
    /// drives the episode strip's own loading state.
    @State private var episodesLoadingSeasonId: String?

    init(show: Show, onDismiss: @escaping () -> Void) {
        self.initialShow = show
        self.onDismiss = onDismiss
        _selectedSeason = State(initialValue: show.currentSeasonIndex)
    }

    private var show: Show { detail ?? initialShow }
    private var season: Season? {
        guard !show.seasons.isEmpty else { return nil }
        return show.seasons[min(selectedSeason, show.seasons.count - 1)]
    }
    private var currentEpisode: Episode? { show.seasons.flatMap(\.episodes).first(where: \.isCurrent) }

    private var imdbRating: Double? { show.externalRatings?.imdbRating ?? show.communityRating }
    private var rottenTomatoes: Int? { show.externalRatings?.rottenTomatoes ?? show.criticRating.map { Int($0) } }
    private var metacritic: Int? { show.externalRatings?.metacritic }

    var body: some View {
        ZStack {
            DetailBackground(image: show.keyArt, artwork: show.artwork)
            // A full-height, right-side atmospheric background on iOS — see
            // `DetailRightBackdrop`'s doc comment. tvOS keeps the season art
            // as the small inline `SeasonBackdropPanel` in `content` instead.
            #if os(iOS)
            DetailRightBackdrop(image: season?.image ?? show.keyArt, artwork: show.artwork) {
                if !show.resumeEpisodeLabel.isEmpty {
                    ResumeCard(title: show.resumeEpisodeLabel, remaining: show.resumeRemaining,
                               progress: show.resumeProgress, action: resumeCurrentEpisode)
                        .focused($focus, equals: .resume)
                }
            }
            #endif
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
        // Fetches the newly-selected season's episodes on tab switch; a no-op
        // once they're already loaded (or mid-fetch), so this is safe to fire
        // redundantly alongside `loadDetail()`'s own initial-season fetch.
        .task(id: selectedSeason) { await loadEpisodesForSelectedSeasonIfNeeded() }
        #if os(tvOS)
        .onExitCommand(perform: onDismiss)
        #endif
    }

    /// Enriches the show with live cast/ratings/tagline, fetches its real
    /// seasons (episodes still empty — fetched per selection), defaults to
    /// the latest season, loads that season's episodes, then merges OMDb
    /// awards/RT. No-ops before the server is up.
    private func loadDetail() async {
        guard let s = await appState.enrichedShow(initialShow) else { return }
        detail = s
        if let seasons = await appState.seasons(for: s.id), !seasons.isEmpty {
            detail?.seasons = seasons
            let index = detail?.currentSeasonIndex ?? 0
            selectedSeason = index
            if index < seasons.count {
                await loadEpisodes(for: seasons[index])
            }
        }
        if let enrichment = await appState.omdbEnrichment(imdbId: s.imdbId) {
            detail?.externalRatings = enrichment.ratings
            detail?.awards = enrichment.awards
        }
    }

    /// Fetches one season's episodes and merges them in place; if any episode
    /// is genuinely in progress, derives the resume card from it (real data
    /// only — never the sample's fake "S3 · E4" placeholder).
    private func loadEpisodes(for season: Season) async {
        guard let seriesId = detail?.id else { return }
        episodesLoadingSeasonId = season.id
        defer { episodesLoadingSeasonId = nil }
        guard let episodes = await appState.episodes(seriesId: seriesId, seasonId: season.id) else { return }
        guard let index = detail?.seasons.firstIndex(where: { $0.id == season.id }) else { return }
        detail?.seasons[index].episodes = episodes
        if let current = episodes.first(where: \.isCurrent) {
            detail?.resumeEpisodeLabel = "S\(season.number) · E\(current.number) — \"\(current.title)\""
            detail?.resumeProgress = current.resumeProgress
            detail?.resumeRemaining = current.resumeRemaining
        }
    }

    private func loadEpisodesForSelectedSeasonIfNeeded() async {
        guard let seasons = detail?.seasons, selectedSeason >= 0, selectedSeason < seasons.count else { return }
        let season = seasons[selectedSeason]
        guard season.episodes.isEmpty, episodesLoadingSeasonId != season.id else { return }
        await loadEpisodes(for: season)
    }

    // tvOS has a 1920pt-wide canvas to spend on an 860pt art panel *and* a
    // 740pt title column side by side, plus 38pt of top breathing room before
    // any of it. An iPad screen has neither the width (which is what
    // squeezed the spec sheet's labels/values down to "RATI…"/"CREA…"/"19…")
    // nor room to spare for that much top padding — see the matching
    // `SeasonBackdropPanel`/`ResumeCard` shrink in `DetailComponents.swift`.
    #if os(iOS)
    private static let contentTopPadding: CGFloat = 14
    private static let titleRowSpacing: CGFloat = 24
    #else
    private static let contentTopPadding: CGFloat = 38
    private static let titleRowSpacing: CGFloat = 40
    #endif

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); DetailTechReadout(status: "SIGNAL ●●●●○", tech: show.techLine) }

            HStack(alignment: .top, spacing: Self.titleRowSpacing) {
                titleBlock
                #if os(tvOS)
                Spacer(minLength: 0)
                SeasonBackdropPanel(image: season?.image ?? show.keyArt, artwork: show.artwork) {
                    // Only ever real watch progress — never the sample's fake
                    // resume text for a show that hasn't actually been started.
                    if !show.resumeEpisodeLabel.isEmpty {
                        ResumeCard(title: show.resumeEpisodeLabel, remaining: show.resumeRemaining,
                                   progress: show.resumeProgress, action: resumeCurrentEpisode)
                            .focused($focus, equals: .resume)
                    }
                }
                #endif
            }
            .padding(.top, 6)

            Spacer(minLength: 18)

            if !show.cast.isEmpty {
                castRow
                Spacer(minLength: 18)
            }

            episodeStrip

            Spacer(minLength: 18)

            bottomBar
        }
        .padding(.init(top: Self.contentTopPadding, leading: 64, bottom: 30, trailing: 64))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    // A narrower art panel frees up width for this column on iOS — wider
    // than tvOS's 740, not narrower, since that's the whole point of
    // shrinking the panel (room for the spec sheet's values and a wider
    // synopsis instead of a 3-line-tall, ~260pt-wide column of clipped text).
    // The vertical rhythm (all these `.padding(.bottom/.top, …)` values) is
    // tightened well past tvOS's — the title font comes down a step since
    // 72pt was sized against a 740pt column, not a ~650pt one —
    // `minimumScaleFactor` was already doing safety-net work tvOS never
    // needed here. `synopsisLineLimit` matches tvOS (3, not a shorter 2) now
    // that the tightened spec sheet leaves the room for a full 3 lines.
    #if os(iOS)
    private static let titleBlockMaxWidth: CGFloat = 650
    private static let studioBottomPadding: CGFloat = 8
    private static let taglineBottomPadding: CGFloat = 6
    private static let titleFontSize: CGFloat = 46
    private static let ratingsTopPadding: CGFloat = 8
    private static let specSheetTopPadding: CGFloat = 8
    private static let synopsisLineLimit: Int = 3
    private static let synopsisTopPadding: CGFloat = 10
    #else
    private static let titleBlockMaxWidth: CGFloat = 740
    private static let studioBottomPadding: CGFloat = 18
    private static let taglineBottomPadding: CGFloat = 10
    private static let titleFontSize: CGFloat = 72
    private static let ratingsTopPadding: CGFloat = 18
    private static let specSheetTopPadding: CGFloat = 20
    private static let synopsisLineLimit: Int = 3
    private static let synopsisTopPadding: CGFloat = 32
    #endif

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(show.studioLine.uppercased())
                .font(Typography.font(16, .heavy)).tracking(4).foregroundStyle(theme.accent)
                .padding(.bottom, Self.studioBottomPadding)

            if let tagline = show.tagline, !tagline.isEmpty {
                Text("“\(tagline)”")
                    .font(Typography.font(19, .medium)).italic()
                    .foregroundStyle(Palette.text(0.6))
                    .lineLimit(2)
                    .padding(.bottom, Self.taglineBottomPadding)
            }

            Text(show.title)
                .font(Typography.font(Self.titleFontSize, .black)).foregroundStyle(Palette.textPrimary)
                .lineLimit(3).minimumScaleFactor(0.5).lineSpacing(-6)

            HStack(spacing: 12) {
                RatingChips(imdb: imdbRating, rottenTomatoes: rottenTomatoes, metacritic: metacritic)
                if show.awards?.academyAwardsLabel != nil { AwardsBadge(awards: show.awards) }
            }
            .padding(.top, Self.ratingsTopPadding)

            SpecSheet {
                SpecCell(label: "Rating") { SpecRating(rating: show.rating, certification: show.certification) }
            } topRight: {
                SpecCell(label: "Run") { SpecValue(show.runSummary) }
            } bottomLeft: {
                SpecCell(label: "Created by") { SpecValue(show.createdBy) }
            } bottomRight: {
                SpecCell(label: "Years") { SpecValue(show.years) }
            }
            .padding(.top, Self.specSheetTopPadding)

            Text(show.synopsis)
                .font(Typography.font(21, .regular)).foregroundStyle(Palette.text(0.72))
                .lineSpacing(6).frame(maxWidth: 780, alignment: .leading)
                .lineLimit(Self.synopsisLineLimit)
                .padding(.top, Self.synopsisTopPadding)
        }
        .frame(maxWidth: Self.titleBlockMaxWidth, alignment: .leading)
    }

    /// Fixed width for the row-leading labels ("CAST" / season name) so both
    /// rows' labels line up and stay put — only the strip beside them scrolls.
    private static let rowLabelWidth: CGFloat = 150

    private var castRow: some View {
        HStack(alignment: .center, spacing: 18) {
            Text("CAST")
                .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.5))
                .frame(width: Self.rowLabelWidth, alignment: .leading)

            rowDivider(height: 106)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(show.cast) { member in
                        CastAvatar(member: member, size: 60)
                    }
                }
                .padding(.vertical, 4)
            }
            .horizontalEdgeFade()
        }
    }

    /// Reserves the same footprint whether it's showing real episodes or its
    /// own loading state, so the layout doesn't jump once seasons/episodes
    /// arrive — same idiom as the dossier panels' loading indicators. Same
    /// fixed-label-left / divider / scrolling-strip treatment as `castRow`.
    @ViewBuilder private var episodeStrip: some View {
        HStack(alignment: .center, spacing: 18) {
            seasonLabel
            rowDivider(height: 189)
            if season == nil || episodesLoadingSeasonId == season?.id {
                loadingEpisodesRow
            } else if let season {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(season.episodes) { ep in
                            EpisodeCard(episode: ep, action: { play(episode: ep, in: season) })
                                .focused($focus, equals: .episode(ep.id))
                        }
                    }
                    // Vertical breathing room so a focused card's
                    // `CardFocusStyle` scale-up (1.1×) stays within the
                    // ScrollView's own clip bounds instead of bleeding into
                    // the season label above or the season selector below.
                    .padding(.vertical, 16)
                }
                .horizontalEdgeFade()
                // Without this, Right at the last episode (or Left at the
                // first) lets focus escape to wherever's geometrically
                // nearest elsewhere on screen — on the simulator's keyboard
                // input that reads as focus just vanishing. Contain
                // Left/Right to the strip; Up/Down still cross normally.
                #if os(tvOS)
                .focusSection()
                #endif
            }
        }
    }

    @ViewBuilder private var seasonLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((season?.name ?? "Season").uppercased())
                .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.5))
            if let season, episodesLoadingSeasonId != season.id {
                Text("\(season.episodes.count) EPISODES")
                    .font(Typography.font(13, .semibold)).tracking(1).foregroundStyle(Palette.text(0.35))
            }
        }
        .frame(width: Self.rowLabelWidth, alignment: .leading)
    }

    private func rowDivider(height: CGFloat) -> some View {
        Rectangle().fill(Palette.text(0.18)).frame(width: 1, height: height)
    }

    private var loadingEpisodesRow: some View {
        HStack(spacing: 10) {
            ProgressView().tint(theme.accent)
            Text("Loading episodes…")
                .font(Typography.font(15, .medium)).foregroundStyle(Palette.text(0.4))
        }
        // Matches the loaded row's total height (card + the vertical
        // padding that absorbs focus scale-up) so nothing jumps when
        // episodes arrive.
        .frame(height: 244, alignment: .leading)
    }

    private var bottomBar: some View {
        HStack(spacing: 24) {
            seasonSelector
            Spacer()
            controls
        }
        .padding(.top, 18)
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.1)).frame(height: 1) }
    }

    private var seasonSelector: some View {
        // A plain HStack lets a squeezed-for-space parent compress each
        // button below its label's natural width, which wraps "S04"/"S07"
        // onto two lines while identical-length neighbors happen to survive
        // (a rounding artifact of how the compression gets distributed —
        // worse the more seasons there are). A ScrollView gives every
        // button its true intrinsic size; once there's not enough room, the
        // row scrolls instead of squeezing.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(show.seasons.enumerated()), id: \.element.id) { index, s in
                    let active = index == selectedSeason
                    Button { selectedSeason = index } label: {
                        Text(s.shortLabel)
                            .font(Typography.font(16, .bold)).tracking(1)
                            .fixedSize()
                            .foregroundStyle(active ? Palette.screen : Palette.text(0.6))
                            .padding(.horizontal, 20).padding(.vertical, 9)
                            .background(active ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 8))
                    .focused($focus, equals: .season(index))
                }
            }
            .padding(5)
        }
        .background(Palette.text(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
        // Without this, pressing Left at the row's edge lets the tvOS focus
        // engine search the whole screen for the geometrically-nearest
        // focusable view (the back button, far to the left) and jump there
        // — reading as "the season selection just disappeared." This keeps
        // Left/Right contained to S01…S10; Up/Down still cross normally.
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func resumeCurrentEpisode() {
        guard let episode = currentEpisode,
              let season = show.seasons.first(where: { s in s.episodes.contains { $0.id == episode.id } }) else { return }
        appState.requestPlayback(.single(episode.asPlayableItem(seriesTitle: show.title, seasonNumber: season.number)))
    }

    private func play(episode: Episode, in season: Season) {
        guard let request = appState.episodeQueueRequest(
            episodes: season.episodes, seriesTitle: show.title, seasonNumber: season.number, startEpisodeId: episode.id
        ) else { return }
        appState.requestPlayback(request)
    }

    private func shufflePlay() {
        Task {
            guard let request = await appState.shufflePlayRequest(seriesId: show.id, seriesTitle: show.title) else { return }
            appState.requestPlayback(request)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: shufflePlay) {
                HStack(spacing: 11) {
                    Image(systemName: "shuffle").font(.system(size: 20, weight: .bold))
                    #if os(tvOS)
                    Text("Shuffle Play")
                    #endif
                }
                .font(Typography.font(20, .heavy)).foregroundStyle(.white)
                #if os(iOS)
                .padding(.horizontal, 17).padding(.vertical, 12)
                #else
                .padding(.horizontal, 30).padding(.vertical, 12)
                #endif
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 13))

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
}
