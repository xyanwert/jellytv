import SwiftUI
import JellyTVKit

/// Discover — recommended films and television from public sources, and the way into
/// downloading them.
///
/// Built to the same shape as the five library screens (`LibraryHeaderLayout`, a chip row,
/// a poster grid, `FilterChipStyle`) because it *is* a browse screen and inventing a
/// second browsing language for it would be the bug. What differs is what a poster means:
/// nothing here is yours yet, so every card can say whether you already own it and
/// selecting one leads to a download decision rather than to playback.
///
/// **The state this screen exists to get right is "nothing to show".** Both anime sources
/// are down as often as not — AniList's API is disabled outright, MyAnimeList goes dark
/// for minutes at a time — so an empty grid is the *common* case for those shelves, and
/// rendering it as a blank would make a working feature look broken forever. Every empty
/// outcome here says which of the three it is: still loading, the source is unreachable
/// (and why), or the source answered and had nothing.
struct DiscoverView: View {
    /// Same two the library screens take: the rail lives *inside* each screen, next to
    /// that screen's own backdrop, so the backdrop shows through behind it.
    var isLibrariesOpen: Bool = false
    var onSelectRail: (RailTarget) -> Void = { _ in }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    /// Owned by `RootView`, not by this screen: the download centre needs the same
    /// store, and a job started here has to still be there when Discover is dismissed.
    @ObservedObject var store: DiscoverStore

    /// Opened when a poster is selected — the detail page and its download decision.
    /// `RT_SHOW_DISCOVER=detail` / `JT_SHOW_DISCOVER=detail` opens straight onto the
    /// fixture title whose download is mid-flight (`DiscoverStore.demo`), so the
    /// progress panel can be looked at without a live server. Inert unless set.
    @State private var presentedRef: String? = {
        let env = ProcessInfo.processInfo.environment
        let mode = env["RT_SHOW_DISCOVER"] ?? env["JT_SHOW_DISCOVER"]
        return DiscoverFixture.opensDetail(mode) ? DiscoverStore.demoDetailRef : nil
    }()

    #if os(tvOS)
    @FocusState private var focused: Focus?
    @State private var lastFocusedRef: String?

