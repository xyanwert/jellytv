import Foundation

public enum LibraryClassifier {

    private static func matches(_ pattern: String, in name: String) -> Bool {
        let lowercased = name.lowercased()
        let tokens = pattern.lowercased().split(separator: "|").map(String.init)
        return tokens.contains { lowercased.contains($0) }
    }

    public static func classify(collectionType: String?, name: String) -> MetaCategory? {
        let isAnime = matches("anime|アニメ|hentai", in: name)
        let isNSFW = matches("xxx|nsfw|adult|porn|jav|hentai", in: name)

        switch collectionType {
        case "movies":
            if isNSFW && isAnime { return .hentai }
            if isNSFW { return .moviesxxx }
            if isAnime { return .animefilm }
            return .movies
        case "tvshows":
            if isNSFW && isAnime { return .hentai }
            if isAnime { return .anime }
            if isNSFW { return .hentai }
            return .shows
        case "homevideos":
            if isNSFW { return .porn }
            return .videos
        default:
            return nil
        }
    }
}
