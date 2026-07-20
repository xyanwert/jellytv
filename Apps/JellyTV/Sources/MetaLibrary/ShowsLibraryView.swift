import SwiftUI
import JellyTVKit

/// The TV Shows library screen: rail + search/Play/Random header, sort/genre
/// filter chips, a "currently selected" band that tracks grid focus, and a
/// poster grid for the whole library. A structural sibling of
/// `MoviesLibraryView` (shared chrome lives in `LibraryComponents.swift`);
/// its own dossier panels (`ShowStatsCastPanel`/`ShowMetaPanel`) swap in
/// network branding and season/year/critics in place of the movie dossier's
/// stat boxes and director/studio/runtime rows. Shows a loading state while
/// the server's shows load — never sample data standing in for the real grid.
struct ShowsLibraryView: View {
    let onSelectRail: (RailTarget) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme

    @State private var shows: [MediaItem] = []
    /// True once `shows` has been populated at least once (even if the
    /// result was empty) — distinguishes "still loading" from "genuinely no
    /// shows" so the grid never has to borrow the sample catalog to fill
    /// the gap. Deliberately never reset to `false` again: a re-sort keeps
    /// showing the previous real results until the new ones land, rather
    /// than blanking the screen on every filter chip tap.
    @State private var hasLoadedShows = false
    @State private var sort: LibrarySort = .newest
    @State private var selectedGenre: String?
    @State private var searchText = ""
    @State private var presentedShow: Show?
    /// Real detail (cast, ratings, season count, network) fetched for the
    /// selected item; shown in place of the sample fallback once it arrives.
    @State private var selectedDetail: Show?
    @FocusState private var focusedId: String?
    @FocusState private var searchFocused: Bool?

    private var allShows: [MediaItem] { shows }

    /// Distinct genres present in the current catalog, most common first.
    private var genres: [String] {
        let counts = Dictionary(grouping: allShows, by: \.genre).mapValues(\.count)
        return counts.keys
            .filter { !$0.isEmpty }
            .sorted { a, b in
                let (ca, cb) = (counts[a] ?? 0, counts[b] ?? 0)
                return ca != cb ? ca > cb : a < b
            }
            .prefix(8)
            .map { $0 }
    }

