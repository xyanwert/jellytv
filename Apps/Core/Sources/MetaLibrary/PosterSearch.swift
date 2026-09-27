import SwiftUI
import JellyTVKit

/// One shelf of search results as the night-paper screen shows it.
struct PosterSearchSection: Identifiable {
    let bucket: AppState.SearchGroupKind
    let title: String
    let items: [MediaItem]
    var id: String { title }
}

/// Search on the TV in Poster Mode — design canvas "TV · Search — night
/// paper": dark dotted paper, a coral SEARCH tab hung off the top edge, the
/// query printed huge in Anton behind a cyan cursor bar (the whole line is
/// the field: Select raises the keyboard), scope chips carrying their counts,
/// the best hit on a coral TOP MATCH card and the rest as shelves of sticker
/// posters with name tags, recent searches as dashed chips.
///
/// The screen's *logic* stays in `SearchLibraryView` (the debounced fetch,
/// the filters, what opening a result does); this is only its drawing, and
/// the Classic branch there is untouched.
///
/// **Nothing here moves because something loaded.** Every band has a fixed
/// height from the first frame; a new search keeps the last results on
/// screen with a SEARCHING… readout in its own slot until the answer lands.
struct PosterSearchTV: View {
    @Binding var query: String
    @Binding var filter: SearchFilter
    @Binding var unwatchedOnly: Bool
    @Binding var includeNSFW: Bool
    let offersNSFW: Bool
    let sections: [PosterSearchSection]
    let count: (SearchFilter) -> Int
    let isSearching: Bool
    let hasSearched: Bool
    let recent: [String]
    var focusedId: FocusState<String?>.Binding
    var fieldFocus: FocusState<Bool?>.Binding
    let onOpen: (MediaItem, AppState.SearchGroupKind) -> Void

    private static let coral = Color(hex: "#F0525F")
    private var device: DeviceClass { DeviceClass.current }
    /// Size off the TV's 1 — the iPad takes the TV's layout at its own scale.
    private var s: CGFloat { device == .pad ? 0.62 : 1 }

