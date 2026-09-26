@preconcurrency import Foundation

/// How many requests one key may make in one window.
///
/// The module under this one deliberately does not rate limit, and says so:
/// it bounds submissions per session and per subject, which is a different
/// bound, and a bound that evaporates on a restart besides. The rate limit is
/// the host's half, and without it one member with a session id can post the
/// submit route as fast as a socket allows (REQ-verify-004, REQ-verify-009,
/// RUN-11).
///
/// A sliding window rather than a token bucket, because what an operator has
/// to be able to say is "ten in a minute" and that is what this counts. Every
/// instant arrives as a parameter, so a suite pins every reading rather than
/// sleeping.
public actor VerifyRateLimiter {

    // MARK: - Properties

    /// How many distinct keys are tracked, after which keys are dropped.
    ///
    /// The table is per source address and per session handle, both of which
    /// an ordinary day produces few of. It is bounded anyway: a listener on a
    /// public interface is reachable by anything, and a table that only ever
    /// grows is a way to exhaust a process's memory with nothing but
    /// connections.
    ///
    /// **A real ceiling, not a moment to try dropping stale keys.** Dropping
    /// the stale ones first is free and is what happens; when every key in
    /// the table is live, that frees nothing at all, and a bound that only
    /// holds while the table is quiet is not a bound. So the least recently
    /// seen go too. What that costs is one key's history, and the key it
    /// costs it to is the one nobody has heard from for longest.
    public static let maximumTrackedKeys: Int = 10_000

    /// How far below the ceiling an eviction goes.
    ///
    /// Not to the ceiling exactly: that would sort the table again on every
    /// new key for as long as a flood lasted. A tenth of it at a time means
    /// the sweep happens once per that many newcomers instead.
    public static let keysEvictedAtOnce: Int = 1_000

    /// How many requests one key may make in one window.
    public let limit: Int

    /// How long the window is.
    public let window: TimeInterval

    private var seen: [String: [Date]] = [:]

    // MARK: - Initializers

    /// - Parameters:
    ///   - limit: How many requests one key may make in one window.
    ///   - window: How long the window is.
    public init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    // MARK: - Public Methods

    /// Records one request and says whether it is over the limit.
    ///
    /// Asking is recording, which is why it is one call: a caller that asks
    /// first and records afterwards has a window between the two in which
    /// every request in flight is under the limit.
    ///
    /// - Parameters:
    ///   - key: What the limit is counted against.
    ///   - now: When the request arrived.
    /// - Returns: Whether this request is over the limit.
    public func isLimited(key: String, now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-window)
        var recent = (seen[key] ?? []).filter { $0 > cutoff }
        guard recent.count < limit else {
            seen[key] = recent
            return true
        }
        recent.append(now)
        seen[key] = recent
        if seen.count > Self.maximumTrackedKeys {
            forget(before: now)
            evictLeastRecentlySeen()
        }
        return false
    }

    /// Drops every key whose requests are all outside the window.
    ///
    /// - Parameter now: The instant the window is measured back from.
    public func forget(before now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        for (key, hits) in seen {
            let recent = hits.filter { $0 > cutoff }
            if recent.isEmpty {
                seen.removeValue(forKey: key)
            } else {
                seen[key] = recent
            }
        }
    }

    /// How many keys are being tracked, for a suite that wants to prove the
    /// table does not grow for ever.
    public var trackedKeyCount: Int { seen.count }

    // MARK: - Private Methods

    /// Drops the keys heard from longest ago, until the table is under the
    /// ceiling with room to spare.
    ///
    /// Only reached when dropping stale keys did not get under the ceiling,
    /// which means the table is full of keys inside the window: a flood of
    /// distinct sources, which is the case the ceiling exists for. An
    /// evicted key starts its window again, and that is the trade being
    /// made: forgiving the request history of whoever has been quietest is
    /// cheaper than a table that grows until the process dies.
    private func evictLeastRecentlySeen() {
        guard seen.count > Self.maximumTrackedKeys else { return }
        let target = max(0, Self.maximumTrackedKeys - Self.keysEvictedAtOnce)
        let oldestFirst = seen.sorted { left, right in
            (left.value.last ?? .distantPast) < (right.value.last ?? .distantPast)
        }
        for entry in oldestFirst.prefix(seen.count - target) {
            seen.removeValue(forKey: entry.key)
        }
    }
}
