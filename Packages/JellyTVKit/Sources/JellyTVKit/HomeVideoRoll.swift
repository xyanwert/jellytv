import Foundation

/// The arithmetic behind the home-video shelf as a camera roll: months as
/// sections, a justified mosaic that lets portrait phone clips stand tall
/// beside landscape ones, "on this day" across the years, and which frames
/// of a video's trickplay sheet a card should page through. Pure, so every
/// rule is tested against dates and sizes rather than against a server.
public enum HomeVideoRoll {
    // MARK: - Sections

    public struct Section: Equatable, Identifiable {
        /// "December 2023", or `undatedTitle`.
        public let title: String
        public let items: [MediaItem]
        public var id: String { title }

        public init(title: String, items: [MediaItem]) {
            self.title = title
            self.items = items
        }
    }

    public static let undatedTitle = "Undated"

    /// Newest month first, newest video first within it; videos with no date
    /// taken go last under one "Undated" section. The order the shelf plays
    /// in is the order it shows, so callers queue from `flattened(_:)`.
    public static func sections(_ items: [MediaItem], calendar: Calendar = .current,
                                locale: Locale = .current) -> [Section] {
        var byMonth: [Date: [MediaItem]] = [:]
        var undated: [MediaItem] = []
        for item in items {
            guard let taken = item.takenAt,
                  let month = calendar.date(from: calendar.dateComponents([.year, .month], from: taken)) else {
                undated.append(item)
                continue
            }
            byMonth[month, default: []].append(item)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        // The month keys are midnight in the calendar's zone; formatting them
        // in any other zone names the month before.
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        var result: [Section] = []
        for month in byMonth.keys.sorted(by: >) {
            let videos = (byMonth[month] ?? []).sorted { a, b in
                (a.takenAt ?? Date.distantPast) > (b.takenAt ?? Date.distantPast)
            }
            result.append(Section(title: formatter.string(from: month), items: videos))
        }
        if !undated.isEmpty { result.append(Section(title: undatedTitle, items: undated)) }
        return result
    }

    public static func flattened(_ sections: [Section]) -> [MediaItem] {
        sections.flatMap(\.items)
    }

    // MARK: - On this day

    public struct Anniversary: Equatable, Identifiable {
        public let item: MediaItem
        public let yearsAgo: Int
        public var id: String { item.id }

        public init(item: MediaItem, yearsAgo: Int) {
            self.item = item
            self.yearsAgo = yearsAgo
        }
        /// "3 YEARS AGO" / "LAST YEAR".
        public var label: String { yearsAgo == 1 ? "LAST YEAR" : "\(yearsAgo) YEARS AGO" }
    }

    /// Videos shot within `window` days of today's date in an earlier year —
    /// this week, other years. Newest year first. Nothing from the current
    /// year: "0 years ago" is just the shelf.
    public static func onThisDay(_ items: [MediaItem], today: Date = Date(), window: Int = 3,
                                 calendar: Calendar = .current) -> [Anniversary] {
        let todayYear = calendar.component(.year, from: today)
        guard let todayDay = calendar.ordinality(of: .day, in: .year, for: today) else { return [] }
        var out: [Anniversary] = []
        for item in items {
            guard let taken = item.takenAt else { continue }
            let year = calendar.component(.year, from: taken)
            guard year < todayYear, let day = calendar.ordinality(of: .day, in: .year, for: taken) else { continue }
            // Distance in days ignoring the year, wrapping at New Year.
            let raw = abs(day - todayDay)
            let distance = min(raw, 365 - raw)
            if distance <= window {
                out.append(Anniversary(item: item, yearsAgo: todayYear - year))
            }
        }
        return out.sorted { a, b in
            if a.yearsAgo != b.yearsAgo { return a.yearsAgo < b.yearsAgo }
            return (a.item.takenAt ?? .distantPast) > (b.item.takenAt ?? .distantPast)
        }
    }

    // MARK: - Justified rows

    public struct Placed: Equatable {
        public let item: MediaItem
        public let width: Double
        public let height: Double
    }

    /// Lays `items` into rows of one shared height each, every row filled edge
    /// to edge, the way Flickr and Photos justify a wall of mixed shapes.
    /// Each tile keeps its own aspect (clamped between 9:16 and 2:1; 16:9 when
    /// unknown); a row's height floats around `targetHeight` so the widths sum
    /// to `width` exactly. The last row is never stretched to fit — three
    /// clips made a wall of giants otherwise — it keeps the target height and
    /// leaves the remainder empty.
    public static func justifiedRows(_ items: [MediaItem], width: Double, targetHeight: Double,
                                     spacing: Double) -> [[Placed]] {
        guard width > 0, targetHeight > 0, !items.isEmpty else { return [] }
        var rows: [[Placed]] = []
        var row: [(MediaItem, Double)] = []
        var aspectSum = 0.0

        func flush(stretch: Bool) {
            guard !row.isEmpty else { return }
            let gaps = spacing * Double(row.count - 1)
            let height = stretch ? min(max((width - gaps) / aspectSum, targetHeight * 0.7), targetHeight * 1.45)
                                 : targetHeight
            rows.append(row.map { Placed(item: $0.0, width: ($0.1 * height).rounded(), height: height.rounded()) })
            row.removeAll()
            aspectSum = 0
        }

        for item in items {
            let aspect = clampedAspect(item.aspectRatio)
            row.append((item, aspect))
            aspectSum += aspect
            // Full when the row at target height would overflow the width.
            let gaps = spacing * Double(row.count - 1)
            if aspectSum * targetHeight + gaps >= width {
                flush(stretch: true)
            }
        }
        flush(stretch: false)
        return rows
    }

    public static func clampedAspect(_ aspect: Double?) -> Double {
        guard let aspect, aspect > 0 else { return 16.0 / 9.0 }
        return min(max(aspect, 9.0 / 16.0), 2.0)
    }

    // MARK: - Frames

    /// Which moments of a video a card should page through: up to `count`
    /// frames spread across the runtime, never more than the sheet actually
    /// holds (one frame per `interval` ms), skipping the very first frame —
    /// usually the black before anything happens — and the very last, which
    /// sits at the end of the file and is as often missing from the sheet as
    /// it is a fade to black. A clip too short to have two frames between
    /// those gets none: nothing to page through.
    public static func frameTimes(runtimeTicks: Int64?, intervalMs: Int, count: Int = 8) -> [Double] {
        guard let runtimeTicks, runtimeTicks > 0, intervalMs > 0 else { return [] }
        let runtime = Double(runtimeTicks) / 10_000_000
        let interval = Double(intervalMs) / 1000
        let last = Int(runtime / interval) - 1      // last frame strictly before the end
        guard last >= 1 else { return [] }
        let n = min(count, last)
        // Grid-aligned so each pick is a distinct frame.
        return (0..<n).map { i in
            let slot = n == 1 ? 1 : 1 + Int((Double(i) / Double(n - 1)) * Double(last - 1))
            return Double(min(slot, last)) * interval
        }.reduce(into: [Double]()) { if $0.last != $1 { $0.append($1) } }
    }

    /// "Sep 6" — for a tile too narrow to carry the year.
    public static func shortDateLabel(_ date: Date?, locale: Locale = .current) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    /// The widest resolution the item's trickplay carries, and the media
    /// source it belongs to.
    public static func bestTrickplay(_ trickplay: [String: [String: JellyfinAPI.TrickplayInfo]]?)
        -> (mediaSourceId: String, widthKey: String, info: JellyfinAPI.TrickplayInfo)? {
        guard let trickplay, let (sourceId, resolutions) = trickplay.first, !resolutions.isEmpty else { return nil }
        guard let best = resolutions.sorted(by: { (Int($0.key) ?? 0) > (Int($1.key) ?? 0) }).first else { return nil }
        return (sourceId, best.key, best.value)
    }

    /// "Dec 18, 2023" in the user's own style, or nil.
    public static func dateLabel(_ date: Date?, locale: Locale = .current) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
