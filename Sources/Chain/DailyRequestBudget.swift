import Foundation

/// The per day brake: how many requests this process may make in a UTC day.
///
/// A **budget counts requests**. It is not a spending cap and must never be
/// described as one. The catalogue this was ported from had to retire a
/// criterion over exactly this: one sentence said "today's allowance" and a
/// reader took the daily request budget and the weekly spending limit for the
/// same thing, which was called the ambiguity most likely to cause a wrong
/// implementation. Budget counts requests. Cap counts money. They never share
/// a word.
///
/// The budget counts **reads and signing together**, so the number an operator
/// sets is the whole process rather than one code path. Before that, a
/// provider's refusal met while paying somebody did not slow down the loop that
/// reads everybody's balances, and the configured number meant nothing.
///
/// Pure and synchronous, so all of the arithmetic below is exercised by tests
/// with no clock and no network.
public struct DailyRequestBudget: Sendable, Equatable {

    // MARK: - Properties

    /// Percentages that are worth warning about the first time they are reached
    /// in a day. Early enough to do something, rare enough to be read.
    public static let warningThresholds: [Int] = [50, 75, 90]

    /// Requests permitted per UTC day. Zero means no budget.
    public let limit: UInt64

    private var reservedToday: UInt64
    private var currentDayStart: Date
    private var announced: Set<Int>

    /// Requests reserved so far in the current UTC day.
    public var used: UInt64 { reservedToday }

    /// Start of the UTC day the counter belongs to.
    public var dayStart: Date { currentDayStart }

    /// Requests left today. Always zero when there is no budget, so a caller
    /// sizing a batch has to look at ``limit`` as well.
    public var remaining: UInt64 {
        guard limit > 0 else { return 0 }
        return reservedToday >= limit ? 0 : limit - reservedToday
    }

    // MARK: - Initializers

    /// - Parameters:
    ///   - limit: Requests per UTC day. Zero means no budget.
    ///   - now: Injected so a test pins the day.
    public init(limit: UInt64, now: Date = Date()) {
        self.limit = limit
        self.reservedToday = 0
        self.currentDayStart = UTCDay.start(of: now)
        self.announced = []
    }

    // MARK: - Public Methods

    /// What happened when a request was reserved.
    public enum Decision: Equatable, Sendable {

        /// The request may proceed. `crossedThreshold` is set only on the first
        /// reservation to reach that percentage today, so a caller reports it
        /// once rather than on every request for the rest of the day.
        case allowed(used: UInt64, limit: UInt64, crossedThreshold: Int?)

        /// The budget is spent. The caller pauses until `until`, the same pause
        /// a provider's own refusal causes.
        case exhausted(until: Date)
    }

    /// Reserves one request against today's budget.
    ///
    /// Reserved **before** the request is sent, not counted after it returns.
    /// Counting afterwards lets a hundred concurrent requests all pass a check
    /// that says ninety-nine are left.
    public mutating func reserve(now: Date = Date()) -> Decision {
        rollDayIfNeeded(now: now)

        guard limit > 0 else {
            reservedToday &+= 1
            return .allowed(used: reservedToday, limit: 0, crossedThreshold: nil)
        }

        guard reservedToday < limit else {
            return .exhausted(until: UTCDay.nextMidnight(after: now))
        }

        reservedToday += 1

        // Integer percentage consumed, floored. Computed in `Double` so a very
        // large limit cannot overflow the multiplication and trap.
        let percent = Int((Double(reservedToday) / Double(limit)) * 100)
        var crossed: Int?
        for threshold in Self.warningThresholds
        where percent >= threshold && !announced.contains(threshold) {
            announced.insert(threshold)
            crossed = threshold
        }

        return .allowed(used: reservedToday, limit: limit, crossedThreshold: crossed)
    }

    /// Applies a counter written earlier in the same UTC day.
    ///
    /// A restart used to zero the counter while the provider's day kept
    /// running, so a crash loop quietly handed the process a fresh budget
    /// every time it came back, and the ceiling an operator set was whatever
    /// the last restart left of it. A snapshot from another day is ignored.
    /// Thresholds already passed are marked announced so restoring does not
    /// warn about them again.
    ///
    /// Takes the **larger** of what is on disk and what this process has
    /// already spent, because both were really spent.
    /// - Returns: Whether the snapshot was applied.
    @discardableResult
    public mutating func restore(used: UInt64, dayStart: Date, now: Date = Date()) -> Bool {
        rollDayIfNeeded(now: now)
        guard UTCDay.start(of: dayStart) == currentDayStart else { return false }
        reservedToday = max(reservedToday, used)
        if limit > 0 {
            let percent = Int((Double(reservedToday) / Double(limit)) * 100)
            for threshold in Self.warningThresholds where percent >= threshold {
                announced.insert(threshold)
            }
        }
        return true
    }

    // MARK: - Private Methods

    private mutating func rollDayIfNeeded(now: Date) {
        let start = UTCDay.start(of: now)
        guard start != currentDayStart else { return }
        currentDayStart = start
        reservedToday = 0
        announced = []
    }
}
