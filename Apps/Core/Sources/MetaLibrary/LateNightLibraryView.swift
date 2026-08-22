import SwiftUI
import JellyTVKit

/// The Late Night library screen (design 4c) — the `.hentai` meta-category
/// (tvshows + anime + NSFW), reached from a Libraries submenu row. Shows-only
/// (movies has no combined NSFW+anime category, so there's no equivalent
/// movies pool to merge in here the way `AnimeLibraryView` does). Named for
/// the design's own tasteful in-product label ("Late Night") rather than the
/// internal `MetaCategory.hentai` case name — the screen never uses that word
/// itself, matching the same discretion the design applies.
///
/// Reskinned with a muted red/crimson identity color and a darker, grittier
/// backdrop treatment (vignette) than the Anime screen's magenta/energetic
/// one. A fixed "18+"/"Explicit content" badge is legitimate here (every item
/// in this category is NSFW by definition, so it's a category-wide fact, not
/// invented per-item data) — but the design's MAL score, content-advisory
/// tags, and "director's cut" callout have no real backing source and are
/// left out, same reasoning as `AnimeLibraryView`.
struct LateNightLibraryView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    // See `MoviesLibraryView`'s identical constants/comment.
    #if os(iOS)
    private static let headerSpacing: CGFloat = 12
    private static let headerTopPadding: CGFloat = 12
    #else
    private static let headerSpacing: CGFloat = 22
    private static let headerTopPadding: CGFloat = 40
    #endif

    @EnvironmentObject private var appState: AppState

    /// The category's own identity color — matches design 4c's `accentLate`
    /// token, seeded from the same hue (20, red) as its background radial glow.
    static let accent = Color(OKLCH(l: 0.56, c: 0.18, h: 20))

    @State private var items: [MediaItem] = []
    @State private var hasLoaded = false
    @State private var sort: LibrarySort = .newest
    @State private var selectedGenre: String?
    @State private var searchText = ""
    @State private var searchTags: [String] = []
    @State private var presentedShow: Show?
    @State private var selectedDetail: Show?
    @FocusState private var focusedId: String?
    @FocusState private var searchFocused: Bool?

    private var allItems: [MediaItem] { items }

    private var genres: [String] {
        let counts = Dictionary(grouping: allItems, by: \.genre).mapValues(\.count)
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
        var result = allItems
        if let selectedGenre { result = result.filter { $0.genre == selectedGenre } }
        if !searchTags.isEmpty { result = result.filter { $0.matches(allOf: searchTags) } }
        return result
    }

    private var selectedItem: MediaItem? {
        filtered.first { $0.id == focusedId }
            ?? filtered.first { $0.rating != nil && $0.backdropImage != nil }
            ?? filtered.first { $0.backdropImage != nil }
            ?? filtered.first
    }

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

    private var isDossierLoading: Bool {
        guard let item = selectedItem else { return false }
        return selectedDetail?.id != item.id
    }

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

    private func openShow(_ item: MediaItem) {
        presentedShow = baseShow(for: item)
    }

    private var exitAction: (() -> Void)? {
        if isLibrariesOpen { return { onSelectRail(.libraries) } }
        if presentedShow != nil { return nil }
        return { onSelectRail(.home) }
    }

    var body: some View {
        ZStack {
            background
            if let selectedItem {
                SelectedBackdrop(item: selectedItem)
            }
            HStack(spacing: 0) {
                NavRail(destination: .lateNight, isLibrariesOpen: isLibrariesOpen,
                        onSelect: onSelectRail, accentOverride: Self.accent)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems()) {
                    VStack(alignment: .leading, spacing: Self.headerSpacing) {
                        header.padding(.horizontal, 48)
                        filterBar.padding(.horizontal, 48)
                        if let dossierShow {
                            LateNightBand(show: dossierShow, isLoading: isDossierLoading)
                        }
                        if !hasLoaded {
                            loadingGrid
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                postersSection
                                    .padding(.horizontal, 48)
                                    .padding(.top, 6)
                                    .padding(.bottom, 60)
                            }
                        }
                    }
                    .padding(.top, Self.headerTopPadding)
                }
            }
            .ignoresSafeArea()
            // See `HomeView`'s matching `.disabled` for why: `presentedShow`
            // is a same-ZStack overlay, not a modal, so without this the
            // rail stays focus-reachable underneath it.
            .disabled(presentedShow != nil)

            if let presentedShow {
                ShowView(show: presentedShow, onDismiss: { self.presentedShow = nil })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.25), value: presentedShow)
        .defaultFocus($searchFocused, true)
        .task(id: "\(sort.rawValue)-\(appState.libraries.count)") {
            let query = sort.query
            items = await appState.loadLateNightShows(sortBy: query.sortBy, sortOrder: query.sortOrder)
            hasLoaded = true
        }
        .task(id: selectedItem?.id) { await loadSelectedDetail() }
        #if os(tvOS)
        .onExitCommand(perform: exitAction)
        #endif
    }

    private var dossierShow: Show? {
        guard let item = selectedItem else { return nil }
        if let selectedDetail, selectedDetail.id == item.id { return selectedDetail }
        return baseShow(for: item)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("LIBRARY // LATE NIGHT")
                        .font(Mono.font(15, .bold))
                        .tracking(2.6)
                        .foregroundStyle(Palette.text(0.5))
                    AdultBadge(accent: Self.accent)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Late Night")
                        .font(Typography.font(34, .black))
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(allItems.count) titles")
                        .font(Typography.font(20, .semibold))
                        .foregroundStyle(Palette.text(0.4))
                    Text("深夜アニメ")
                        .font(Mono.font(16, .bold))
                        .tracking(1.5)
                        .foregroundStyle(Self.accent)
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
                .background(Self.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Self.accent.opacity(0.4), radius: 16, y: 4)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: "#0B0808").opacity(0.5))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.text(0.07), lineWidth: 1))
    }

    private var searchField: some View {
        TagSearchField(tags: $searchTags, liveText: $searchText, placeholder: "Search seinen, psychological, uncut cuts…",
                       accent: Self.accent, trailing: "\(filtered.count)",
                       field: true, focus: $searchFocused)
    }

    private func randomize() {
        guard let item = filtered.randomElement() else { return }
        focusedId = item.id
    }

    // MARK: - Filters

    private var filterBar: some View {
        // Scrolling instead of a plain (non-scrolling) HStack keeps every
        // chip a single line on an iPad's narrower width instead of
        // squeeze-wrapping — see `MoviesLibraryView`'s identical comment.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Text("FILTER")
                    .font(Mono.font(13, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.4))
                ForEach(LibrarySort.allCases) { option in
                    LibraryFilterChip(label: option.rawValue, isOn: sort == option, action: { sort = option }, accent: Self.accent)
                }
                Rectangle().fill(Palette.text(0.14)).frame(width: 1, height: 26)
                ForEach(genres, id: \.self) { genre in
                    LibraryFilterChip(
                        label: genre, isOn: selectedGenre == genre,
                        action: { selectedGenre = (selectedGenre == genre) ? nil : genre },
                        accent: Self.accent
                    )
                }
            }
        }
    }

    // MARK: - Poster grid

    private var loadingGrid: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Self.accent)
            Text("Loading late night…")
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
                Text("Showing \(filtered.count) of \(allItems.count)")
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
        let genrePart = selectedGenre?.uppercased() ?? "ALL LATE NIGHT"
        return "\(genrePart) · \(sort.rawValue.uppercased())"
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(hex: "#0A0808")
            RadialGradient(colors: [Color(OKLCH(l: 0.24, c: 0.09, h: 20)).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.82, y: 0.0), startRadius: 0, endRadius: 1300)
            Vignette()
        }
        .ignoresSafeArea()
    }
}

