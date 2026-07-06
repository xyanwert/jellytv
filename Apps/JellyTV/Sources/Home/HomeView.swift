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
            backdropGlow
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

    /// Subtle accent glow in the top-right, echoing the design's backdrop.
    private var backdropGlow: some View {
        RadialGradient(
            colors: [Color(OKLCH(l: 0.38, c: 0.08, h: 230)).opacity(0.55), .clear],
            center: UnitPoint(x: 0.82, y: 0.14),
            startRadius: 0,
            endRadius: 950
        )
        .ignoresSafeArea()
    }
}
