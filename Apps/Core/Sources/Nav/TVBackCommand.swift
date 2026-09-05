import SwiftUI

extension View {
    /// The tvOS Menu-button ("go back") contract every rail-having screen
    /// should follow, expressed once instead of re-derived per screen:
    ///
    /// 1. If a submenu/overlay is open (the Libraries flyout), Menu closes
    ///    *that* and nothing else.
    /// 2. Otherwise, if a detail/full-screen overlay is presented over this
    ///    screen, do nothing here — its own nearer `.onExitCommand` (on the
    ///    detail's own root) already wins focus-chain resolution while it's
    ///    presented, since this screen's content sits `.disabled` underneath
    ///    it. Don't double-handle the press.
    /// 3. Otherwise, perform this screen's own "go back" action — `nil`
    ///    (the default) for a true root, which lets tvOS's system default
    ///    (suspend toward the Home Screen) apply, the same way Apple's own
    ///    apps behave with nowhere further back to go.
    ///
    /// A behavior-preserving extraction of what Home hand-rolled as its own
    /// `onExitCommand` — pulled out so the next screens to adopt this
    /// contract (Search, Home Videos, and reconciling Settings/the library
    /// screens' own duplicated `exitAction`s) get one call instead of
    /// another copy-paste.
    @ViewBuilder
    func tvBackCommand(
        closeOverlay overlayIsOpen: Bool,
        onCloseOverlay: @escaping () -> Void,
        isDetailPresented: Bool,
        goBack: (() -> Void)? = nil
    ) -> some View {
        #if os(tvOS)
        let action: (() -> Void)? = overlayIsOpen ? onCloseOverlay
            : (isDetailPresented ? nil : goBack)
        self.onExitCommand(perform: action)
        #else
        self
        #endif
    }
}