    var body: some View {
        if device == .phone {
            phoneBody
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 40 * s) {
                    tab(width: 150 * s, font: 34 * s)
                    queryField
                }
                .frame(height: 160 * s, alignment: .bottom)

                chips
                    .padding(.top, 30 * s)
                    .frame(height: (58 + 30 + 24) * s, alignment: .top)

                results
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.leading, 56 * s)
            .padding(.trailing, 70 * s)
        }
    }

    @ViewBuilder private var queryField: some View {
        #if os(tvOS)
        PosterSearchQueryField(text: $query, focus: fieldFocus)
        #else
        PosterSearchTouchField(text: $query, focus: fieldFocus, size: 120 * s, underline: false)
        #endif
    }

    /// The iPhone artboard ("iPhone · Search"): one scrolling column — the
    /// tab, the query typed straight into big Anton over a white rule, the
    /// chips, a full-width TOP MATCH card, then shelves of small tilted
    /// stickers. The field sits at the top here, where the design puts it.
    private var phoneBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                tab(width: 86, font: 18)
                    .frame(height: 70, alignment: .bottom)
                #if os(iOS)
                PosterSearchTouchField(text: $query, focus: fieldFocus, size: 58, underline: true)
                #endif
                chips
                if !hasSearched {
                    idle
                } else if sections.isEmpty {
                    nothing
                } else {
                    if let top = sections.first, let item = top.items.first {
                        Button { onOpen(item, top.bucket) } label: {
                            PosterSearchTopMatch(item: item, kind: top.bucket, width: 354, height: 300)
                        }
                        .buttonStyle(PosterSearchCardStyle(cornerRadius: 24))
                    }
                    ForEach(sections) { section in shelf(section) }
                    recentRow
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 120)
            .containerRelativeFrame(.horizontal)
        }
        .phoneTabBarClearance()
    }

    // MARK: - Header

    /// Hung off the top edge: the coral drawn far above its own frame so it
    /// meets the screen's edge whatever the safe area above.
    private func tab(width: CGFloat, font: CGFloat) -> some View {
        Text("SEARCH")
            .font(Display.font(font)).tracking(1)
            .foregroundStyle(Palette.posterInk)
            .padding(.bottom, font * 0.5)
            .frame(width: width, height: width, alignment: .bottom)
            .background(alignment: .bottom) {
                UnevenRoundedRectangle(bottomLeadingRadius: width * 0.17, bottomTrailingRadius: width * 0.17,
                                       style: .continuous)
                    .fill(Self.coral)
                    .frame(width: width, height: width * 2.8)
            }
            .accessibilityHidden(true)
    }

    // MARK: - Scope chips

    private var chipScale: CGFloat { device == .phone ? 0.6 : s }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14 * chipScale) {
                ForEach(SearchFilter.allCases) { f in
                    Button { filter = f } label: {
                        PosterSearchChip(label: f.label.uppercased(), count: hasSearched ? count(f) : nil,
                                         on: filter == f, s: chipScale)
                    }
                    .buttonStyle(PosterSearchChipStyle())
                }
                Rectangle().fill(Color(hex: "#34353D")).frame(width: 3, height: 34 * chipScale).padding(.horizontal, 6)
                Button { unwatchedOnly.toggle() } label: {
                    PosterSearchChip(label: "UNWATCHED", count: nil, on: unwatchedOnly, systemImage: "eye.slash.fill",
                                     s: chipScale)
                }
                .buttonStyle(PosterSearchChipStyle())
                if offersNSFW {
                    Button { includeNSFW.toggle() } label: {
                        PosterSearchChip(label: "NSFW", count: nil, on: includeNSFW, systemImage: "lock.fill", s: chipScale)
                    }
                    .buttonStyle(PosterSearchChipStyle())
                }
                // Its own slot: a search in flight never reflows the row.
                Text("SEARCHING…")
                    .font(Mono.font(18 * chipScale, .bold)).tracking(2)
                    .foregroundStyle(Palette.posterTeal)
                    .opacity(isSearching ? 1 : 0)
                    .padding(.leading, 20 * chipScale)
            }
            // Room for a focused chip's lift and ring.
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, -8)
        .padding(.vertical, -10)
        #if os(tvOS)
        .scrollClipDisabled()
        .focusSection()
        #endif
    }

    // MARK: - Results

    @ViewBuilder private var results: some View {
        if !hasSearched {
            idle
        } else if sections.isEmpty {
            nothing
        } else {
            HStack(alignment: .top, spacing: 60 * s) {
                if let top = sections.first, let item = top.items.first {
                    Button { onOpen(item, top.bucket) } label: {
                        PosterSearchTopMatch(item: item, kind: top.bucket, width: 560 * s, height: 600 * s)
                    }
                    .buttonStyle(PosterSearchCardStyle(cornerRadius: 34 * s))
                    .focused(focusedId, equals: "top:" + item.id)
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(sections) { section in
                            shelf(section)
                        }
                        recentRow.padding(.top, 6)
                    }
                    .padding(.bottom, 60)
                }
                #if os(tvOS)
                .scrollClipDisabled()
                #endif
            }
        }
    }

    /// Sticker scale: the TV's 1, the iPad's, or the phone's small tilted row.
    private var stickerScale: CGFloat { device == .phone ? 0.52 : s }

    private func shelf(_ section: PosterSearchSection) -> some View {
        let k = stickerScale
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14 * k) {
                Text(section.title).font(Display.font(device == .phone ? 22 : 40 * s))
                Rectangle().fill(Color(hex: "#34353D")).frame(height: 3)
                Text(String(format: "%02d", section.items.count))
                    .font(Display.font(device == .phone ? 18 : 28 * s)).foregroundStyle(Self.coral)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 34 * k) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        Button { onOpen(item, section.bucket) } label: {
                            PosterSearchSticker(item: item, wide: section.bucket == .videos,
                                                ink: PosterSearchSticker.inks[index % PosterSearchSticker.inks.count],
                                                k: k,
                                                // The phone's row leans, sticker by sticker.
                                                tilt: device == .phone ? [-3, 2, -2, 3][index % 4] : 0)
                        }
                        .buttonStyle(PosterSearchCardStyle(cornerRadius: 18 * k))
                        .focused(focusedId, equals: item.id)
                    }
                }
                // Room for the focused sticker's lift and its name tag.
                .padding(.vertical, 26 * k)
                .padding(.horizontal, 8)
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    private var recentRow: some View {
        let k: CGFloat = device == .phone ? 0.7 : s
        return HStack(spacing: 14 * k) {
            Text("RECENT //")
                .font(Mono.font(22 * k, .bold))
                .foregroundStyle(Color(hex: "#8E8D96"))
            ForEach(recent.prefix(device == .phone ? 3 : 6), id: \.self) { term in
                Button { query = term } label: {
                    Text(term.uppercased())
                        .font(Display.font(22 * k)).tracking(1)
                        .foregroundStyle(Color(hex: "#C9C8CF"))
                        .lineLimit(1)
                        .padding(.horizontal, 18 * k)
                        .frame(height: 48 * k)
                        .background(Color(hex: "#1E1F25"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(hex: "#3A3B43"), style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
                }
                .buttonStyle(PosterSearchCardStyle(cornerRadius: 10))
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var idleScale: CGFloat { device == .phone ? 0.45 : s }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 34) {
            VStack(alignment: .leading, spacing: -28 * idleScale) {
                Text("WHAT ARE WE")
                Text("WATCHING?")
            }
            .font(Display.font(120 * idleScale))
            .foregroundStyle(Palette.text(0.12))
            if !recent.isEmpty { recentRow }
        }
        .padding(.top, 20)
    }

    private var nothing: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("NOTHING FOR “\(query.uppercased())”")
                .font(Display.font(80 * idleScale)).lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Palette.text(0.22))
            if offersNSFW, !includeNSFW {
                Text("Adult libraries are excluded — turn on NSFW to include them.")
                    .font(Typography.font(max(14, 22 * idleScale), .semibold))
                    .foregroundStyle(Palette.text(0.4))
            }
            if !recent.isEmpty { recentRow.padding(.top, 20) }
        }
        .padding(.top, 20)
    }
}