    private var filtered: [MediaItem] {
        var items = allShows
        if let selectedGenre { items = items.filter { $0.genre == selectedGenre } }
        if !searchText.isEmpty {
            items = items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return items
    }

    private var selectedItem: MediaItem? {
        // A focused poster wins. Otherwise (initial state, nothing focused)
        // feature the first item that actually has backdrop art rather than
        // `filtered.first` — the newest item is often an unidentified file
        // with no artwork, which would leave the big backdrop blank.
        filtered.first { $0.id == focusedId }
            ?? filtered.first { $0.rating != nil && $0.backdropImage != nil }
            ?? filtered.first { $0.backdropImage != nil }
            ?? filtered.first
    }

    /// The show shown in the dossier: real fetched detail once it's in and
    /// matches the current selection, otherwise a bare base (real list fields,
    /// no cast/season count/network) that the dossier renders as a loading state.
    private var dossierShow: Show? {
        guard let item = selectedItem else { return nil }
        if let detail = selectedDetail, detail.id == item.id { return detail }
        return baseShow(for: item)
    }

    /// True while the full detail for the current selection hasn't arrived yet
    /// — the dossier shows "loading" rather than any placeholder/fake metadata.
    private var isDossierLoading: Bool {
        guard let item = selectedItem else { return false }
        return selectedDetail?.id != item.id
    }

    /// A bare `Show` carrying only an item's real list-level fields (title,
    /// rating, year, certification, synopsis). Cast/season-count/network stay
    /// empty until the live detail fetch fills them in — never demo data.
    private func baseShow(for item: MediaItem) -> Show {
        var show = SampleCatalog.show(for: item)
        if let rating = item.rating {
            show.rating = String(format: "%.1f", rating)
            show.communityRating = rating
        }
        if let year = item.year { show.years = year }
        if let certification = item.certification, !certification.isEmpty { show.certification = certification }
        if let synopsis = item.synopsis, !synopsis.isEmpty { show.synopsis = synopsis }
        return show
    }

    /// Fetches full Jellyfin detail for the selected item, then concurrently
    /// merges OMDb ratings/awards and TMDB network branding. Debounced so
    /// scrolling the grid doesn't fetch per poster; `.task(id:)` cancels the
    /// prior run when the selection changes.
    private func loadSelectedDetail() async {
        guard let item = selectedItem else { selectedDetail = nil; return }
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
        guard var show = await appState.enrichedShow(baseShow(for: item)) else { return }
        selectedDetail = show
        let imdbId = show.imdbId
        async let omdbEnrichment = appState.omdbEnrichment(imdbId: imdbId)
        async let network = appState.tmdbNetwork(imdbId: imdbId)
        let enrichment = await omdbEnrichment
        let resolvedNetwork = await network
        guard !Task.isCancelled else { return }
        if let enrichment {
            show.externalRatings = enrichment.ratings
            show.awards = enrichment.awards
        }
        show.network = resolvedNetwork
        selectedDetail = show
    }

    /// Opens the Show detail screen with a bare base; `ShowView` fetches its
    /// own live detail (cast, ratings, tagline) on appear.
    private func openShow(_ item: MediaItem) {
        presentedShow = baseShow(for: item)
    }

    var body: some View {
        ZStack {
            background
            // The focused show's backdrop: a full-screen layer pinned to the
            // top, behind the rail and the scrolling content — the same
            // treatment Movies uses.
            if let selectedItem {
                SelectedBackdrop(item: selectedItem)
            }
            HStack(spacing: 0) {
                NavRail(destination: .tv, isLibrariesOpen: false, onSelect: onSelectRail)
                // Header, filters and the selected-show band stay pinned; only
                // the poster catalog scrolls beneath them.
                VStack(alignment: .leading, spacing: 22) {
                    header.padding(.horizontal, 48)
                    filterBar.padding(.horizontal, 48)
                    if let dossierShow {
                        SelectedShowBand(show: dossierShow, isLoading: isDossierLoading)
                    }
                    if !hasLoadedShows {
                        loadingGrid
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            postersSection
                                .padding(.horizontal, 48)
                                .padding(.top, 6)   // room for the top row's focus glow
                                .padding(.bottom, 60)
                        }
                    }
                }
                .padding(.top, 40)
            }
            .ignoresSafeArea()

            if let presentedShow {
                ShowView(show: presentedShow, onDismiss: { self.presentedShow = nil })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.25), value: presentedShow)
        // Focus the search field on appear (a top control) rather than the
        // first poster — focusing a poster makes tvOS auto-scroll it into
        // place, which pushes the header/search off the top of the screen.
        .defaultFocus($searchFocused, true)
        // `appState.libraries.count` is part of the task id (not just `sort`)
        // so this re-fires once the server connection finishes configuring —
        // otherwise a view that appears before `AppState.refresh()` completes
        // would fetch once with no client yet, get back `[]`, and never retry
        // until the user touches a chip.
        .task(id: "\(sort.rawValue)-\(appState.libraries.count)") {
            let query = sort.query
            shows = await appState.loadShows(sortBy: query.sortBy, sortOrder: query.sortOrder)
            hasLoadedShows = true
        }
        // Fetch rich detail (cast/season count/network) for the selected item.
        .task(id: selectedItem?.id) { await loadSelectedDetail() }
        .onExitCommand(perform: presentedShow == nil ? { onSelectRail(.home) } : nil)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIBRARY // TV SHOWS")
                    .font(Mono.font(15, .bold))
                    .tracking(2.6)
                    .foregroundStyle(Palette.text(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("TV Shows")
                        .font(Typography.font(34, .black))
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(allShows.count) titles")
                        .font(Typography.font(20, .semibold))
                        .foregroundStyle(Palette.text(0.4))
                }
            }
            .fixedSize()

            searchField

            Button {} label: {
                HStack(spacing: 11) {
                    Image(systemName: "play.fill").font(.system(size: 18))
                    Text("Play")
                }
                .font(Typography.button)
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 15)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: theme.accent.opacity(0.4), radius: 16, y: 4)
            }
            .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 14))

            Button(action: randomize) {
                HStack(spacing: 10) {
                    Image(systemName: "shuffle").font(.system(size: 18, weight: .semibold))
                    Text("Random")
                }
                .font(Typography.button)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 15)
                .background(Palette.text(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.2), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 14))
        }
    }

    private var searchField: some View {
        AppTextField(placeholder: "Search TV shows…", text: $searchText,
                     systemImage: "magnifyingglass", trailing: "\(filtered.count)",
                     accent: theme.secondaryAccent, field: true, focus: $searchFocused)
    }

    private func randomize() {
        guard let item = filtered.randomElement() else { return }
        focusedId = item.id
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: 12) {
            Text("FILTER")
                .font(Mono.font(13, .bold))
                .tracking(2)
                .foregroundStyle(Palette.text(0.4))
            ForEach(LibrarySort.allCases) { option in
                LibraryFilterChip(label: option.rawValue, isOn: sort == option) { sort = option }
            }
            Rectangle().fill(Palette.text(0.14)).frame(width: 1, height: 26)
            ForEach(genres, id: \.self) { genre in
                LibraryFilterChip(label: genre, isOn: selectedGenre == genre) {
                    selectedGenre = (selectedGenre == genre) ? nil : genre
                }
            }
        }
    }

    // MARK: - Poster grid

    /// Shown in place of the grid until the first real fetch resolves —
    /// never the sample catalog standing in for real shows.
    private var loadingGrid: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(theme.accent)
            Text("Loading TV shows…")
                .font(Mono.font(15, .medium)).tracking(1)
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 140)
    }

    private var postersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(sectionCaption)
                    .font(Mono.font(15, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.5))
                Spacer()
                Text("Showing \(filtered.count) of \(allShows.count)")
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(Palette.text(0.4))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 210), spacing: 22)], spacing: 26) {
                ForEach(filtered) { item in
                    LibraryPosterCard(item: item, onSelect: { openShow(item) })
                        .focused($focusedId, equals: item.id)
                }
            }
        }
    }

    private var sectionCaption: String {
        let genrePart = selectedGenre?.uppercased() ?? "ALL TV SHOWS"
        return "\(genrePart) · \(sort.rawValue.uppercased())"
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Palette.background
            RadialGradient(colors: [Color(OKLCH(l: 0.34, c: 0.10, h: 235)).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.82, y: 0.04), startRadius: 0, endRadius: 1100)
        }
        .ignoresSafeArea()
    }
}

