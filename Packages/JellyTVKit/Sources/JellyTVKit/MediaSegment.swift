import Foundation

// MARK: - Wire shape

public extension JellyfinAPI {
    /// One segment of an item's timeline — an intro, the end credits, a recap.
    ///
    /// Jellyfin has served these from `GET /MediaSegments/{itemId}` since
    /// 10.10; *providers* fill them (Intro Skipper fingerprints the audio,
    /// Chapter Segments Provider reads chapter names, TheIntroDB queries a
    /// crowd-sourced database). The server is the only thing that knows the
    /// timings — nothing here detects anything.
    ///
    /// Captured verbatim from xyan-media (Jellyfin 12.0.0) so the decode is
    /// written against bytes rather than documentation:
    ///
    /// ```json
    /// { "Id": "01a0b23e…", "ItemId": "095a5741…",
    ///   "Type": "Intro", "StartTicks": 0, "EndTicks": 775479481 }
    /// ```
    ///
    /// Note what is **not** there: no `Action` and no `StreamIndex`, both of
    /// which some versions of the DTO document. The server therefore has no
    /// opinion about whether to skip automatically or offer a button — that
    /// policy is entirely the client's, see `MediaSegment.Kind`.
    ///
    /// `type` stays a `String` rather than an enum on purpose: an unrecognised
    /// segment kind must not fail the whole document's decode, and the mapping
    /// to something this app acts on belongs in the domain type below.
    struct MediaSegment: Decodable, Equatable, Sendable {
        public let id: String?
        public let itemId: String?
        public let type: String?
        public let startTicks: Int64?
        public let endTicks: Int64?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case itemId = "ItemId"
            case type = "Type"
            case startTicks = "StartTicks"
            case endTicks = "EndTicks"
        }

        public init(id: String? = nil, itemId: String? = nil, type: String? = nil,
                    startTicks: Int64? = nil, endTicks: Int64? = nil) {
            self.id = id
            self.itemId = itemId
            self.type = type
            self.startTicks = startTicks
            self.endTicks = endTicks
        }
    }
}

// MARK: - Domain shape

/// A stretch of an item the viewer may want to jump over, in seconds.
public struct MediaSegment: Equatable, Sendable, Hashable, Identifiable {
    /// What the stretch is. Everything Jellyfin can report is represented, but
    /// only `intro` and `outro` are offered as a skip — a recap is often the
    /// only reminder of what happened last week, an advert break inside a
    /// recording has no reliable end, and a preview is the thing people
    /// deliberately stay for.
    public enum Kind: String, Sendable, CaseIterable {
        case intro
        case outro
        case recap
        case preview
        case commercial
        case unknown

        /// Jellyfin's `Type` string, matched case-insensitively. Anything
        /// unrecognised — a provider inventing its own kind, a newer server
        /// adding one — lands on `.unknown` rather than throwing.
        public init(serverType: String?) {
            switch serverType?.lowercased() {
            case "intro": self = .intro
            case "outro", "credits": self = .outro
            case "recap": self = .recap
            case "preview": self = .preview
            case "commercial": self = .commercial
            default: self = .unknown
            }
        }

        /// Whether this app offers a button for it. See the note above.
        public var isSkippable: Bool { self == .intro || self == .outro }

