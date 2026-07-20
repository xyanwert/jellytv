import Foundation

/// "At-most-once-every-N-seconds" gate — used to cap how often the player
/// posts `/Sessions/Playing/Progress` regardless of how often its time
/// observer ticks.
public final class Throttle: @unchecked Sendable {
    private let interval: TimeInterval
    private var last: Date?
    private let lock = NSLock()

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Runs `action` if at least `interval` has elapsed since the last fire.
    @discardableResult
    public func fire(_ action: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let last, now.timeIntervalSince(last) < interval {
            return false
        }
        last = now
        action()
        return true
    }
}