/// The "currently selected" text band: the focused show's title / meta /
/// synopsis on the left and the TV "Signal Dossier" info panel on the right,
/// laid over the top of `SelectedBackdrop`. Rich fields (rating, cast, network)
/// come from `SampleCatalog.show(for:)` — the same demo-template seam the
/// Movies band uses.
private struct SelectedShowBand: View {
    let show: Show
    var isLoading: Bool = false

    @EnvironmentObject private var theme: Theme

    private static let height: CGFloat = 536

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            info
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 16) {
                ShowStatsCastPanel(show: show, isLoading: isLoading)
                ShowMetaPanel(show: show, isLoading: isLoading)
            }
        }
        .padding(.horizontal, 100)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .id(show.id)
        .transition(.opacity)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SELECTED // NOW IN YOUR LIBRARY")
                .font(Mono.font(14, .bold))
                .tracking(3)
                .foregroundStyle(theme.accent)

            Text(show.title)
                .font(Typography.font(72, .black))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .lineSpacing(-6)

            HStack(spacing: 12) {
                Text("★ \(show.rating)")
                    .fontWeight(.heavy)
                    .foregroundStyle(theme.accent)
                Text(show.certification)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.text(0.3), lineWidth: 1.5))
                Text(show.years)
                dot
                Text(genreTail)
            }
            .font(Typography.font(19, .semibold))
            .foregroundStyle(Palette.text(0.68))

            Text(show.synopsis)
                .font(Typography.font(20, .medium))
                .foregroundStyle(Palette.text(0.7))
                .lineLimit(3)
                .lineSpacing(6)
                .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var genreTail: String {
        show.genreLabel.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? show.genreLabel
    }

    private var dot: some View { Text("·").foregroundStyle(Palette.text(0.4)) }
}

