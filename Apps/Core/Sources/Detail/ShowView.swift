import SwiftUI
import JellyTVKit

/// Focusable fields on the Show view.
private enum ShowField: Hashable {
    /// tvOS's hero Resume/Play button — the default-focus target there.
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
    /// Swallows a second SHUFFLE ALL press while the first is still
    /// building its queue — see `shufflePlay`.
    @State private var shuffleInFlight = false
    /// iPad only. One-shot guard, same reasoning as `HomeView`'s:
    /// `.defaultFocus` only gets one resolution attempt, and `initialShow`
    /// starts with no seasons (real detail arrives async via `loadDetail()`),
    /// so the very first attempt can fire before `.season(selectedSeason)`
    /// exists to focus. Never re-armed after the first real hand-off, so a
    /// later season/episode refresh can't yank focus back once the user has
    /// moved on. tvOS doesn't need this — its default (`.resume`) is always
    /// present from the first frame.
    @State private var hasEstablishedFocus = false
    /// Optimistic favorite override so the FAVOURITE/"+" action's icon flips
    /// immediately — `show.isFavorite` only updates once `loadDetail()`
    /// re-fetches, which this doesn't wait for. `nil` defers to the real
    /// value; reverted on a failed write. Shared by iPhone's quick action and
    /// tvOS's hero icon button.
    @State private var favoriteOverride: Bool?
    #if os(iOS)
    /// Phone only — which of the EPISODES/DETAILS/CAST tabs is showing.
    @State private var phoneTab: PhoneShowTab = .episodes
    #endif

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

    /// tvOS defaults to the hero's Resume/Play button — it's always present
    /// once the hero renders (its label/enabled-state degrade gracefully
    /// before `primaryEpisode` resolves), so unlike iPad's `.season` default
    /// it needs no corrective re-assertion once real data lands. iPad keeps
    /// defaulting into its episode drawer.
    private var initialFocus: ShowField {
        #if os(tvOS)
        .resume
        #else
        .season(selectedSeason)
        #endif
    }

    var body: some View {
        Group {
            #if os(iOS)
            if DeviceClass.current == .phone {
                phoneBody
            } else {
                padTVBody
            }
            #else
            tvBody
            #endif
        }
        .background(Color(hex: "#070A10").ignoresSafeArea())
        .defaultFocus($focus, initialFocus)
        .task { await loadDetail() }
        // Fetches the newly-selected season's episodes on tab switch; a no-op
        // once they're already loaded (or mid-fetch), so this is safe to fire
        // redundantly alongside `loadDetail()`'s own initial-season fetch.
        .task(id: selectedSeason) { await loadEpisodesForSelectedSeasonIfNeeded() }
        #if os(iOS)
        .onChange(of: focus) { _, newValue in
            if newValue != nil { hasEstablishedFocus = true }
        }
        // Corrective re-assertion once real seasons land — `.defaultFocus`'s
        // one shot may already have come and gone against an empty
        // `initialShow.seasons`. See `hasEstablishedFocus`'s doc comment.
        .onChange(of: show.seasons.isEmpty) { _, isEmpty in
            guard !isEmpty, !hasEstablishedFocus else { return }
            hasEstablishedFocus = true
            focus = .season(selectedSeason)
        }
        #endif
        #if os(tvOS)
        .onExitCommand(perform: onDismiss)
        #endif
    }

    #if os(iOS)
    /// iPad: the existing full-screen "editorial dossier" — its own left
    /// spine, the dossier/drawer split, over a full-bleed backdrop: the
    /// show's own key art, unblurred, and every episode reachable down the
    /// right-hand drawer. tvOS dropped this composition for `tvBody` (a
    /// hero-plus-browse-band layout closer to Netflix/Disney+/Apple TV/HBO
    /// Max's own show pages) — see `tvBody`'s doc comment for why.
    private var padTVBody: some View {
        ZStack {
            ShowFullBackdrop(image: show.keyArt, artwork: show.artwork)
            HStack(spacing: 0) {
                DetailSpine(genreLabel: show.genreLabel, markerTop: "EP",
                            markerBottom: currentEpisode?.numberLabel ?? "—", onBack: onDismiss)
                content
                episodeDrawer
            }
            .ignoresSafeArea()
        }
    }
    #endif

