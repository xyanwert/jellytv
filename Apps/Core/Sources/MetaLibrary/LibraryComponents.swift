import SwiftUI
import JellyTVKit

#if os(iOS)
/// Fixes a standard UIKit tap/scroll interaction, not a bug in any one
/// screen: `UIScrollView.delaysContentTouches` (on by default) holds a touch
/// for a beat to see whether it's the start of a scroll before handing it to
/// the content underneath, and while the view is still gliding from a
/// momentum scroll, that held touch is consumed as "stop scrolling" instead
/// of reaching the card's `Button` at all. Reproduced directly: with the grid
/// settled (two accessibility snapshots a second apart showing identical
/// positions) a tap always fired; the same tap landed on a card still
/// decelerating from a scroll and fired nothing, sometimes for more than one
/// attempt in a row — exactly "the first page is fine, but scrolling brings
/// the problem back". Disabling the delay lets the very next touch-down
/// activate its control immediately, scrolling or not.
private struct ScrollTouchDelayFix: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // The responder chain from a plain `UIView` walks up through
        // superviews, which is however many layers of SwiftUI's own hosting
        // views sit between this and the actual `UIScrollView` backing the
        // enclosing `ScrollView`.
        var responder: UIResponder? = uiView
        while let current = responder {
            if let scrollView = current as? UIScrollView {
                scrollView.delaysContentTouches = false
                return
            }
            responder = current.next
        }
    }
}

extension View {
    /// See `ScrollTouchDelayFix`. Attach to the content placed directly
    /// inside a `ScrollView` (not the `ScrollView` itself).
    func fixesScrollTapDelay() -> some View {
        background(ScrollTouchDelayFix())
    }
}
#endif

/// Sort chips shared by the Movies and Shows library screens. Each maps to a
/// real Jellyfin `sortBy`/`sortOrder` pair — picking a chip re-fetches the
/// library in that order rather than just re-arranging local state.
enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case az = "A–Z"
    case topRated = "Top Rated"

    var id: String { rawValue }

    var query: (sortBy: String, sortOrder: String) {
        switch self {
        case .newest: return ("DateCreated", "Descending")
        case .az: return ("SortName", "Ascending")
        case .topRated: return ("CommunityRating", "Descending")
        }
    }
}