// MARK: - The query line

/// The query printed huge, a cyan cursor bar and an EDIT pill — one focusable
/// control. Select raises the keyboard through the same invisible-UIKit-field
/// bridge `SearchHeroField` uses (`TVTextField`); what is typed lands here.
#if os(tvOS)
private struct PosterSearchQueryField: View {
    @Binding var text: String
    var focus: FocusState<Bool?>.Binding

    @State private var editing = false

    private var active: Bool { focus.wrappedValue == true || editing }

    /// Sized from its own length (Anton runs about half an em a letter),
    /// then held at that width, so the cursor sits right after the last
    /// letter — a fit-to-width text claims the whole line and parked the
    /// cursor at the far end.
    private var queryText: some View {
        let shown = text.isEmpty ? "TYPE TO SEARCH" : text.uppercased()
        let size = min(150, 1000 / max(1, CGFloat(shown.count) * 0.5))
        return Text(shown)
            .font(Display.font(max(56, size)))
            .tracking(2)
            .foregroundStyle(text.isEmpty ? Palette.text(0.2) : Palette.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: 1040, alignment: .leading)
            .fixedSize()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if active {
                TVTextField(text: $text, isSecure: false, isEditing: $editing, onSubmit: {})
                    .frame(width: 600, height: 150)
                    .opacity(0.02)
            }
            Button { editing = true } label: {
                HStack(alignment: .bottom, spacing: 12) {
                    // Its own width while it fits, so the cursor sits right
                    // after the last letter; shrunk to fit past that.
                    queryText
                    Rectangle()
                        .fill(Palette.posterTeal)
                        .frame(width: 22, height: 120)
                        .opacity(active ? 1 : 0.45)
                        .padding(.bottom, 12)
                    HStack(spacing: 10) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 22, weight: .bold))
                        Text("EDIT").font(Display.font(24))
                    }
                    .foregroundStyle(active ? Palette.posterInk : Color(hex: "#C9C8CF"))
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .background(active ? Color.white : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(active ? .white : Color(hex: "#4A4B53"), lineWidth: 3))
                    .padding(.leading, 24)
                    .padding(.bottom, 18)
                    .scaleEffect(active ? 1.08 : 1)
                }
                .frame(height: 150, alignment: .bottomLeading)
                .animation(.spring(response: 0.26, dampingFraction: 0.7), value: active)
            }
            .buttonStyle(AppTextFieldButtonStyle())
            .focused(focus, equals: true)
        }
        .onChange(of: editing) {
            if !editing { focus.wrappedValue = true }
        }
    }
}
#endif

#if os(iOS)
/// Touch: the query typed straight into big Anton — a real `TextField`, the
/// cyan caret its cursor, a white rule under it on the phone (the artboard),
/// and a clear button once there is something to clear.
private struct PosterSearchTouchField: View {
    @Binding var text: String
    var focus: FocusState<Bool?>.Binding
    let size: CGFloat
    let underline: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Printed in capitals like the TV's line; search is
            // case-insensitive, so the query is simply kept upper-case.
            TextField("", text: Binding(get: { text.uppercased() }, set: { text = $0.uppercased() }),
                      prompt: Text("TYPE TO SEARCH").foregroundStyle(Palette.text(0.2)))
                .font(Display.font(size))
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.posterTeal)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focus, equals: true)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Button { text = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(Palette.text(0.45))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .opacity(text.isEmpty ? 0 : 1)
            .accessibilityLabel("Clear search")
        }
        .frame(height: size * 1.15)
        .overlay(alignment: .bottom) {
            if underline { Rectangle().fill(Palette.textPrimary).frame(height: 4) }
        }
    }
}
#endif

