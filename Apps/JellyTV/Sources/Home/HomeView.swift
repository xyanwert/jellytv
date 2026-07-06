import SwiftUI
import JellyTVKit

/// Focus targets on the Home screen that we drive explicitly.
enum HomeFocus: Hashable {
    case heroResume
    case continueFirst
}

/// The Home screen: top bar, libraries, hero, and content rows over the design
/// background. Opens Settings from the top-bar avatar.
struct HomeView: View {
    let onOpenSettings: () -> Void

    @State private var activeTab = 0
    @FocusState private var focus: HomeFocus?
    @EnvironmentObject private var theme: Theme

    // Default focus target; JT_FOCUS=continue lands on the first Continue card
    // (used to screenshot the focused state), otherwise the hero Resume action.
    private var initialFocus: HomeFocus {
        ProcessInfo.processInfo.environment["JT_FOCUS"] == "continue" ? .continueFirst : .heroResume
    }

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
                    ContinueWatchingRow(items: SampleCatalog.continueWatching,
                                        firstCardFocus: $focus, firstCardTag: .continueFirst)
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
        .defaultFocus($focus, initialFocus)
    }

    /// The featured episode still: spans the full width across the top, with a
    /// left-side scrim so the hero text stays readable and a long fade to the
    /// background along the bottom.
    private var heroBackdrop: some View {
        Image("HeroBackdrop")
            .resizable()
            .scaledToFill()
            .frame(height: 820)
            .frame(maxWidth: .infinity)
            .clipped()
            .opacity(0.7)
            .overlay {
                // darken the left, where the hero text sits
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
                // slight top darken (legibility) + long fade-out at the bottom
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }
}