    private enum Focus: Hashable {
        case chip(String)
        case card(String)
        case search
    }
    #else
    @FocusState private var searchFocus: SearchField?
    private enum SearchField: Hashable { case search }
    #endif

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                NavRail(destination: .discover, isLibrariesOpen: isLibrariesOpen,
                        onSelect: onSelectRail)
                content
            }
            // **The backdrop is a background, not a ZStack sibling.** An image set to
            // `.fill` inside a fixed height has an *ideal width* of that height times
            // its own aspect ratio — 675pt for a 16:9 still at 380 — and a ZStack takes
            // the width of its widest child. So on a 402pt phone the backdrop made the
            // entire screen 675pt wide: the header, the chip row and half the tab bar
            // sat off both edges, measured rather than guessed (`axe describe-ui` put
            // the content at x = -119). A background is sized by the view it sits
            // behind and cannot do that, and it draws in the same place.
            .background(alignment: .top) { backdropLayer }
            // Off the focus pool while the detail is up — `.allowsHitTesting(false)` alone
            // leaves the grid and chips reachable to the tvOS focus engine under it.
            .disabled(presentedRef != nil)
            if let ref = presentedRef {
                DiscoverDetailView(ref: ref, store: store, onClose: { presentedRef = nil })
                    .zIndex(10)
            }
        }
        .background(Palette.background)
        .task { await store.loadCategories() }
        // Health goes stale — a source down at launch may be up now. Checked when the
        // screen reappears rather than on a timer, because these are somebody else's
        // servers and we are a guest on them.
        .onAppear { Task { await store.refreshSourceHealth() } }
        .discoverActionAlert(store)
    }

    // MARK: - Layout

    private var content: some View {
        VStack(alignment: .leading, spacing: DeviceClass.current == .phone ? 16 : 22) {
            header
            // `LibraryHeaderLayout` drops the search field on a phone, where a title and
            // a field cannot share a row — but **Discover without search is unusable
            // there**: its shelves are Trending, Popular and Top Rated, so a specific
            // film simply cannot be reached, and finding a specific film is the whole
            // point of the screen. It gets its own row under the header instead.
            if DeviceClass.current == .phone { searchField }
            if !appState.hasMovieSource { noFilmsNote }
            categoryRow
            grid
        }
        .padding(.horizontal, DiscoverMetrics.pagePadding)
        .padding(.top, DiscoverMetrics.topPadding)
    }

    private var header: some View {
        LibraryHeaderLayout {
            DiscoverPageHeader(
                eyebrow: "DISCOVER",
                title: store.isSearchMode ? "Results" : (shelfTitle ?? "Discover"),
                count: countLabel
            )
        } search: {
            searchField
        } actions: {
            EmptyView()
        }
    }

    /// The capabilities document says whether films are on at all. Without a TMDB key
    /// Discover is television and anime only, and a shelf row with no film shelf on it
    /// would otherwise read as a server short of films rather than one short of a key.
    private var noFilmsNote: some View {
        Label("Films need a TMDB key on the server — television and anime still work.",
              systemImage: "key.fill")
            .font(Typography.font(DiscoverMetrics.body - 3, .medium))
            .foregroundStyle(Palette.text(0.5))
    }

    @ViewBuilder
    private var searchField: some View {
        #if os(tvOS)
        AppTextField(
            placeholder: "Search films and TV",
            text: $store.searchText,
            accent: theme.secondaryAccent,
            field: Focus.search,
            focus: $focused
        )
        .onChange(of: store.searchText) { _, _ in store.searchTextChanged() }
        #else
        // Bound to the store, not mirrored from a local copy: the store outlives this
        // view, and a local copy came back empty over a grid still showing results.
        TextField("Search films and TV", text: $store.searchText)
            .textFieldStyle(.plain)
            .font(Typography.font(19, .semibold))
            .foregroundStyle(Palette.text(0.9))
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.text(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.secondaryAccent.opacity(0.5), lineWidth: 1.5)
                    )
            )
            .focused($searchFocus, equals: .search)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .onChange(of: store.searchText) { _, _ in store.searchTextChanged() }
        #endif
    }

    /// The shelf chips. A shelf whose source is down stays in the row rather than being
    /// hidden — hiding it would make the feature look like it never had anime at all,
    /// when the truth is that a source is temporarily unreachable and will come back.
    @ViewBuilder
    private var categoryRow: some View {
        if !store.categories.isEmpty && !store.isSearchMode {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.categories) { category in
                        chip(for: category)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
            }
            .horizontalEdgeFade()
            #if os(tvOS)
            // Without this, Left/Right at the row's edge lets the focus engine search
            // the whole screen and jump somewhere unrelated — reads as the selection
            // vanishing. Scoped to this one row, never the whole bar.
            .focusSection()
            #endif
        }
    }

    @ViewBuilder
    private func chip(for category: YsojAPI.DiscoverCategory) -> some View {
        let usable = store.sources.first { $0.id == category.sourceId }?.isUsable ?? true
        LibraryFilterChip(
            label: category.title,
            isOn: store.selectedCategoryId == category.id,
            action: { store.selectCategory(category.id) },
            accent: theme.accent,
            // A down source is marked, not removed. The slash tells you before you press
            // that this shelf has nothing today.
            systemImage: usable ? nil : "exclamationmark.triangle.fill"
        )
        .opacity(usable ? 1 : 0.55)
        #if os(tvOS)
        .focused($focused, equals: .chip(category.id))
        #endif
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        switch effectiveState {
        case .idle, .loading:
            // `.idle` is "nothing has been asked yet" — still a wait, never a bare grid.
            LibraryLoadingState(message: "Looking…", accent: theme.accent)
        case .unavailable(let source, let reason):
            // The state this screen was built for: name the source, quote the server's
            // own reason, and say plainly that nothing is wrong with the user's server.
            LibraryEmptyState(
                message: "\(source) isn't responding",
                hint: "This shelf's source is unavailable right now — nothing is wrong with your server. Other shelves still work.",
                systemImage: "antenna.radiowaves.left.and.right.slash",
                detail: reason
            )
        case .empty:
            LibraryEmptyState(
                message: store.isSearchMode ? "Nothing found" : "Nothing here",
                hint: store.isSearchMode
                    ? "No films or television matched that search."
                    : "This shelf came back empty."
            )
        case .failed(let message):
            LibraryEmptyState(message: "Couldn't load", hint: message,
                              systemImage: "exclamationmark.triangle")
        case .loaded:
            posterGrid
        }
    }

    /// Effective, not raw: in search mode the shelf's state says nothing useful.
    private var effectiveState: DiscoverStore.ShelfState {
        guard store.isSearchMode else { return store.shelfState }
        if store.isSearching { return .loading }
        return store.searchResults.isEmpty ? .empty : .loaded
    }

    private var posterGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: rowSpacing) {
                ForEach(store.visibleItems) { item in
                    DiscoverPosterCard(item: item) {
                        #if os(tvOS)
                        lastFocusedRef = item.ref
                        #endif
                        presentedRef = item.ref
                    }
                    #if os(tvOS)
                    .focused($focused, equals: .card(item.ref))
                    .zoomOrigin(focused == .card(item.ref))
                    #endif
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 60)
            // The phone's tab bar and TV bar float over the grid; without this the last
            // row of posters sits under them and a tap on one opens the remote.
            .phoneTabBarClearance()
        }
    }

    // MARK: - Backdrop

    /// The focused item's own backdrop, the same atmospheric treatment the library
    /// screens use — drawn behind everything, pinned to the top.
    @ViewBuilder
    private var backdropLayer: some View {
        if let url = focusedBackdropURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.clear
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: backdropHeight)
            .clipped()
            // Pre-darken toward the page's own base colour before fading, so the image
            // dissolves into the page instead of hard-cutting — `Palette.background` is
            // a gradient, not a colour, so the scrims name the base tone directly.
            .overlay(
                LinearGradient(
                    colors: [Palette.pageBase.opacity(0.2), Palette.pageBase.opacity(0.85),
                             Palette.pageBase],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // Left-darken, for text legibility over busy art.
            .overlay(
                LinearGradient(colors: [Palette.pageBase, .clear],
                               startPoint: .leading, endPoint: .trailing)
                // `maxWidth`, not a fixed 500: on a 393pt phone a 500pt scrim is wider
                // than the screen it is darkening.
                .frame(maxWidth: 500), alignment: .leading
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.45), value: url)
        }
    }

    private var focusedBackdropURL: URL? {
        #if os(tvOS)
        if case .card(let ref) = focused,
           let item = store.visibleItems.first(where: { $0.ref == ref }) {
            return item.backdropURL ?? item.posterURL
        }
        if let lastFocusedRef,
           let item = store.visibleItems.first(where: { $0.ref == lastFocusedRef }) {
            return item.backdropURL ?? item.posterURL
        }
        #endif
        return store.visibleItems.first?.backdropURL
    }

    // MARK: - Chrome sizing

    private var shelfTitle: String? {
        store.categories.first { $0.id == store.selectedCategoryId }?.title
    }

    private var countLabel: String? {
        let count = store.visibleItems.count
        guard count > 0 else { return nil }
        return LibraryChrome.countLabel(shown: count, total: count, noun: "titles")
    }

    #if os(tvOS)
    private var backdropHeight: CGFloat { 780 }
    private var rowSpacing: CGFloat { 40 }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 30), count: 6)
    }
    #else
    private var backdropHeight: CGFloat { DeviceClass.current == .phone ? 380 : 560 }
    private var rowSpacing: CGFloat { DeviceClass.current == .phone ? 18 : 26 }
    /// **Adaptive, not a fixed count of `.flexible()` columns**, which is what the five
    /// library screens use and the reason theirs lay out correctly on a phone.
    ///
    /// A `.flexible()` grid's *ideal* width is the sum of its children's ideal widths,
    /// and a poster card's ideal width is its caption on one line — so a shelf of
    /// long titles ("Spider-Man: Brand New Day") made the grid wider than the phone,
    /// which made the whole screen wider, which pushed the header and half the tab bar
    /// off both edges. An adaptive column's ideal is its `minimum`, so the grid asks
    /// for what it can fit rather than what its contents would like.
    private var columns: [GridItem] {
        let phone = DeviceClass.current == .phone
        return [GridItem(.adaptive(minimum: phone ? 104 : 150,
                                   maximum: phone ? 170 : 220),
                         spacing: phone ? 12 : 22)]
    }
    #endif
}

