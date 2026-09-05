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
    /// Closes the submenu. iOS-only in practice: tvOS closes it with the Menu
    /// button — each rail-having screen wires that itself via
    /// `.tvBackCommand(closeOverlay: isLibrariesOpen, onCloseOverlay: ...)`
    /// (see `Nav/TVBackCommand.swift`). There is no single shared
    /// `RootView`-level exit-command handler — every screen owns its own
    /// Menu-button contract via that shared helper. Touch has no Menu
    /// button, and a flyout you can only close by finding the same small
    /// icon again is a trap. Optional so a caller that has no toggle to
    /// offer simply gets the tvOS behaviour.
    var onDismiss: (() -> Void)? = nil
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
            // Tap anywhere on the dimmed screen to close. Sits *under* the
            // submenu so it never steals the panel's own taps, and above the
            // disabled content, which can't receive them anyway.
            #if os(iOS)
            if isOpen, let onDismiss {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
            }
            #endif

            if isOpen {
                LibrariesSubmenu(libraries: libraries)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isOpen)
    }
}
