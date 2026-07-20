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

    public init(id: String, seriesId: String? = nil, title: String, subtitle: String? = nil,
                runtimeTicks: Int64? = nil, resumePositionTicks: Int64? = nil,
                isFavorite: Bool = false, imageURL: String? = nil) {
        self.id = id
        self.seriesId = seriesId
        self.title = title
        self.subtitle = subtitle
        self.runtimeTicks = runtimeTicks
        self.resumePositionTicks = resumePositionTicks
        self.isFavorite = isFavorite
        self.imageURL = imageURL
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
