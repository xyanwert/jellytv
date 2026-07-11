import Foundation

/// What RootView's content area shows. Libraries is deliberately not a case here
/// — it's a submenu that can be open while `.home` is active, not a separate
/// screen (see design.md's "Libraries is a submenu, not a route" decision).
enum NavDestination: Hashable {
    case home
    case settings
    case search
    case movies
    case tv
}
