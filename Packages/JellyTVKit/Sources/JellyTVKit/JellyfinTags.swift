import Foundation

/// The rules for handling Jellyfin's free-form item `Tags` — normalisation,
/// case-collapsing, and the clobber-safe edit of an item DTO.
///
/// **Jellyfin enforces nothing here.** `Tags` is a bare string array on the
/// item; the server will happily store `workout`, `Workout` and `WORKOUT` as
/// three unrelated tags, and then every filter and every chip row treats them
/// as three things. v1 (`/Users/xyan/code/jelly-tv-ios`) hit exactly this and
/// answered it with case-insensitive canonicalisation in its local tag store
/// (commit `066e234`); the rules survive the move to server-side tags even
/// though none of that code does — v1 never wrote a tag to Jellyfin at all.
///
/// Pure functions on purpose: the interesting failure here is a *wrong edit*
/// of an item, not a network fault, and this is the part that can be tested
/// without a server.
public enum JellyfinTags {
    /// v1's cap, kept: long enough for a phrase, short enough that a chip row
    /// stays a chip row.
    public static let maxLength = 80

    /// Keys Jellyfin will hand you but **refuses to take back**.
    ///
    /// `Trickplay` is a dictionary of `TrickplayInfoDto`, a record whose
    /// deserialisation constructor parameters don't match its own serialised
    /// property names — so `POST /Items/{id}` throws
    /// `InvalidOperationException: Each parameter in the deserialization
    /// constructor on type 'MediaBrowser.Model.Dto.TrickplayInfoDto' must
    /// bind to an object property or field` and answers **500** for any item
    /// that has trickplay data. Which, on a healthy server, is most of them.
    ///
    /// It arrives whether or not `Trickplay` was in the `fields` list, so
    /// there is no asking the GET not to send it. Dropping it costs nothing:
    /// it is derived data the server regenerates, `UpdateItem` never writes
    /// it, and it is still served afterwards (verified).
    ///
    /// The failure is a bare "Error processing request." with the real
    /// exception only in the server's log — so if a future Jellyfin adds
    /// another type like this, the symptom will be an unexplained 500 and
    /// this is the list to extend.
    private static let unparseableKeys = ["Trickplay"]

    /// Trimmed and length-capped, or nil when there is nothing left.
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    /// The spelling to actually store for `raw`, given what already exists.
    ///
    /// If the vocabulary already holds a case-variant, **that** spelling wins.
    /// Typing "gaby" when the library says "Gaby" must not create a second
    /// tag — the user meant the one they can already see.
    public static func canonical(_ raw: String, in vocabulary: [String]) -> String? {
        guard let normalized = normalized(raw) else { return nil }
        return vocabulary.first { $0.caseInsensitiveCompare(normalized) == .orderedSame } ?? normalized
    }

    public static func contains(_ tag: String, in tags: [String]) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// Add or remove `tag`, matched case-insensitively. Order is preserved so
    /// a chip row doesn't reshuffle itself when one chip is toggled.
    public static func toggling(_ tag: String, in tags: [String]) -> [String] {
        contains(tag, in: tags)
            ? tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
            : tags + [tag]
    }

    /// The item DTO to POST back, given the one the server just handed us.
    ///
    /// **The whole item goes back, not a patch.** `POST /Items/{id}` takes a
    /// full `BaseItemDto` and writes every field it understands — so anything
    /// missing from the body is written as *null*. Editing the raw JSON the
    /// server itself returned, rather than encoding a Swift struct of our
    /// own, is what makes that safe: fields this app has never heard of go
    /// back exactly as they came, and adding a property to our models can
    /// never quietly start wiping one.
    ///
    /// It also locks the field. Jellyfin's metadata refresh re-runs the
    /// providers and overwrites what they own, so a hand-applied tag on a
    /// film would evaporate at the next scan; `LockedFields: ["Tags"]` is the
    /// server's own opt-out, and touching tags at all is a clear statement
    /// that the user owns them now. Nothing else about the item is locked.
    public static func itemDTO(_ dto: [String: Any], settingTags tags: [String]) -> [String: Any] {
        var updated = dto
        for key in unparseableKeys { updated.removeValue(forKey: key) }
        updated["Tags"] = tags
        var locked = (dto["LockedFields"] as? [String]) ?? []
        if !locked.contains("Tags") { locked.append("Tags") }
        updated["LockedFields"] = locked
        return updated
    }
}