/// A Discover poster.
///
/// Deliberately not `LibraryPosterCard`: these images are third-party URLs rather than
/// Jellyfin's own endpoints (so plain `AsyncImage`, per the external-images rule), and a
/// card here has to answer a question a library card never does — **do I already have
/// this?** Offering to download something already on the server is the fastest way to
/// make Discover feel broken, so the answer is on the card, not two screens deep.
struct DiscoverPosterCard: View {
    let item: YsojAPI.DiscoverItem
    var onSelect: () -> Void = {}

    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                poster
                #if !os(tvOS)
                caption
                #endif
            }
        }
        #if os(tvOS)
        .buttonStyle(CardFocusStyle(glow: theme.accent))
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(accessibilityLabel)
    }

    private var poster: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fallbackGradient)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    if let url = item.posterURL {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            // The item's own title while the art loads — a poster-shaped
                            // hole with nothing in it reads as a failure.
                            Text(item.title)
                                .font(Typography.font(15, .bold))
                                .foregroundStyle(Palette.text(0.7))
                                .multilineTextAlignment(.center)
                                .padding(10)
                        }
                    } else {
                        Text(item.title)
                            .font(Typography.font(15, .bold))
                            .foregroundStyle(Palette.text(0.75))
                            .multilineTextAlignment(.center)
                            .padding(10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if item.alreadyOwned {
                ownedBadge
            }
        }
    }

    /// "You have this." A tick in the accent rather than a word, because it sits on forty
    /// posters at once and a label on each would read as a spreadsheet.
    private var ownedBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(Color.black)
            .frame(width: 26, height: 26)
            .background(Circle().fill(theme.accent))
            .padding(8)
            .accessibilityHidden(true)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(Typography.font(DeviceClass.current == .phone ? 13 : 15, .bold))
                .foregroundStyle(Palette.text(0.9))
                .lineLimit(2)
            HStack(spacing: 6) {
                if let year = item.year {
                    Text(String(year))
                }
                if let rating = item.rating {
                    Text("★ " + String(format: "%.1f", rating))
                }
            }
            .font(Mono.font(DeviceClass.current == .phone ? 10 : 12, .medium))
            .foregroundStyle(Palette.text(0.4))
        }
    }

    /// A deterministic per-title gradient so a poster-less row is still distinguishable
    /// from its neighbours, the same trick `CastPortrait` uses for a missing headshot.
    private var fallbackGradient: LinearGradient {
        let hue = Double(abs(item.ref.hashValue) % 360) / 360.0
        return LinearGradient(
            colors: [Color(hue: hue, saturation: 0.34, brightness: 0.34),
                     Color(hue: hue, saturation: 0.28, brightness: 0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var accessibilityLabel: String {
        var parts = [item.title]
        if let year = item.year { parts.append(String(year)) }
        if item.alreadyOwned { parts.append("already in your library") }
        return parts.joined(separator: ", ")
    }
}