/// A soft edge-darkening overlay (design 4c's inset vignette) — the grittier,
/// more claustrophobic counterpart to the Anime screen's diagonal speed-lines.
private struct Vignette: View {
    var body: some View {
        RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 420, endRadius: 1000)
            .allowsHitTesting(false)
    }
}

/// The vertical Japanese watermark between the info block and the dossier
/// panel (design 4c's "黒い髄 · 深夜枠" signature). Same reasoning as
/// `AnimeLibraryView`'s `KatakanaSignature`: no real per-title Japanese name
/// exists, so this stays a fixed category label ("深夜アニメ" — "late-night
/// anime") rather than inventing a translation of whatever's selected. Carries
/// its own shadow + dark backing from the start (learned from the Anime
/// screen's first pass, where a plain low-opacity glyph over arbitrary
/// backdrop art was only legible by luck).
private struct LateKatakanaSignature: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array("深夜アニメ".enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(Mono.font(20, .bold))
            }
        }
        .tracking(2)
        .foregroundStyle(LateNightLibraryView.accent.opacity(0.7))
        .shadow(color: .black.opacity(0.8), radius: 5)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize()
    }
}

/// The "currently selected" band (design 4c): the focused title's info on the
/// left (with a fixed "VIEWER DISCRETION" advisory — accurate for every item
/// in this category, not per-item data) and the Content Dossier + crew panels
/// on the right, recolored to the late-night accent with the cast panel
/// relabeled "SEIYUU" and the dossier status word "RESTRICTED".
private struct LateNightBand: View {
    let show: Show
    var isLoading: Bool = false