/// The Shows dossier's top panel: the "SIGNAL DOSSIER / DECODED" header, the
/// show's network branding where the Movies dossier shows critics/audience
/// stat boxes, and the same two-column cast grid with Oscar-winner medals.
/// Same fixed footprint as `MoviesLibraryView`'s `StatsCastPanel` so the two
/// screens' dossiers read as siblings.
private struct ShowStatsCastPanel: View {
    let show: Show
    var isLoading: Bool = false

    @EnvironmentObject private var theme: Theme

    static let size = CGSize(width: 440, height: 380)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isLoading {
                loadingBody
            } else {
                NetworkLockup(network: show.network, fallbackName: show.studios.first)
                castSection
            }
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(Color(hex: "#0E121A").opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
    }

    private var header: some View {
        HStack {
            Text("SIGNAL DOSSIER")
                .font(Mono.font(12, .bold))
                .tracking(2.4)
                .foregroundStyle(Palette.text(0.42))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(isLoading ? Palette.text(0.35) : theme.accent).frame(width: 7, height: 7)
                    .shadow(color: isLoading ? .clear : theme.accent, radius: 6)
                Text(isLoading ? "SCANNING" : "DECODED")
                    .font(Mono.font(11, .bold))
                    .tracking(1)
                    .foregroundStyle(isLoading ? Palette.text(0.4) : theme.accent)
            }
        }
    }

    /// Shown until the live detail arrives — a quiet indicator, never fake data.
    private var loadingBody: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(theme.accent)
            Text("Decoding signal…")
                .font(Mono.font(14, .medium)).tracking(1)
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Cast (two-column grid)

    @ViewBuilder private var castSection: some View {
        if !show.cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("CAST")
                    .font(Mono.font(12, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.42))
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    alignment: .leading, spacing: 14
                ) {
                    ForEach(show.cast.prefix(6)) { member in
                        CastListItem(member: member, portrait: 42)
                    }
                }
            }
        }
    }
}

/// The Shows dossier's bottom panel: a season-count/year stat pair (replacing
/// the Movies dossier's director/studio/runtime rows) and a critics-score row
/// with a circular gauge — its own fixed-size card below `ShowStatsCastPanel`.
/// No Oscar-art background treatment here — not applicable to TV.
private struct ShowMetaPanel: View {
    let show: Show
    var isLoading: Bool = false

    @EnvironmentObject private var theme: Theme

    /// Same fixed footprint as the Movies dossier's `MetaPanel`.
    static let size = CGSize(width: 440, height: 140)

    private var critics: Int? { show.externalRatings?.rottenTomatoes ?? show.criticRating.map { Int($0) } }

    var body: some View {
        Group {
            if isLoading { loadingBody } else { rows }
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(Color(hex: "#0E121A").opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
    }

    /// This panel's own decode indicator, matching `ShowStatsCastPanel`'s
    /// visual language so neither dossier window goes blank while the other
    /// is still decoding.
    private var loadingBody: some View {
        HStack(spacing: 10) {
            ProgressView().tint(theme.accent)
            Text("Decoding…")
                .font(Mono.font(13, .medium)).tracking(1)
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 16) {
            seasonYearRow
            if let critics { criticsRow(critics) }
        }
    }

    @ViewBuilder private var seasonYearRow: some View {
        let hasSeasonCount = show.seasonCount != nil
        let hasYear = show.premiereYear?.isEmpty == false
        if hasSeasonCount || hasYear {
            HStack {
                if let count = show.seasonCount {
                    bigStat("\(count) Season\(count == 1 ? "" : "s")")
                }
                Spacer(minLength: 12)
                if let year = show.premiereYear, !year.isEmpty {
                    bigStat(year)
                }
            }
        }
    }

    private func bigStat(_ value: String) -> some View {
        Text(value)
            .font(Typography.font(22, .black))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
    }

    private func criticsRow(_ percent: Int) -> some View {
        HStack {
            Text("CRITICS")
                .font(Mono.font(13, .semibold)).tracking(1)
                .foregroundStyle(Palette.text(0.42))
            Spacer(minLength: 12)
            CriticsGauge(percent: percent, size: 40)
        }
    }
}
