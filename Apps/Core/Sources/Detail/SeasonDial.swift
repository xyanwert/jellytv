import SwiftUI
import JellyTVKit

/// The season picker for every show page, replacing the row of "S01 S02 …"
/// chips. That row worked for three seasons and fell apart at thirty: South
/// Park's ran off the screen as a strip of identical labels with no sign of
/// where the viewer was or what they had watched.
///
/// **A dial and a ribbon.** The dial is one big season number with the
/// season's readout ("6 LEFT", "DONE") and an UP NEXT tag when it is the one
/// `SeasonGuide` suggested; the ribbon beside or under it is the whole run of
/// the show as ticks, each filled to how much of that season has been
/// watched, the selected one tall and outlined, the suggested one marked. Any
/// length of show reads at a glance and never scrolls.
///
/// - tvOS: the dial is one focusable control. Left/Right step seasons (a swipe
///   across the clickpad runs through them), Select opens `SeasonWall`, Up and
///   Down leave as normal.
/// - Touch: ‹ › step, dragging along the ribbon scrubs, tapping the number
///   opens the wall.
struct SeasonDial<Field: Hashable>: View {
    let seasons: [Season]
    @Binding var selected: Int
    let suggested: Int?
    var compact = false
    var focus: FocusState<Field?>.Binding
    let focusValue: Field
    var onOpenAll: () -> Void

    @EnvironmentObject private var theme: Theme

    private var order: [Int] { SeasonGuide.displayOrder(seasons) }
    private var position: Int { order.firstIndex(of: selected) ?? 0 }
    private var current: Season? { seasons.indices.contains(selected) ? seasons[selected] : nil }
    private var isTV: Bool { DeviceClass.current == .tv }
    private var progressColor: Color { theme.isPoster ? Palette.posterTeal : theme.accent }