/// The genre tail of a `MediaItem.meta` line ("Movie · Thriller" → "Thriller").
extension MediaItem {
    var genre: String {
        guard meta.contains("·") else { return "" }
        return meta.split(separator: "·").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// True when every term matches — title, genre, or a Jellyfin tag
    /// contains it (case-insensitive) — so `TagSearchField`'s chips AND
    /// together instead of only ever narrowing on title text. An empty term
    /// list always matches (no filter applied).
    func matches(allOf terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        return terms.allSatisfy { term in
            title.localizedCaseInsensitiveContains(term)
                || genre.localizedCaseInsensitiveContains(term)
                || tags.contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }
}

/// A tvOS-adapted, chip/tag-based search field for the library screens.
/// Pressing Return commits the current text as an accent-filled capsule
/// inline in the field and clears the live text; selecting the field again
/// starts the next term. Every committed chip ANDs together (via
/// `MediaItem.matches(allOf:)`) rather than replacing the previous search,
/// so "yuri" then "tentacle" narrows to items matching both — built for
/// libraries whose items carry rich Jellyfin `Tags` metadata that a single
/// free-text field can't express. Backspace on an empty live-text field pops
/// the most recent chip. Same underlying `TVTextField` UIKit bridge as
/// `AppTextField` (a focused tvOS `TextField` paints an unremovable white
/// pill and won't reliably raise the keyboard for an off-screen field) — a
/// separate view rather than a new `AppTextField` mode because the chip row
/// needs a materially different label layout.
///
/// Return committing *and* keeping the keyboard up for the next term was
/// tried and reverted: tvOS's system text-input overlay dismisses itself on
/// Return regardless of whether the app resigns first responder, and while
/// silently reclaiming first-responder afterward let plain characters keep
/// being captured, a second physical Return then never reached
/// `textFieldShouldReturn` at all (confirmed — no delegate callback fired) —
/// so the field looked like it accepted a second term but silently dropped
/// it on submit. Requiring one more Select between terms is worse UX but
/// actually reliable.
struct TagSearchField<F: Hashable>: View {
    @Binding var tags: [String]
    @Binding var liveText: String
    let placeholder: String
    let accent: Color
    var trailing: String? = nil
    let field: F
    var focus: FocusState<F?>.Binding

    @State private var editing = false

    private var isFocused: Bool { focus.wrappedValue == field }
    private var isEmpty: Bool { liveText.isEmpty }

    /// Shorter on iPad than the tvOS field's 60pt: it sits inline with the
    /// filter chips in `LibraryControlBar` rather than on a row of its own,
    /// so it should read as part of that line — still well clear of the 44pt
    /// touch minimum. (A generic type can't hold a `static let`, hence a
    /// computed property.)
    private var iosFieldHeight: CGFloat { 48 }

    var body: some View {
        #if os(iOS)
        iosField
            .frame(height: iosFieldHeight)
        #else
        ZStack {
            if isFocused || editing {
                TVTextField(text: $liveText, isSecure: false, isEditing: $editing,
                            onSubmit: commit, onDeleteBackward: deleteLastChip)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .opacity(0.02)
            }

            Button { editing = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.text(0.45))
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(Typography.font(15, .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accent, in: Capsule())
                    }
                    Text(displayText)
                        .font(Typography.font(20, .semibold))
                        .foregroundStyle(isEmpty ? Palette.text(0.32) : Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let trailing {
                        Text(trailing)
                            .font(Mono.font(16, .bold))
                            .foregroundStyle(Palette.text(0.4))
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(stroke, lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .animation(.easeOut(duration: 0.18), value: isFocused)
            }
            .buttonStyle(AppTextFieldButtonStyle())
            .focused(focus, equals: field)
        }
        .onChange(of: editing) {
            if !editing { focus.wrappedValue = field }
        }
        .frame(height: 60)
        #endif
    }

    #if os(iOS)
    @ViewBuilder private var iosField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.text(0.45))
            ForEach(tags, id: \.self) { tag in
                // Tapping a chip removes it — touch's natural substitute for
                // tvOS's "backspace on an empty field pops the last chip".
                Button { tags.removeAll { $0 == tag } } label: {
                    HStack(spacing: 4) {
                        Text(tag).font(Typography.font(15, .bold)).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            TextField("", text: $liveText, prompt: Text(placeholder).foregroundStyle(Palette.text(0.32)))
                .font(Typography.font(20, .semibold))
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focus, equals: field)
                .onSubmit(commit)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(Mono.font(16, .bold))
                    .foregroundStyle(Palette.text(0.4))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: iosFieldHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(stroke, lineWidth: 1.5))
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
    #endif

    private var displayText: String { isEmpty ? placeholder : liveText }
    private var fill: Color { .white.opacity(isFocused ? 0.08 : 0.05) }
    private var stroke: Color { isFocused ? accent : .white.opacity(0.14) }

    private func commit() {
        let trimmed = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        liveText = ""
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        tags.append(trimmed)
    }

    private func deleteLastChip() {
        guard !tags.isEmpty else { return }
        tags.removeLast()
    }
}

/// Restacks a library screen's header (title block + search + Play/Random)
/// for phone width. iPad packs all three into one `HStack` because there's
/// room; at phone width the title block's `.fixedSize()` (needed so a long
/// eyebrow/title doesn't get squeezed) instead forced the search field and
/// both buttons off the trailing edge — the exact "iPad layout clipped into
/// a narrow column" symptom this pass exists to fix.
///
/// **Phone drops `search()` and `actions()` entirely — title only.** Per
/// `Browse.dc.html`: there is one search on this phone (the Search tab), so
/// a per-library search field is a second, redundant entry point rather than
/// a convenience; and Play/Random were explicitly deferred (nothing replaces
/// them here). Both closures are still required parameters so every call
/// site keeps one shared header shape, but on phone neither is ever invoked
/// — a library screen's phone header is exactly the eyebrow/title/count
/// block, with Sort/Genre living one row down in its own dropdown bar (see
/// `LibrarySortGenreDropdownBar`). Shared by all five library screens
/// (Movies, Shows, Anime, Late Night, Home Videos) rather than each
/// re-deriving its own phone breakpoint.
///
/// **tvOS: the search field is compact and trailing, not the header.** It
/// used to be a 1000pt bar that took the row for itself and took default
/// focus with it, so every library opened on a glowing empty text field.
/// Search on a TV is a secondary act — the on-screen keyboard is the worst
/// part of the platform — so it sits at the trailing end at a fixed width,
/// the title breathes, and focus lands on the content instead.
struct LibraryHeaderLayout<TitleBlock: View, Search: View, Actions: View>: View {
    @ViewBuilder var titleBlock: () -> TitleBlock
    @ViewBuilder var search: () -> Search
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        if DeviceClass.current == .phone {
            titleBlock()
        } else {
            HStack(spacing: 20) {
                titleBlock()
                #if os(tvOS)
                Spacer(minLength: 24)
                search().frame(width: 440)
                #else
                search()
                #endif
                actions()
            }
        }
    }
}

/// Small shared answers for the library headers, so five screens don't drift.
enum LibraryChrome {
    /// "30 titles", or "12 of 30 titles" once a filter or search narrows the
    /// list. One number in one place — it used to be printed three times
    /// (header, search field, "Showing N of M" over the grid).
    static func countLabel(shown: Int, total: Int, noun: String) -> String {
        shown == total ? "\(total) \(noun)" : "\(shown) of \(total) \(noun)"
    }

    /// The search field's trailing count — iPad only. On tvOS the field is
    /// compact and the header count beside the title already says it.
    static func searchTrailing(count: Int) -> String? {
        #if os(tvOS)
        return nil
        #else
        return "\(count)"
        #endif
    }
}

/// The grid's stand-in until the first real fetch resolves — never the sample
/// catalog. One shape for the five library screens.
struct LibraryLoadingState: View {
    let message: String
    let accent: Color

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(accent)
            Text(message)
                .font(Typography.font(17, .medium))
                .foregroundStyle(Palette.text(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }
}

#if os(iOS)
/// Phone's replacement for the horizontal `LibraryFilterChip` scroll:
/// Sort and Genre each become a `Menu` dropdown showing the current value,
/// with a tick against the active row (`Browse.dc.html`'s open-menu state).
/// A phone can't scroll a chip rail and read it at the same time, and a
/// deep library's genre list is as long as the catalog is varied — a
/// dropdown shows one answer and puts the rest one tap away instead of
/// running every option past the trailing edge. iPad/tvOS keep the chip
/// rail (more room, and chips read from across the room on tvOS); this is
/// phone-only, shared by Movies/Shows/Anime/Late Night — the four screens
/// built on `LibrarySort` + a genre filter.
struct LibrarySortGenreDropdownBar: View {
    @Binding var sort: LibrarySort
    let genres: [String]
    @Binding var selectedGenre: String?
    /// Overrides the sort dropdown's "active" tint — Anime/Late Night's own
    /// identity color, same override `LibraryFilterChip` takes.
    var accent: Color? = nil
    /// The library's unfiltered total, shown at the row's trailing edge —
    /// `Browse.dc.html` repeats it here even though the section caption row
    /// below also says it, as a quiet "this is the whole library" anchor
    /// next to the controls that narrow it.
    let totalCount: Int

    @EnvironmentObject private var theme: Theme
    private var effectiveAccent: Color { accent ?? theme.accent }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(LibrarySort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                LibraryDropdownPill(icon: "arrow.up.arrow.down", text: sort.rawValue, active: true, accent: effectiveAccent)
            }
            Menu {
                Button {
                    selectedGenre = nil
                } label: {
                    if selectedGenre == nil {
                        Label("All genres", systemImage: "checkmark")
                    } else {
                        Text("All genres")
                    }
                }
                ForEach(genres, id: \.self) { genre in
                    Button {
                        selectedGenre = genre
                    } label: {
                        if selectedGenre == genre {
                            Label(genre, systemImage: "checkmark")
                        } else {
                            Text(genre)
                        }
                    }
                }
            } label: {
                LibraryDropdownPill(icon: nil, text: selectedGenre ?? "All genres", active: false, accent: effectiveAccent)
            }
            Spacer(minLength: 0)
            Text("\(totalCount)")
                .font(Mono.font(11, .bold))
                .foregroundStyle(Palette.text(0.32))
        }
    }

}

/// The visual half of a phone library dropdown — a `Menu`'s label, not the
/// menu itself, so any screen with its own picker (Sort/Genre here, Search's
/// own TYPE filter) gets the identical pill rather than a close approximation.
/// Free-standing rather than nested in `LibrarySortGenreDropdownBar` for
/// exactly that reason — Search's filter isn't a `LibrarySort`, so it can't
/// share that struct, only this look.
struct LibraryDropdownPill: View {
    let icon: String?
    let text: String
    let active: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(active ? accent : Palette.text(0.7))
            }
            Text(text)
                .font(Typography.font(15, .heavy))
                .foregroundStyle(active ? Palette.textPrimary : Palette.text(0.72))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(active ? accent : Palette.text(0.45))
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(active ? accent.opacity(0.12) : Palette.text(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(active ? accent.opacity(0.45) : Palette.text(0.13), lineWidth: 1))
    }
}

/// A same-height (42pt) companion to `LibraryDropdownPill` for a plain
/// on/off toggle sitting beside it — Search's Unwatched/NSFW, which are
/// independent booleans, not a list to pick one item from, so they were
/// never a dropdown candidate in the first place (see `phoneFilterRow`).
/// The `LibraryFilterChip` text-label version of these two was itself the
/// problem: "Unwatched" plus "NSFW" plus the TYPE dropdown ran past a
/// phone's content width and needed a `ScrollView` with NSFW cut off at the
/// trailing edge. Icon-only, at a fixed square instead of hugging a label,
/// is what actually fits the row — the tradeoff is a first look has to learn
/// what eye-slash/lock mean, same bargain the chrome's own glyph-only
/// controls already make.
struct LibraryIconToggleChip: View {
    let systemImage: String
    let isOn: Bool
    let accent: Color
    let action: () -> Void
    let accessibilityLabel: String

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isOn ? .white : Palette.text(0.7))
                .frame(width: 42, height: 42)
                .background(isOn ? accent : Palette.text(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isOn ? .clear : Palette.text(0.13), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 12))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
#endif

extension View {
    /// The library screens' outer content margin — 48pt on iPad/tvOS (room to
    /// spare in landscape), 20pt on phone (a portrait column can't give up
    /// that much to both edges and still leave the search field/grid usable).
    func libraryContentMargin() -> some View {
        padding(.horizontal, DeviceClass.current == .phone ? 20 : 48)
    }

