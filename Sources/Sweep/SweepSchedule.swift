@preconcurrency import Foundation

/// When the next sweep is due.
///
/// Pure arithmetic over a configured interval and the last sweep's start, so
/// every rule below is pinned by a test rather than discovered on a bad
/// morning.
public enum SweepSchedule: Sendable {

    // MARK: - Public Methods

    /// The interval used when nothing usable was configured.
    public static let defaultInterval: TimeInterval = 1800

    /// The shortest interval accepted. Anything lower spins the loop.
    public static let minimumInterval: UInt64 = 60

    /// The largest interval that still fits a sleep measured in nanoseconds.
    public static let maximumInterval: UInt64 = UInt64.max / 1_000_000_000

    /// Whole seconds from a configured value.
    ///
    /// A value that is not a whole number, is under a minute, or would
    /// overflow a sleep falls back to the default. Zero used to produce a
    /// tight loop that spent the day's chain budget in minutes, and anything
    /// unparseable used to become the default in silence.
    ///
    /// - Parameter raw: What the operator wrote, or nil.
    /// - Returns: The interval, and the rejected value when one was rejected,
    ///   so a caller can say so rather than swallowing it.
    public static func interval(from raw: String?) -> (seconds: TimeInterval, rejected: String?) {
        guard let raw else { return (defaultInterval, nil) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let seconds = UInt64(trimmed),
            seconds >= minimumInterval,
            seconds <= maximumInterval
        else {
            return (defaultInterval, raw)
        }
        return (TimeInterval(seconds), nil)
    }

    /// Whole seconds an interval is worth, clamped into the accepted range.
    ///
    /// A value that is not a number at all becomes the default rather than
    /// either end of the range: the floor would sweep every minute and spend
    /// the day's chain budget by lunchtime, and the ceiling would stop
    /// sweeping for the rest of the century. Neither is a safe reading of
    /// nonsense.
    ///
    /// - Parameter interval: The interval in seconds.
    public static func wholeSeconds(_ interval: TimeInterval) -> UInt64 {
        guard interval.isFinite else { return UInt64(defaultInterval) }
        guard interval >= Double(minimumInterval) else { return minimumInterval }
        guard interval <= Double(maximumInterval) else { return maximumInterval }
        return UInt64(interval.rounded(.down))
    }

    /// How long to wait before the next sweep, or nil when one is due now.
    ///
    /// Nil for a missing last sweep, and nil for one recorded in the future.
    /// A clock that stepped backwards is doubt, and doubt sweeps rather than
    /// leaving everybody's roles stale for however long the skew was.
    ///
    /// - Parameters:
    ///   - lastSweep: When the last sweep started, or nil.
    ///   - now: The instant to measure from.
    ///   - interval: The configured interval, in whole seconds.
    public static func secondsUntilDue(lastSweep: Date?, now: Date, interval: UInt64) -> UInt64? {
        guard interval > 0, let lastSweep else { return nil }
        let elapsed = now.timeIntervalSince(lastSweep)
        guard elapsed >= 0 else { return nil }
        let window = TimeInterval(interval)
        guard elapsed < window else { return nil }
        return UInt64((window - elapsed).rounded(.up))
    }
}