    var body: some View {
        Group {
            if compact && theme.isPoster && DeviceClass.current == .pad {
                // The iPad drawer wears the TV's strip, stacked for touch.
                PosterSeasonStrip(seasons: seasons, order: order, selected: selected, suggested: suggested,
                                  position: position, onSelect: { selected = $0 }, onOpenAll: onOpenAll, s: 0.72)
            } else if compact {
                VStack(alignment: .leading, spacing: 12) {
                    dial
                    SeasonRibbon(seasons: seasons, order: order, selected: $selected, suggested: suggested,
                                 color: progressColor, height: 30)
                }
            } else {
                #if os(tvOS)
                // On the TV the whole bar — number and ribbon — is one
                // control, ~1300pt wide: a press from any button above or Up
                // from any episode below lands on it. The narrower dial alone
                // was unreachable straight down from Play (verified).
                Button(action: onOpenAll) {
                    if theme.isPoster {
                        PosterSeasonStrip(seasons: seasons, order: order, selected: selected,
                                          suggested: suggested, position: position)
                    } else {
                        HStack(alignment: .center, spacing: 34) {
                            dialFace(focused: false)
                            SeasonRibbon(seasons: seasons, order: order, selected: $selected, suggested: suggested,
                                         color: progressColor, height: 46)
                                .frame(width: 760)
                        }
                    }
                }
                .buttonStyle(SeasonDialStyle(poster: theme.isPoster))
                .focused(focus, equals: focusValue)
                .onMoveCommand { direction in
                    switch direction {
                    case .left: step(-1)
                    case .right: step(1)
                    default: break
                    }
                }
                .accessibilityAdjustableAction { direction in
                    step(direction == .increment ? 1 : -1)
                }
                #else
                HStack(alignment: .center, spacing: 28) {
                    dial
                    SeasonRibbon(seasons: seasons, order: order, selected: $selected, suggested: suggested,
                                 color: progressColor, height: 34)
                        .frame(maxWidth: 460)
                }
                #endif
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: - Dial

    private var dial: some View {
        HStack(spacing: isTV ? 14 : 8) {
            #if os(iOS)
            stepButton(-1, systemImage: "chevron.left")
            #endif
            #if os(tvOS)
            Button(action: onOpenAll) { dialFace(focused: false) }
                .buttonStyle(SeasonDialStyle(poster: theme.isPoster))
                .focused(focus, equals: focusValue)
                .onMoveCommand { direction in
                    switch direction {
                    case .left: step(-1)
                    case .right: step(1)
                    default: break
                    }
                }
                .accessibilityAdjustableAction { direction in
                    step(direction == .increment ? 1 : -1)
                }
            #else
            Button(action: onOpenAll) { dialFace(focused: false) }
                .buttonStyle(.plain)
                .accessibilityHint("Shows every season")
            stepButton(1, systemImage: "chevron.right")
            #endif
        }
    }

    private func dialFace(focused: Bool) -> some View {
        HStack(alignment: .center, spacing: isTV ? 18 : 10) {
            #if os(tvOS)
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .black))
                .opacity(position > 0 ? 0.9 : 0.2)
            #endif
            VStack(alignment: .leading, spacing: 0) {
                Text(current.map { $0.number > 0 ? "SEASON" : "SEASON" } ?? "SEASON")
                    .font(theme.isPoster ? Display.font(isTV ? 18 : 12) : Mono.font(isTV ? 14 : 10, .bold))
                    .tracking(2)
                    .opacity(0.6)
                Text(bigLabel)
                    .font(theme.isPoster ? Display.font(isTV ? 64 : (compact ? 40 : 46))
                                         : Typography.font(isTV ? 56 : (compact ? 36 : 40), .black))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(current?.number ?? 0)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(minWidth: isTV ? 120 : 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                // Both slots are always laid out and only shown or hidden:
                // an UP NEXT tag that came and went changed the bar's height
                // on every Left/Right, and the episode shelf under it jumped.
                do {
                    Text("UP NEXT")
                        .font(theme.isPoster ? Display.font(isTV ? 18 : 12) : Mono.font(isTV ? 13 : 10, .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Palette.posterInk)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: "#F0525F"), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .rotationEffect(.degrees(theme.isPoster ? -3 : 0))
                        .opacity(selected == suggested ? 1 : 0)
                }
                if let current {
                    let readout = SeasonGuide.readout(for: current)
                    Text(readout.isEmpty ? " " : readout)
                        .font(theme.isPoster ? Display.font(isTV ? 22 : 14) : Mono.font(isTV ? 15 : 11, .bold))
                        .tracking(1)
                        .opacity(0.75)
                    Text("\(position + 1) OF \(seasons.count)")
                        .font(Mono.font(isTV ? 13 : 10, .bold))
                        .tracking(1)
                        .opacity(0.45)
                }
            }
            .frame(minWidth: isTV ? 130 : 84, alignment: .leading)
            #if os(tvOS)
            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .black))
                .opacity(position < order.count - 1 ? 0.9 : 0.2)
            #endif
        }
        .animation(.snappy(duration: 0.22), value: selected)
    }

    private var bigLabel: String {
        guard let current else { return "—" }
        return current.number > 0 ? "\(current.number)" : "SP"
    }

    #if os(iOS)
    private func stepButton(_ delta: Int, systemImage: String) -> some View {
        let enabled = delta < 0 ? position > 0 : position < order.count - 1
        return Button { step(delta) } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .frame(width: 44, height: 44)
                .background(Palette.text(enabled ? 0.12 : 0.05), in: Circle())
                .foregroundStyle(Palette.text(enabled ? 0.95 : 0.3))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(delta < 0 ? "Previous season" : "Next season")
    }
    #endif

    private func step(_ delta: Int) {
        let next = position + delta
        guard order.indices.contains(next) else { return }
        selected = order[next]
    }
}