        /// The button's words. "Skip credits" rather than "Skip outro",
        /// because nobody calls it an outro.
        public var actionLabel: String {
            switch self {
            case .intro: return "Skip intro"
            case .outro: return "Skip credits"
            case .recap: return "Skip recap"
            case .preview: return "Skip preview"
            case .commercial: return "Skip ad"
            case .unknown: return "Skip"
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let startSeconds: Double
    public let endSeconds: Double

    public init(id: String, kind: Kind, startSeconds: Double, endSeconds: Double) {
        self.id = id
        self.kind = kind
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public var duration: Double { endSeconds - startSeconds }

    /// Whether `time` falls inside the segment. The end is exclusive so the
    /// button disappears exactly as the skip target is reached, rather than
    /// lingering for one more tick on a segment already left behind.
    public func contains(_ time: Double) -> Bool {
        time >= startSeconds && time < endSeconds
    }
}

// MARK: - The arithmetic

/// Turning what the server said into what the player acts on. Pure and
/// tested — no `AVPlayer`, no network, no simulator.
public enum MediaSegments {
    static let ticksPerSecond: Double = 10_000_000

    /// Anything shorter than this is noise rather than a sequence worth a
    /// button. A two-second "intro" is a detector artefact, and offering a
    /// skip for it costs more attention than it saves.
    public static let minimumDuration: Double = 5

    /// Map the wire shapes to domain segments, then `collapse` them.
    ///
    /// `runtimeSeconds` clamps the far end when known: providers occasionally
    /// report an end past the file's own runtime (Jellyfin has an open issue
    /// for exactly that on chapter-derived segments), and a skip target beyond
    /// the end would trip end-of-item handling and auto-advance — jumping the
    /// viewer into the *next* episode when they asked to skip some credits.
    public static func from(_ wire: [JellyfinAPI.MediaSegment],
                            runtimeSeconds: Double? = nil) -> [MediaSegment] {
        let mapped: [MediaSegment] = wire.compactMap { segment in
            guard let id = segment.id,
                  let start = segment.startTicks,
                  let end = segment.endTicks else { return nil }
            var startSeconds = Double(start) / ticksPerSecond
            var endSeconds = Double(end) / ticksPerSecond
            if let runtimeSeconds, runtimeSeconds > 0 {
                startSeconds = min(startSeconds, runtimeSeconds)
                endSeconds = min(endSeconds, runtimeSeconds)
            }
            guard endSeconds - startSeconds >= minimumDuration else { return nil }
            return MediaSegment(id: id,
                                kind: Kind(serverType: segment.type),
                                startSeconds: max(0, startSeconds),
                                endSeconds: endSeconds)
        }
        return collapse(mapped)
    }

    private typealias Kind = MediaSegment.Kind

    /// Resolve segments of the same kind that overlap, keeping one of each.
    ///
    /// **Why this exists at all.** Jellyfin runs *every* enabled segment
    /// provider and stores all of their answers — `MediaSegmentProviderOrder`
    /// sorts which runs first but never stops after one succeeds, so
    /// `/MediaSegments/{id}` returns the union. Two providers that both know
    /// an episode (Intro Skipper fingerprinting it locally, TheIntroDB looking
    /// it up) therefore yield two `Intro` segments, and the DTO carries no
    /// provider field, so the client cannot prefer one source over the other.
    /// The tie has to be broken on the numbers alone.
    ///
    /// **The rule: the shorter one wins.** Over-skipping is the worse error by
    /// a wide margin — cutting into the first scene is jarring and costs the
    /// viewer something they can only recover by seeking back, while leaving a
    /// couple of seconds of theme playing is barely noticed. So where two
    /// candidates disagree, this keeps the one that claims less.
    ///
    /// Segments of *different* kinds are never merged; an intro overlapping a
    /// recap is two true statements about the same stretch.
    public static func collapse(_ segments: [MediaSegment]) -> [MediaSegment] {
        var kept: [MediaSegment] = []
        for kind in Kind.allCases {
            let ofKind = segments.filter { $0.kind == kind }
                .sorted { ($0.startSeconds, $0.duration) < ($1.startSeconds, $1.duration) }
            var winners: [MediaSegment] = []
            for candidate in ofKind {
                if let index = winners.firstIndex(where: { $0.overlaps(candidate) }) {
                    if candidate.duration < winners[index].duration {
                        winners[index] = candidate
                    }
                } else {
                    winners.append(candidate)
                }
            }
            kept.append(contentsOf: winners)
        }
        return kept.sorted { $0.startSeconds < $1.startSeconds }
    }

    /// The segment to offer a skip for at `time`, or nil.
    ///
    /// Only skippable kinds are considered, and the *shortest* match wins when
    /// several contain the moment — the same conservatism as `collapse`.
    public static func skippable(at time: Double, in segments: [MediaSegment]) -> MediaSegment? {
        segments
            .filter { $0.kind.isSkippable && $0.contains(time) }
            .min { $0.duration < $1.duration }
    }
}

private extension MediaSegment {
    func overlaps(_ other: MediaSegment) -> Bool {
        startSeconds < other.endSeconds && other.startSeconds < endSeconds
    }
}
