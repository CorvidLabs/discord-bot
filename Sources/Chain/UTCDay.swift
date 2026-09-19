import Foundation

/// The day boundary the request budget counts against.
///
/// UTC, and never the host's local day, because the day being rationed belongs
/// to the provider rather than to the machine. A box in Sydney that rolled its
/// counter at local midnight would hand itself a second day's budget ten hours
/// before the provider agreed, and would then be cut off mid afternoon with a
/// counter reading half spent.
public enum UTCDay: Sendable {

    // MARK: - Public Methods

    /// Midnight UTC at the start of the day `date` falls in.
    public static func start(of date: Date) -> Date {
        calendar().startOfDay(for: date)
    }

    /// Midnight UTC at the start of the following day.
    ///
    /// This is when a spent budget becomes spendable again, so it is the time
    /// an operator is told a pause ends.
    public static func nextMidnight(after date: Date) -> Date {
        let start = start(of: date)
        // A day is 86,400 seconds in UTC: there is no daylight saving to step
        // over, and the fallback keeps a calendar refusal from becoming a pause
        // that never ends.
        return calendar().date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// An ISO 8601 instant in UTC, for a message a person will read.
    public static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: - Private Methods

    /// A Gregorian calendar pinned to UTC.
    ///
    /// Built per call rather than held in a `static let`, because `Calendar` is
    /// a value carrying a locale and a timezone that a host is free to change
    /// underneath a cached copy.
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC") ?? .current
        return calendar
    }
}