/// The season bar's focus on tvOS: the plate goes dark and lifts with a white
/// edge. Not the chips' white fill — the ribbon's colours live inside this
/// control and would vanish on white.
private struct SeasonDialStyle: ButtonStyle {
    let poster: Bool

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, poster: poster)
    }

    private struct Content: View {
        #if os(tvOS)
        @Environment(\.isFocused) private var focused
        #else
        private let focused = false
        #endif
        let configuration: ButtonStyle.Configuration
        let poster: Bool

        var body: some View {
            #if os(tvOS)
            if poster {
                // The Poster strip draws its own focus (the sticker lifts, the
                // tape lights): no plate — a box around it was what made the
                // bar read as an afterthought on the ink band.
                configuration.label
                    .environment(\.seasonStripFocused, focused)
                    .scaleEffect(configuration.isPressed ? 0.98 : 1)
            } else {
                plate
            }
            #else
            plate
            #endif
        }

        private var plate: some View {
            configuration.label
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: poster ? 14 : 18, style: .continuous)
                        .fill(focused ? Palette.posterInk.opacity(0.92) : Palette.text(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: poster ? 14 : 18, style: .continuous)
                        .strokeBorder(focused ? Color.white : Palette.text(0.12), lineWidth: focused ? 4 : 1.5)
                }
                .rotationEffect(.degrees(poster && !focused ? -0.6 : 0))
                .scaleEffect(focused ? 1.03 : (configuration.isPressed ? 0.98 : 1))
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 18, y: 8)
                .animation(.spring(response: 0.28, dampingFraction: 0.62), value: focused)
        }
    }
}

// MARK: - Poster strip (tvOS)

private struct SeasonStripFocusedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    fileprivate var seasonStripFocused: Bool {
        get { self[SeasonStripFocusedKey.self] }
        set { self[SeasonStripFocusedKey.self] = newValue }
    }
}

/// The season bar in Poster Mode on the TV, drawn *into* the ink band rather
/// than boxed on top of it: the season is a white sticker hung off the teal
/// stripe above (big Anton number, like the episode cards'), a fixed readout
/// column beside it, and the run of the show as a tape of tabs out to the
/// screen's edge — each filled teal to how much has been watched, the
/// selected one a raised white tab.
///
/// **Nothing in it changes size when the season changes.** Every slot has a
/// fixed frame, the UP NEXT tag is shown or hidden rather than inserted, the
/// selected tab rises by an offset rather than by growing — Left/Right used
/// to resize the bar and jump the episode shelf under it.
private struct PosterSeasonStrip: View {
    let seasons: [Season]
    let order: [Int]
    let selected: Int
    let suggested: Int?
    let position: Int
    /// Touch (the iPad's episode drawer): the strip stacks — sticker and
    /// readout over the tape — the sticker opens the wall, ‹ › step, and the
    /// tabs take a tap or a drag. Nil on the TV, where the whole strip is one
    /// focusable button and Left/Right step.
    var onSelect: ((Int) -> Void)? = nil
    var onOpenAll: (() -> Void)? = nil
    /// Size, off the TV's 1.
    var s: CGFloat = 1

    @Environment(\.seasonStripFocused) private var focused

    private var touch: Bool { onSelect != nil }
    private var height: CGFloat { 96 * s }
    private var current: Season? { seasons.indices.contains(selected) ? seasons[selected] : nil }