    /// A library header's title block wants `.fixedSize()` on iPad/tvOS — it
    /// shares a row with `search()`/`actions()` there, and without it a long
    /// eyebrow/title gets squeezed by its neighbors. On phone `search()`/
    /// `actions()` are gone (`LibraryHeaderLayout`) and the title block owns
    /// the whole row alone, so the same `.fixedSize()` instead makes it
    /// report its full unconstrained width regardless of the phone's actual
    /// (much narrower) column — the eyebrow row and the "N titles" count
    /// bleed straight off the trailing edge with nothing to wrap or clip
    /// them (seen on Late Night's "LIBRARY // LATE NIGHT [18+]" + "Late
    /// Night 500 titles 深夜アニメ", the widest of the five headers).
    /// Dropping the horizontal fix on phone lets the text wrap/truncate
    /// against the real proposed width instead.
    func libraryTitleBlockSizing() -> some View {
        #if os(iOS)
        fixedSize(horizontal: DeviceClass.current != .phone, vertical: true)
        #else
        fixedSize()
        #endif
    }
}

/// A compact "🔒 18+" pill — the rail's `LibrariesSubmenu` row and any screen
/// header that needs to flag its whole catalog as adult content share this
/// one visual, rather than each re-declaring the lock icon + pill chrome.
struct AdultBadge: View {
    var accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill").font(.system(size: 10, weight: .heavy))
            Text("18+").font(Typography.font(12, .black))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: accent.opacity(0.55), radius: 8)
    }
}

