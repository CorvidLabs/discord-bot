import Foundation
import Testing
@testable import Chain

/// The per day brake, which counts **requests**.
///
/// It is not a spending cap and shares no vocabulary with one. Everything in
/// this suite counts requests; nothing in it is money.
@Suite("The daily request budget")
internal struct RequestBudgetTests {

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Counting

    @Test("A budget counts every request and says how many are left")
    internal func counts() {
        var budget = DailyRequestBudget(limit: 3, now: Self.noon)
        #expect(budget.used == 0)
        #expect(budget.remaining == 3)
        _ = budget.reserve(now: Self.noon)
        _ = budget.reserve(now: Self.noon)
        #expect(budget.used == 2)
        #expect(budget.remaining == 1)
    }

    @Test("The last request is allowed and the one after it is refused until tomorrow")
    internal func exhausts() {
        var budget = DailyRequestBudget(limit: 2, now: Self.noon)
        #expect(budget.reserve(now: Self.noon) == .allowed(used: 1, limit: 2, crossedThreshold: 50))
        #expect(budget.reserve(now: Self.noon) == .allowed(used: 2, limit: 2, crossedThreshold: 90))
        #expect(budget.reserve(now: Self.noon) == .exhausted(until: UTCDay.nextMidnight(after: Self.noon)))
        #expect(budget.remaining == 0)
    }

    @Test("Without a budget nothing is ever refused, and it says so rather than pretending")
    internal func noBudgetMeansNoRefusals() {
        var budget = DailyRequestBudget(limit: 0, now: Self.noon)
        for _ in 0..<1_000 {
            #expect(budget.reserve(now: Self.noon) == .allowed(used: budget.used, limit: 0, crossedThreshold: nil))
        }
        #expect(budget.used == 1_000)
        // Zero remaining with a limit of zero means unlimited, so a caller
        // sizing a batch has to look at the limit as well.
        #expect(budget.remaining == 0)
        #expect(budget.limit == 0)
    }

    @Test("Each percentage worth worrying about is announced once, not on every request")
    internal func thresholdsAnnounceOnce() {
        var budget = DailyRequestBudget(limit: 100, now: Self.noon)
        var crossings: [Int] = []
        for _ in 0..<100 {
            if case .allowed(_, _, let crossed) = budget.reserve(now: Self.noon), let crossed {
                crossings.append(crossed)
            }
        }
        #expect(crossings == DailyRequestBudget.warningThresholds)
    }

    // MARK: - The day rolling over

    @Test("The counter starts again when the provider's day does, not when this box's does")
    internal func rollsAtUTCMidnight() {
        var budget = DailyRequestBudget(limit: 5, now: Self.noon)
        _ = budget.reserve(now: Self.noon)
        _ = budget.reserve(now: Self.noon)
        #expect(budget.used == 2)

        let tomorrow = UTCDay.nextMidnight(after: Self.noon)
        _ = budget.reserve(now: tomorrow)
        #expect(budget.used == 1)
        #expect(budget.dayStart == UTCDay.start(of: tomorrow))
    }

    @Test("A day that rolls over forgets the warnings it already gave")
    internal func thresholdsResetWithTheDay() {
        var budget = DailyRequestBudget(limit: 2, now: Self.noon)
        _ = budget.reserve(now: Self.noon)
        let tomorrow = UTCDay.nextMidnight(after: Self.noon)
        #expect(budget.reserve(now: tomorrow) == .allowed(used: 1, limit: 2, crossedThreshold: 50))
    }

    // MARK: - Surviving a restart

    @Test("Restarting does not hand the process a fresh budget")
    internal func restartKeepsTheCount() {
        var budget = DailyRequestBudget(limit: 10, now: Self.noon)
        let restored = budget.restore(used: 7, dayStart: UTCDay.start(of: Self.noon), now: Self.noon)
        #expect(restored)
        #expect(budget.used == 7)
        #expect(budget.remaining == 3)
    }

    @Test("Yesterday's count is not spent against today")
    internal func yesterdayIsIgnored() {
        var budget = DailyRequestBudget(limit: 10, now: Self.noon)
        let yesterday = UTCDay.start(of: Self.noon.addingTimeInterval(-86_400))
        let restored = budget.restore(used: 9, dayStart: yesterday, now: Self.noon)
        #expect(restored == false)
        #expect(budget.used == 0)
    }

    @Test("A restored count never undoes requests this process has already made")
    internal func restoreTakesTheLarger() {
        var budget = DailyRequestBudget(limit: 10, now: Self.noon)
        for _ in 0..<6 {
            _ = budget.reserve(now: Self.noon)
        }
        let restored = budget.restore(used: 2, dayStart: UTCDay.start(of: Self.noon), now: Self.noon)
        #expect(restored)
        #expect(budget.used == 6)
    }

    @Test("Coming back after a warning was already given does not warn about it again")
    internal func restoreDoesNotRewarn() {
        var budget = DailyRequestBudget(limit: 10, now: Self.noon)
        let restored = budget.restore(used: 9, dayStart: UTCDay.start(of: Self.noon), now: Self.noon)
        #expect(restored)
        #expect(budget.reserve(now: Self.noon) == .allowed(used: 10, limit: 10, crossedThreshold: nil))
    }

    // MARK: - The day itself

    @Test("A day starts and ends at UTC midnight wherever the box thinks it is")
    internal func utcDayBoundaries() {
        let start = UTCDay.start(of: Self.noon)
        #expect(start <= Self.noon)
        #expect(UTCDay.nextMidnight(after: Self.noon).timeIntervalSince(start) == 86_400)
        #expect(UTCDay.stamp(start).hasSuffix("Z"))
    }
}
