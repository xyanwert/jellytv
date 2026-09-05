import SwiftUI
import JellyTVKit

#if os(tvOS)
/// The home-video shelf as a camera roll: an "On this day" strip when there
/// is one, then the videos by month — newest first, a pinned month header
/// over each — laid as a justified mosaic in which portrait phone clips
/// stand tall beside landscape ones. Every card is `HomeVideoCard`; the one
/// under the remote pages through its own frames.
///
/// Why a roll and not a grid: these files have no titles worth reading (a
/// camera's serial gibberish) and no artwork beyond one frame, but 296 of
/// the 399 here carry the day they were shot — which is the one thing a
/// family actually browses home videos by. The arithmetic is `HomeVideoRoll`
/// (kit, tested); this is only the layout.
struct HomeVideoRollView: View {
    let items: [MediaItem]
    /// Sections by month, or one flat mosaic for a shuffled order.
    let grouped: Bool
    /// The content width the rows justify to.
    let width: CGFloat
    let accent: Color
    var focus: FocusState<String?>.Binding
    /// A card was chosen: the item, and the order the shelf plays on from it.
    let onPlay: (MediaItem, [MediaItem]) -> Void
    /// The first card of the roll has mounted — the screen seeds focus there.
    let onFirstCardAppear: (MediaItem) -> Void

    private static let rowHeight: CGFloat = 214
    private static let spacing: CGFloat = 14

    private var sections: [HomeVideoRoll.Section] {
        grouped ? HomeVideoRoll.sections(items) : [HomeVideoRoll.Section(title: "", items: items)]
    }
    private var order: [MediaItem] { HomeVideoRoll.flattened(sections) }
    private var anniversaries: [HomeVideoRoll.Anniversary] { grouped ? HomeVideoRoll.onThisDay(items) : [] }
    private var firstId: String? { anniversaries.first?.item.id ?? order.first?.id }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 30, pinnedViews: [.sectionHeaders]) {
            if !anniversaries.isEmpty { onThisDay }
            ForEach(sections) { section in
                Section {
                    rows(for: section)
                } header: {
                    if !section.title.isEmpty { header(section) }
                }
            }
        }
    }

    // MARK: - On this day

    private var onThisDay: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 14, weight: .bold)).foregroundStyle(accent)
                Text("ON THIS DAY")
                    .font(Mono.font(14, .bold)).tracking(2.2)
                    .foregroundStyle(accent)
                Text("\(anniversaries.count)")
                    .font(Mono.font(14, .bold))
                    .foregroundStyle(Palette.text(0.4))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(anniversaries) { anniversary in
                        let item = anniversary.item
                        let aspect = HomeVideoRoll.clampedAspect(item.aspectRatio)
                        card(item, size: CGSize(width: (Self.rowHeight * aspect).rounded(), height: Self.rowHeight),
                             badge: anniversary.label, queue: anniversaries.map(\.item))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            }
            .horizontalEdgeFade()
            // Left/Right stay in the strip — see `ShowView.seasonSelector`.
            .focusSection()
        }
    }

    // MARK: - Months

    private func header(_ section: HomeVideoRoll.Section) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(section.title.uppercased())
                .font(Mono.font(14, .bold)).tracking(2.2)
                .foregroundStyle(Palette.text(0.7))
            Text("\(section.items.count)")
                .font(Mono.font(14, .bold))
                .foregroundStyle(Palette.text(0.35))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        // Pinned over the scrolling rows, so it needs its own ground.
        .background(Palette.background.opacity(0.92))
    }

    private func rows(for section: HomeVideoRoll.Section) -> some View {
        let rows = HomeVideoRoll.justifiedRows(section.items, width: Double(width),
                                               targetHeight: Double(Self.rowHeight), spacing: Double(Self.spacing))
        return LazyVStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(row, id: \.item.id) { placed in
                        card(placed.item, size: CGSize(width: placed.width, height: placed.height),
                             badge: nil, queue: order)
                    }
                }
            }
        }
        // Room for the focused card's lift, which the roll would otherwise clip.
        .padding(.vertical, 8)
    }

    private func card(_ item: MediaItem, size: CGSize, badge: String?, queue: [MediaItem]) -> some View {
        HomeVideoCard(item: item, size: size, live: focus.wrappedValue == item.id,
                      caption: HomeVideoRoll.dateLabel(item.takenAt), badge: badge,
                      onSelect: { onPlay(item, queue) })
            .focused(focus, equals: item.id)
            .onAppear { if item.id == firstId { onFirstCardAppear(item) } }
    }
}
#endif