/// A single filter/sort chip, shared by both library screens' filter bars.
struct LibraryFilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void
    /// Overrides the "on" fill (`theme.accent`) — used by a meta-category
    /// screen with its own identity color (design 4b's magenta anime accent).
    var accent: Color? = nil
    /// Leading SF Symbol — e.g. "eye.slash" for an Unwatched toggle,
    /// "lock.fill" for an NSFW toggle — so a chip that isn't a plain sort/
    /// genre label still reads as a distinct kind of control at a glance.
    var systemImage: String? = nil

    @EnvironmentObject private var theme: Theme

    private var effectiveAccent: Color { accent ?? theme.accent }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 14, weight: .bold))
                }
                Text(label)
            }
            .font(Typography.font(17, .bold))
            .lineLimit(1)
        }
        .buttonStyle(FilterChipStyle(isOn: isOn, accent: effectiveAccent))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// How a filter chip wears its two states — *selected* and *focused* — so
/// that they never read as one.
///
/// **Selected is the accent; focused is white.** Before this, a focused chip
/// was the resting grey pill with `FocusScaleStyle`'s thin LED ring drawn
/// around it — on a 40pt capsule that ring is a hairline, the label stayed at
/// 70% grey, and the cursor was visibly *weaker* than the accent-filled chip
/// it sat next to. Now the pill under the remote turns solid white with ink
/// text, lifts by 10% and carries the accent's glow, which is what every TV
/// app does with a focused pill and reads from across the room. A chip that
/// is selected *and* focused keeps the white pill and sets its label in the
/// accent, so moving the remote onto the active filter still says "this one
/// is on" without two accent fills fighting.
///
/// On touch there is no focus: the chip is exactly what it was (accent or
/// translucent, with a press dip).
struct FilterChipStyle: ButtonStyle {
    let isOn: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, isOn: isOn, accent: accent)
    }

    private struct Content: View {
        #if os(tvOS)
        @Environment(\.isFocused) private var focused: Bool
        #else
        private let focused = false
        #endif
        let configuration: ButtonStyle.Configuration
        let isOn: Bool
        let accent: Color

        private static let ink = Color(hex: "#0C0F16")

        var body: some View {
            configuration.label
                .foregroundStyle(textColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(fill, in: Capsule())
                .overlay(Capsule().stroke(stroke, lineWidth: 1.5))
                .scaleEffect(focused ? 1.1 : (configuration.isPressed ? 0.96 : 1))
                // A plain dark lift, nothing tinted: an accent-coloured glow
                // under a white pill read as a red smear bleeding into the
                // backdrop. The white fill against the grey row already *is*
                // the focus signal; it needs a shadow, not a halo.
                .shadow(color: focused ? .black.opacity(0.4) : .clear, radius: 10, y: 4)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focused)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }

        private var fill: Color {
            if focused { return .white }
            return isOn ? accent : Palette.text(0.06)
        }

        private var textColor: Color {
            if focused { return isOn ? accent : Self.ink }
            return isOn ? .white : Palette.text(0.7)
        }

        private var stroke: Color {
            (focused || isOn) ? .clear : Palette.text(0.14)
        }
    }
}

