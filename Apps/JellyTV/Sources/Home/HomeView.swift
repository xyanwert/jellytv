import SwiftUI
import JellyTVKit

/// Focus targets on the Home screen that we drive explicitly.
enum HomeFocus: Hashable {
    case heroResume
}

/// The Home screen: top bar, libraries, hero, and content rows over the design
/// background. Opens Settings from the top-bar avatar.
struct HomeView: View {
    let onOpenSettings: () -> Void

    @State private var activeTab = 0
    @FocusState private var focus: HomeFocus?
    @EnvironmentObject private var theme: Theme

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            heroBackdrop
            content
        }
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TopBar(
                    tabs: SampleCatalog.navTabs,
                    activeTab: $activeTab,
                    profile: SampleCatalog.profile,
                    onOpenSettings: onOpenSettings
                )

                if activeTab == 0 {
                    LibraryChipsRow(libraries: SampleCatalog.libraries)
                        .padding(.top, 18)
                    HeroView(hero: SampleCatalog.hero, resumeFocus: $focus)
                    ContinueWatchingRow(items: SampleCatalog.continueWatching)
                        .padding(.top, 80)
                    RecommendedRow(items: SampleCatalog.recommended)
                        .padding(.top, 35)
                        .padding(.bottom, 80)
                } else {
                    ComingSoon(title: SampleCatalog.navTabs[activeTab])
                        .padding(.top, 40)
                }
            }
        }
        .defaultFocus($focus, .heroResume)
    }

    /// The featured episode still, placed top-right and faded into the
    /// background on the left (where the hero text sits) and along top/bottom.
    private var heroBackdrop: some View {
        Image("HeroBackdrop")
            .resizable()
            .scaledToFill()
            .frame(width: 1280, height: 680)
            .clipped()
            .opacity(0.6)
            .overlay {
                // fade the left edge into the background
                LinearGradient(
                    stops: [
                        .init(color: Palette.screen, location: 0.0),
                        .init(color: Palette.screen.opacity(0.72), location: 0.30),
                        .init(color: Palette.screen.opacity(0.0), location: 0.78),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .overlay {
                // fade top and bottom
                LinearGradient(
                    stops: [
                        .init(color: Palette.screen.opacity(0.85), location: 0.0),
                        .init(color: .clear, location: 0.22),
                        .init(color: .clear, location: 0.55),
                        .init(color: Palette.screen, location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .ignoresSafeArea()
    }
}
