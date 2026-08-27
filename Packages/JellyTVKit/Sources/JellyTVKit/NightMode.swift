import Foundation

/// How long the player keeps going once Night mode is engaged, before it
/// stops itself. Selectable in Settings → Playback.
///
/// A wall-clock promise, not a playback-time one: "stop after two hours" has
/// to mean two hours of the room being dark, whatever the stream does in the
/// meantime.
public enum SleepTimer: Double, CaseIterable, Sendable, Identifiable {
    case h1 = 3600
    case h2 = 7200
    case h8 = 28800

    public var id: Double { rawValue }

    /// Full run of the timer, in seconds.
    public var seconds: Double { rawValue }

    public var label: String {
        switch self {
        case .h1: return "1 hr"
        case .h2: return "2 hrs"
        case .h8: return "8 hrs"
        }
    }

    public static let `default`: SleepTimer = .h2

    /// The share of the timer spent winding down — the sound rides to zero
    /// across it and the picture goes with it. Held as a fraction rather than
    /// a fixed number of minutes so every setting fades at the same *feel*:
    /// 9 minutes on the 1-hour timer, 72 on the 8-hour one, each slow enough
    /// that no single step is audible.
    public static let fadeFraction: Double = 0.15

    public var fadeSeconds: Double { seconds * Self.fadeFraction }

    /// `1h 58m` while there's an hour or more left, `12:04` once there isn't
    /// — the two never read as each other, which a bare `1:58` would.
    public static func remainingLabel(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        guard hours == 0 else { return "\(hours)h \(minutes)m" }
        return String(format: "%d:%02d", minutes, total % 60)
    }
}
