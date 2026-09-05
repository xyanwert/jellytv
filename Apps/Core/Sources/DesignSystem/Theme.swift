import SwiftUI
import JellyTVKit

/// Ported from `/Users/xyan/code/jelly-tv-ios`'s `Core/Theme/Theme.swift` —
/// the third leg of `#if os(tvOS)/#else`: that split alone can't tell an
/// iPad from an iPhone, and the shared views increasingly need to (rail vs.
/// tab bar, landscape vs. portrait). Resolved once per process — an iPad
/// doesn't morph into an iPhone, and Stage Manager resizing is a
/// `horizontalSizeClass` concern handled separately inside views, not a
/// `DeviceClass` one.
enum DeviceClass: String, Sendable, CaseIterable {
    case phone
    case pad
    case tv

    static var current: DeviceClass {
        #if os(tvOS)
        return .tv
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
        #else
        return .pad
        #endif
    }
}

extension View {
    /// Extra bottom clearance for a screen's scrolling content on phone, so
    /// its last row isn't hidden behind `PhoneTabBar`. The bar is a plain
    /// `.overlay`, not a `.safeAreaInset` — nearly every screen's own content
    /// HStack already calls `.ignoresSafeArea()` (for the full-bleed hero/
    /// backdrop behind it), which would swallow a safe-area inset applied
    /// above it the same way, so the clearance has to be real bottom padding
    /// on the scrollable content itself, not a layout-system inset.
    func phoneTabBarClearance() -> some View {
        padding(.bottom, DeviceClass.current == .phone ? 74 : 0)
    }

    /// Every browsing screen's `HStack(rail; content)` ignores the safe area
    /// on pad/tv so the rail's translucent background reaches every screen
    /// edge (the rail itself pads its own icons away from the notch/menu bar
    /// manually). On phone there is no rail to justify that — `NavRail`
    /// renders nothing there — and ignoring the safe area anyway pulled the
    /// screen's header text (a title, a search field, `TopBar`'s eyebrow)
    /// up underneath the Dynamic Island/status bar, since nothing else in
    /// that subtree was left to claim the top inset. Respecting the safe
    /// area on phone instead means the header clears the island by exactly
    /// as much as *that* device needs, not a guessed constant that happens
    /// to work on one model. Each screen's own backdrop layer keeps its
    /// *own* independent `.ignoresSafeArea()` (see `HomeView.heroBackdropLayer`
    /// / `SelectedBackdrop`), so full-bleed art is unaffected either way.
    @ViewBuilder
    func railContentSafeArea() -> some View {
        if DeviceClass.current == .phone {
            self
        } else {
            self.ignoresSafeArea()
        }
    }
}

/// App-wide theme: the selected accent color, persisted in `UserDefaults` and
/// published so both screens update live when it changes.
@MainActor
final class Theme: ObservableObject {
    static let storageKey = "accentColor"
    static let transitionKey = "heroTransition"
    static let rotationKey = "heroRotation"
    static let libraryBackdropKey = "libraryBackdropEffect"

    @Published var option: AccentOption {
        didSet { UserDefaults.standard.set(option.rawValue, forKey: Self.storageKey) }
    }

    /// Hero backdrop transition style.
    @Published var transitionStyle: HeroTransitionStyle {
        didSet { UserDefaults.standard.set(transitionStyle.rawValue, forKey: Self.transitionKey) }
    }

    /// Hero auto-rotation interval.
    @Published var rotationInterval: HeroRotation {
        didSet { UserDefaults.standard.set(rotationInterval.rawValue, forKey: Self.rotationKey) }
    }

    /// Treatment applied to the artwork behind the library screens.
    @Published var libraryBackdropEffect: LibraryBackdropEffect {
        didSet { UserDefaults.standard.set(libraryBackdropEffect.rawValue, forKey: Self.libraryBackdropKey) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        option = raw.flatMap(AccentOption.init(rawValue:)) ?? .default

        let t = UserDefaults.standard.string(forKey: Self.transitionKey)
        transitionStyle = t.flatMap(HeroTransitionStyle.init(rawValue:)) ?? .default

        let r = UserDefaults.standard.object(forKey: Self.rotationKey) as? Double
        rotationInterval = r.flatMap(HeroRotation.init(rawValue:)) ?? .default

        let b = UserDefaults.standard.string(forKey: Self.libraryBackdropKey)
        libraryBackdropEffect = b.flatMap(LibraryBackdropEffect.init(rawValue:)) ?? .default
    }

    /// The current accent as a SwiftUI color.
    var accent: Color { Color(hex: option.hex) }

    /// A secondary accent, complementary to `accent` — for controls (like
    /// text-field focus borders) that shouldn't compete with primary actions
    /// but should still track the chosen theme color.
    var secondaryAccent: Color { accent.complementary }
}
