import Foundation

/// The decisions a show page makes about its seasons, kept pure so they can be
/// tested without a server: which season to open on, what state each one is
/// in, and the order the picker walks them.
///
/// **Open where the viewer is.** The page used to open on the *last* season —
/// its "current season" looked for an in-progress episode, but seasons arrive
/// without their episodes, so the search never matched and the fallback won
/// every time: The Simpsons opened on its newest season with the viewer in
/// season 10. Jellyfin's `/Shows/NextUp` names the exact next episode, and each
/// season item carries its own progress, so the answer is available before a
/// single episode is fetched.
public enum SeasonGuide {
    public enum State: Equatable, Sendable {
        case unwatched
        /// Fraction watched, 0 < value < 1.
        case inProgress(Double)
        case finished
    }

    public static func state(of season: Season) -> State {
        if season.isPlayed { return .finished }
        if let unplayed = season.unplayedCount, unplayed == 0, (season.episodeCount ?? 0) > 0 { return .finished }
        if let pct = season.playedPercentage, pct > 0 {
            return pct >= 100 ? .finished : .inProgress(min(pct / 100, 0.999))
        }
        return .unwatched
    }

    /// The season to open on, as an index into `seasons`:
    ///
    /// 1. the season holding the next-up episode, when Jellyfin named one;
    /// 2. else the first regular season partway through;
    /// 3. else the first regular season not yet finished;
    /// 4. else (everything watched, or nothing known) the first regular season.
    ///
    /// Specials (season 0) are never chosen unless they are all there is: they
    /// sort first on Jellyfin, and opening a fresh show on a behind-the-scenes
    /// reel is the wrong first impression.
    public static func suggestedIndex(seasons: [Season], nextUpSeasonId: String?) -> Int {
        guard !seasons.isEmpty else { return 0 }
        if let id = nextUpSeasonId, let index = seasons.firstIndex(where: { $0.id == id }) {
            return index
        }
        let regular = seasons.indices.filter { seasons[$0].number > 0 }
            .sorted { seasons[$0].number < seasons[$1].number }
        if let index = regular.first(where: { if case .inProgress = state(of: seasons[$0]) { return true }; return false }) {
            return index
        }
        if let index = regular.first(where: { state(of: seasons[$0]) != .finished }) {
            return index
        }
        return regular.first ?? 0
    }

    /// Indices of `seasons` in the order the picker walks them: regular seasons
    /// by number, Specials at the end — the order a viewer counts in.
    public static func displayOrder(_ seasons: [Season]) -> [Int] {
        let regular = seasons.indices.filter { seasons[$0].number > 0 }
            .sorted { seasons[$0].number < seasons[$1].number }
        let specials = seasons.indices.filter { seasons[$0].number <= 0 }
        return regular + specials
    }

    /// "6 LEFT", "DONE", "13 EPS" — the one-line readout under a season.
    public static func readout(for season: Season) -> String {
        switch state(of: season) {
        case .finished:
            return "DONE"
        case .inProgress:
            if let left = season.unplayedCount { return "\(left) LEFT" }
            return "WATCHING"
        case .unwatched:
            if let count = season.episodeCount, count > 0 { return "\(count) EP\(count == 1 ? "" : "S")" }
            return ""
        }
    }
}
