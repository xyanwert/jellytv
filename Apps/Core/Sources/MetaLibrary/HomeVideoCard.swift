import SwiftUI
import JellyTVKit

/// A card for one home video.
///
/// **Everything about it is a consequence of home videos having no
/// metadata.** They carry no poster, no series or season, and file names that
/// are usually a camera's serial gibberish (`f1147594904`,
/// `0C5F6BEE-0AF4-472B-A046-A64AB3B374A2`). So the title is **deliberately not
/// shown**: printing a UUID under every card is noise dressed as information.
/// What is left that means anything — when it was shot, how long it runs, the
/// user's tags — sits inside the thumbnail, over the corners.
///
/// **Under the remote the card plays the video's own frames.** Jellyfin has
/// already baked a trickplay sheet (a frame every 10s) for nearly every one
/// of these, so a focused card pages through up to eight of them with a
/// crossfade and a thin line showing where in the video each frame sits —
/// one sheet download, no video decode, no scrubbing. Unfocused cards stay
/// still, so a wall of them costs what one does.
///
/// Two shapes: the tvOS mosaic hands each card its exact `size` (portrait
/// phone clips stand tall beside landscape ones); the iPad grid leaves `size`
/// nil and the card fills its column at 16:9.
struct HomeVideoCard: View {
    let item: MediaItem
    /// The tile's exact size, from the mosaic; nil fills the width at 16:9.
    var size: CGSize? = nil
    /// Whether the remote is on this card — starts the frame slideshow.
    var live: Bool = false
    /// Small caption in the corner ("Dec 18, 2023"); the roll passes the date.
    var caption: String? = nil
    /// A mono badge top-left ("3 YEARS AGO").
    var badge: String? = nil
    var onSelect: () -> Void = {}

    @EnvironmentObject private var appState: AppState
    @State private var loaded: UIImage?
    @State private var frames: [Frame] = []
    @State private var liveSince = Date()

    private struct Frame: Equatable {
        let seconds: Double
        let image: UIImage
    }

    private var primaryURL: URL? {
        guard let image = item.image, image.hasPrefix("http") else { return nil }
        return URL(string: image)
    }

