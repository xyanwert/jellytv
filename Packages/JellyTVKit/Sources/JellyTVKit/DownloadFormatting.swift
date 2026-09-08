import Foundation

/// How the download centre says sizes and times — pure, shared by the plan sheet and
/// every job row, and tested, instead of a formatter allocated per row per poll tick.
public enum DownloadFormatting {

    /// Rounded hard: a plan quotes an estimate, and "18.2 GB" would claim a precision the
    /// server does not have until a torrent is actually chosen.
    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        return formatter
    }()

    public static func bytes(_ count: Int64) -> String {
        bytesFormatter.string(fromByteCount: max(0, count))
    }

    /// "43s", "12m", "1h 05m" — short enough for a row, precise enough to plan around.
    public static func eta(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
    }
}