/// What the Random button is doing right now.
enum RandomPlayState: Equatable {
    case idle
    /// A queue is being built — a round trip over a whole library.
    case loading
    /// The scope came back with nothing playable.
    case empty
}

/// The Random button, on both platforms, and the whole of its state machine.
///
/// **It reports itself because it is slow enough to look broken.** A press
/// builds a play queue over an entire library server-side — half a second on
/// a small one, longer on thousands of episodes — and an unchanged button
/// during that gap gets pressed again, which would throw the first queue away
/// and start a second. So the glyph becomes a spinner, and a second press is
/// swallowed rather than queued behind the first.
///
/// **Empty is a caption, not a silence.** A scope with nothing playable in it
/// says so for a beat and then returns to normal; a button that simply does
/// nothing reads as a bug, which is exactly what v1 found the hard way. The
/// frame carries a `minWidth` sized for the longest of the three labels so
/// the row it sits in doesn't reflow as the state changes.
struct RandomPlayButton: View {
    /// iPad's compact control-bar pill, tvOS's header pill, or a bare square
    /// icon (Search's field-height companion buttons) — three presentations
    /// of the same build-a-queue-and-play state machine.
    enum Size {
        case bar, header
        case icon(dimension: CGFloat, cornerRadius: CGFloat, glyphSize: CGFloat)
    }

    let size: Size
    @Binding var state: RandomPlayState
    let action: () -> Void
    /// Every existing caller wants "shuffle"/"Random" — Search's Play
    /// button, sharing this same state machine, is the one exception.
    var idleGlyph: String = "shuffle"
    var idleLabel: String = "Random"

    private var label: String {
        switch state {
        case .idle, .loading: return idleLabel
        case .empty: return "Nothing to play"
        }
    }

    private var isBar: Bool { if case .bar = size { return true }; return false }

    var body: some View {
        switch size {
        case .bar, .header:
            pillBody
        case .icon(let dimension, let cornerRadius, let glyphSize):
            iconBody(dimension: dimension, cornerRadius: cornerRadius, glyphSize: glyphSize)
        }
    }

    private var pillBody: some View {
        let corner: CGFloat = isBar ? 12 : 14
        let minWidth: CGFloat = isBar ? 158 : 196
        return Button(action: action) {
            HStack(spacing: isBar ? 8 : 10) {
                glyph(size: isBar ? 15 : 18)
                Text(label)
                    .font(isBar ? Typography.font(16, .semibold) : Typography.button)
                    .lineLimit(1)
            }
            .foregroundStyle(isBar ? Palette.text(0.85) : Color.white)
            .frame(minWidth: minWidth)
            .padding(.horizontal, isBar ? 16 : 24)
            .modifier(RandomPlayButtonShape(isBar: isBar, corner: corner))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: corner))
        .fixedSize()
        .accessibilityLabel(state == .loading ? "Building a random queue" : label)
        // Owned here rather than by each screen: five callers would otherwise
        // each need the same timer to undo the same transient message.
        .task(id: state) {
            guard state == .empty else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if state == .empty { state = .idle }
        }
    }

    private func iconBody(dimension: CGFloat, cornerRadius: CGFloat, glyphSize: CGFloat) -> some View {
        Button(action: action) {
            glyph(size: glyphSize)
                .foregroundStyle(Palette.text(0.85))
                .frame(width: dimension, height: dimension)
                .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Palette.text(0.16), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: cornerRadius))
        .accessibilityLabel(state == .loading ? "Building a queue" : label)
        .task(id: state) {
            guard state == .empty else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if state == .empty { state = .idle }
        }
    }

    @ViewBuilder
    private func glyph(size: CGFloat) -> some View {
        switch state {
        case .idle:
            Image(systemName: idleGlyph).font(.system(size: size, weight: .semibold))
        case .loading:
            // Sized to the glyph it replaces, so the row holds still.
            ProgressView()
                .controlSize(.small)
                .frame(width: size, height: size)
        case .empty:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: size, weight: .semibold))
        }
    }
}

