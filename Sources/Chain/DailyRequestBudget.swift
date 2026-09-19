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

    /// Requests left on the day `now` falls in, or nil when there is no budget.
    ///
    /// Nil rather than zero, unlike ``remaining``. A consumer that has to take
    /// its whole allowance in one piece asks this before it starts, and for
    /// that question "no ceiling" and "no room" are opposite answers that a
    /// zero cannot tell apart.
    ///
    /// It also answers for the day `now` falls in rather than the day the
    /// counter was last touched, so a process asked at one minute past midnight
    /// is told about today rather than about yesterday.
    public func remaining(at now: Date) -> UInt64? {
        guard limit > 0 else { return nil }
        guard UTCDay.start(of: now) == currentDayStart else { return limit }
        return remaining
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

        /// The day has requests left, but fewer than a reservation that has to
        /// be taken whole asked for. Nothing was reserved.
        ///
        /// Deliberately not ``exhausted``. The budget is not spent, and what is
        /// left belongs to every caller that can use it a request at a time.
        /// Pausing the process because one indivisible consumer did not fit
        /// would hand the rest of the day to nobody.
        case notEnoughBudget(requested: UInt64, remaining: UInt64)
    }

    /// Reserves one request against today's budget.
    ///
    /// Reserved **before** the request is sent, not counted after it returns.
    /// Counting afterwards lets a hundred concurrent requests all pass a check
    /// that says ninety-nine are left.
    public mutating func reserve(now: Date = Date()) -> Decision {
        reserve(count: 1, now: now)
    }

    /// Reserves `count` requests against today's budget, all of them or none.
    ///
    /// For work that cannot be half done. A payout run reads and sends
    /// thousands of times and either completes the list or leaves somebody out
    /// of it, so finding the ceiling half way down the list is the failure the
    /// whole run was arranged to avoid. Taking the requests up front turns that
    /// into a refusal before the first one leaves.
    ///
    /// All or nothing in both directions: a reservation that does not fit takes
    /// nothing at all, so the remainder is still there for the callers that
    /// work one request at a time. There is no way to hand a reservation back,
    /// which is deliberate. A budget that can be returned is a budget two
    /// consumers can each believe they hold, and the return is the write a
    /// crash skips. A caller that reserves more than it uses has under-used the
    /// day, which is the recoverable direction.
    public mutating func reserve(count: UInt64, now: Date = Date()) -> Decision {
        rollDayIfNeeded(now: now)

        // Reserving nothing changes nothing, and must not be the call that
        // trips a pause on a process that was never going to send anything.
        guard count > 0 else {
            return .allowed(used: reservedToday, limit: limit, crossedThreshold: nil)
        }

        guard limit > 0 else {
            let (sum, overflow) = reservedToday.addingReportingOverflow(count)
            reservedToday = overflow ? UInt64.max : sum
            return .allowed(used: reservedToday, limit: 0, crossedThreshold: nil)
        }

        let left = remaining
        guard left > 0 else {
            return .exhausted(until: UTCDay.nextMidnight(after: now))
        }
        guard count <= left else {
            return .notEnoughBudget(requested: count, remaining: left)
        }

        reservedToday += count

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
