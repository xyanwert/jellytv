import Foundation

/// The values `RT_SHOW_DISCOVER` / `JT_SHOW_DISCOVER` (and the `…_DOWNLOADS` pair) take.
///
/// Named once because four files branch on them: both root views build the fixture store
/// and seed the matching capabilities, `AppState` decides which capabilities those are,
/// and `DiscoverView` decides whether to open straight onto a title. They were spelled as
/// string literals in each, which is how `filmonly` came to exist in two of them and not
/// the other two.
///
/// Permanent, inert-unless-set hooks, the same convention as `JT_SHOW_MOVIES` — there is
/// nothing here to revert.
enum DiscoverFixture {
    /// Shelves and the download centre, seeded from fixtures.
    static let demo = "demo"
    /// Opens on the fixture title whose season is mid-download.
    static let detail = "detail"
    /// The same title once its download has landed — in the library, with Play.
    static let landed = "landed"
    /// A title already in the library before any download.
    static let owned = "owned"
    /// The same title against a server whose engine can only fetch films: no season or
    /// episode chips at all, and the bar replaced by the sentence saying why.
    static let filmOnly = "filmonly"
    /// The download that could not be made — the server's reason, and Try again.
    static let failed = "failed"
    /// A title with nothing downloading: the "Download to <library>" bar and the chips
    /// that choose where it goes.
    static let download = "download"

    /// Every mode that wants the fixture store and the fixture capabilities.
    static let modes = [demo, detail, landed, owned, filmOnly, failed, download]

    static func uses(_ mode: String?) -> Bool { modes.contains(mode ?? "") }

    /// Whether this value opens the fixture title's page rather than the shelves.
    static func opensDetail(_ mode: String?) -> Bool {
        [detail, landed, owned, filmOnly, failed, download].contains(mode ?? "")
    }
}
