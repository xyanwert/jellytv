import Foundation

/// The normalized shape the player queues/seeks/reports-progress against,
/// regardless of whether it started life as a `Movie` or an `Episode` — the
/// domain layer deliberately keeps those distinct display-shaped structs;
/// this is the one small adapter the player itself needs.
public struct PlayableItem: Identifiable, Hashable, Sendable {
    public let id: String
    /// Non-nil for episodes — the owning show's id.
    public let seriesId: String?
    public let title: String
    /// "S1 · E2 — Title" for an episode; nil for a movie.
    public let subtitle: String?
    public let runtimeTicks: Int64?
    public let resumePositionTicks: Int64?
    public let isFavorite: Bool
    public let imageURL: String?
    /// The item's logo artwork (Jellyfin `Logo` image), when the server has
    /// one. The player chrome shows this *instead of* the title — a title
    /// treated as artwork beats the same words set in the UI font — and falls
    /// back to `title` whenever it's nil.
    public let logoURL: String?
    /// Jellyfin's free-form `Tags`, surfaced as chips under the title. Only
    /// populated when the fetch that built this item asked for the `Tags`
    /// field; an empty array simply renders no row.
    public let tags: [String]

    public init(id: String, seriesId: String? = nil, title: String, subtitle: String? = nil,
                runtimeTicks: Int64? = nil, resumePositionTicks: Int64? = nil,
                isFavorite: Bool = false, imageURL: String? = nil,
                logoURL: String? = nil, tags: [String] = []) {
        self.id = id
        self.seriesId = seriesId
        self.title = title
        self.subtitle = subtitle
        self.runtimeTicks = runtimeTicks
        self.resumePositionTicks = resumePositionTicks
        self.isFavorite = isFavorite
        self.imageURL = imageURL
        self.logoURL = logoURL
        self.tags = tags
    }
}

/// One player launch — a single item or a queue (season autoplay, shuffle
/// play). Presented via `.fullScreenCover(item:)`.
public struct PlaybackRequest: Identifiable, Hashable, Sendable {
    public let items: [PlayableItem]
    public let startIndex: Int
    public let shuffled: Bool

    public init(items: [PlayableItem], startIndex: Int = 0, shuffled: Bool = false) {
        self.items = items
        self.startIndex = startIndex
        self.shuffled = shuffled
    }

    /// Content-derived — deliberately NOT `UUID()` — so an unrelated
    /// `AppState` change doesn't retrigger `.fullScreenCover(item:)` and
    /// tear down an in-flight player mid-play.
    public var id: String {
        "\(items.map(\.id).joined(separator: ","))#\(startIndex)#\(shuffled)"
    }

    public static func single(_ item: PlayableItem) -> PlaybackRequest {
        PlaybackRequest(items: [item])
    }

    public static func queue(_ items: [PlayableItem], startIndex: Int) -> PlaybackRequest {
        PlaybackRequest(items: items, startIndex: startIndex)
    }

    public static func shuffled(_ items: [PlayableItem]) -> PlaybackRequest {
        PlaybackRequest(items: items, startIndex: 0, shuffled: true)
    }
}