    // MARK: - Phone (`Detail.dc.html`)
    //
    // Genuinely different from the iPad dossier/drawer, not a shrink of it:
    // one vertically-scrolling column instead of a fixed, non-scrolling
    // full-screen layout. Key art is a *contained block that ends* (296pt),
    // not a banner the whole page lives inside — everything below it sits on
    // the plain page background, matching `Detail.dc.html`. Season/episode
    // browsing moves into an EPISODES/DETAILS/CAST tab strip instead of the
    // iPad drawer, which needs a whole screen edge to itself.
    #if os(iOS)

    private var phoneBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                PhoneShowKeyArt(image: show.keyArt, artwork: show.artwork, onClose: onDismiss)
                phoneIdentity
                    .padding(.top, 18)
                    .padding(.horizontal, 20)

                if show.resumeProgress > 0, !show.resumeEpisodeLabel.isEmpty {
                    phoneProgressRow
                        .padding(.top, 22)
                        .padding(.horizontal, 20)
                }

                phoneContinueButton
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                phoneQuickActions
                    .padding(.top, 18)

                if let (episode, _) = primaryEpisode {
                    phoneEpisodeHeadline(episode)
                        .padding(.top, 22)
                        .padding(.horizontal, 20)
                }

                phoneTabBar
                    .padding(.top, 26)
                    .padding(.horizontal, 20)

