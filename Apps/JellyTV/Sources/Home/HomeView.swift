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
                RecommendedRow(items: SampleCatalog.recommended)
                    .padding(.top, 35)
                    .padding(.bottom, 80)
            }
        }
        .defaultFocus($focus, initialFocus)
    }

    /// The hero backdrop: the current slide's still spans the top, crumbling (or
    /// fading) to the next slide on advance, with stable scrims on top so the
    /// hero text stays readable and the image fades into the background.
    private var heroBackdrop: some View {
        GeometryReader { geo in
            ZStack {
                Image(currentHero.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: 820)
                    .clipped()
                    .opacity(0.7)
                    .id(currentHero.id)
                    .transition(theme.transitionStyle.anyTransition(canvasWidth: geo.size.width))

                scrims
            }
            .frame(width: geo.size.width, height: 820, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    /// Stable framing gradients layered over the (transitioning) image.
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
                        .init(color: .clear, location: 0.16),
                        .init(color: .clear, location: 0.52),
                        .init(color: Palette.screen, location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(height: 820)
            .frame(maxHeight: .infinity, alignment: .top)
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
                withAnimation(.easeInOut(duration: 0.8)) {
                    heroIndex = (heroIndex + 1) % heroes.count
                }
                slideStartTime = Date()
            }
        }
    }
}
