import Foundation

/// Adult content on the TV is **hidden unless someone has just asked for it**.
///
/// Not a preference. A preference is set once and forgotten, and whoever picks
/// the remote up next inherits it — which on a television in a living room is
/// the whole problem. This is a door that swings shut by itself: a code opens
/// it, and twelve hours later it is closed again whether anyone remembered or
/// not.
///
/// **It is not a security boundary and must not be described as one.** The
/// code is compiled into the app, the server serves the same items to any
/// client that asks, and anyone with the Jellyfin web UI can see everything
/// regardless. What it buys is that adult libraries are not *there* — not on
/// Home, not in Continue Watching, not in the Libraries menu, not in search
/// results — unless someone deliberately went and opened them. That is the
/// ask, and it is worth being precise about, because the obvious "improvement"
/// (a longer code, a hash) would buy nothing at all.
///
/// The hardcoded code is deliberate and temporary — a real one belongs on the
/// server, per account, and that is a later conversation.
public enum AdultLock {
    /// Hardcoded for now. See the type comment before hardening this.
    public static let code = "111282"
    /// How many digits the keypad collects before it checks — the code's own
    /// length, so the pad submits itself rather than needing an OK button
    /// nobody can reach without arrowing down to it.
    public static var digits: Int { code.count }
    /// One evening, not one session and not forever. Long enough that the
    /// code isn't re-typed between two episodes; short enough that tomorrow
    /// starts closed.
    public static let duration: TimeInterval = 12 * 60 * 60

    public static func matches(_ entered: String) -> Bool {
        entered.trimmingCharacters(in: .whitespaces) == code
    }

    public static func expiry(from now: Date) -> Date {
        now.addingTimeInterval(duration)
    }

    /// Unlocked strictly *before* the deadline: a stored date that has just
    /// passed reads as locked, which is what a relaunch after the twelve
    /// hours has to do.
    public static func isUnlocked(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return now < until
    }

    public static func remaining(until: Date?, now: Date) -> TimeInterval {
        guard let until else { return 0 }
        return max(0, until.timeIntervalSince(now))
    }

    /// "11h 42m" / "42m" / "under a minute" — what the Settings row reads.
    /// `nil` when nothing is open, so the caller has one thing to check.
    public static func remainingLabel(until: Date?, now: Date) -> String? {
        guard isUnlocked(until: until, now: now) else { return nil }
        let seconds = Int(remaining(until: until, now: now))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "under a minute"
    }
}
