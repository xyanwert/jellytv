import SwiftUI
import UIKit
import JellyTVKit

/// SCENES — swipe through thumbnails of the film, tap one to go there, and
/// keep going past the end to start the next episode.
///
/// **It never scrubs the video to build these.** Every thumbnail is cut out of
/// a Jellyfin trickplay sprite sheet (see `TrickplayClient`), so a page costs
/// one sheet download and some bitmap arithmetic rather than six
/// frame-accurate seeks. The live player is paused and untouched throughout.
///
/// Ported as *behaviour* from `/Users/xyan/code/jelly-tv-ios`'s
/// `Core/Components/SpreadView.swift`, which arrived at this shape over a
/// dozen commits. Two of its structural decisions are load-bearing and are
/// kept deliberately:
///
/// - **Paging is a `TabView(.page)`, not a hand-rolled drag.** v1 shipped a
///   `DragGesture` carousel first and replaced it (`4c5b8b3`) because the
///   commit-versus-settle race made the outgoing page visibly slide back in.
///   The native pager also means a fast swiper can't outrun it: a drag has to
///   physically complete to land a page, unlike a button that can be mashed.
/// - **Past the last page is a whole-page "Next video" card**, not a small
///   button — the same idea as the transport row's circles, that the thing you
///   reach for should be impossible to miss.
///
/// What v1 had and this does not: a slideshow mode that auto-advanced the
/// pages every 3/5/10s, and a second hidden `AVPlayer` that scrubbed for
/// thumbnails when a server had no trickplay data. An item without trickplay
/// gets told so plainly instead.
struct PlayerScenesPanel: View {
    let controller: PlayerController
    let accent: Color
    let onDismiss: () -> Void

    /// One cell. `image` stays nil until its slice arrives.
    private struct Thumb: Identifiable, Equatable {
        let id: Int
        let time: Double
        var image: UIImage?
    }

    /// What occupies one slot in the grid. The navigation tiles sit *in* the
    /// grid rather than on a page of their own, so the last page reads
    /// "…, 21:02, 21:22, [Next video ›]" — the button lands exactly where the
    /// next thumbnail would have been if the film were longer.
    private enum Tile: Identifiable, Equatable {
        case thumb(index: Int, time: Double)
        case nextVideo
        case previousVideo

        var id: String {
            switch self {
            case .thumb(let index, _): return "t\(index)"
            case .nextVideo: return "next"
            case .previousVideo: return "prev"
            }
        }
    }

    /// Why the panel is closing, which decides whether playback resumes.
    private enum DismissReason { case close, seek, navigate }

    /// Where the panel opened. Paging is measured from here, not from a clock
    /// that would otherwise still be moving.
    @State private var baseTime: Double = 0
    @State private var wasPlaying = false
    @State private var page = 0
    /// Pages keep their thumbnails once loaded, so swiping back is instant and
    /// costs no fetches — which is most of what makes fast swiping cheap.
    @State private var pages: [Int: [Thumb]] = [:]
    @State private var trickplay: (widthKey: String, info: JellyfinAPI.TrickplayInfo)?
    @State private var resolved = false
    @State private var dismissReason: DismissReason = .close
    /// Bumped on every page change and on dismissal. A slice that comes back
    /// from the network after its page is gone checks this and drops itself
    /// rather than landing in whatever cell now holds that index.
    @State private var loadGeneration = 0

    private enum Layout {
        static let columns = 3
        static let rows = 2
        static var cells: Int { columns * rows }
        static let spacing: CGFloat = 14
        static let radius: CGFloat = 18
        static let inset: CGFloat = 44
        /// The footer's targets. Taller than v1's 56pt: this is the control a
        /// non-technical viewer uses to travel, and it should be as
        /// unmissable as the transport circles behind it.
        static let footerHeight: CGFloat = 76
    }

    // MARK: - Paging maths

    /// How much film one page spans. Near where you paused the cells are ten
    /// seconds apart — the "what did she just say" case. Page outward and the
    /// step widens, so reaching something an hour away isn't twenty swipes.
    private func window(forPage p: Int) -> Double {
        switch abs(p) {
        case 0...3: return 60
        case 4...8: return 300
        default: return 360
        }
    }

    /// A page's span, chained from page 0 so the tiers above don't leave gaps
    /// or overlaps at the boundaries where the step size changes.
    private func span(forPage p: Int) -> (start: Double, end: Double) {
        if p == 0 { return (baseTime, baseTime + window(forPage: 0)) }
        if p > 0 {
            let previous = span(forPage: p - 1)
            return (previous.end, previous.end + window(forPage: p))
        }
        let next = span(forPage: p + 1)
        return (next.start - window(forPage: p), next.start)
    }