/// The two canvases' background/height treatments, split out only because a
/// `ViewBuilder` can't branch on the fill and the frame in one expression
/// without duplicating the whole label.
private struct RandomPlayButtonShape: ViewModifier {
    let isBar: Bool
    let corner: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return Group {
            if isBar {
                content.frame(height: 48)
            } else {
                content.padding(.vertical, 15)
            }
        }
        .background(Palette.text(isBar ? 0.08 : 0.1), in: shape)
        .overlay(shape.stroke(Palette.text(isBar ? 0.16 : 0.2), lineWidth: 1))
    }
}

/// Home Videos' sort/filter row — `[Latest Added][Shuffled] | [Unwatched][Favorites]`.
/// The separate Random *button* that plays immediately lives outside this
/// row entirely (`VideosLibraryView.header`) — see `VideosLibraryView.Sort`
/// for why the sort chip and the play button are deliberately different
/// controls, and why the chip stopped being called "Random" too.
///
/// **Two groups, not one.** "Latest Added" and "Shuffled" are an exclusive pick
/// of what order the grid itself shows, so they read as one cluster.
/// "Unwatched" and "Favorites" are independent filters of what's on screen
/// and can combine with each other or with either sort, so a hairline
/// divider keeps the two kinds of chip from reading as one long row.
struct HomeVideoFilterBar: View {
    let accent: Color
    @Binding var sort: VideosLibraryView.Sort
    @Binding var unwatchedOnly: Bool
    @Binding var favoritesOnly: Bool
    /// Fired on every tap of the Random chip, even one that doesn't change
    /// `sort` — see `VideosLibraryView.randomSortNonce`.
    let onSelectRandom: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LibraryFilterChip(label: VideosLibraryView.Sort.latestAdded.label,
                              isOn: sort == .latestAdded,
                              action: { sort = .latestAdded }, accent: accent)
            LibraryFilterChip(label: VideosLibraryView.Sort.random.label,
                              isOn: sort == .random,
                              action: { sort = .random; onSelectRandom() }, accent: accent)
            Rectangle().fill(Palette.text(0.14)).frame(width: 1, height: 24)
            LibraryFilterChip(label: "Unwatched", isOn: unwatchedOnly,
                              action: { unwatchedOnly.toggle() }, accent: accent)
            LibraryFilterChip(label: "Favorites", isOn: favoritesOnly,
                              action: { favoritesOnly.toggle() }, accent: accent)
        }
    }
}

#if os(iOS)
/// Picks which item's artwork becomes a library screen's page backdrop.
///
/// iPad-only, and only because iPad has no selection: tvOS points the
/// backdrop at whatever poster the remote is focused on, so it always has a
/// meaningful answer. With that band removed from iPad there is nothing
/// "selected", so the screen picks one title at random per visit instead —
/// the library gets a different face each time you open it rather than
/// always wearing its newest item's art.
///
/// Prefers items with a real wide `backdropImage`; only if the library has
/// none at all does it settle for poster art, which crops badly full-screen.
enum LibraryBackdrop {
    static func pick(from items: [MediaItem]) -> String? {
        let wide = items.filter { $0.backdropImage != nil }
        let pool = wide.isEmpty ? items.filter { $0.image != nil } : wide
        return pool.randomElement()?.id
    }
}
#endif

/// Stands in for the poster grid when there's nothing to draw. An empty
/// library otherwise leaves the whole screen blank below the control bar,
/// which reads as a failure rather than as "this library has no items" — on
/// tvOS too, where the hero has nothing to show either when the list is empty
/// (that was the Anime screen for a while: a title, three chips, and a
/// thousand pixels of nothing).
///
/// Says which of the two empty cases it is, since they need different
/// actions from the user — narrow the filters, or go classify a library.
struct LibraryEmptyState: View {
    let message: String
    var hint: String? = nil

