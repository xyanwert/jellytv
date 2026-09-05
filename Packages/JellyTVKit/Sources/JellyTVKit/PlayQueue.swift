import Foundation

/// Turning a library's worth of raw Jellyfin rows into the queue the player
/// walks — "what plays next" made explicit.
///
/// **A playlist here is ephemeral and client-side.** Nothing is written to
/// Jellyfin's own `/Playlists` API; a queue is built fresh for the press that
/// asked for it, lives as long as the player is up, and is thrown away with
/// it. Pressing Random twice is meant to give two different orders, and that
/// falls out of building rather than storing.
///
/// Everything here is pure so it can be tested without a server —
/// `AppState` does the fetching and hands the rows in.
public enum PlayQueue {
    /// The most items a generated queue holds.
    ///
    /// Not a display cap — it's how many rows get *fetched*. The order is
    /// randomised **by the server** (`sortBy=Random`), so a 500-item queue
    /// drawn from a 3,525-episode library is a uniform sample of all 3,525,
    /// not the first 500 of them shuffled (measured against the real server:
    /// two 500-item draws from that library overlapped by 69 items, against
    /// 71 expected for a uniform sample — a "first page, then shuffle"
    /// implementation would have overlapped by 500).
    ///
    /// So the cap costs nothing a viewer can reach. Lifting it to the whole
    /// library does cost: 3,525 episodes is a 4.1 MB response and 3.3s of
    /// waiting after a button press, against 608 KB and 0.5s for 500.
    public static let limit = 500

    /// The cap for an **ordered** queue — one series, played through.
    ///
    /// Deliberately higher than `limit`, because the two caps mean different
    /// things. A shuffle's cap is a *sample*: the server randomises across
    /// everything first, so item 501 was never more likely to be missed than
    /// item 1. An ordered queue's cap is a *wall* — it truncates from the far
    /// end, and episode 501 is simply unreachable. Long-running shows exist
    /// (this server's largest is 329 episodes; a thousand-episode anime is
    /// not exotic), and the whole fetch is lean enough that the higher
    /// ceiling is nearly free: 226 episodes measured at 328 KB and ~150 ms.
    public static let seriesLimit = 2000

    /// Whether a row is something that can actually be played.
    ///
    /// **`LocationType == "Virtual"` is the one that matters.** Jellyfin
    /// files metadata-only episodes — unaired ones, and the stub entries
    /// AniDB/TheTVDB invent for specials and sketch galleries — as real rows
    /// with no file behind them. They are not rare: of 3,525 episodes in this
    /// user's adult-anime library, **859 are virtual**, so an unfiltered
    /// shuffle would be nearly a quarter dead ends. v1 shipped that bug three
    /// times (a crash on an empty expanded queue, then Next stranding on a
    /// fileless special) and fixed it in layers; this is the same
    /// belt-and-braces, paired with `isMissing=false` on the fetch itself.
    public static func isPlayable(_ item: JellyfinAPI.JellyfinItem) -> Bool {
        if item.locationType == "Virtual" { return false }
        return true
    }

    /// One raw row as the player's item, given a lookup for the logo artwork
    /// and tags an episode has to borrow from its series.
    ///
    /// Returns nil for anything unplayable, so a caller can `compactMap`
    /// straight through.
    public static func playableItem(
        from item: JellyfinAPI.JellyfinItem,
        seriesIdentity: [String: (logoURL: String?, tags: [String])] = [:],
        imageBaseURL: URL? = nil,
        hidesTitle: Bool = false
    ) -> PlayableItem? {
        guard isPlayable(item) else { return nil }

        if item.type == "Episode" {
            // The chrome shows the *series* as the title and the episode as
            // the subtitle — same shape `Episode.asPlayableItem` builds, so a
            // shuffled queue and a season queue read identically.
            let series = item.seriesId.flatMap { seriesIdentity[$0] }
            let season = item.parentIndexNumber ?? 0
            let number = item.indexNumber ?? 0
            return PlayableItem(
                id: item.id,
                seriesId: item.seriesId,
                title: item.seriesName ?? item.name ?? "Untitled",
                subtitle: "S\(season) · E\(number) — \"\(item.name ?? "")\"",
                runtimeTicks: item.runTimeTicks,
                resumePositionTicks: item.userData?.playbackPositionTicks,
                isFavorite: item.userData?.isFavorite ?? false,
                imageURL: item.queueImageURLString(imageBaseURL),
                logoURL: series?.logoURL,
                tags: series?.tags ?? []
            )
        }

        let identity = item.playerIdentity(imageBaseURL: imageBaseURL)
        return PlayableItem(
            id: item.id,
            title: item.name ?? "Untitled",
            runtimeTicks: item.runTimeTicks,
            resumePositionTicks: item.userData?.playbackPositionTicks,
            isFavorite: item.userData?.isFavorite ?? false,
            imageURL: item.queueImageURLString(imageBaseURL),
            logoURL: identity.logoURL,
            tags: identity.tags,
            hidesTitle: hidesTitle
        )
    }

    /// Merge what several libraries returned into one queue.
    ///
    /// A screen's catalogue is rarely one library — the Shows page draws on
    /// every `tvshows` library the server has — so each is fetched separately
    /// (in parallel, so one slow or empty library can't hold up the rest) and
    /// the results are interleaved here.
    ///
    /// **The shuffle is re-done across the merge**, not just within each
    /// library: concatenating three already-random lists would otherwise play
    /// all of library A, then all of B. Ids are de-duplicated first, because
    /// the same item can legitimately be reachable through two libraries and
    /// the player's queue position would count it twice.
    ///
    /// Note the one bias worth knowing about: each library contributes at
    /// most `limit` rows, so merging a 3,000-item library with a 10-item one
    /// over-represents the small one. In practice a category is one or two
    /// libraries of comparable size, and the alternative — a count query per
    /// library to weight the draws — costs a round trip to fix a skew nobody
    /// pressing a shuffle button can perceive.
    public static func merge(_ groups: [[PlayableItem]], limit: Int = PlayQueue.limit) -> [PlayableItem] {
        var seen = Set<String>()
        var pool: [PlayableItem] = []
        for group in groups {
            for item in group where seen.insert(item.id).inserted {
                pool.append(item)
            }
        }
        return Array(pool.shuffled().prefix(limit))
    }
}

extension JellyfinAPI.JellyfinItem {
    /// The still the player's queue surfaces use (the scenes panel's
    /// "next video" tile). An episode's own `Primary` is the frame from that
    /// episode; a series poster would be the same picture for every row.
    func queueImageURLString(_ base: URL?) -> String? {
        guard let base, let tag = imageTags?["Primary"] else { return nil }
        return JellyfinAPI.imageURL(baseURL: base, itemId: id, imageType: "Primary",
                                    tag: tag, maxWidth: 640)?.absoluteString
    }
}