                phoneTabContent
                    .padding(.top, 18)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 50)
            .phoneTabBarClearance()
        }
        .background(Color(hex: "#07080C").ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
    }

    private var phoneIdentity: some View {
        VStack(spacing: 11) {
            Text(show.title)
                .font(Typography.font(32, .black))
                .tracking(-1)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Palette.textPrimary)
                .shadow(color: .black.opacity(0.55), radius: 20)
                .frame(width: 350)

            HStack(spacing: 7) {
                ForEach(phoneSpecChips, id: \.self) { chip in
                    Text(chip)
                        .font(Mono.font(10, .bold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.text(0.78))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Palette.text(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Palette.text(0.13), lineWidth: 1))
                }
                if !show.rating.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 9))
                        Text(show.rating)
                    }
                    .font(Mono.font(10, .bold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Palette.text(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }

            if !phoneMetaLine.isEmpty {
                Text(phoneMetaLine)
                    .font(Typography.font(13, .semibold))
                    .foregroundStyle(Palette.text(0.55))
            }
        }
    }

    /// `show.certification` + `show.techLine`'s "·"-separated pieces
    /// ("4K · HDR · ATMOS" → 3 chips) — real fields, just split apart to
    /// match `Detail.dc.html`'s row of separate spec chips instead of one
    /// run-together string.
    private var phoneSpecChips: [String] {
        var chips: [String] = []
        if !show.certification.isEmpty { chips.append(show.certification) }
        chips.append(contentsOf: show.techLine.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        return chips
    }

    /// "2023 – 2026 · 3 Seasons · Sci-Fi Drama" — years, a real season
    /// count, and the genre tail of `genreLabel` ("TV Shows / Sci-Fi Drama").
    private var phoneMetaLine: String {
        var parts: [String] = []
        if !show.years.isEmpty { parts.append(show.years) }
        let seasonCount = show.seasonCount ?? show.seasons.count
        if seasonCount > 0 { parts.append("\(seasonCount) Season\(seasonCount == 1 ? "" : "s")") }
        let genreTail = show.genreLabel.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !genreTail.isEmpty { parts.append(genreTail) }
        return parts.joined(separator: " · ")
    }

    /// Only shown when there's a genuine in-progress episode — never a fake
    /// "0%" bar for a show nobody has started (see `phoneBody`'s gate).
    private var phoneProgressRow: some View {
        HStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.text(0.16))
                    Capsule().fill(theme.accent).frame(width: geo.size.width * show.resumeProgress)
                }
            }
            .frame(height: 4)
            Text(show.resumeRemaining.uppercased())
                .font(Mono.font(11, .bold))
                .foregroundStyle(Palette.text(0.55))
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// One full-width pill — the single primary action, impossible to miss.
    /// Labels itself CONTINUE against a real in-progress episode, PLAY
    /// against a fresh show with nothing started.
    private var phoneContinueButton: some View {
        let hasProgress = currentEpisode != nil
        let label = primaryEpisode.map { "\(hasProgress ? "CONTINUE" : "PLAY") S\($1.number) · E\($0.number)" } ?? "PLAY"
        return Button {
            if let (episode, season) = primaryEpisode { play(episode: episode, in: season) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                Text(label).font(Typography.font(16, .heavy)).tracking(0.3)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(theme.accent, in: Capsule())
            .shadow(color: theme.accent.opacity(0.42), radius: 20, y: 8)
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1).blendMode(.overlay))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.02, cornerRadius: 999))
        .disabled(primaryEpisode == nil)
    }

    /// RESTART / SHUFFLE / FAVOURITE as icon-above-caption — none of them
    /// competes with CONTINUE for the thumb's attention.
    private var phoneQuickActions: some View {
        HStack(spacing: 54) {
            phoneQuickAction(icon: "backward.end.fill", caption: "RESTART", action: restartPrimaryEpisode)
                .disabled(primaryEpisode == nil)
            phoneQuickAction(icon: "shuffle", caption: "SHUFFLE", action: shufflePlay)
            phoneQuickAction(icon: effectiveIsFavorite ? "heart.fill" : "heart",
                              caption: "FAVOURITE", tint: effectiveIsFavorite ? theme.accent : .white,
                              action: toggleFavorite)
        }
    }

    private func phoneQuickAction(icon: String, caption: String, tint: Color = .white,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                Text(caption).font(Mono.font(10, .bold)).tracking(1.2).foregroundStyle(Palette.text(0.6))
            }
        }
        .buttonStyle(.plain)
    }

    /// Left-aligned from here down — "this is reading, not choosing"
    /// (`Detail.dc.html`). Real per-episode overview when the server has
    /// one; otherwise just the title line, never a stand-in synopsis.
    private func phoneEpisodeHeadline(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("S\(season?.number ?? 0) · E\(episode.number) — \(episode.title)")
                .font(Typography.font(16, .heavy))
                .foregroundStyle(Palette.textPrimary)
            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(Typography.font(14, .medium))
                    .foregroundStyle(Palette.text(0.6))
                    .lineSpacing(3)
                    .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phoneTabBar: some View {
        HStack(spacing: 26) {
            ForEach(PhoneShowTab.allCases, id: \.self) { tab in
                Button { phoneTab = tab } label: {
                    Text(tab.label)
                        .font(Mono.font(12, .bold))
                        .tracking(1.6)
                        .foregroundStyle(phoneTab == tab ? Palette.textPrimary : Palette.text(0.42))
                        .padding(.bottom, 11)
                        // Each tab draws its own underline directly beneath
                        // its own label — as wide as that label's real
                        // rendered width, so it moves and resizes correctly
                        // to DETAILS/CAST instead of only ever fitting under
                        // EPISODES (the widest, default tab).
                        .overlay(alignment: .bottom) {
                            Capsule().fill(theme.accent).frame(height: 2)
                                .opacity(phoneTab == tab ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottomLeading) {
            Rectangle().fill(Palette.text(0.1)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var phoneTabContent: some View {
        switch phoneTab {
        case .episodes: phoneEpisodesTab
        case .details: phoneDetailsTab
        case .cast: phoneCastTab
        }
    }

    @ViewBuilder
    private var phoneEpisodesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            seasonSelector
            if season == nil || episodesLoadingSeasonId == season?.id {
                HStack(spacing: 10) {
                    ProgressView().tint(theme.accent)
                    Text("Loading episodes…")
                        .font(Typography.font(15, .medium)).foregroundStyle(Palette.text(0.4))
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else if let season {
                LazyVStack(spacing: 8) {
                    ForEach(season.episodes) { ep in
                        DrawerEpisodeRow(episode: ep, action: { play(episode: ep, in: season) })
                    }
                }
            }
        }
    }

    /// The 2×2 spec sheet, same real fields as the iPad rail, stacked full
    /// width instead of squeezed into a narrow drawer column.
    private var phoneDetailsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            phoneDetailRow(label: "Rating") {
                HStack(spacing: 6) {
                    Text("★").foregroundStyle(theme.accent)
                    Text(show.rating)
                    Text(show.certification).font(Typography.font(13, .semibold)).foregroundStyle(Palette.text(0.4))
                }
                .font(Typography.font(17, .heavy)).foregroundStyle(Palette.textPrimary)
            }
            phoneDetailRow(label: "Run") { phoneDetailValue(show.runSummary) }
            phoneDetailRow(label: "Created by") { phoneDetailValue(show.createdBy) }
            phoneDetailRow(label: "Years") { phoneDetailValue(show.years) }
            if !show.synopsis.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SYNOPSIS").font(Mono.font(11, .bold)).tracking(1.5).foregroundStyle(Palette.text(0.42))
                    Text(show.synopsis)
                        .font(Typography.font(15, .regular))
                        .foregroundStyle(Palette.text(0.72))
                        .lineSpacing(5)
                }
                .padding(.top, 4)
            }
        }
    }

    private func phoneDetailRow<Value: View>(label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(label.uppercased()).font(Mono.font(12, .semibold)).tracking(1).foregroundStyle(Palette.text(0.42))
            Spacer(minLength: 12)
            value()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.text(0.08)).frame(height: 1).padding(.top, 22) }
    }

    private func phoneDetailValue(_ text: String) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(Typography.font(17, .bold))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private var phoneCastTab: some View {
        if show.cast.isEmpty {
            Text("No cast information yet.")
                .font(Typography.font(15, .medium))
                .foregroundStyle(Palette.text(0.4))
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                ForEach(show.cast) { member in
                    CastAvatar(member: member, size: 56, labelWidth: 96)
                }
            }
        }
    }
    #endif

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

    #if os(iOS)
    // 44, not the old 14: `content` ignores the safe area so the readout sat
    // under the iPad status bar's battery indicator.
    private static let contentTopPadding: CGFloat = 44

    /// iPad: one column of dossier over the art — title block, cast — with
    /// the control row pinned to the bottom. Seasons and episodes aren't here
    /// at all: they live in `episodeDrawer` down the right-hand edge, so
    /// nothing has to share the middle of the screen with them. tvOS dropped
    /// this whole composition for `tvBody`.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock

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

            specRail
                .padding(.top, Self.specSheetTopPadding)

            Text(show.synopsis)
                .font(Typography.font(21, .regular)).foregroundStyle(Palette.text(0.72))
                .lineSpacing(6).frame(maxWidth: 780, alignment: .leading)
                .lineLimit(Self.synopsisLineLimit)
                .padding(.top, Self.synopsisTopPadding)
        }
        .frame(maxWidth: Self.titleBlockMaxWidth, alignment: .leading)
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
    #endif

    // MARK: - Episode drawer (design 2a-drawer) — iPad only now
    //
    // tvOS matched this composition for a while (episodes down a right-hand
    // drawer with the season selector at its top) but that's an iPad/tablet
    // pattern, not how real tvOS streaming apps lay out a show page — see
    // `tvBody`'s doc comment. tvOS now uses `tvEpisodeList` instead, reusing
    // the same `DrawerEpisodeRow`.
    #if os(iOS)
    private static let drawerWidth: CGFloat = 448

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

            // Same reserve-the-footprint rule as `tvEpisodeList`: the drawer
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

    /// **Playing an episode queues the whole show from there** — the rest of
    /// this season in order, then every season after it, in order.
    ///
    /// It used to queue the selected season only, which made the last episode
    /// of a season the end of the evening even with nine seasons left. The
    /// full run costs one lean request (226 episodes measured at 328 KB /
    /// ~150 ms), so this waits for it rather than opening the player on a
    /// short queue and quietly extending it later.
    ///
    /// If that request doesn't answer, the season we already have on screen
    /// still goes behind the episode — playing something beats playing
    /// nothing, and the season queue is exactly what this did before.
    private func play(episode: Episode, in season: Season) {
        Task {
            if let request = await appState.seriesQueueRequest(
                seriesId: show.id, seriesTitle: show.title, startEpisodeId: episode.id,
                logoURL: show.logoArt, tags: show.tags
            ) {
                appState.requestPlayback(request)
                return
            }
            guard let fallback = appState.episodeQueueRequest(
                episodes: season.episodes, seriesTitle: show.title, seasonNumber: season.number,
                startEpisodeId: episode.id, seriesLogoURL: show.logoArt, seriesTags: show.tags
            ) else { return }
            appState.requestPlayback(fallback)
        }
    }

    /// Every episode of every season, in a fresh random order each press —
    /// the order comes from the server, which re-rolls per request.
    ///
    /// The in-flight guard is not politeness: a second press mid-build would
    /// throw the first queue away and hand `.fullScreenCover` a different
    /// identity, tearing down a player that was already coming up.
    private func shufflePlay() {
        guard !shuffleInFlight else { return }
        shuffleInFlight = true
        Task {
            defer { shuffleInFlight = false }
            guard let request = await appState.shufflePlayRequest(
                seriesId: show.id, seriesTitle: show.title) else { return }
            appState.requestPlayback(request)
        }
    }

    /// The episode CONTINUE/RESTART/Resume act on: whichever one is actually
    /// in progress, or the selected season's first episode when nothing is —
    /// a fresh show gets "PLAY S1 · E1", not a dead button. Shared by
    /// iPhone's quick actions and tvOS's hero Resume button.
    private var primaryEpisode: (episode: Episode, season: Season)? {
        if let current = currentEpisode,
           let s = show.seasons.first(where: { se in se.episodes.contains { $0.id == current.id } }) {
            return (current, s)
        }
        guard let season, let first = season.episodes.first else { return nil }
        return (first, season)
    }

    #if os(iOS)
    /// **RESTART — a real "from zero," not a relabeled resume.** Builds the
    /// same queue `play(episode:in:)` would, then zeroes the *starting*
    /// item's `resumePositionTicks` before handing it to the player, so
    /// playback genuinely begins at 0 instead of wherever Jellyfin left off.
    /// Nothing in `JellyTVKit`'s queue builders takes a "start from zero"
    /// flag, so this reconstructs just that one `PlayableItem` client-side
    /// rather than growing that API for a single call site.
    private func restartPrimaryEpisode() {
        guard let (episode, season) = primaryEpisode else { return }
        Task {
            let request = await appState.seriesQueueRequest(
                seriesId: show.id, seriesTitle: show.title, startEpisodeId: episode.id,
                logoURL: show.logoArt, tags: show.tags
            ) ?? appState.episodeQueueRequest(
                episodes: season.episodes, seriesTitle: show.title, seasonNumber: season.number,
                startEpisodeId: episode.id, seriesLogoURL: show.logoArt, seriesTags: show.tags
            )
            guard let request, request.startIndex < request.items.count else { return }
            var items = request.items
            let starting = items[request.startIndex]
            items[request.startIndex] = PlayableItem(
                id: starting.id, seriesId: starting.seriesId, title: starting.title,
                subtitle: starting.subtitle, runtimeTicks: starting.runtimeTicks,
                resumePositionTicks: nil, isFavorite: starting.isFavorite,
                imageURL: starting.imageURL, logoURL: starting.logoURL,
                tags: starting.tags, hidesTitle: starting.hidesTitle
            )
            appState.requestPlayback(PlaybackRequest(items: items, startIndex: request.startIndex,
                                                      shuffled: request.shuffled))
        }
    }
    #endif

    private var effectiveIsFavorite: Bool { favoriteOverride ?? show.isFavorite }

    /// Real Jellyfin endpoint (`setFavorite`/`clearFavorite`) — same call
    /// `PlayerEngine.toggleFavorite()` makes for the in-player opinion row,
    /// here for the series as a whole. Optimistic, reverted on failure.
    /// Shared by iPhone's FAVOURITE quick action and tvOS's hero "+"/heart
    /// icon button — the tvOS control row's own "+" used to be a permanent
    /// empty stub ("pending a decision on what it should do"); this is that
    /// decision, since the real behavior already existed for iPhone.
    private func toggleFavorite() {
        guard let client = appState.jellyfinClient else { return }
        let newValue = !effectiveIsFavorite
        favoriteOverride = newValue
        Task {
            do {
                if newValue {
                    try await client.setFavorite(userId: appState.currentUserId, itemId: show.id)
                } else {
                    try await client.clearFavorite(userId: appState.currentUserId, itemId: show.id)
                }
            } catch {
                favoriteOverride = !newValue
            }
        }
    }

    #if os(tvOS)

    // MARK: - tvOS (the show page as Netflix / Apple TV / Disney+ / Max shelve it)
    //
    // Two earlier tvOS layouts are gone from here. The dossier/drawer copied
    // iPad — episodes down a narrow full-height right-hand column, a tablet
    // pattern — and had no Play/Resume button at all. The first hero pass
    // fixed that but stretched one line of text per episode across a 1250pt
    // *vertical* list (a focus ring the size of a billboard), floated a lone
    // back button in ~200pt of nothing above the title, and let bright key
    // art (a daylit cartoon) fight white type and swallow the cast names.
    //
    // Now: a 490pt hero whose text column sits on a near-solid left ramp
    // (`ShowFullBackdrop`'s tvOS stops), the show's own *logo* as its title
    // when Jellyfin has one, one metadata line, three lines of synopsis and
    // the action row — no back button (Menu is the tvOS convention, and the
    // spine-less hero has nothing for one to anchor to). Below, on what is by
    // then the page colour: the season selector, a *horizontal shelf* of big
    // episode cards (`TVEpisodeCard` — the native tvOS idiom, and Left/Right
    // through a season is what a remote is for), and a cast row.
    private static let heroHeight: CGFloat = 490

    /// Flips on appear; the hero and the shelves enter in order off it.
    @State private var entered = false

    private var tvBody: some View {
        ZStack(alignment: .topLeading) {
            ShowFullBackdrop(image: show.keyArt, artwork: show.artwork)
            VStack(alignment: .leading, spacing: 0) {
                tvHero
                    .frame(height: Self.heroHeight, alignment: .bottomLeading)
                    .entrance(entered, delay: 0.08, rise: 28)
                tvShelves
                    .entrance(entered, delay: 0.24)
            }
        }
        .ignoresSafeArea()
        .onAppear { entered = true }
    }

    private var tvHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)

            // The real studio when the server has one — never the
            // "Series 003 // Benthic Pictures" template line, which is
            // `SampleCatalog` copy and used to leak onto every real show.
            if let studio = show.studios.first, !studio.isEmpty {
                Text(studio.uppercased())
                    .font(Mono.font(14, .bold)).tracking(3).foregroundStyle(theme.accent)
            }

            tvTitle

            // One line, never an empty cell — each piece renders only when
            // it has something to say. Jellyfin's own community rating leads
            // (always present when the server has one); `RatingChips`' OMDb
            // figures follow and stay blank when that enrichment hasn't
            // resolved or isn't configured.
            HStack(spacing: 10) {
                if !show.rating.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill").font(.system(size: 15))
                        Text(show.rating)
                    }
                    .fontWeight(.heavy)
                    .foregroundStyle(theme.accent)
                }
                RatingChips(imdb: imdbRating, rottenTomatoes: rottenTomatoes, metacritic: metacritic)
                if !show.certification.isEmpty {
                    Text(show.certification)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.text(0.35), lineWidth: 1.5))
                }
                if !show.years.isEmpty { Text(show.years) }
                if let count = show.seasonCount, count > 0 {
                    metaDot
                    Text("\(count) Season\(count == 1 ? "" : "s")")
                }
                if !genreTail.isEmpty { metaDot; Text(genreTail) }
                if show.awards?.academyAwardsLabel != nil { AwardsBadge(awards: show.awards) }
            }
            .font(Typography.font(19, .semibold))
            .foregroundStyle(Palette.text(0.72))

            if !show.synopsis.isEmpty {
                Text(show.synopsis)
                    .font(Typography.font(19, .regular)).foregroundStyle(Palette.text(0.78))
                    .lineLimit(3).lineSpacing(5)
                    .frame(maxWidth: 840, alignment: .leading)
            }

            tvHeroActions
                .padding(.top, 8)
        }
        .padding(.leading, 80)
        .padding(.bottom, 36)
        .frame(maxWidth: 1040, alignment: .leading)
    }

    /// The show's logo art *is* its title when Jellyfin has one (same rule the
    /// player chrome follows — `PlayerIdentityMark`); plain type is only the
    /// fallback, and what shows while the logo is still loading.
    @ViewBuilder private var tvTitle: some View {
        if let logo = show.logoArt, let url = URL(string: logo) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 640, maxHeight: 180, alignment: .leading)
                        .shadow(color: .black.opacity(0.6), radius: 20, y: 2)
                        .accessibilityLabel(show.title)
                } else {
                    tvTitleText
                }
            }
        } else {
            tvTitleText
        }
    }

    private var tvTitleText: some View {
        Text(show.title)
            .font(Typography.font(84, .black)).foregroundStyle(Palette.textPrimary)
            .lineLimit(2).minimumScaleFactor(0.6).lineSpacing(-4)
            .shadow(color: .black.opacity(0.5), radius: 20)
    }

    /// The genre tail of `genreLabel` ("TV Shows / Sci-Fi Drama" → "Sci-Fi
    /// Drama") for the hero's one-line metadata row.
    private var genreTail: String {
        show.genreLabel.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? show.genreLabel
    }

    private var metaDot: some View { Text("·").foregroundStyle(Palette.text(0.4)) }

    /// Resume/Play (the primary, default-focus action), Random (this show's
    /// whole-series shuffle), and Favourite. Contained in its own
    /// `.focusSection()` — same reasoning as `seasonSelector`'s — so Left/
    /// Right among these three doesn't let the focus engine search the whole
    /// screen at the row's edges.
    private var tvHeroActions: some View {
        HStack(spacing: 16) {
            Button(action: resumePrimaryEpisode) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill").font(.system(size: 19, weight: .bold))
                    Text(resumeLabel).font(Typography.font(21, .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32).padding(.vertical, 18)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: theme.accent.opacity(0.45), radius: 24, y: 8)
            }
            .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 14))
            .focused($focus, equals: .resume)
            .disabled(primaryEpisode == nil)

            Button(action: shufflePlay) {
                HStack(spacing: 10) {
                    if shuffleInFlight {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "shuffle").font(.system(size: 17, weight: .semibold))
                    }
                    Text("Random")
                }
                .font(Typography.font(18, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 26).padding(.vertical, 17)
                .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.18), lineWidth: 1.5))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 14))

            Button(action: toggleFavorite) {
                Image(systemName: effectiveIsFavorite ? "heart.fill" : "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(effectiveIsFavorite ? theme.accent : Palette.text(0.85))
                    .frame(width: 58, height: 58)
                    .background(Palette.text(0.08), in: Circle())
                    .overlay(Circle().stroke(Palette.text(0.16), lineWidth: 1.5))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 999))
        }
        .focusSection()
    }

    private var resumeLabel: String {
        guard let (episode, season) = primaryEpisode else { return "Play" }
        let verb = currentEpisode != nil ? "Resume" : "Play"
        return "\(verb) S\(season.number) · E\(episode.number)"
    }

    private func resumePrimaryEpisode() {
        guard let (episode, season) = primaryEpisode else { return }
        play(episode: episode, in: season)
    }

    /// Everything below the hero, on the page colour: season selector, the
    /// episode shelf, the cast row. Each strip pads its own content to the
    /// 80pt page margin rather than this container padding for them, so the
    /// two horizontal scrollers can run to the screen edge and fade there
    /// (`horizontalEdgeFade`) instead of hard-cutting at a margin.
    private var tvShelves: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text("EPISODES")
                    .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.55))
                // `.fixedSize()`: the ScrollView inside `seasonSelector` was
                // built for a fixed-width drawer column and otherwise soaks up
                // the row's leftover width instead of hugging its chips.
                seasonSelector
                    .fixedSize()
                Spacer(minLength: 0)
                if let season, episodesLoadingSeasonId != season.id, !season.episodes.isEmpty {
                    Text("\(season.episodes.count) EPISODES")
                        .font(Mono.font(13, .bold)).tracking(1.5).foregroundStyle(Palette.text(0.35))
                }
            }
            .padding(.horizontal, 80)
            // The whole full-width header row is a focus section, not just
            // the chips inside it. tvOS's focus engine needs horizontal
            // overlap to move Up, and a section's *frame* stands in for its
            // content — so Up from any episode card (including one scrolled
            // far right of the season chips, which otherwise has nothing
            // above it and goes nowhere) finds this row and lands on a chip.
            // Confirmed by hand: without it, Up from card 3 was a dead end.
            .focusSection()

            tvEpisodeShelf

            if !show.cast.isEmpty {
                tvCastRow
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The selected season as a sideways shelf of `TVEpisodeCard`s. Reserves
    /// the shelf's full height while loading so nothing reflows when the
    /// episodes land. The vertical padding inside the scroller absorbs the
    /// cards' focus scale-up so it stays within the scroller's own clip
    /// bounds; `.focusSection()` keeps Left/Right to the shelf.
    @ViewBuilder private var tvEpisodeShelf: some View {
        if season == nil || episodesLoadingSeasonId == season?.id {
            HStack(spacing: 10) {
                ProgressView().tint(theme.accent)
                Text("Loading episodes…")
                    .font(Typography.font(16, .medium)).foregroundStyle(Palette.text(0.4))
            }
            .frame(height: TVEpisodeCard.height + 24, alignment: .leading)
            .padding(.horizontal, 80)
        } else if let season {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(season.episodes) { ep in
                        TVEpisodeCard(episode: ep, action: { play(episode: ep, in: season) })
                            .focused($focus, equals: .episode(ep.id))
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 12)
            }
            .horizontalEdgeFade()
            .focusSection()
        }
    }

    private var tvCastRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CAST")
                .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.55))
                .padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(show.cast) { member in
                        CastAvatar(member: member, size: 60, labelWidth: 124)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 4)
            }
            .horizontalEdgeFade()
        }
    }
    #endif
}
