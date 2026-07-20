import Foundation

/// "Is this still the latest in-flight operation?" guard — used pervasively
/// in the player engine so a superseded load (queue advance, re-resolve)
/// can't clobber state a newer operation already moved past.
///
/// ```swift
/// let token = generation.next()
/// // ...await something...
/// if generation.isCancelled(token) { return }  // a newer op superseded us
/// ```
public final class Generation: @unchecked Sendable {
    private var current: Int = 0
    private let lock = NSLock()

    public init() {}

    public func next() -> Int {
        lock.lock()
        current += 1
        let v = current
        lock.unlock()
        return v
    }

    public func isCancelled(_ token: Int) -> Bool {
        lock.lock()
        let c = current
        lock.unlock()
        return token != c
    }
}