    /// The six sample points for a page — the middle of each slice, not its
    /// edge, since a frame sitting on a cut is the least representative one.
    private func sampleTimes(forPage p: Int) -> [Double] {
        let s = span(forPage: p)
        let step = (s.end - s.start) / Double(Layout.cells)
        return (0..<Layout.cells).map { s.start + (Double($0) + 0.5) * step }
    }

    /// **Only the moments that actually exist in this film.** Everything past
    /// the runtime (or before zero) is dropped here rather than rendered as a
    /// cell that can never load — a spinner that spins forever is worse than
    /// an absent tile, and that was the whole bug this replaced.
    private func validTimes(forPage p: Int) -> [Double] {
        sampleTimes(forPage: p).filter { $0 >= 0 && $0 <= controller.duration }
    }

    /// The pages that hold at least one real moment.
    private var contentPages: ClosedRange<Int> {
        guard controller.duration > 0 else { return 0...0 }
        var forward = 0
        while forward < 100, !validTimes(forPage: forward + 1).isEmpty { forward += 1 }
        var backward = 0
        while backward > -100, !validTimes(forPage: backward - 1).isEmpty { backward -= 1 }
        return backward...forward
    }

    /// Content pages, plus one spill page **only** when the last page has no
    /// free slot for the Next-video tile. Usually there is one, and no extra
    /// page is created at all.
    private var pageRange: ClosedRange<Int> {
        let content = contentPages
        guard showsNextTile, validTimes(forPage: content.upperBound).count >= Layout.cells else {
            return content
        }
        return content.lowerBound...(content.upperBound + 1)
    }

    private var showsNextTile: Bool { controller.hasNext }
    private var showsPreviousTile: Bool { controller.hasPrevious }

    /// What a page renders: its real thumbnails, with a navigation tile
    /// appended (or prepended) on the pages that touch the ends of the film.
    private func tiles(forPage p: Int) -> [Tile] {
        let content = contentPages
        if p > content.upperBound { return showsNextTile ? [.nextVideo] : [] }

        let times = validTimes(forPage: p)
        let all = sampleTimes(forPage: p)
        var result: [Tile] = []

        // Leading edge: the film starts partway into this page.
        if showsPreviousTile, p == content.lowerBound, let first = times.first,
           first != all.first {
            result.append(.previousVideo)
        }
        result += times.enumerated().map { Tile.thumb(index: $0.offset, time: $0.element) }
        // Trailing edge: the film ends partway through this page, so the
        // button takes the slot the next thumbnail would have had.
        if showsNextTile, p == content.upperBound, result.count < Layout.cells {
            result.append(.nextVideo)
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Opaque: the panel replaces the chrome rather than floating over
            // it, and nothing underneath is moving — the player is paused.
            Color.black.opacity(0.94).ignoresSafeArea()

            VStack(spacing: 22) {
                header
                pager
                footer
            }
            .padding(Layout.inset)
        }
        .task { await open() }
        .onDisappear { close() }
        .onChange(of: page) { _, _ in Task { await loadPage(page) } }
    }

    // MARK: - Header