    var body: some View {
        Button(action: onSelect) {
            // **The card's size comes from this empty shape, never from the
            // picture.** A `.fit` image carries its own aspect ratio, and when
            // the artwork sits directly in the stack the stack adopts it — a
            // portrait thumbnail then stretched its cell into a tall tile and
            // broke the row. Sizing nothing first and hanging everything off it
            // as overlays is the same order `LibraryPosterCard` uses.
            tile
                .overlay { artwork }
                // Only as much scrim as the corner text needs: the picture is
                // the whole content of the card, so darkening all of it to
                // float a label would be self-defeating.
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                   startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) { overlays }
                .overlay(alignment: .topLeading) { badgeView }
                .overlay(alignment: .bottom) { if live, !frames.isEmpty { progressLine } }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Palette.text(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(CardFocusStyle(glow: Color(item.artwork.top), scale: 1.06))
        // The card shows no title, so the one place the name still exists is
        // here — a screen reader gets something better than "button".
        .accessibilityLabel(accessibilityText)
        .task(id: primaryURL) {
            guard let url = primaryURL else { loaded = nil; return }
            loaded = await LetterboxTrimmer.shared.image(for: url)
        }
        .onChange(of: live, initial: true) { _, isLive in
            if isLive { liveSince = Date() }
        }
        .task(id: live) {
            guard live, frames.isEmpty else { return }
            await loadFrames()
        }
    }

    @ViewBuilder private var tile: some View {
        if let size {
            Color.clear.frame(width: size.width, height: size.height)
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
        }
    }

    // MARK: - Picture

    /// The slideshow while focused and frames are in hand; otherwise
    /// Jellyfin's own thumbnail with any baked-in black bars trimmed off, or
    /// the deterministic gradient when the item has none — a legitimate final
    /// state, not a placeholder.
    ///
    /// The gradient also covers a case peculiar to these libraries: Jellyfin
    /// advertises `ImageTags.Primary` for items whose image can 404, so a
    /// failed load and a missing one have to look the same.
    @ViewBuilder
    private var artwork: some View {
        if live, !frames.isEmpty {
            slideshow
        } else if let loaded {
            framed(loaded)
        } else {
            gradient
        }
    }

    /// **Every card ends up filled edge to edge with no black edges.** Once
    /// `LetterboxTrimmer` has taken the bars off, a picture whose shape
    /// roughly matches the tile is scaled to fill and clipped; one that
    /// doesn't (a portrait clip that was pillarboxed into a 16:9 export, in a
    /// landscape tile) is shown whole over a blurred, dimmed copy of itself —
    /// a wash of its own colours reads as deliberate where dead black reads
    /// as broken.
    private func framed(_ image: UIImage) -> some View {
        let imageAspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let tileAspect = size.map { $0.width / max($0.height, 1) } ?? 16.0 / 9.0
        let fills = abs(imageAspect - tileAspect) / tileAspect < 0.35
        return ZStack {
            if !fills {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 18)
                    .overlay(Color.black.opacity(0.4))
            }
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: fills ? .fill : .fit)
        }
        // A `.fill` layer overflows its frame by design; clip before the
        // card's own shape so the blur can't bleed past the corners.
        .clipped()
    }

    private var gradient: some View {
        LinearGradient(colors: [Color(item.artwork.top), Color(item.artwork.bottom)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Slideshow

    /// Seconds each frame holds, and how much of that is the crossfade into
    /// the next. Slow enough to see, quick enough to feel like the video.
    private static let framePeriod: TimeInterval = 1.2
    private static let fadeShare: TimeInterval = 0.3

    /// Which frame is showing at `t`, which is next, and how far into the
    /// crossfade we are (0 = showing the current frame alone).
    private func slide(at t: TimeInterval) -> (current: Int, next: Int, fade: Double) {
        let period = Self.framePeriod
        let index = Int(t / period) % frames.count
        let within = (t - floor(t / period) * period) / period
        let fade = max(0, (within - (1 - Self.fadeShare)) / Self.fadeShare)
        return (index, (index + 1) % frames.count, fade)
    }

    private var slideshow: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { context in
            let t = context.date.timeIntervalSince(liveSince)
            let s = slide(at: t)
            ZStack {
                Image(uiImage: frames[s.current].image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                Image(uiImage: frames[s.next].image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(s.fade)
            }
            .clipped()
        }
        .transition(.opacity)
    }

    /// Where in the video the showing frame sits: a hairline track with a lit
    /// segment that steps along as the frames do, so the card reads as a
    /// scan through the whole clip rather than a random shuffle.
    private var progressLine: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { context in
            let t = context.date.timeIntervalSince(liveSince)
            let s = slide(at: t)
            let runtime = Double(item.runtimeTicks ?? 0) / 10_000_000
            let a = frames[s.current].seconds, b = frames[s.next].seconds
            let seconds = s.next > s.current ? a + (b - a) * s.fade : a
            let position = runtime > 0 ? min(1, seconds / runtime) : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.22))
                    Rectangle().fill(.white.opacity(0.95))
                        .frame(width: max(6, geo.size.width * position))
                        .shadow(color: .white.opacity(0.6), radius: 3)
                }
            }
            .frame(height: 3)
        }
    }

    /// Up to eight frames across the runtime, from the item's own trickplay
    /// geometry — no per-item request; the sheet is the one download, shared
    /// through `AppState.cardTrickplay` with every other card that needs it.
    private func loadFrames() async {
        guard let trickplay = appState.cardTrickplay,
              let best = HomeVideoRoll.bestTrickplay(item.trickplay) else { return }
        let times = HomeVideoRoll.frameTimes(runtimeTicks: item.runtimeTicks, intervalMs: best.info.interval)
        var collected: [Frame] = []
        for seconds in times {
            guard !Task.isCancelled else { return }
            if let image = await trickplay.thumbnail(forSeconds: seconds, itemId: item.id, widthKey: best.widthKey,
                                                     info: best.info, mediaSourceId: best.mediaSourceId) {
                collected.append(Frame(seconds: seconds, image: image))
            }
        }
        // Two at least, or there is nothing to page through.
        if collected.count >= 2 {
            withAnimation(.easeOut(duration: 0.3)) { frames = collected }
        }
    }

    // MARK: - Corners

    private var overlays: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.tags.isEmpty {
                // Two at most: a third chip wraps into the artwork.
                HStack(spacing: 6) {
                    ForEach(item.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(Typography.font(12, .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                }
            }
            // A portrait tile is too narrow for "Sep 6, 2020 · 26 sec" on one
            // line, so it stacks the two and drops the year.
            if isNarrow {
                VStack(alignment: .leading, spacing: 4) {
                    captionText(short: true)
                    durationPill
                }
            } else {
                HStack(spacing: 8) {
                    captionText(short: false)
                    durationPill
                }
            }
        }
        .padding(10)
        .padding(.bottom, live && !frames.isEmpty ? 3 : 0)
    }

    private var isNarrow: Bool { (size?.width ?? .infinity) < 170 }

    @ViewBuilder private func captionText(short: Bool) -> some View {
        if let caption {
            Text(short ? (HomeVideoRoll.shortDateLabel(item.takenAt) ?? caption) : caption)
                .font(Typography.font(14, .bold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
        }
    }

    @ViewBuilder private var durationPill: some View {
        if let duration = item.durationLabel {
            Text(duration)
                .font(Mono.font(12, .bold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder private var badgeView: some View {
        if let badge {
            Text(isNarrow ? badge.replacingOccurrences(of: " YEARS AGO", with: " YRS") : badge)
                .font(Mono.font(11, .bold)).tracking(1.4)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                .padding(10)
        }
    }

    private var accessibilityText: String {
        [caption ?? item.title, item.durationLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
