import Foundation

/// The arithmetic behind the movie page's "movie night" facts — when the film
/// ends, how old an actor was, where a rating sits in this library. Pure, so
/// every rule here is tested without a server or a clock, and every chip the
/// row shows is computed from something real or not shown at all.
public enum MovieNightFacts {
    private static let ticksPerSecond: Double = 10_000_000

    /// When the film ends if it starts now: `now` plus what is left of it
    /// (the whole runtime, or the remainder past a resume position).
    public static func endsAt(now: Date, runtimeTicks: Int64?, resumeTicks: Int64?) -> Date? {
        guard let runtimeTicks, runtimeTicks > 0 else { return nil }
        let remaining = max(0, runtimeTicks - max(0, resumeTicks ?? 0))
        return now.addingTimeInterval(Double(remaining) / ticksPerSecond)
    }

    /// "ENDS 11:24 PM", in the user's own clock style.
    public static func endsAtLabel(now: Date, runtimeTicks: Int64?, resumeTicks: Int64?,
                                   locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard let end = endsAt(now: now, runtimeTicks: runtimeTicks, resumeTicks: resumeTicks) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "ENDS \(formatter.string(from: end).uppercased())"
    }

    /// How old someone was in the release year. Year arithmetic only — month
    /// precision would pretend to know the shooting dates. Nil outside 1…120,
    /// which is where a bad birth year in the metadata shows up.
    public static func ageAtRelease(birthDate: Date?, releaseYear: Int?,
                                    calendar: Calendar = Calendar(identifier: .gregorian)) -> Int? {
        guard let birthDate, let releaseYear else { return nil }
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let age = releaseYear - utc.component(.year, from: birthDate)
        return (1...120).contains(age) ? age : nil
    }

    /// "1929 – 2021" for the departed, "b. 1929" for the living; nil with no
    /// birth date.
    public static func lifespan(birthDate: Date?, deathDate: Date?,
                                calendar: Calendar = Calendar(identifier: .gregorian)) -> String? {
        guard let birthDate else { return nil }
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let born = utc.component(.year, from: birthDate)
        if let deathDate {
            return "\(born) – \(utc.component(.year, from: deathDate))"
        }
        return "b. \(born)"
    }

    /// The "TOP N%" a rating earns among the others in this library — the
    /// share of them rated *higher*, rounded up, never below 1. Nil under
    /// twenty ratings: a percentile over a dozen films is a coin toss dressed
    /// as a statistic.
    public static func topPercent(rating: Double?, among others: [Double]) -> Int? {
        guard let rating, others.count >= 20 else { return nil }
        let higher = others.filter { $0 > rating }.count
        let percent = Int((Double(higher) / Double(others.count) * 100).rounded(.up))
        return max(1, percent)
    }

    /// Jellyfin's ISO dates ("1929-12-13T07:00:00.0000000Z") carry seven
    /// fractional digits, which `ISO8601DateFormatter` rejects. The calendar
    /// day is all any fact here needs, so that is all that is parsed.
    public static func date(fromJellyfin string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(string.prefix(10)))
    }

    /// "SUBS: ENGLISH, SPANISH" / "NO SUBTITLES" — nil when the file's streams
    /// are unknown (nothing fetched yet), so the chip is absent rather than
    /// wrong.
    public static func subtitlesLabel(_ languages: [String], streamsKnown: Bool) -> String? {
        guard streamsKnown else { return nil }
        guard !languages.isEmpty else { return "NO SUBTITLES" }
        return "SUBS: \(languages.prefix(3).joined(separator: ", ").uppercased())"
    }

    /// The "vibe" chips — what kind of film this is, in a few words each:
    /// `heist`, `road trip`, `based on true story`. Jellyfin's TMDB provider
    /// files TMDB's keywords on the item as **tags**, so every server with
    /// that provider has these without a TMDB key of its own; when the key
    /// is on, TMDB's own list (ordered by relevance) goes first and the tags
    /// fill in behind it.
    ///
    /// Two TMDB conventions are facts, not vibes, and lead the list:
    /// `duringcreditsstinger` / `aftercreditsstinger` become "STAY FOR THE
    /// CREDITS" / "SCENE AFTER THE CREDITS" — the one thing a family wants to
    /// know before anyone stands up. Dropped: place tags ("berlin, germany"),
    /// which are settings rather than selling points, and any other run-on
    /// machine token nobody would say out loud.
    public static func vibeChips(tags: [String], keywords: [String] = [], limit: Int = 4) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        func add(_ label: String) {
            let key = label.lowercased()
            guard !seen.contains(key), out.count < limit else { return }
            seen.insert(key)
            out.append(label)
        }
        let all = (keywords + tags).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for token in all where stingers[token.lowercased()] != nil {
            add(stingers[token.lowercased()]!)
        }
        for token in all {
            let lower = token.lowercased()
            guard stingers[lower] == nil, !lower.contains(","), lower.count <= 24 else { continue }
            if !lower.contains(" ") && lower.count > 14 { continue }
            add(token.uppercased())
        }
        return out
    }

    private static let stingers: [String: String] = [
        "duringcreditsstinger": "STAY FOR THE CREDITS",
        "aftercreditsstinger": "SCENE AFTER THE CREDITS",
    ]
}
