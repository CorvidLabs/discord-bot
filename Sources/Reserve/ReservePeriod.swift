import Foundation

/// Naming the period an epoch was paid in.
///
/// A firing is identified by its *period* — an ISO week, a year-month — and
/// never by a timestamp. The difference is the whole point: two runs an hour
/// apart produce two different timestamps and the same period key, so the second
/// one is refused. A missed period is still paid late, because the rule is one
/// epoch per period rather than one epoch per calendar slot.
///
/// Everything here is UTC. A period that shifted with the host's timezone would
/// let a payout that was refused in one place succeed in another.
public enum ReservePeriod: Sendable {

    // MARK: - Public Methods

    /// The ISO-8601 week containing `date`, as `2026-W38`.
    ///
    /// ISO week rules, so the week starts on Monday and the year at the turn of
    /// January belongs to whichever year holds most of the week. Both are
    /// surprising once and then consistent forever, which is what matters.
    public static func isoWeek(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = parts.yearForWeekOfYear ?? 0
        let week = parts.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    /// The calendar month containing `date`, as `2026-09`.
    public static func month(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// The calendar day containing `date`, as `2026-09-18`.
    public static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Midnight UTC on the Monday of the ISO week containing `date`.
    public static func isoWeekStart(_ date: Date) -> Date {
        let calendar = utcGregorian()
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        // Gregorian weekdays run 1 = Sunday … 7 = Saturday; ISO weeks start on
        // Monday, so Sunday is six days into its week rather than zero.
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    /// Midnight UTC on the Monday after the ISO week containing `date`.
    public static func isoWeekEnd(_ date: Date) -> Date {
        let start = isoWeekStart(date)
        return utcGregorian().date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 24 * 60 * 60)
    }

    // MARK: - Private Methods

    private static func utcGregorian() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }
}
