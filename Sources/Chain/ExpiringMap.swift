import Foundation

/// A small map whose entries stop being usable after a while.
///
/// Time arrives as a parameter rather than being read from a clock, so every
/// expiry boundary below is exercised by a test that finishes instantly. A
/// cache tested by sleeping is a cache tested at one lifetime only.
///
/// A lifetime of zero means nothing is ever usable from the cache, which is a
/// legitimate way for an operator to turn caching off.
internal struct ExpiringMap<Key: Hashable & Sendable, Value: Sendable>: Sendable {

    // MARK: - Properties

    /// How long an entry stays usable.
    internal let lifetime: TimeInterval

    private var entries: [Key: Entry] = [:]

    private struct Entry: Sendable {
        let value: Value
        let expiresAt: Date
    }

    // MARK: - Initializers

    internal init(lifetime: TimeInterval) {
        self.lifetime = max(lifetime, 0)
    }

    // MARK: - Internal Methods

    /// Stores a value, usable until the lifetime is up.
    internal mutating func set(_ value: Value, for key: Key, now: Date) {
        entries[key] = Entry(value: value, expiresAt: now.addingTimeInterval(lifetime))
    }

    /// The value, or nil when it was never stored or is past its lifetime.
    ///
    /// Drops the entry on the way out, so a map nobody reads again does not
    /// keep it for ever.
    internal mutating func value(for key: Key, now: Date) -> Value? {
        guard let entry = entries[key] else { return nil }
        guard now < entry.expiresAt else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    /// Whether a usable entry exists, without taking it.
    internal mutating func contains(_ key: Key, now: Date) -> Bool {
        value(for: key, now: now) != nil
    }

    internal mutating func remove(_ key: Key) {
        entries.removeValue(forKey: key)
    }

    internal mutating func removeAll() {
        entries.removeAll()
    }

    /// Drops everything past its lifetime.
    internal mutating func prune(now: Date) {
        entries = entries.filter { now < $0.value.expiresAt }
    }

    /// How many entries are held, usable or not.
    internal var count: Int { entries.count }
}
