import SwiftUI
import JellyTVKit

/// The Home Videos library screen — Jellyfin's `homevideos` collection type,
/// which resolves to the `.videos` and `.porn` meta-categories.
///
/// **This existed as a gap, not a design.** Every other collection type had a
/// screen; `homevideos` had none, so such a library was listed in the rail's
/// Libraries submenu and then did nothing at all when tapped. Both categories
/// land here and the screen takes its identity from whichever it was opened
/// for — the NSFW one gets the accent and the category-wide 18+ badge, the
/// same treatment Late Night gives `.hentai`.
///
/// Deliberately simpler than Movies/Shows: home videos are loose files, not a
/// catalogue with cast and ratings, so there is no dossier band and no detail
/// screen — a card plays. The header/filter layout follows the same
/// two-row pattern as Movies/Shows/Anime/Late Night (see `controlBar`), but
/// `filterBar`'s chip vocabulary is still bespoke to this screen: home videos
/// sort two ways rather than three, plus two independent filters
/// (Unwatched, Favorites) the other screens have no equivalent of.
struct VideosLibraryView: View {
    /// The two ways to *browse* this screen — what the grid's own order is.
    ///
    /// **Distinct from the separate Random button below, on purpose.**
    /// Selecting this chip only reshuffles what the grid displays; a card
    /// still just plays when tapped, same as any other order. The Random
    /// *button* (`playRandom`) does the opposite — it builds a shuffled queue
    /// and starts playing immediately, without touching this order at all, so
    /// browsing randomly and playing randomly stay two separate actions
    /// rather than one control awkwardly meaning both. The chip is labelled
    /// **"Shuffled"**, not "Random": two controls on one screen with the same
    /// word and different effects is a coin toss for whoever is holding the
    /// remote, and this one describes an *order*, which is what the word says.
    enum Sort: Hashable {
        case latestAdded
        case random

        var label: String {
            switch self {
            // tvOS lays the shelf out as a camera roll by the day each video
            // was shot (`HomeVideoRollView`), so the chip says what it does.
            #if os(tvOS)
            case .latestAdded: return "By Date"
            #else
            case .latestAdded: return "Latest Added"
            #endif
            case .random: return "Shuffled"
            }
        }

        var query: (sortBy: String, sortOrder: String) {
            switch self {
            case .latestAdded: return ("DateCreated", "Descending")
            case .random: return ("Random", "Ascending")
            }
        }
    }


    let category: MetaCategory
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    // See `MoviesLibraryView`'s identical constants — the same numbers, so
    // the title sits where it sits on every other library screen.
    private static let headerSpacing: CGFloat = 16
    private static let headerTopPadding: CGFloat = 24
    /// What `libraryContentMargin()` pads on tvOS — the roll needs the number
    /// to justify its rows to the width that is actually left.
    private static let contentMargin: CGFloat = 48

    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedId: String?
    /// One-shot latch for `seedFocusIfNeeded`.
    @State private var hasSeededFocus = false

    @State private var items: [MediaItem] = []
    /// Set once on the first successful fetch and never reset by a re-sort, so
    /// "still loading" and "genuinely empty" stay distinguishable — an
    /// `isEmpty` check can't tell them apart, and the difference is a spinner
    /// versus a wrong "nothing here".
    @State private var hasLoaded = false
    @State private var sort: Sort = .latestAdded
    /// Bumped on every tap of the Random *sort* chip, including a repeat tap
    /// while it's already selected. `.task(id:)` only refires when its id
    /// string actually changes, and re-selecting the same `Sort` case
    /// wouldn't — without this, a second press of "Random" would silently
    /// keep the first shuffle instead of drawing a new one.
    @State private var randomSortNonce = 0
    @State private var searchText = ""
    @State private var searchTags: [String] = []
    /// The two filter chips — independent and combinable (AND), unlike a sort
    /// chip's exclusive pick.
    @State private var unwatchedOnly = false
    @State private var favoritesOnly = false
    /// The separate Random *button*'s state — it builds a queue over a whole
    /// library, which is a round trip long enough to need reporting.
    @State private var randomState: RandomPlayState = .idle
    /// The page's atmospheric backdrop — a wallpaper, since these libraries
    /// have no artwork of their own to build a screen around. Fetched once per
    /// category; nil until it arrives, and nil forever if it never does.
    @State private var backdrop: UIImage?

    private var isAdult: Bool { category.isNSFW }
    private var accent: Color { isAdult ? Color(hex: "#E0457B") : theme.accent }