    /// BACK top-left, the range dead-centre, the page counter trailing.
    ///
    /// v1 used a quiet icon-only ✕ here, having deliberately toned it down —
    /// but everywhere else in *both* apps, including this app's own
    /// `PlayerTopBar`, leaving a screen is a loud labelled pill. Consistency
    /// with the chrome the user just came from wins over v1's local choice.
    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            backButton
            Spacer(minLength: 0)
            pageCounter
        }
        .overlay { rangeReadout }
    }

    private var backButton: some View {
        Button {
            dismissReason = .close
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                Text("BACK")
                    .font(Typography.font(20, .heavy))
            }
            .foregroundStyle(.white)
            .padding(.leading, 20)
            .padding(.trailing, 26)
            .padding(.vertical, 14)
            .background(accent, in: Capsule())
            .shadow(color: accent.opacity(0.4), radius: 20, y: 8)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 30))
    }

    @ViewBuilder
    private var rangeReadout: some View {
        // The page's *real* extent — first to last moment it actually holds,
        // not the arithmetic span, which can run past the end of the film.
        if let first = validTimes(forPage: page).first,
           let last = validTimes(forPage: page).last {
            VStack(spacing: 4) {
                Text("SCENES")
                    .font(Mono.font(14, .bold))
                    .tracking(2.4)
                    .foregroundStyle(accent)
                // A final page can hold a single moment, where "21:17 → 21:17"
                // reads as a mistake. Show the one time.
                Text(first == last
                     ? formatPlayerClock(first, matching: controller.duration)
                     : "\(formatPlayerClock(first, matching: controller.duration))  →  \(formatPlayerClock(last, matching: controller.duration))")
                    .font(Mono.font(26, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text(0.92))
            }
            .allowsHitTesting(false)
        }
    }

    private var pageCounter: some View {
        Text("\(page - pageRange.lowerBound + 1) / \(pageRange.count)")
            .font(Mono.font(15, .bold))
            .monospacedDigit()
            .foregroundStyle(Palette.text(0.6))
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Palette.text(0.07), in: Capsule())
    }

    // MARK: - Pager

    /// `TabView(.page)` rather than a `DragGesture`: v1 tried the hand-rolled
    /// version first and the commit-vs-settle race made the outgoing page
    /// slide back in (`4c5b8b3`). Its dot indicator is off — the header's
    /// range readout says where you are far better than six dots would.
    @ViewBuilder
    private var pager: some View {
        Group {
            #if os(iOS)
            TabView(selection: $page) {
                ForEach(Array(pageRange), id: \.self) { p in
                    pageContent(p)
                        .tag(p)
                        .contentShape(Rectangle())
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            #else
            // **No `TabView` on tvOS.** `.page` style is iOS-only, and a
            // `TabView` without it paints a tab bar across the top of the
            // panel. There is no swipe to support here anyway — a Siri Remote
            // travels by focus — so the current page is rendered directly and
            // PREV/NEXT do the paging.
            pageContent(page)
                .transition(.opacity)
            #endif
        }
        // Reset the pager if the item changes underneath us rather than
        // showing one film's thumbnails over another's.
        .id(controller.currentItem?.id ?? "none")
    }

    @ViewBuilder
    private func pageContent(_ p: Int) -> some View {
        if resolved && trickplay == nil {
            unavailable
        } else {
            grid(tiles(forPage: p))
        }
    }

    /// Only as many rows as there are tiles. A last page holding two
    /// thumbnails and a Next button is one row of three — not one row plus a
    /// second row of nothing.
    private func grid(_ tiles: [Tile]) -> some View {
        let rows = max(1, Int(ceil(Double(tiles.count) / Double(Layout.columns))))
        return VStack(spacing: Layout.spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: Layout.spacing) {
                    ForEach(0..<Layout.columns, id: \.self) { column in
                        let index = row * Layout.columns + column
                        if index < tiles.count {
                            tileView(tiles[index])
                        } else {
                            // Invisible, not a dark box: it exists only to keep
                            // the remaining tiles at one-third width.
                            spacerCell
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func tileView(_ tile: Tile) -> some View {
        switch tile {
        case .thumb(let index, let time):
            cell(thumb: pages[page]?.first { $0.time == time } ?? Thumb(id: index, time: time, image: nil))
        case .nextVideo:
            navigationTile(.next)
        case .previousVideo:
            navigationTile(.previous)
        }
    }

    private var spacerCell: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }

    private func cell(thumb: Thumb) -> some View {
        Button {
            Task { await go(to: thumb.time) }
        } label: {
            // The size comes from this `Rectangle`, never from the loaded
            // image — otherwise a cell resizes the instant its thumbnail
            // arrives and the grid twitches as they land one by one.
            Rectangle()
                .fill(Palette.text(0.06))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if let image = thumb.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ProgressView().tint(Palette.text(0.4))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(formatPlayerClock(thumb.time, matching: controller.duration))
                        .font(Mono.font(15, .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(10)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
                        .stroke(Palette.text(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(CardFocusStyle(glow: accent, scale: 1.06))
        .accessibilityLabel("Jump to \(formatPlayerClock(thumb.time, matching: controller.duration))")
    }

    /// Said plainly rather than papered over: the server has no scene data for
    /// this item, and nothing the app could substitute is worth the wait.
    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Palette.text(0.3))
            Text("No scenes for this one")
                .font(Typography.font(28, .bold))
                .foregroundStyle(Palette.text(0.85))
            Text("The server hasn't generated preview images for this item.")
                .font(Typography.font(19, .medium))
                .foregroundStyle(Palette.text(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation tiles

    private enum Edge { case previous, next }

    /// A grid cell that starts the next (or previous) video. Same footprint as
    /// a thumbnail so the row stays even, accent-filled so it can't be mistaken
    /// for one — this is the only tile in the grid that leaves the film.
    private func navigationTile(_ edge: Edge) -> some View {
        Button {
            Task { await navigate(edge) }
        } label: {
            Rectangle()
                .fill(accent)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: edge == .next ? "forward.end.fill" : "backward.end.fill")
                            .font(.system(size: 44, weight: .black))
                        Text(edge == .next ? "Next video" : "Previous video")
                            .font(Typography.font(21, .heavy))
                    }
                    .foregroundStyle(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous))
                .shadow(color: accent.opacity(0.4), radius: 16, y: 8)
        }
        .buttonStyle(CardFocusStyle(glow: accent, scale: 1.06))
        .accessibilityLabel(edge == .next ? "Play the next video" : "Play the previous video")
    }

    // MARK: - Footer

    /// Bottom-centre, labelled, and big. The same reasoning as the transport
    /// circles: a control a non-technical viewer travels with should be
    /// unmissable, and an arrow on its own is not a word.
    private var footer: some View {
        HStack(spacing: 16) {
            footerButton(icon: "chevron.left", label: "PREV", leading: true,
                         enabled: page > pageRange.lowerBound) { page -= 1 }
            footerButton(icon: "chevron.right", label: "NEXT", leading: false,
                         enabled: page < pageRange.upperBound) { page += 1 }
        }
    }

    private func footerButton(icon: String, label: String, leading: Bool,
                              enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { action() }
        } label: {
            HStack(spacing: 12) {
                if leading {
                    Image(systemName: icon).font(.system(size: 22, weight: .black))
                }
                Text(label)
                    .font(Typography.font(22, .heavy))
                    .tracking(0.6)
                if !leading {
                    Image(systemName: icon).font(.system(size: 22, weight: .black))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 34)
            .frame(height: Layout.footerHeight)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(Palette.text(0.18), lineWidth: 1))
            // v1's own button style never read `isEnabled`, so a disabled
            // page control looked identical to a live one. Dim it here.
            .opacity(enabled ? 1 : 0.32)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: Layout.footerHeight / 2))
        .disabled(!enabled)
    }

    // MARK: - Lifecycle

    private func open() async {
        baseTime = controller.currentTime
        wasPlaying = controller.isPlaying
        if wasPlaying { controller.pause() }
        trickplay = await controller.resolveTrickplay()
        resolved = true
        await loadPage(page)
    }

    /// Hand playback back exactly as it was found — except when leaving to
    /// play a different item, where the queue advance starts playback itself
    /// and calling `play()` here would race the item swap.
    private func close() {
        loadGeneration &+= 1
        if wasPlaying && dismissReason != .navigate { controller.play() }
    }

    private func loadPage(_ p: Int) async {
        guard let trickplay else { return }
        let times = validTimes(forPage: p)
        guard !times.isEmpty else { return }
        // Already loaded: swiping back costs nothing, which is most of what
        // keeps a fast swiper from generating a pile of redundant fetches.
        if let existing = pages[p], existing.count == times.count,
           existing.allSatisfy({ $0.image != nil }) { return }

        loadGeneration &+= 1
        let generation = loadGeneration

        if pages[p]?.count != times.count {
            pages[p] = times.enumerated().map { Thumb(id: $0.offset, time: $0.element, image: nil) }
        }

        for (index, time) in times.enumerated() {
            if pages[p]?[index].image != nil { continue }
            let image = await controller.trickplayThumbnail(
                at: time, widthKey: trickplay.widthKey, info: trickplay.info
            )
            // The page may be long gone by now — drop the slice rather than
            // writing it into whatever occupies this index today.
            guard generation == loadGeneration else { return }
            if pages[p] != nil, index < pages[p]!.count { pages[p]![index].image = image }
        }
    }

    /// `seek(to:)`, not `jump(to:)`: a tapped thumbnail already knows its exact
    /// target and isn't a control anyone mashes, so it skips the transport
    /// row's coalescing gate.
    private func go(to time: Double) async {
        dismissReason = .seek
        await controller.seek(to: time)
        onDismiss()
    }

    /// Queue navigation goes through the controller's own mash gate, so a
    /// hammered edge card can't stack item swaps.
    private func navigate(_ edge: Edge) async {
        dismissReason = .navigate
        onDismiss()
        if edge == .next {
            await controller.next()
        } else {
            await controller.previous()
        }
    }
}
