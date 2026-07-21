import SwiftUI
import JellyTVKit

/// Wraps a screen's own rail-adjacent content with the Libraries slide-out
/// submenu: dims the content and lays `LibrariesSubmenu` in front of it.
/// Shared by every rail-having screen (Home, Movies, TV, Settings, the search
/// placeholder) so pressing the rail's Libraries icon opens the submenu over
/// whatever screen is currently showing instead of forcing a navigation to
/// Home first.
struct LibrariesOverlayContent<Content: View>: View {
    let isOpen: Bool
    let libraries: [Library]
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            content()
                .opacity(isOpen ? 0.5 : 1)
                // `.allowsHitTesting(false)` alone still leaves these controls
                // in the tvOS focus graph — Right from the rail's Libraries
                // icon kept losing to whatever was last focused back here
                // instead of entering the submenu. `.disabled` drops them from
                // focus resolution entirely, not just from hit-testing.
                .disabled(isOpen)
            if isOpen {
                LibrariesSubmenu(libraries: libraries)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isOpen)
    }
}
