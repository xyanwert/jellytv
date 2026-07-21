import Foundation

public enum LibraryClassifier {

    private static func matches(_ pattern: String, in name: String) -> Bool {
        let lowercased = name.lowercased()
        let tokens = pattern.lowercased().split(separator: "|").map(String.init)
        return tokens.contains { lowercased.contains($0) }
    }

    /// Name-heuristic guess, used only to seed a library's classification the
    /// first time it's seen — the user can always override in Settings →
    /// Libraries, and a saved override always wins over this guess.
    public static func guessIsAnime(name: String) -> Bool {
        matches("anime|アニメ|hentai", in: name)
    }

    public static func guessIsNSFW(name: String) -> Bool {
        matches("xxx|nsfw|adult|porn|jav|hentai", in: name)
    }

    public static func classify(collectionType: String?, name: String) -> MetaCategory? {
        guard let collectionType else { return nil }
        return MetaCategory.resolve(
            collectionType: collectionType,
            isNSFW: guessIsNSFW(name: name),
            isAnime: guessIsAnime(name: name)
        )
    }
}