    #if os(tvOS)
    private static let messageSize: CGFloat = 26
    private static let hintSize: CGFloat = 18
    private static let topPadding: CGFloat = 140
    #else
    private static let messageSize: CGFloat = 20
    private static let hintSize: CGFloat = 14
    private static let topPadding: CGFloat = 120
    #endif

    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(Typography.font(Self.messageSize, .semibold))
                .foregroundStyle(Palette.text(0.55))
            if let hint {
                Text(hint)
                    .font(Typography.font(Self.hintSize, .medium))
                    .foregroundStyle(Palette.text(0.38))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Self.topPadding)
    }
}

/// The focused item's full-screen backdrop — pinned to the top, behind the
/// rail/content, scrimmed for legibility and alpha-masked at the bottom so it
/// dissolves into the page over the first poster row. Shared by the Movies and
/// Shows library screens; sits behind the header, filters, and the selected-
/// item band so the image reads across the whole top of the screen.
struct SelectedBackdrop: View {
    let item: MediaItem
    /// Extra gaussian blur over the whole backdrop, from Settings →
    /// Appearance → "Background library image effect". Defaults to 0 so the
    /// tvOS call sites — where the backdrop is the *focused* item's art and
    /// is meant to be legible as a picture — keep the sharp treatment they
    /// were designed with.
    var blur: Double = 0

    /// How far down the screen the backdrop reaches before it has fully faded
    /// out — tall enough to cover the header, filters, the text band, and the
    /// top of the first poster row.
    private static let height: CGFloat = 900
    /// Shift the image content up so it sits a little higher than dead-center —
    /// the top of the art rides above the screen edge (roughly y = -100).
    private static let imageShift: CGFloat = -100

    /// The high-resolution wide image (real Backdrop when present), falling
    /// back to the poster if that's all the item has.
    private var imageURL: String? { item.backdropImage ?? item.image }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                heroImage(width: geo.size.width, blur: CGFloat(blur))
                    .opacity(0.9)
                // A softly-blurred copy of the image, shown only across the
                // top (behind the header/filters) and fading to the sharp
                // image below — takes the visual busyness out from under the
                // header without blurring the whole backdrop. `max` so it
                // never comes out *sharper* than the base layer when the
                // whole backdrop is already blurred.
                heroImage(width: geo.size.width, blur: max(18, CGFloat(blur)))
                    .opacity(0.9)
                    .mask(topBlur)
                scrims
            }
            .frame(width: geo.size.width, height: Self.height, alignment: .top)
            .mask(bottomFade)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .id(item.id)
        .transition(.opacity)
    }

    /// The backdrop rendered into a 1.5× box then clipped back to the frame —
    /// the same 50% zoom `HomeView.heroImage` applies, so the backdrop reads
    /// bigger/closer without changing its footprint. The image content is
    /// shifted up by `imageShift`; the blur (when set) is applied on the
    /// oversized box before clipping so it doesn't bleed transparent edges.
    private func heroImage(width: CGFloat, blur: CGFloat = 0) -> some View {
        backdrop
            .frame(width: width * 1.5, height: Self.height * 1.5)
            .blur(radius: blur)
            .offset(y: Self.imageShift)
            .frame(width: width, height: Self.height)
            .clipped()
    }

    @ViewBuilder private var backdrop: some View {
        if let art = imageURL, art.hasPrefix("http"), let url = URL(string: art) {
            JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
        } else if let art = imageURL {
            Image(art).resizable().scaledToFill()
        } else {
            item.artwork.gradient
        }
    }

    /// Mask for the blurred copy: opaque across the top (behind the header and
    /// filters), fading to clear so the sharp image shows below.
    private var topBlur: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.10),
                .init(color: .clear, location: 0.24),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// The darkening scrims from `HomeView.heroScrims`: a left→right scrim so
    /// the title/synopsis stay legible over the art, a top darkening so the
    /// header controls read over it, and a pre-darkening toward black at the
    /// bottom *before* the alpha mask cuts it away — that pre-darkening is what
    /// makes the image dissolve into the page rather than read as a hard cut.
    private var scrims: some View {
        Color.clear
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0.0),
                        .init(color: .black.opacity(0.35), location: 0.35),
                        .init(color: .black.opacity(0.10), location: 0.70),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.5), location: 0.0),
                        .init(color: .black.opacity(0.28), location: 0.07),
                        .init(color: .clear, location: 0.18),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.62),
                        .init(color: .black.opacity(0.5), location: 0.85),
                        .init(color: .black.opacity(0.9), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
    }

    /// Fades the bottom of the backdrop to transparent so it blends into the
    /// content below — several stops (rather than one straight ramp) so the
    /// falloff eases out gently, the same treatment as `HomeView.heroBottomFade`.
    /// The top stays fully opaque (it's at the screen edge, behind the header).
    private var bottomFade: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.68),
                .init(color: .white.opacity(0.7), location: 0.78),
                .init(color: .white.opacity(0.3), location: 0.87),
                .init(color: .white.opacity(0.08), location: 0.94),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// A single poster in a library grid (design 4a): artwork, a real ★ rating
