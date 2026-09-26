import SwiftUI
import JellyTVKit

/// Poster Mode's hero text (`AppStyle.poster`) — the same slot, inputs and focus
/// tag as `HeroView`, so `HomeView` swaps one for the other and nothing about
/// focus, rotation or the crumble behind it changes. What changes is the voice:
/// the title in the display face, an ink eyebrow sticker, metadata as chips, a
/// white arrow pill for Resume, and the title again, enormous and faint, behind
/// everything.
struct PosterHeroView: View {
    let hero: HeroFeature
    var resumeFocus: FocusState<HomeFocus?>.Binding
    var onDetails: () -> Void = {}

    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState
    @State private var favoriteOverride: Bool?
    @State private var detailsTick = 0

    #if os(iOS)
    private static let titleSize: CGFloat = 76
    private static let titleBoxHeight: CGFloat = 150
    private static let ghostSize: CGFloat = 230
    private static let synopsisSize: CGFloat = 17
    private static let synopsisBoxHeight: CGFloat = 50
    private static let spacing: CGFloat = 10
    #else
    private static let titleSize: CGFloat = 132
    private static let titleBoxHeight: CGFloat = 250
    private static let ghostSize: CGFloat = 380
    private static let synopsisSize: CGFloat = 25
    private static let synopsisBoxHeight: CGFloat = 72
    private static let spacing: CGFloat = 16
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            // Its own identity, so it can land on its own beat: the eyebrow
            // sticker slaps on once the art has mostly crumbled away.
            eyebrow
                .id(hero.id)
                .transition(.posterSlap.animation(
                    .spring(response: 0.42, dampingFraction: 0.5)
                        .delay(theme.transitionStyle.duration * 0.55)))
            textBlock
                .id(hero.id)
                .transition(.opacity.animation(.easeInOut(duration: theme.transitionStyle.duration)))
            actions
                .padding(.top, Self.spacing * 0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            // The ghost title rides with the slide, so it crossfades with the
            // text rather than sitting still while the art crumbles past it.
            PosterGhostTitle(text: hero.title, size: Self.ghostSize)
                .id(hero.id)
                .transition(.opacity.animation(.easeInOut(duration: theme.transitionStyle.duration)))
                .offset(y: -Self.ghostSize * 0.2)
        }
        .onChange(of: hero.id) { _, _ in favoriteOverride = nil }
    }

    /// Fixed height whether or not the slide has an eyebrow, so the title
    /// below never shifts between slides.
    private var eyebrow: some View {
        Text(hero.eyebrow.isEmpty ? " " : hero.eyebrow.uppercased())
            .font(Display.font(DeviceClass.current == .tv ? 26 : 16))
            .tracking(1.5)
            .foregroundStyle(Palette.posterTeal)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Palette.posterInk, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(hero.eyebrow.isEmpty ? 0 : 1)
            .rotationEffect(.degrees(-2))
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            let lines = HeroView.titleLines(hero.title.uppercased())
            VStack(alignment: .leading, spacing: -Self.titleSize * 0.12) {
                Text(lines.0)
                if let second = lines.1 { Text(second) }
            }
            .font(Display.font(Self.titleSize))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .frame(height: Self.titleBoxHeight, alignment: .bottomLeading)

            chips

            Text(hero.synopsis.isEmpty ? " " : hero.synopsis)
                .font(Typography.font(Self.synopsisSize, .semibold))
                .foregroundStyle(hero.synopsis.isEmpty ? .clear : Palette.text(0.82))
                .lineSpacing(5)
                .lineLimit(2)
                .frame(maxWidth: DeviceClass.current == .tv ? 980 : 560, alignment: .topLeading)
                .frame(height: Self.synopsisBoxHeight, alignment: .topLeading)
        }
    }

    /// Certification leads, inverted; the rest are ink chips. Empty fields drop
    /// out rather than leaving a gap — the row's height is fixed by its font.
    private var chips: some View {
        HStack(spacing: 10) {
            if !hero.certification.isEmpty { PosterChip(text: hero.certification, inverted: true) }
            ForEach([hero.year, hero.genre, hero.episode, hero.qualityBadge].filter { !$0.isEmpty }, id: \.self) {
                PosterChip(text: $0)
            }
        }
        .frame(height: DeviceClass.current == .tv ? 40 : 26, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: DeviceClass.current == .tv ? 22 : 12) {
            Button(action: resume) {
                PosterArrowPill(title: hero.resumeLabel)
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 999))
            .focused(resumeFocus, equals: .heroResume)

            Button { detailsTick += 1; PageLaunch.then(onDetails) } label: {
                PosterOutlinePill(title: "Details")
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 999))
            .pageLaunchBeat(detailsTick)

            let on = favoriteOverride ?? hero.isFavorite
            Button(action: toggleFavorite) {
                PosterRoundButton(systemImage: on ? "heart.fill" : "heart",
                                  tint: on ? theme.accent : Palette.textPrimary)
            }
            .buttonStyle(FocusScaleStyle(scale: 1.1, cornerRadius: 999))
            .accessibilityLabel(on ? "Remove from favourites" : "Add to favourites")
        }
        #if os(tvOS)
        // Same containment as `HeroView.actionsRow`: without it Left/Right at
        // the row's ends searches the whole screen for somewhere to land.
        .focusSection()
        #endif
    }

    private func toggleFavorite() {
        guard let client = appState.jellyfinClient else { return }
        let newValue = !(favoriteOverride ?? hero.isFavorite)
        favoriteOverride = newValue
        Task {
            do {
                if newValue {
                    try await client.setFavorite(userId: appState.currentUserId, itemId: hero.id)
                } else {
                    try await client.clearFavorite(userId: appState.currentUserId, itemId: hero.id)
                }
            } catch {
                favoriteOverride = !newValue
            }
        }
    }

    private func resume() {
        Task {
            guard let request = await appState.resumeRequest(for: hero) else { return }
            appState.requestPlayback(request)
        }
    }
}
