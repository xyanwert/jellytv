import SwiftUI
import JellyTVKit

/// Focus targets on the Home screen that we drive explicitly.
enum HomeFocus: Hashable {
    case heroResume
    case continueFirst
}

/// The Home screen: rail, hero carousel, and content rows over the design
/// background. Opens Settings from the readout row's avatar; the rail's own
/// icons are handled by `onSelectRail` (routed up to `RootView`).
struct HomeView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void
    let onOpenSettings: () -> Void

    @FocusState private var focus: HomeFocus?
    @EnvironmentObject private var theme: Theme

    // Hero carousel state.
    @State private var heroIndex = 0
    @State private var slideStartTime = Date()
    @State private var rotateTask: Task<Void, Never>?
    // The slide currently departing (crumbling/fading away) on top of the new
    // base, and how far along its departure is (1 = intact, 0 = gone). Nil when
    // idle. This is what makes the swap a reveal — the new slide is always the
    // opaque base underneath, so no black shows between shattering cells.
    @State private var outgoingHero: HeroFeature?
    @State private var departProgress: Double = 1
    // The show opened from a Recommended poster, presented full-screen over Home.
    @State private var selectedShow: Show?

    private var heroes: [HeroFeature] { SampleCatalog.heroes }
    private var currentHero: HeroFeature { heroes[heroIndex % heroes.count] }

    // Default focus target; JT_FOCUS=continue lands on the first Continue card
    // (used to screenshot the focused state), otherwise the hero Resume action.
    private var initialFocus: HomeFocus {
        ProcessInfo.processInfo.environment["JT_FOCUS"] == "continue" ? .continueFirst : .heroResume
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            heroBackdrop
            HStack(spacing: 0) {
                NavRail(
                    destination: .home,
                    isLibrariesOpen: isLibrariesOpen,
                    isServerConnected: SampleCatalog.server.isConnected,
                    onSelect: onSelectRail
                )
                ZStack(alignment: .leading) {
                    content
                        .opacity(isLibrariesOpen ? 0.5 : 1)
                        .allowsHitTesting(!isLibrariesOpen)
                    if isLibrariesOpen {
                        LibrariesSubmenu(libraries: SampleCatalog.libraries)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.2), value: isLibrariesOpen)

            if let selectedShow {
                ShowView(show: selectedShow, onDismiss: { self.selectedShow = nil })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.25), value: selectedShow)
        .onAppear {
            if ProcessInfo.processInfo.environment["JT_SHOW_DEMO"] == "1", selectedShow == nil {
                selectedShow = SampleCatalog.show(for: SampleCatalog.recommended[5])
            }
        }
        // Restart rotation when the interval changes; cancel on teardown.
        .task(id: theme.rotationInterval) { startHeroRotation() }
        .onDisappear { rotateTask?.cancel() }
        // Menu/Back closes the Libraries submenu when it's open; otherwise let
        // the press fall through to the system's default behavior (nil action).
        .onExitCommand(perform: isLibrariesOpen ? { onSelectRail(.home) } : nil)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TopBar(profile: SampleCatalog.profile, onOpenSettings: onOpenSettings)

                HeroView(
                    hero: currentHero,
                    heroCount: heroes.count,
                    heroIndex: heroIndex,
                    slideStartTime: slideStartTime,
                    rotationSeconds: theme.rotationInterval.seconds,
                    resumeFocus: $focus
                )
                ContinueWatchingRow(items: SampleCatalog.continueWatching,
                                    firstCardFocus: $focus, firstCardTag: .continueFirst)
                    .padding(.top, 80)
                RecommendedRow(items: SampleCatalog.recommended,
                               onSelect: { selectedShow = SampleCatalog.show(for: $0) })
                    .padding(.top, 35)
                    .padding(.bottom, 80)
            }
        }
        .defaultFocus($focus, initialFocus)
    }

    private static let backdropHeight: CGFloat = 820

    /// The hero backdrop: the incoming slide is a solid base and the outgoing
    /// slide crumbles (or fades) away on top of it (a reveal — never any black),
    /// with legibility scrims for the title text. The whole backdrop is masked
    /// with a bottom fade so it dissolves smoothly into the page background.
    private var heroBackdrop: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: Self.backdropHeight)
            ZStack {
                imageStack(size: size)
                    .opacity(0.7)
                scrims
            }
            .frame(width: geo.size.width, height: Self.backdropHeight, alignment: .top)
            .mask(bottomFade)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    /// New slide as an opaque base, the departing slide crumbling/fading on top.
    private func imageStack(size: CGSize) -> some View {
        ZStack {
            heroImage(currentHero, size: size)
            if let outgoingHero {
                heroImage(outgoingHero, size: size)
                    .modifier(HeroDepartureModifier(
                        style: theme.transitionStyle,
                        progress: departProgress,
                        canvasSize: size,
                        accent: theme.accent
                    ))
                    .zIndex(1)
            }
        }
    }

    private func heroImage(_ hero: HeroFeature, size: CGSize) -> some View {
        Image(hero.image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    /// Fades the whole backdrop to transparent toward the bottom so it blends
    /// into the page background — no hard image edge above the content rows.
    private var bottomFade: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.46),
                .init(color: .clear, location: 0.82),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Legibility gradients for the title text (left wash + a touch at the top).
    /// The bottom fade to the background is handled by `bottomFade`, not here.
    private var scrims: some View {
        Color.clear
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Palette.screen, location: 0.0),
                        .init(color: Palette.screen.opacity(0.6), location: 0.30),
                        .init(color: Palette.screen.opacity(0.0), location: 0.64),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Palette.screen.opacity(0.5), location: 0.0),
                        .init(color: .clear, location: 0.18),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
    }

    // MARK: - Rotation

    private func startHeroRotation() {
        rotateTask?.cancel()
        slideStartTime = Date()
        guard heroes.count > 1 else { return }
        let seconds = theme.rotationInterval.seconds
        rotateTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                let style = theme.transitionStyle

                // Snapshot the departing slide and swap the base to the next one
                // instantly beneath it (hidden — the departing slide is intact
                // and opaque at this instant).
                outgoingHero = currentHero
                departProgress = 1
                withAnimation(.easeInOut(duration: 0.45)) {
                    heroIndex = (heroIndex + 1) % heroes.count   // crossfades hero text
                }
                slideStartTime = Date()

                // Crumble/fade the departing slide away, revealing the new base.
                withAnimation(style.animation) {
                    departProgress = 0
                }

                // Drop the spent layer once the departure completes.
                try? await Task.sleep(for: .seconds(style.duration + 0.05))
                if Task.isCancelled { break }
                outgoingHero = nil
                departProgress = 1
            }
        }
    }
}