// MARK: - Pieces

private struct PosterSearchChip: View {
    let label: String
    let count: Int?
    let on: Bool
    var systemImage: String? = nil
    var s: CGFloat = 1

    var body: some View {
        HStack(spacing: 12 * s) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 20 * s, weight: .bold)) }
            Text(label).font(Display.font(28 * s)).tracking(1)
            if let count {
                Text("\(count)").font(Mono.font(20 * s, .bold)).opacity(0.7)
            }
        }
        .foregroundStyle(on ? Palette.posterInk : Color(hex: "#C9C8CF"))
        .padding(.horizontal, 24 * s)
        .frame(height: 58 * s)
        .background(on ? Palette.textPrimary : .clear, in: Capsule())
        .overlay(Capsule().strokeBorder(on ? Palette.textPrimary : Color(hex: "#3A3B43"), lineWidth: max(2, 3 * s)))
    }
}

/// Focus on the night paper: lift, and a cyan ring — the chips' and cards'
/// shared answer, since white is already what *selected* means here.
private struct PosterSearchChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }
    private struct Styled: View {
        @Environment(\.isFocused) private var focused
        let configuration: ButtonStyle.Configuration
        var body: some View {
            configuration.label
                .overlay(Capsule().strokeBorder(Palette.posterTeal, lineWidth: 4).padding(-7).opacity(focused ? 1 : 0))
                .scaleEffect(focused ? 1.08 : (configuration.isPressed ? 0.96 : 1))
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: focused)
        }
    }
}

private struct PosterSearchCardStyle: ButtonStyle {
    let cornerRadius: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, cornerRadius: cornerRadius)
    }
    private struct Styled: View {
        @Environment(\.isFocused) private var focused
        let configuration: ButtonStyle.Configuration
        let cornerRadius: CGFloat
        var body: some View {
            configuration.label
                .environment(\.posterSearchFocused, focused)
                .scaleEffect(focused ? 1.06 : (configuration.isPressed ? 0.97 : 1))
                .offset(y: focused ? -8 : 0)
                .animation(.spring(response: 0.26, dampingFraction: 0.66), value: focused)
        }
    }
}

private struct PosterSearchFocusedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    fileprivate var posterSearchFocused: Bool {
        get { self[PosterSearchFocusedKey.self] }
        set { self[PosterSearchFocusedKey.self] = newValue }
    }
}

/// A result as a sticker: the poster in a thick frame (white when focused,
/// with a cyan ring), its name tag stuck across the foot.
private struct PosterSearchSticker: View {
    let item: MediaItem
    let wide: Bool
    let ink: Color
    var k: CGFloat = 1
    var tilt: Double = 0

    static let inks = [Color(hex: "#1F9D55"), Color(hex: "#2E8FA8"), Color(hex: "#6A4FC8"), Color(hex: "#F0525F")]

    @Environment(\.posterSearchFocused) private var focused

    var body: some View {
        let w: CGFloat = (wide ? 330 : 200) * k
        let h: CGFloat = wide ? w * 9 / 16 : w * 1.5
        let r = 18 * k
        VStack(alignment: .leading, spacing: 0) {
            art
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(focused ? .white : Color(hex: "#2A2B31"), lineWidth: max(3, 6 * k)))
                .overlay(RoundedRectangle(cornerRadius: r + 4, style: .continuous)
                    .strokeBorder(Palette.posterTeal, lineWidth: 6).padding(-6).opacity(focused ? 1 : 0))
                .shadow(color: .black.opacity(focused ? 0.6 : 0.5), radius: (focused ? 25 : 14) * k, y: (focused ? 30 : 14) * k)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title.uppercased())
                    .font(Display.font(max(12, 24 * k))).lineLimit(1)
                    .foregroundStyle(ink)
                    .padding(.horizontal, 12 * k).padding(.vertical, 4 * k)
                    .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 7 * k, bottomLeadingRadius: 0,
                                                                      bottomTrailingRadius: 7 * k, topTrailingRadius: 7 * k))
                if let year = item.year, !year.isEmpty {
                    Text(year)
                        .font(Display.font(max(10, 16 * k))).tracking(1)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 12 * k).padding(.vertical, 3 * k)
                        .background(Color(hex: "#2A2B31"), in: UnevenRoundedRectangle(bottomLeadingRadius: 7 * k,
                                                                                         bottomTrailingRadius: 7 * k))
                }
            }
            .frame(maxWidth: w + 20 * k, alignment: .leading)
            .rotationEffect(.degrees(-3), anchor: .leading)
            .padding(.top, -24 * k).padding(.leading, -8 * k)
        }
        .frame(width: w, alignment: .leading)
        .rotationEffect(.degrees(tilt))
    }

    @ViewBuilder private var art: some View {
        let source = wide ? (item.thumbImage ?? item.backdropImage ?? item.image) : item.image
        if let source, source.hasPrefix("http"), let url = URL(string: source) {
            JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
        } else {
            item.artwork.gradient
        }
    }
}

