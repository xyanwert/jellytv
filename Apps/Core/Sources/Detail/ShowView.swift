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
            // iPad shows the key art itself — full bleed, deliberately
            // unblurred, scrims doing all the legibility work. tvOS keeps the
            // blurred atmospheric wallpaper it shares with the Movie dossier.
            #if os(iOS)
            ShowFullBackdrop(image: show.keyArt, artwork: show.artwork)
            #else
            DetailBackground(image: show.keyArt, artwork: show.artwork)
            #endif
            HStack(spacing: 0) {
                DetailSpine(genreLabel: show.genreLabel, markerTop: "EP",
                            markerBottom: currentEpisode?.numberLabel ?? "—", onBack: onDismiss)
                content
                #if os(iOS)
                episodeDrawer
                #endif
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
    // 44, not tvOS's 38 and not the old 14: `content` ignores the safe area so
    // the readout sat under the iPad status bar's battery indicator.
    private static let contentTopPadding: CGFloat = 44
    private static let titleRowSpacing: CGFloat = 24
    #else
    private static let contentTopPadding: CGFloat = 38
    private static let titleRowSpacing: CGFloat = 40
    #endif

    #if os(iOS)
    /// iPad: one column of dossier over the art — readout, title block, cast —
    /// with the control row pinned to the bottom. Seasons and episodes aren't
    /// here at all: they live in `episodeDrawer` down the right-hand edge, so
    /// nothing has to share the middle of the screen with them.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Left-aligned rather than tvOS's trailing readout: the drawer owns
            // the top-right corner now. The generous top padding keeps it clear
            // of the iPad status bar, which it used to collide with.
            DetailTechReadout(status: "SIGNAL ●●●●○", tech: show.techLine)

            titleBlock
                .padding(.top, 30)

            if !show.cast.isEmpty {
                castStrip
                    .padding(.top, 26)
            }

            Spacer(minLength: 24)

            foot
        }
        .padding(.init(top: Self.contentTopPadding, leading: 64, bottom: 34, trailing: 40))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    #else
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); DetailTechReadout(status: "SIGNAL ●●●●○", tech: show.techLine) }

            HStack(alignment: .top, spacing: Self.titleRowSpacing) {
                titleBlock
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
    #endif
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
    // Wider and taller-breathing than the pre-drawer iPad pass: the episode
    // strip and season bar left the column entirely, so the height they used
    // to eat goes back into the title, the spec rail and the synopsis.
    private static let titleBlockMaxWidth: CGFloat = 700
    private static let studioBottomPadding: CGFloat = 10
    private static let taglineBottomPadding: CGFloat = 8
    private static let titleFontSize: CGFloat = 52
    private static let ratingsTopPadding: CGFloat = 16
    private static let specSheetTopPadding: CGFloat = 18
    private static let synopsisLineLimit: Int = 4
    private static let synopsisTopPadding: CGFloat = 16
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

            #if os(iOS)
            specRail
                .padding(.top, Self.specSheetTopPadding)
            #else
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
            #endif

            Text(show.synopsis)
                .font(Typography.font(21, .regular)).foregroundStyle(Palette.text(0.72))
                .lineSpacing(6).frame(maxWidth: 780, alignment: .leading)
                .lineLimit(Self.synopsisLineLimit)
                .padding(.top, Self.synopsisTopPadding)
        }
        .frame(maxWidth: Self.titleBlockMaxWidth, alignment: .leading)
    }

    #if os(tvOS)
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
    #endif

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

    // MARK: - iPad (design 2a-drawer)

    #if os(iOS)
    private static let drawerWidth: CGFloat = 448

    /// The 2×2 `SpecSheet` folded into a single hairline row. With the drawer
    /// taking the right third of the screen there's width for four cells but
    /// not for two rows of them — and the height that buys is what lets the
    /// cast strip live in this column instead of the middle of the screen.
    /// Values are a step down from `SpecValue`'s 22pt and every cell scales
    /// its own text, so a long creator name shrinks rather than pushing the
    /// rail past the column.
    private var specRail: some View {
        HStack(spacing: 0) {
            railBox(label: "Rating", first: true) {
                HStack(spacing: 7) {
                    Text("★").foregroundStyle(theme.accent)
                    Text(show.rating)
                    Text(show.certification)
                        .font(Typography.font(14, .semibold))
                        .foregroundStyle(Palette.text(0.4))
                }
                .font(Typography.font(19, .heavy))
                .foregroundStyle(Palette.textPrimary)
            }
            railDivider
            railBox(label: "Run") { railValue(show.runSummary) }
            railDivider
            railBox(label: "Created by") { railValue(show.createdBy) }
            railDivider
            railBox(label: "Years") { railValue(show.years) }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.12)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.text(0.08)).frame(height: 1) }
    }

    private func railBox<Value: View>(label: String, first: Bool = false,
                                      @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Typography.font(12, .semibold)).tracking(2)
                .foregroundStyle(Palette.text(0.4))
            value()
        }
        .padding(.vertical, 12)
        .padding(.leading, first ? 0 : 22)
        .padding(.trailing, 22)
    }

    private func railValue(_ text: String) -> some View {
        Text(text)
            .font(Typography.font(19, .bold))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var railDivider: some View {
        Rectangle().fill(Palette.text(0.08)).frame(width: 1, height: 46)
    }

    /// Cast keeps its faces on iPad, but down here in a column wide enough
    /// that no name clips — the old strip shared a squeezed middle row with
    /// the episodes and truncated to "Kiernan Sh…".
    private var castStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("STARRING")
                .font(Mono.font(11, .bold)).tracking(2)
                .foregroundStyle(Palette.text(0.42))
            // Wide enough cells that no name clips, and scrolling rather
            // than capped, so a big cast stays reachable instead of losing
            // everyone past the sixth.
            ScrollView(.horizontal, showsIndicators: false) {
                // 106 + 10 keeps six across without scrolling on a 13-inch
                // iPad while still clearing the longest names; a larger cast
                // (or an 11-inch screen) scrolls into the trailing fade.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(show.cast) { member in
                        CastAvatar(member: member, size: 56, labelWidth: 106)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 112)
            .horizontalEdgeFade()
        }
    }

    /// The control row, as one lit bar — the same object the Movie one-sheet
    /// uses. No fill here: a series has no single progress to draw, and the
    /// episode actually in progress carries its own in the drawer.
    ///
    /// Shuffle-everything is the bar's action (`shufflePlay` already queues
    /// every episode of every season), and the settings that used to be pills
    /// ride along its right as a readout that lights only what is on.
    ///
    /// "＋ LIST" is still the empty stub it has always been on both detail
    /// screens — left in place pending a decision on what it should do.
    private var foot: some View {
        NeonTransportBar(icon: "shuffle", label: "SHUFFLE ALL",
                         sub: show.runSummary.uppercased(), progress: 0,
                         tint: theme.accent, action: shufflePlay) {
            HStack(spacing: 16) {
                NeonReadoutItem(label: "AUDIO", value: "EN 5.1", tint: theme.accent)
                NeonReadoutItem(label: "SUBS", value: "OFF", tint: theme.accent)
                NeonReadoutItem(label: "\u{FF0B} LIST", tint: theme.accent)
            }
        }
    }

    /// The right-hand episode drawer: season selector on top, then the whole
    /// selected season as a vertical list. A fixed-width, full-height panel —
    /// translucent at its leading edge so the backdrop still reads through it
    /// — so every episode is reachable without a sideways scroll, and long
    /// titles have room to be read.
    private var episodeDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("EPISODES")
                    .font(Mono.font(11, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.45))
                Spacer(minLength: 12)
                Text(show.runSummary.uppercased())
                    .font(Mono.font(11, .bold)).tracking(1.5)
                    .foregroundStyle(Palette.text(0.38))
                    .lineLimit(1)
            }

            seasonSelector
                .padding(.top, 14)

            // Same reserve-the-footprint rule as the tvOS strip: the drawer
            // holds its full height whether it's loading or listing, so
            // nothing reflows when a season's episodes land.
            if season == nil || episodesLoadingSeasonId == season?.id {
                drawerLoading
            } else if let season {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(season.episodes) { ep in
                            DrawerEpisodeRow(episode: ep, action: { play(episode: ep, in: season) })
                        }
                    }
                    .padding(.vertical, 18)
                }
            }
        }
        .padding(.init(top: Self.contentTopPadding, leading: 32, bottom: 34, trailing: 32))
        .frame(width: Self.drawerWidth)
        .background(drawerBackground)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.text(0.09)).frame(width: 1) }
    }

    private var drawerBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.screen.opacity(0.62), location: 0.0),
                .init(color: Palette.screen.opacity(0.90), location: 0.14),
                .init(color: Palette.screen.opacity(0.94), location: 1.0),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var drawerLoading: some View {
        VStack(spacing: 10) {
            ProgressView().tint(theme.accent)
            Text("Loading episodes…")
                .font(Typography.font(15, .medium))
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    private func resumeCurrentEpisode() {
        guard let episode = currentEpisode,
              let season = show.seasons.first(where: { s in s.episodes.contains { $0.id == episode.id } }) else { return }
        appState.requestPlayback(.single(episode.asPlayableItem(
            seriesTitle: show.title, seasonNumber: season.number,
            logoURL: show.logoArt, tags: show.tags)))
    }

    private func play(episode: Episode, in season: Season) {
        guard let request = appState.episodeQueueRequest(
            episodes: season.episodes, seriesTitle: show.title, seasonNumber: season.number,
            startEpisodeId: episode.id, seriesLogoURL: show.logoArt, seriesTags: show.tags
        ) else { return }
        appState.requestPlayback(request)
    }

    private func shufflePlay() {
        Task {
            guard let request = await appState.shufflePlayRequest(seriesId: show.id, seriesTitle: show.title) else { return }
            appState.requestPlayback(request)
        }
    }

    #if os(tvOS)
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
    #endif
}
