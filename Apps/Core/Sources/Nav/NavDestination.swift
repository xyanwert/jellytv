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
    /// The Anime library screen (design 4b) — covers both the `.animefilm`
    /// (movies+anime) and `.anime` (tvshows+anime) meta-categories in one
    /// unified browsing surface, reached from a Libraries submenu row rather
    /// than a dedicated rail icon (the rail's Libraries icon itself reads as
    /// active while here; see `NavRail.activeTarget`).
    case animeLibrary
    /// The Late Night library screen (design 4c) — the `.hentai` meta-category
    /// (tvshows + anime + NSFW), reached the same way as `animeLibrary`.
    case lateNight
}