/// The best hit, big: coral card, its title printed huge and faint behind, an
/// ink slash, the poster as a framed sticker leaning in from the right, and a
/// name tag — what it is and its year — stuck across the foot.
private struct PosterSearchTopMatch: View {
    let item: MediaItem
    let kind: AppState.SearchGroupKind
    var width: CGFloat = 560
    var height: CGFloat = 600
    /// Everything inside scales off the TV card's 560pt width.
    private var u: CGFloat { width / 560 }

    @Environment(\.posterSearchFocused) private var focused

    private var kindLabel: String {
        switch kind {
        case .movies: return "MOVIE"
        case .shows: return "SHOW"
        case .anime: return "ANIME"
        case .videos: return "HOME VIDEO"
        }
    }

    /// The poster sticker: the TV's 290pt at the card's scale, held under
    /// the card's height on a short, wide card (the phone's).
    private var posterW: CGFloat { min(290 * u, height * 0.62) }
    private var posterTop: CGFloat { min(70 * u, height - posterW * 1.5 - 24 * u) }

    var body: some View {
        // Every layer is an overlay on a card of fixed size, so nothing
        // inside (the faint title runs far wider than the card) can grow it.
        Color(hex: "#F0525F")
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                Text(item.title.uppercased())
                    .font(Display.font(200 * u)).lineSpacing(-40 * u)
                    .foregroundStyle(Palette.posterInk.opacity(0.16))
                    .lineLimit(2)
                    .fixedSize()
                    .offset(x: -10 * u, y: 6 * u)
            }
            .overlay(alignment: .topLeading) {
                Rectangle().fill(Palette.posterInk)
                    .frame(width: 820 * u + width, height: 18 * u)
                    .rotationEffect(.degrees(-14))
                    .offset(x: -80 * u - width / 2, y: height * 0.73)
            }
            .overlay(alignment: .topTrailing) {
                art
                    .frame(width: posterW, height: posterW * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white, lineWidth: 8 * u))
                    .compositingGroup()
                    .shadow(color: Palette.posterInk.opacity(0.9), radius: 0, x: 10 * u, y: 10 * u)
                    .rotationEffect(.degrees(5))
                    .offset(x: -34 * u, y: posterTop)
            }
            .overlay(alignment: .topLeading) {
                Text("TOP MATCH")
                    .font(Display.font(max(12, 20 * u))).tracking(1)
                    .foregroundStyle(Palette.posterTeal)
                    .padding(.horizontal, 14 * u).frame(height: max(26, 40 * u))
                    .background(Palette.posterInk, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .offset(x: 30 * u, y: 30 * u)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title.uppercased())
                        .font(Display.font(46 * u)).lineLimit(2).minimumScaleFactor(0.5)
                        .foregroundStyle(Palette.posterInk)
                        .padding(.horizontal, 16 * u).padding(.vertical, 6 * u)
                        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0,
                                                                          bottomTrailingRadius: 8, topTrailingRadius: 8))
                    Text([kindLabel, item.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Display.font(max(11, 22 * u))).tracking(1)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 16 * u).padding(.vertical, 5 * u)
                        .background(Palette.posterInk, in: UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
                }
                .frame(maxWidth: width * 0.78, alignment: .leading)
                .rotationEffect(.degrees(-3), anchor: .leading)
                .padding(.leading, 30 * u).padding(.bottom, 40 * u)
            }
            .clipShape(RoundedRectangle(cornerRadius: 34 * u, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(Palette.posterTeal, lineWidth: 6).padding(-8).opacity(focused ? 1 : 0))
    }

    @ViewBuilder private var art: some View {
        if let source = item.image, source.hasPrefix("http"), let url = URL(string: source) {
            JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
        } else {
            item.artwork.gradient
        }
    }
}

/// The paper itself: ink with a grid of faint dots, drawn once.
struct PosterNightPaper: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.posterInk))
            var dots = Path()
            let step: CGFloat = 30, r: CGFloat = 1.7
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += step
                }
                y += step
            }
            ctx.fill(dots, with: .color(Color(hex: "#26272E")))
        }
        .drawingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
