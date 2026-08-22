import SwiftUI
import JellyTVKit

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

    var body: some View {
        #if os(iOS)
        iosField
            .frame(height: 60)
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
        .frame(height: 60)
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

    @EnvironmentObject private var theme: Theme

    private var effectiveAccent: Color { accent ?? theme.accent }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.font(17, .bold))
                .foregroundStyle(isOn ? .white : Palette.text(0.7))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(isOn ? effectiveAccent : Palette.text(0.06), in: Capsule())
                .overlay(Capsule().stroke(isOn ? .clear : Palette.text(0.14), lineWidth: 1.5))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 999))
    }
}

/// The focused item's full-screen backdrop — pinned to the top, behind the
/// rail/content, scrimmed for legibility and alpha-masked at the bottom so it
/// dissolves into the page over the first poster row. Shared by the Movies and
/// Shows library screens; sits behind the header, filters, and the selected-
/// item band so the image reads across the whole top of the screen.
struct SelectedBackdrop: View {
    let item: MediaItem

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
                heroImage(width: geo.size.width)
                    .opacity(0.9)
                // A softly-blurred copy of the image, shown only across the
                // top (behind the header/filters) and fading to the sharp
                // image below — takes the visual busyness out from under the
                // header without blurring the whole backdrop.
                heroImage(width: geo.size.width, blur: 18)
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

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                artwork
                LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.82)],
                               startPoint: .center, endPoint: .bottom)

                if let rating = item.rating {
                    Text("★ " + String(format: "%.1f", rating))
                        .font(Typography.font(13, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(12)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(Typography.font(19, .heavy))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.6), radius: 10, y: 2)
                    if !caption.isEmpty {
                        Text(caption)
                            .font(Mono.font(13, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.text(0.72))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(CardFocusStyle(glow: dominant, scale: 1.1))
    }

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

/// The dossier's top panel (design 4a, and reused with an anime-flavored
/// label for 4b): a "DOSSIER / DECODED" header, two big rating stat boxes
/// (critics / audience), and a two-column cast grid with Oscar-winner medals.
/// Rich data is fetched per selection (Jellyfin detail + optional OMDb);
/// anything absent simply doesn't render, so the panel degrades cleanly on
/// sparse metadata. `accent` is passed in (rather than read from `Theme`
/// directly) so a category screen with its own identity color — design 4b's
/// magenta anime accent — can use that instead of the user's global theme.
struct StatsCastPanel: View {
    let movie: Movie
    var isLoading: Bool = false
    var accent: Color
    var dossierLabel: String = "SIGNAL DOSSIER"
    var castLabel: String = "CAST"

    /// Fixed footprint — independent of `MetaPanel`'s — so this panel never
    /// resizes/jumps as content changes (loading → loaded, rich → sparse);
    /// content is top-aligned inside it. `MetaPanel` never renders on iOS (see
    /// the bands' `#if os(tvOS)` gate), so there this is the *only* dossier
    /// panel — wider and shorter than the tvOS pairing (which stacks a second
    /// panel underneath) fits the freed vertical space better and leaves more
    /// room for the title/synopsis column beside it.
    #if os(iOS)
    static let size = CGSize(width: 440, height: 260)
    #else
    static let size = CGSize(width: 440, height: 380)
    #endif

    // See the identical comment on `size` — iOS packs the same content into a
    // shorter box via tighter spacing and a 3-column (not 2) cast grid.
    #if os(iOS)
    private static let contentSpacing: CGFloat = 10
    private static let statBoxVerticalPadding: CGFloat = 10
    private static let castColumns = 3
    private static let castRowSpacing: CGFloat = 10
    #else
    private static let contentSpacing: CGFloat = 16
    private static let statBoxVerticalPadding: CGFloat = 13
    private static let castColumns = 2
    private static let castRowSpacing: CGFloat = 14
    #endif

    /// Audience score (IMDb / community), 0–10.
    private var audience: Double? { movie.externalRatings?.imdbRating ?? movie.communityRating }
    /// Critics score (Rotten Tomatoes / Jellyfin critic), a percentage.
    private var critics: Int? { movie.externalRatings?.rottenTomatoes ?? movie.criticRating.map { Int($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.contentSpacing) {
            header
            if isLoading {
                loadingBody
            } else {
                statBoxes
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
            Text(dossierLabel)
                .font(Mono.font(12, .bold))
                .tracking(2.4)
                .foregroundStyle(Palette.text(0.42))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(isLoading ? Palette.text(0.35) : accent).frame(width: 7, height: 7)
                    .shadow(color: isLoading ? .clear : accent, radius: 6)
                Text(isLoading ? "SCANNING" : "DECODED")
                    .font(Mono.font(11, .bold))
                    .tracking(1)
                    .foregroundStyle(isLoading ? Palette.text(0.4) : accent)
            }
        }
    }

    /// Shown until the live detail arrives — a quiet indicator, never fake data.
    private var loadingBody: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(accent)
            Text("Decoding signal…")
                .font(Mono.font(14, .medium)).tracking(1)
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ratings

    @ViewBuilder private var statBoxes: some View {
        if critics != nil || audience != nil {
            HStack(spacing: 12) {
                if let critics { statBox(value: "\(critics)%", label: "CRITICS", accented: true) }
                if let audience { statBox(value: String(format: "%.1f", audience), label: "AUDIENCE", accented: false) }
            }
        }
    }

    private func statBox(value: String, label: String, accented: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Typography.font(34, .black))
                .foregroundStyle(accented ? accent : Palette.textPrimary)
            Text(label)
                .font(Mono.font(11, .bold)).tracking(1.5)
                .foregroundStyle(Palette.text(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Self.statBoxVerticalPadding).padding(.horizontal, 16)
        .background(Palette.text(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
    }

    // MARK: - Cast grid (3 columns on iOS, 2 on tvOS — see `castColumns`)

    @ViewBuilder private var castSection: some View {
        if !movie.cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(castLabel)
                    .font(Mono.font(12, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.42))
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: Self.castColumns),
                    alignment: .leading, spacing: Self.castRowSpacing
                ) {
                    ForEach(movie.cast.prefix(6)) { member in
                        CastListItem(member: member, portrait: 42)
                    }
                }
            }
        }
    }
}

/// The dossier's bottom panel (design 4a): director / studio / runtime crew
/// rows, in its own fixed-size card below `StatsCastPanel`. The director's
/// name renders upper-case. When the film has actually *won* an Oscar (other
/// awards are ignored per the product decision — see `MovieAwards.academyAwardsLabel`),
/// the panel gets a quiet trophy-art background at 40% opacity instead of the
/// flat panel color, as a subtle Oscar signal rather than another text badge.
struct MetaPanel: View {
    let movie: Movie
    var isLoading: Bool = false
    var accent: Color

    /// Fixed footprint — independent of `StatsCastPanel`'s — so this panel
    /// never resizes/jumps as content changes. Narrower on iOS, matching
    /// `StatsCastPanel`'s iPad-width fix.
    #if os(iOS)
    static let size = CGSize(width: 300, height: 140)
    #else
    static let size = CGSize(width: 440, height: 140)
    #endif

    private static let oscarArtURL = URL(string: "https://w.wallhaven.cc/full/4y/wallhaven-4yzo3d.jpg")
    private var wonOscar: Bool { (movie.awards?.oscarsWon ?? 0) > 0 }

    var body: some View {
        Group {
            if isLoading { loadingBody } else { metaRows }
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
    }

    /// This panel's own decode indicator — smaller than `StatsCastPanel`'s
    /// (there's less vertical room here), but the same visual language, so
    /// both dossier windows read as "still decoding" rather than one loading
    /// and the other going blank.
    private var loadingBody: some View {
        HStack(spacing: 10) {
            ProgressView().tint(accent)
            Text("Decoding…")
                .font(Mono.font(13, .medium)).tracking(1)
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metaRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !movie.director.isEmpty { crewRow(label: "Director", value: movie.director.uppercased()) }
            if !movie.studios.isEmpty { crewRow(label: "Studio", value: movie.studios.prefix(2).joined(separator: ", ")) }
            if !movie.runtime.isEmpty { crewRow(label: "Runtime", value: movie.runtime) }
        }
    }

    private func crewRow(label: String, value: String) -> some View {
        HStack {
            Text(label.uppercased()).font(Mono.font(13, .semibold)).tracking(1).foregroundStyle(Palette.text(0.42))
            Spacer(minLength: 12)
            Text(value).font(Typography.font(15, .bold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
        }
    }

    @ViewBuilder private var background: some View {
        ZStack {
            Color(hex: "#0E121A").opacity(0.7)
            if wonOscar, let oscarArtURL = Self.oscarArtURL {
                AsyncImage(url: oscarArtURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: Self.size.width, height: Self.size.height)
                            .opacity(0.4)
                    }
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
            }
        }
    }
}

/// The Shows dossier's top panel: the "SIGNAL DOSSIER / DECODED" header, the
/// show's network branding where the Movies dossier shows critics/audience
/// stat boxes, and the same two-column cast grid with Oscar-winner medals.
/// Same fixed footprint as `StatsCastPanel` so the Movies/Shows/Anime
/// screens' dossiers all read as siblings. `accent` is passed in (rather than
/// read from `Theme`) so a category screen with its own identity color can
/// use that instead of the user's global theme.
struct ShowStatsCastPanel: View {
    let show: Show
    var isLoading: Bool = false
    var accent: Color
    var castLabel: String = "CAST"
    var dossierLabel: String = "SIGNAL DOSSIER"
    /// The ready-state status word (e.g. "DECODED", or "RESTRICTED" for a
    /// gated/adult category) — "SCANNING" (the loading word) stays fixed
    /// since it means the same thing everywhere.
    var readyLabel: String = "DECODED"

    // See `StatsCastPanel`'s identical comment — `ShowMetaPanel` never renders
    // on iOS either, so this is the only dossier panel there.
    #if os(iOS)
    static let size = CGSize(width: 440, height: 260)
    #else
    static let size = CGSize(width: 440, height: 380)
    #endif

    #if os(iOS)
    private static let contentSpacing: CGFloat = 10
    private static let networkMinHeight: CGFloat = 52
    private static let castColumns = 3
    private static let castRowSpacing: CGFloat = 10
    #else
    private static let contentSpacing: CGFloat = 16
    private static let networkMinHeight: CGFloat = 64
    private static let castColumns = 2
    private static let castRowSpacing: CGFloat = 14
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Self.contentSpacing) {
            header
            if isLoading {
                loadingBody
            } else {
                NetworkLockup(network: show.network, fallbackName: show.studios.first, minHeight: Self.networkMinHeight)
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
            Text(dossierLabel)
                .font(Mono.font(12, .bold))
                .tracking(2.4)
                .foregroundStyle(Palette.text(0.42))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(isLoading ? Palette.text(0.35) : accent).frame(width: 7, height: 7)
                    .shadow(color: isLoading ? .clear : accent, radius: 6)
                Text(isLoading ? "SCANNING" : readyLabel)
                    .font(Mono.font(11, .bold))
                    .tracking(1)
                    .foregroundStyle(isLoading ? Palette.text(0.4) : accent)
            }
        }
    }

    /// Shown until the live detail arrives — a quiet indicator, never fake data.
    private var loadingBody: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(accent)
            Text("Decoding signal…")
                .font(Mono.font(14, .medium)).tracking(1)
                .foregroundStyle(Palette.text(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Cast grid (3 columns on iOS, 2 on tvOS — see `castColumns`)

    @ViewBuilder private var castSection: some View {
        if !show.cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(castLabel)
                    .font(Mono.font(12, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.42))
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: Self.castColumns),
                    alignment: .leading, spacing: Self.castRowSpacing
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
struct ShowMetaPanel: View {
    let show: Show
    var isLoading: Bool = false
    var accent: Color

    /// Same fixed footprint as the Movies dossier's `MetaPanel`.
    #if os(iOS)
    static let size = CGSize(width: 300, height: 140)
    #else
    static let size = CGSize(width: 440, height: 140)
    #endif

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
            ProgressView().tint(accent)
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