/// badge when the server has one, and a title/year/genre caption. Shared by
/// the Movies and Shows library screens — purely presentational, driven by
/// the generic `MediaItem`.
struct LibraryPosterCard: View {
    let item: MediaItem
    var onSelect: () -> Void = {}

    private var isRemote: Bool { item.image?.hasPrefix("http") == true }
    private var dominant: Color {
        if let name = item.image, !isRemote { return DominantColor.of(name, fallback: Color(item.artwork.top)) }
        return Color(item.artwork.top)
    }

    private var caption: String {
        [item.year, item.genre].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Three-per-row phone cards (~106pt wide) are noticeably narrower than
    /// iPad/tvOS's two/three-per-row ~180-200pt cards — the same 19pt title /
    /// 13pt caption / 14pt padding that fits comfortably there wraps and
    /// crowds badly here, so phone gets its own smaller scale.
    private var isPhone: Bool { DeviceClass.current == .phone }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                artwork
                #if os(tvOS)
                // Clean art. The poster already carries its own title; the
                // hero above names, rates and dates whatever is focused; and
                // a badge plus a caption stamped onto every one of forty
                // posters is what made the grid read as a spreadsheet rather
                // than a shelf. Only a poster-less item (gradient fallback)
                // keeps its name, because nothing else on that card has it.
                if item.image == nil {
                    fallbackTitle
                }
                #else
                LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.82)],
                               startPoint: .center, endPoint: .bottom)

                if let rating = item.rating {
                    Text("★ " + String(format: "%.1f", rating))
                        .font(Typography.font(isPhone ? 10 : 13, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, isPhone ? 6 : 9)
                        .padding(.vertical, isPhone ? 3 : 4)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: isPhone ? 5 : 7, style: .continuous))
                        .padding(isPhone ? 7 : 12)
                }

                VStack(alignment: .leading, spacing: isPhone ? 2 : 4) {
                    // Phone drops the title text entirely — three-per-row
                    // posters are already close enough to full-size that the
                    // artwork's own baked-in title (nearly every poster has
                    // one) does the job, and repeating it in a second,
                    // smaller typeface directly on top of the first reads as
                    // redundant rather than helpful. iPad/tvOS's larger,
                    // farther-away cards keep it.
                    if !isPhone {
                        Text(item.title)
                            .font(Typography.font(19, .heavy))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.6), radius: 10, y: 2)
                    }
                    if !caption.isEmpty {
                        Text(caption)
                            .font(Mono.font(isPhone ? 10 : 13, .semibold))
                            .tracking(0.6)
                            .lineLimit(1)
                            .foregroundStyle(Palette.text(0.72))
                    }
                }
                .padding(isPhone ? 8 : 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                #endif
            }
            #if os(iOS)
            // Fills its grid cell instead of pinning to 200pt. Paired with an
            // `.adaptive(minimum:)` column that carries no maximum, that lets
            // the grid justify across the whole content width — otherwise the
            // columns cap out and the remainder collects as a dead gap at the
            // right edge. 2:3 is the same proportion as the tvOS 200×300.
            .frame(maxWidth: .infinity)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            #else
            // Trimmed from 200×300 (same 2:3 ratio) — the fixed 536pt
            // dossier band that used to sit above this grid ate almost the
            // whole screen before a second poster row could ever show; this
            // and the band's own shrink are what actually buys that row back.
            .frame(width: 157, height: 235)
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.1))
        .focused($isFocusedCard)
        // The page a poster opens zooms out of that poster — see `ZoomTransition`.
        .zoomOrigin(isFocusedCard)
    }

    @FocusState private var isFocusedCard: Bool

    #if os(tvOS)
    private var fallbackTitle: some View {
        Text(item.title)
            .font(Typography.font(19, .heavy))
            .foregroundStyle(Palette.textPrimary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                       startPoint: .center, endPoint: .bottom))
    }
    #endif

    @ViewBuilder private var artwork: some View {
        if let image = item.image, isRemote, let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
        } else if let name = item.image {
            Image(name).resizable().scaledToFill()
        } else {
            item.artwork.gradient
        }
    }
}