    // See `AnimeMovieBand`'s identical comment.
    #if os(iOS)
    private static let height: CGFloat = 300
    private static let horizontalPadding: CGFloat = 56
    private static let itemSpacing: CGFloat = 24
    private static let bandAlignment: VerticalAlignment = .top
    private static let frameAlignment: Alignment = .top
    private static let infoSpacing: CGFloat = 10
    private static let titleFontSize: CGFloat = 44
    private static let titleLineLimit = 1
    private static let infoMaxWidth: CGFloat = 520
    private static let synopsisMaxWidth: CGFloat = 520
    #else
    private static let height: CGFloat = 536
    private static let horizontalPadding: CGFloat = 100
    private static let itemSpacing: CGFloat = 32
    private static let bandAlignment: VerticalAlignment = .center
    private static let frameAlignment: Alignment = .center
    private static let infoSpacing: CGFloat = 16
    private static let titleFontSize: CGFloat = 72
    private static let titleLineLimit = 2
    private static let infoMaxWidth: CGFloat = 720
    private static let synopsisMaxWidth: CGFloat = 620
    #endif

    var body: some View {
        HStack(alignment: Self.bandAlignment, spacing: Self.itemSpacing) {
            info
            Spacer(minLength: 8)
            LateKatakanaSignature()
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 16) {
                ShowStatsCastPanel(show: show, isLoading: isLoading, accent: LateNightLibraryView.accent,
                                   castLabel: "SEIYUU", dossierLabel: "CONTENT DOSSIER", readyLabel: "RESTRICTED")
                #if os(tvOS)
                ShowMetaPanel(show: show, isLoading: isLoading, accent: LateNightLibraryView.accent)
                #endif
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height, alignment: Self.frameAlignment)
        .id(show.id)
        .transition(.opacity)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Self.infoSpacing) {
            HStack(spacing: 12) {
                Text("SELECTED // LATE NIGHT BLOCK")
                    .font(Mono.font(14, .bold))
                    .tracking(3)
                    .foregroundStyle(LateNightLibraryView.accent)
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill").font(.system(size: 11, weight: .bold))
                    Text("VIEWER DISCRETION")
                }
                .font(Mono.font(11, .bold))
                .tracking(0.5)
                .foregroundStyle(Palette.text(0.65))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Palette.text(0.2), lineWidth: 1))
            }

            Text(show.title)
                .font(Typography.font(Self.titleFontSize, .black))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(Self.titleLineLimit)
                .minimumScaleFactor(0.5)
                .lineSpacing(-6)

            HStack(spacing: 12) {
                Text("★ \(show.rating)")
                    .fontWeight(.heavy)
                    .foregroundStyle(LateNightLibraryView.accent)
                Text(show.certification)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.text(0.3), lineWidth: 1.5))
                Text(show.years)
                dot
                Text(genreTail)
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12, weight: .bold))
                    Text("EXPLICIT CONTENT")
                }
                .font(Typography.font(15, .bold))
                .foregroundStyle(LateNightLibraryView.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(LateNightLibraryView.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(LateNightLibraryView.accent.opacity(0.4), lineWidth: 1))
            }
            .font(Typography.font(19, .semibold))
            .foregroundStyle(Palette.text(0.68))

            Text(show.synopsis)
                .font(Typography.font(20, .medium))
                .foregroundStyle(Palette.text(0.7))
                .lineLimit(3)
                .lineSpacing(6)
                .frame(maxWidth: Self.synopsisMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: Self.infoMaxWidth, alignment: .leading)
    }

    private var genreTail: String {
        show.genreLabel.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? show.genreLabel
    }

    private var dot: some View { Text("·").foregroundStyle(Palette.text(0.4)) }
}