    var body: some View {
        Group {
            if touch {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 18) {
                        sticker
                            .onTapGesture { onOpenAll?() }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Season \(current?.number ?? 0), show every season")
                        readout
                        Spacer(minLength: 0)
                        stepButton(-1, "chevron.left")
                        stepButton(1, "chevron.right")
                    }
                    // The sticker's full height (tilt and shadow included): at
                    // the readout's it ran down into the tape.
                    .frame(height: 128 * s)
                    tape.frame(height: 52)
                }
            } else {
                HStack(alignment: .center, spacing: 30) {
                    sticker
                        // Clear of the right chevron, which rides past the sticker's edge.
                        .padding(.trailing, 16)
                    readout
                    tape.frame(height: 64)
                }
                .frame(height: height)
            }
        }
        .animation(.snappy(duration: 0.2), value: selected)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: focused)
    }

    // The season as a sticker, hung off the stripe above the band.
    private var sticker: some View {
        VStack(spacing: -6 * s) {
            Text("SEASON")
                .font(Display.font(18 * s)).tracking(2 * s)
            Text(current.map { $0.number > 0 ? "\($0.number)" : "SP" } ?? "—")
                .font(Display.font(66 * s))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(current?.number ?? 0)))
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .foregroundStyle(Palette.posterInk)
        .frame(width: 138 * s, height: 116 * s)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                .strokeBorder(focused ? Palette.posterTeal : .clear, lineWidth: 5)
        }
        // TV: chevrons ride the sticker's edges while it has the remote.
        .overlay(alignment: .leading) { if !touch { chevron("chevron.left", on: position > 0).offset(x: -22) } }
        .overlay(alignment: .trailing) { if !touch { chevron("chevron.right", on: position < order.count - 1).offset(x: 22) } }
        .compositingGroup()
        .shadow(color: Palette.posterInk, radius: 0, x: 7 * s, y: 7 * s)
        .rotationEffect(.degrees(focused ? 0 : -3))
        .scaleEffect(focused ? 1.07 : 1)
        // TV: hangs up across the band's stripe — an offset, so the bar's
        // own height never includes it.
        .offset(y: touch ? 0 : -22)
    }

    private func chevron(_ name: String, on: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(Palette.posterInk)
            .frame(width: 34, height: 34)
            .background(Color.white, in: Circle())
            .overlay(Circle().strokeBorder(Palette.posterInk, lineWidth: 2.5))
            .opacity(focused && on ? 1 : 0)
    }

    private func stepButton(_ delta: Int, _ name: String) -> some View {
        let next = position + delta
        let enabled = order.indices.contains(next)
        return Button { if enabled { onSelect?(order[next]) } } label: {
            Image(systemName: name)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(Palette.posterInk)
                .frame(width: 44, height: 44)
                .background(Color.white, in: Circle())
                .overlay(Circle().strokeBorder(Palette.posterInk, lineWidth: 2.5))
                .compositingGroup()
                .shadow(color: Palette.posterInk, radius: 0, x: 3, y: 3)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
        .accessibilityLabel(delta < 0 ? "Previous season" : "Next season")
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            Text("UP NEXT")
                .font(Display.font(19 * s)).tracking(1.2)
                .foregroundStyle(Palette.posterInk)
                .padding(.horizontal, 8 * s).padding(.vertical, 2 * s)
                .background(Color(hex: "#F0525F"), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .rotationEffect(.degrees(-3))
                .opacity(selected == suggested ? 1 : 0)
            Text(current.map { SeasonGuide.readout(for: $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? " ")
                .font(Display.font(28 * s)).tracking(1)
                .foregroundStyle(Palette.textPrimary)
            Text("\(position + 1) OF \(seasons.count)")
                .font(Mono.font(13 * s, .bold)).tracking(1.5)
                .foregroundStyle(Palette.text(0.5))
        }
        .lineLimit(1)
        .frame(width: 170 * s, height: height, alignment: .leading)
    }

    // The whole run as a tape of tabs. Numbers on every tab up to 16
    // seasons, every fifth past that; the tape never scrolls.
    private var tape: some View {
        GeometryReader { geo in
            let count = max(order.count, 1)
            let spacing: CGFloat = count > 40 ? 3 : 6
            let width = min(110, max(6, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)))
            HStack(spacing: spacing) {
                ForEach(Array(order.enumerated()), id: \.element) { _, index in
                    tab(seasons[index], index: index, width: width,
                        labelled: count <= 16 || seasons[index].number % 5 == 0 || seasons[index].number == 1)
                }
            }
            .frame(height: geo.size.height, alignment: .center)
            #if os(iOS)
            // Tap a tab, or drag along the tape to scrub.
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let slot = width + spacing
                let i = min(max(Int((value.location.x / slot).rounded(.down)), 0), order.count - 1)
                if order.indices.contains(i), selected != order[i] { onSelect?(order[i]) }
            })
            #endif
        }
        .opacity(focused || touch ? 1 : 0.85)
    }

    private func tab(_ season: Season, index: Int, width: CGFloat, labelled: Bool) -> some View {
        let isSelected = index == selected
        let fill: Double = {
            switch SeasonGuide.state(of: season) {
            case .finished: return 1
            case .inProgress(let f): return max(f, 0.1)
            case .unwatched: return 0
            }
        }()
        let tabHeight: CGFloat = 44 * max(s, 0.8)
        let shape = RoundedRectangle(cornerRadius: min(8, width / 3), style: .continuous)
        return ZStack(alignment: .leading) {
            shape.fill(isSelected ? Color.white : Color(hex: "#262830"))
            if !isSelected {
                // Watched, left to right, like tape wound on.
                shape.fill(Palette.posterTeal.opacity(season.number == 0 ? 0.6 : 1))
                    .frame(width: width * fill)
            }
            if labelled && width >= 22 {
                Text(season.number == 0 ? "SP" : "\(season.number)")
                    .font(Display.font(width >= 44 ? 24 * max(s, 0.8) : 16))
                    .foregroundStyle(isSelected ? Palette.posterInk : (fill >= 0.5 ? Palette.posterInk : Palette.text(0.7)))
                    .frame(width: width)
            }
        }
        .frame(width: width, height: tabHeight)
        .clipShape(shape)
        .overlay(alignment: .top) {
            if index == suggested {
                Circle().fill(Color(hex: "#F0525F"))
                    .overlay(Circle().strokeBorder(Palette.posterInk, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(y: -9)
            }
        }
        .compositingGroup()
        .shadow(color: Palette.posterInk, radius: 0, x: isSelected ? 5 : 0, y: isSelected ? 5 : 0)
        // Raised by an offset, not a taller frame: the strip keeps its height.
        .offset(y: isSelected ? -8 : 0)
    }
}

// MARK: - Ribbon

/// Every season as a tick, left to right in `order`: filled from the bottom to
/// how much of it has been watched, full for a finished one, hollow for an
/// unwatched one. The selected tick is tall and white-edged; the suggested one
/// carries a coral dot above it. Numbers every fifth season so a long run can
/// be read like a ruler. On touch a drag along it scrubs the selection.
struct SeasonRibbon: View {
    let seasons: [Season]
    let order: [Int]
    @Binding var selected: Int
    let suggested: Int?
    let color: Color
    var height: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let count = max(order.count, 1)
            let spacing: CGFloat = count > 40 ? 2 : (count > 16 ? 3 : 5)
            let width = max(3, min(26, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(order.enumerated()), id: \.element) { position, index in
                        tick(seasons[index], index: index, width: width)
                    }
                }
                .frame(height: height, alignment: .bottom)
                HStack(spacing: spacing) {
                    ForEach(Array(order.enumerated()), id: \.element) { position, index in
                        let number = seasons[index].number
                        let label = number == 0 ? "SP" : ((number == 1 || number % 5 == 0 || count <= 12) ? "\(number)" : "")
                        Text(label)
                            .font(Mono.font(DeviceClass.current == .tv ? 12 : 9, .bold))
                            .foregroundStyle(Palette.text(index == selected ? 0.95 : 0.4))
                            .fixedSize()
                            .frame(width: width)
                    }
                }
            }
            #if os(iOS)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let slot = width + spacing
                let position = Int((value.location.x / slot).rounded(.down))
                let clamped = min(max(position, 0), order.count - 1)
                if order.indices.contains(clamped), selected != order[clamped] { selected = order[clamped] }
            })
            #endif
        }
        .frame(height: height + (DeviceClass.current == .tv ? 20 : 16))
        .animation(.snappy(duration: 0.2), value: selected)
        .accessibilityHidden(true)
    }

    private func tick(_ season: Season, index: Int, width: CGFloat) -> some View {
        let isSelected = index == selected
        let fill: Double = {
            switch SeasonGuide.state(of: season) {
            case .finished: return 1
            case .inProgress(let f): return max(f, 0.12)
            case .unwatched: return 0
            }
        }()
        let h = isSelected ? height : height * 0.62
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: min(width / 2, 4), style: .continuous)
                .fill(Palette.text(0.14))
            RoundedRectangle(cornerRadius: min(width / 2, 4), style: .continuous)
                .fill(color.opacity(season.number == 0 ? 0.6 : 1))
                .frame(height: h * fill)
        }
        .frame(width: width, height: h)
        .overlay(RoundedRectangle(cornerRadius: min(width / 2, 4), style: .continuous)
            .strokeBorder(isSelected ? Color.white : .clear, lineWidth: 2))
        .overlay(alignment: .top) {
            if index == suggested {
                Circle().fill(Color(hex: "#F0525F"))
                    .frame(width: max(6, min(width, 10)), height: max(6, min(width, 10)))
                    .offset(y: -12)
            }
        }
    }
}