    /// **The server's own library name, not a fixed label.** A `homevideos`
    /// library can be named anything ("Nalguitas", "Camcorder Dumps") and
    /// more than one can resolve into this same category (any such library
    /// classifies as NSFW or not independently) — every one that does names
    /// itself here, joined, rather than papering over real names with
    /// "Home Videos"/"After Hours". Those two only survive as a fallback for
    /// the render before `appState.libraries` has loaded.
    private var title: String {
        let names = appState.libraries
            .filter { appState.metaCategory(for: $0) == category }
            .map(\.name)
        guard !names.isEmpty else { return isAdult ? "After Hours" : "Home Videos" }
        return names.joined(separator: " · ")
    }

    /// Wider cells than the poster grids: these cards are 16:9, so a 180pt
    /// column would make them 101pt tall and unreadable.
    #if os(iOS)
    // 300pt (iPad's minimum) is wider than a whole phone portrait column —
    // two ~160pt 16:9 cards side by side reads as a grid; one 300pt card
    // would leave dead margin on either side of it instead.
    private static var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: DeviceClass.current == .phone ? 160 : 300), spacing: 22)]
    }
    #else
    private static let gridColumns = [GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 22)]
    #endif

    private var filtered: [MediaItem] {
        // Through the overrides: a tag applied from the player's tag panel
        // has to show on the card you back out to, and nothing re-runs the
        // loader below while the player is up.
        var result = appState.applyingTagOverrides(items)
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        }
        for tag in searchTags {
            result = result.filter { $0.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame } }
        }
        if unwatchedOnly {
            result = result.filter { !$0.played }
        }
        if favoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        return result
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            // Behind the rail, not beside it: the rail is semi-transparent, so
            // the backdrop has to be drawn earlier in the stack for it to show
            // through — the same arrangement Home and Movies use.
            backdropLayer
            HStack(spacing: 0) {
                NavRail(destination: .videosLibrary(category), isLibrariesOpen: isLibrariesOpen,
                        onSelect: onSelectRail, accentOverride: accent)
                LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems(),
                                        onDismiss: { onSelectRail(.libraries) }) {
                    VStack(alignment: .leading, spacing: Self.headerSpacing) {
                        controlBar.libraryContentMargin()
                        if !hasLoaded {
                            loading
                        } else {
                            #if os(tvOS)
                            // The roll's rows justify to the real content
                            // width, so the reader sits outside the scroll
                            // view (inside one it has no height to give).
                            GeometryReader { geo in
                                ScrollView(.vertical, showsIndicators: false) {
                                    roll(width: geo.size.width - 2 * Self.contentMargin)
                                        .libraryContentMargin()
                                        .padding(.top, 6)
                                        .padding(.bottom, 60)
                                }
                            }
                            #else
                            ScrollView(.vertical, showsIndicators: false) {
                                grid
                                    .libraryContentMargin()
                                    .padding(.top, 6)
                                    .padding(.bottom, 60)
                                    .phoneTabBarClearance()
                                    .fixesScrollTapDelay()
                            }
                            #endif
                        }
                    }
                    .padding(.top, Self.headerTopPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .railContentSafeArea()
        }
        // Keyed on the category alone, deliberately: re-sorting must not
        // refire this and reshuffle every card's artwork underneath the user.
        // Only arriving at a different library does.
        .task(id: category.rawValue) {
            backdrop = await appState.wallhavenBackdrop(for: category)
        }
        // "Unwatched"/"Favorites" filter the already-loaded list rather than
        // driving a re-fetch, so neither belongs in this task's identity —
        // only what actually changes the server query does. The nonce is
        // folded in only for `.random`, so re-selecting "Latest Added" after
        // a shuffle is a plain, single re-fetch rather than picking up a
        // stale nonce from an unrelated earlier shuffle.
        .task(id: "\(category.rawValue)-\(sort)-\(sort == .random ? randomSortNonce : 0)-\(appState.libraries.count)") {
            let query = sort.query
            let loaded = await appState.loadHomeVideos(category: category,
                                                       sortBy: query.sortBy,
                                                       sortOrder: query.sortOrder)
            guard !Task.isCancelled else { return }
            items = loaded
            hasLoaded = true
        }
    }

    /// Full-bleed, pinned to the top, dissolving into the page before the grid
    /// gets going.
    ///
    /// Follows the house treatment for atmospheric backdrops: render into a
    /// 1.5× box and clip (a subtle zoom rather than an exact fit), left-darken
    /// so the header and rail keep their contrast, top-darken because the
    /// title and search field sit up there, and **pre-darken toward black at
    /// the fading edge before the alpha mask** — that pre-darken is what makes
    /// the image dissolve into the page instead of hard-cutting.
    ///
    /// It is held well back (a third of full strength). A wallpaper is here to
    /// give the screen a mood, and one of these can easily be a brightly-lit
    /// photograph that would otherwise win every contrast fight on the page.
    @ViewBuilder
    private var backdropLayer: some View {
        if let backdrop {
            GeometryReader { geo in
                Image(uiImage: backdrop)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width * 1.5, height: geo.size.height * 1.5)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    // Header legibility.
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.85), .black.opacity(0.35), .clear],
                            startPoint: .top, endPoint: .center
                        )
                    }
                    // Rail and left-column legibility.
                    .overlay {
                        LinearGradient(
                            colors: [Palette.screen, Palette.screen.opacity(0.35), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    }
                    // Pre-darken toward the page colour at the fading edge, so
                    // the mask below dissolves rather than cuts.
                    .overlay {
                        LinearGradient(
                            colors: [.clear, Palette.screen.opacity(0.7), Palette.screen],
                            startPoint: .center, endPoint: .bottom
                        )
                    }
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.45),
                                .init(color: .clear, location: 0.72),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .opacity(0.34)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    /// Two-row layout shared with Movies/Shows/Anime/Late Night: an eyebrow +
    /// title + search + actions row, then a `FILTER` chip row underneath.
    /// Replaces the old iPad-only single-line `controlBar` (search + chips +
    /// Random button all crammed into one 48pt-tall `HStack`), which
    /// truncated every chip's label on a real device the moment more than a
    /// couple were on screen at once — the fix is more room, not smaller
    /// text. tvOS gains real search/filter controls on this screen for the
    /// first time in the same move; it previously had none at all here.
    private var controlBar: some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            header
            filterBar
        }
    }

    private var header: some View {
        LibraryHeaderLayout {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if isAdult { AdultBadge(accent: accent) }
                Text(title)
                    .font(Typography.font(34, .black))
                    .foregroundStyle(Palette.textPrimary)
                if hasLoaded {
                    Text(LibraryChrome.countLabel(shown: filtered.count, total: items.count, noun: "videos"))
                        .font(Typography.font(20, .semibold))
                        .foregroundStyle(Palette.text(0.4))
                }
            }
            .libraryTitleBlockSizing()
        } search: {
            searchField
        } actions: {
            // The separate Random *button* — plays a shuffled queue over the
            // whole library immediately, and never touches the grid's own
            // sort in `filterBar` below.
            #if os(iOS)
            RandomPlayButton(size: .icon(dimension: 48, cornerRadius: 14, glyphSize: 18),
                              state: $randomState, action: playRandom)
            #else
            RandomPlayButton(size: .header, state: $randomState, action: playRandom)
            #endif
        }
    }

    private var searchField: some View {
        TagSearchField(
            tags: $searchTags,
            liveText: $searchText,
            placeholder: "Search \(title.lowercased())…",
            accent: accent,
            trailing: LibraryChrome.searchTrailing(count: filtered.count),
            field: "videos-search",
            focus: $focusedId
        )
    }

    /// **Two groups, not one** — see `HomeVideoFilterBar`'s own doc comment
    /// for why "Latest Added"/"Random" (an exclusive sort) and
    /// "Unwatched"/"Favorites" (independent filters) sit either side of a
    /// hairline divider rather than reading as one long row.
    ///
    /// **Phone: Sort becomes a dropdown, same as the poster-grid screens'
    /// `LibrarySortGenreDropdownBar`** — this screen has no genre concept, so
    /// there's only the one dropdown, but the reasoning is identical (a chip
    /// rail can't be scrolled and read at once on a narrow phone column).
    /// Unwatched/Favorites are only two independent toggles, not a long rail,
    /// so they stay plain chips beside it rather than folding into a menu.
    @ViewBuilder
    private var filterBar: some View {
        #if os(iOS)
        if DeviceClass.current == .phone {
            phoneFilterBar
        } else {
            filterChipRail
        }
        #else
        filterChipRail
        #endif
    }

    /// Scrolls, unlike `LibrarySortGenreDropdownBar`'s dropdown row — three
    /// controls (a Sort dropdown plus two independent toggle chips) don't fit
    /// an unconstrained `HStack` in a 362pt content column, and letting the
    /// row's own `HStack` squeeze them shrinks the dropdown's label to
    /// "Lat…" and wraps the chips' text onto a second line instead. A short
    /// horizontal scroll for two toggle chips isn't the "can't scroll and
    /// read at once" problem `LibrarySortGenreDropdownBar` exists to solve —
    /// there's only ever two of them, both fully legible at a glance.
    #if os(iOS)
    private var phoneFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    ForEach([Sort.latestAdded, .random], id: \.self) { option in
                        Button {
                            sort = option
                            if option == .random { randomSortNonce += 1 }
                        } label: {
                            if sort == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accent)
                        Text(sort.label)
                            .font(Typography.font(15, .heavy))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.45), lineWidth: 1))
                }
                LibraryFilterChip(label: "Unwatched", isOn: unwatchedOnly, action: { unwatchedOnly.toggle() }, accent: accent)
                LibraryFilterChip(label: "Favorites", isOn: favoritesOnly, action: { favoritesOnly.toggle() }, accent: accent)
            }
        }
    }
    #endif

    private var filterChipRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                #if os(iOS)
                Text("FILTER")
                    .font(Mono.font(13, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.4))
                #endif
                HomeVideoFilterBar(
                    accent: accent,
                    sort: $sort,
                    unwatchedOnly: $unwatchedOnly,
                    favoritesOnly: $favoritesOnly,
                    onSelectRandom: { randomSortNonce += 1 }
                )
            }
        }
    }

    private var loading: some View {
        LibraryLoadingState(message: "Loading \(title.lowercased())…", accent: accent)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 14) {
            // iPad only — see `MoviesLibraryView.postersSection`.
            #if os(iOS)
            HStack(alignment: .firstTextBaseline) {
                Text("\(title.uppercased()) · \(sort.label.uppercased())")
                    .font(Mono.font(15, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.5))
                Spacer()
                Text("Showing \(filtered.count) of \(items.count)")
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(Palette.text(0.4))
            }
            #endif
            if filtered.isEmpty {
                LibraryEmptyState(message: items.isEmpty ? "Nothing in this library yet."
                                                         : "Nothing matches this search.")
            }
            LazyVGrid(columns: Self.gridColumns, spacing: 26) {
                ForEach(filtered) { item in
                    HomeVideoCard(item: item,
                                  onSelect: { play(item) })
                        .focused($focusedId, equals: item.id)
                        .onAppear { seedFocusIfNeeded(item) }
                }
            }
        }
    }

    /// See `MoviesLibraryView.seedFocusIfNeeded`. `focusedId` doubles as the
    /// search field's focus here, so "nothing focused" is the only state this
    /// is allowed to override.
    private func seedFocusIfNeeded(_ item: MediaItem) {
        #if os(tvOS)
        guard !hasSeededFocus, item.id == filtered.first?.id else { return }
        hasSeededFocus = true
        if focusedId == nil { focusedId = item.id }
        #endif
    }

    #if os(tvOS)
    /// The camera roll — see `HomeVideoRollView`. Grouped by month for the
    /// dated order; a shuffle is one flat mosaic, since months would only be
    /// re-sorting what the user just asked to have scrambled.
    private func roll(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if filtered.isEmpty {
                LibraryEmptyState(message: items.isEmpty ? "Nothing in this library yet."
                                                         : "Nothing matches this search.")
            }
            HomeVideoRollView(
                items: filtered,
                grouped: sort != .random,
                width: max(320, width),
                accent: accent,
                focus: $focusedId,
                onPlay: { item, queue in play(item, queue: queue) },
                onFirstCardAppear: { item in
                    guard !hasSeededFocus else { return }
                    hasSeededFocus = true
                    if focusedId == nil { focusedId = item.id }
                }
            )
        }
    }
    #endif

    // MARK: - Stand-in artwork

    /// **A tap plays that video and queues the rest of the list behind it.**
    ///
    /// This is the plainest case of what a playlist is for in this app: home
    /// videos have no detail screen, so a card *is* a play button, and what
    /// the queue should be is simply the shelf you were looking at. The queue
    /// is `filtered` — the visible, searched, sorted list, in the order it is
    /// on screen — so pressing Next in the player gives you the card that was
    /// to the right of the one you tapped, and the last one ends the queue
    /// rather than looping somewhere unexpected.
    ///
    /// Built from the rows the grid already holds, with no fetch in between:
    /// the point of these cards is that a tap plays immediately, and the
    /// resume position and tags a `PlayableItem` needs already came back with
    /// the list.
    private func play(_ item: MediaItem, queue: [MediaItem]? = nil) {
        // The file name is meaningless for these, so the player chrome leaves
        // it off — same reasoning as the card showing no title. The roll
        // passes its own order (by month, or the "On this day" strip), which
        // is what is on screen there.
        guard let request = appState.listQueueRequest(queue ?? filtered, startingAt: item.id,
                                                      hidesTitle: true) else { return }
        appState.requestPlayback(request)
    }

    /// Unlike a tap, Random reaches past the visible list to the whole
    /// library — a shuffle limited to the current page isn't a shuffle. Every
    /// press builds a fresh order.
    private func playRandom() {
        guard randomState != .loading else { return }
        randomState = .loading
        Task {
            let request = await appState.randomQueue(for: .homeVideos(category))
            guard let request else { randomState = .empty; return }
            randomState = .idle
            appState.requestPlayback(request)
        }
    }
}