// MARK: - The wall

/// Every season at once, as posters with their progress — for jumping from
/// season 3 to season 27 without twenty-four presses. Opened by Select on the
/// dial (tvOS) or a tap on its number (touch).
struct SeasonWall: View {
    let seasons: [Season]
    let fallbackImage: String?
    /// A still from inside each season, by season id (`AppState.seasonStills`)
    /// — preferred over the season's poster, which is often the same design
    /// every year. Empty until it loads; the posters stand in meanwhile.
    var stills: [String: String] = [:]
    let selected: Int
    let suggested: Int?
    var onPick: (Int) -> Void
    var onClose: () -> Void

    @EnvironmentObject private var theme: Theme
    @FocusState private var focused: Int?

    private var order: [Int] { SeasonGuide.displayOrder(seasons) }
    private var isTV: Bool { DeviceClass.current == .tv }
    private var columns: [GridItem] {
        let minimum: CGFloat = isTV ? 170 : (DeviceClass.current == .phone ? 96 : 130)
        return [GridItem(.adaptive(minimum: minimum), spacing: isTV ? 30 : 14)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isTV ? 28 : 16) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if theme.isPoster {
                    PosterSectionHeader(title: "All Seasons", count: seasons.count)
                        .padding(.horizontal, isTV ? -56 : -20)
                } else {
                    Text("All seasons")
                        .font(Typography.font(isTV ? 44 : 26, .black))
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer(minLength: 0)
                #if os(iOS)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .black))
                        .frame(width: 40, height: 40)
                        .background(Palette.text(0.12), in: Circle())
                        .foregroundStyle(Palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                #endif
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: isTV ? 34 : 18) {
                        ForEach(order, id: \.self) { index in
                            Button { onPick(index) } label: { tile(index) }
                                .buttonStyle(CardFocusStyle(glow: Palette.posterTeal, scale: 1.08))
                                .focused($focused, equals: index)
                                .id(index)
                        }
                    }
                    .padding(isTV ? 30 : 4)
                }
                .onAppear {
                    proxy.scrollTo(selected, anchor: .center)
                    focused = selected
                }
            }
        }
        .padding(isTV ? 80 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.pageBase.opacity(0.97).ignoresSafeArea())
        #if os(tvOS)
        .onExitCommand(perform: onClose)
        #endif
    }

    private func tile(_ index: Int) -> some View {
        let season = seasons[index]
        let state = SeasonGuide.state(of: season)
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                // The tile's shape comes from a clear 2:3 box; the art only
                // fills it. The season's own poster when it has one; else a
                // poster made for it (`madePoster`) — never the show's
                // backdrop repeated down the wall.
                Color.clear
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay { artwork(season) }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(index == selected ? Color.white : Palette.text(0.12),
                                      lineWidth: index == selected ? 4 : 1))
                    .grayscale(state == .finished ? 0.8 : 0)
                GeometryReader { geo in
                    let fraction: Double = {
                        switch state { case .finished: return 1; case .inProgress(let f): return f; case .unwatched: return 0 }
                    }()
                    Rectangle().fill(theme.isPoster ? Palette.posterTeal : theme.accent)
                        .frame(width: geo.size.width * fraction, height: 5)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                if state == .finished {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: isTV ? 30 : 18, weight: .bold))
                        .foregroundStyle(.white, Palette.posterInk)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                if index == suggested {
                    Text("UP NEXT")
                        .font(Display.font(isTV ? 18 : 11))
                        .foregroundStyle(Palette.posterInk)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: "#F0525F"), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .rotationEffect(.degrees(-4))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            Text(season.number > 0 ? "SEASON \(season.number)" : "SPECIALS")
                .font(theme.isPoster ? Display.font(isTV ? 24 : 14) : Typography.font(isTV ? 20 : 13, .heavy))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            let readout = SeasonGuide.readout(for: season)
            if !readout.isEmpty {
                Text(readout)
                    .font(Mono.font(isTV ? 14 : 10, .bold))
                    .foregroundStyle(Palette.text(0.5))
            }
        }
    }

    @ViewBuilder private func artwork(_ season: Season) -> some View {
        if let poster = season.image, let url = URL(string: poster) {
            JellyfinAsyncImage(url: url, fallback: blank)
        } else {
            madePoster(season)
        }
    }

    private var blank: LinearGradient {
        LinearGradient(colors: [Palette.text(0.1), Palette.text(0.03)], startPoint: .top, endPoint: .bottom)
    }

    /// A season with no poster of its own gets one made: a still from inside
    /// that season (`stills`) over ink, the teal/coral stripes where they
    /// meet, and the number set big enough to find the season by. A season
    /// the server has no pictures for at all (South Park 19–26 here: no
    /// poster, no episode stills) gets a ground of its own colour instead —
    /// the show's backdrop repeated down the wall is what made every one of
    /// them look the same.
    private func madePoster(_ season: Season) -> some View {
        let still = stills[season.id]
        let numberSize: CGFloat = isTV ? 110 : (DeviceClass.current == .phone ? 58 : 76)
        // Walk the hue wheel by season so neighbours never match.
        let hue = (Double(max(season.number, 0)) * 0.137).truncatingRemainder(dividingBy: 1)
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Palette.posterInk
                PosterStripeBand().opacity(0.8)
                Group {
                    if let still, let url = URL(string: still) {
                        JellyfinAsyncImage(url: url, fallback: blank)
                    } else {
                        ZStack {
                            Color(hue: hue, saturation: 0.55, brightness: 0.78)
                            PosterPaper(dotColor: .white.opacity(0.22), spacing: 10, radius: 0.9)
                        }
                    }
                }
                .frame(width: w, height: h * 0.58)
                .clipped()
                PosterAccentStripes(angle: .degrees(-12), length: w * 1.6, scale: isTV ? 0.5 : 0.28)
                    .frame(width: w, height: h * 0.58, alignment: .bottom)
                    .offset(x: -w * 0.2, y: isTV ? 10 : 6)
                Text(season.number > 0 ? String(format: "%02d", season.number) : "SP")
                    .font(Display.font(numberSize))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.leading, isTV ? 14 : 8)
                    .frame(width: w, height: h, alignment: .bottomLeading)
                    .offset(y: numberSize * 0.06)
            }
            .frame(width: w, height: h)
        }
        .accessibilityHidden(true)
    }
}
