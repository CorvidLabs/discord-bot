import Foundation
import Testing
@testable import Chain

/// The one counter and the one breaker that every caller shares.
///
/// The failure paths are the suite. What happens when the budget runs out, when
/// the provider refuses, when an operator lifts a pause by hand and when the
/// process comes back up is the part an operator lives with, and in the bot
/// this was ported from none of it had ever been run by a test.
@Suite("The shared request governor")
internal struct RequestGovernorTests {

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - One budget for the whole process

    @Test("Reading and signing spend the same budget, so the number is the whole process")
    internal func oneBudgetForEveryCaller() async throws {
        let governor = RequestGovernor(limit: 4)
        // Two callers, one counter. Before this, each counted separately and
        // the configured number meant nothing.
        for _ in 0..<2 {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        for _ in 0..<2 {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.usedRequests == 4)
        #expect(snapshot.remainingRequests == 0)
    }

    @Test("A spent budget refuses the next request before it leaves the process")
    internal func spentBudgetRefuses() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        await #expect(throws: ChainError.requestBudgetSpent(until: UTCDay.nextMidnight(after: Self.noon))) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.isPaused)
        #expect(snapshot.pauseReason == .budgetSpent)
        #expect(snapshot.percentUsed == 100)
    }

    @Test("A pause ends by itself when the day rolls over")
    internal func pauseEndsWithTheDay() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        let tomorrow = UTCDay.nextMidnight(after: Self.noon)
        try await governor.reserveRequest(for: Fixture.sweep, now: tomorrow)
        let snapshot = await governor.snapshot(now: tomorrow)
        #expect(snapshot.isPaused == false)
        #expect(snapshot.usedRequests == 1)
    }

    // MARK: - Work that cannot be half done

    @Test("Work that cannot be half done takes its requests up front or does not start")
    internal func bulkReservationIsAllOrNothing() async throws {
        let governor = RequestGovernor(limit: 100)
        try await governor.reserveRequests(60, for: Fixture.sweep, now: Self.noon)
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 60)
        #expect(await governor.remainingRequests(now: Self.noon) == 40)
    }

    @Test("A reservation the day cannot cover spends nothing and pauses nothing (SEE-9)")
    internal func bulkRefusalLeavesTheDayAlone() async throws {
        let governor = RequestGovernor(limit: 100)
        try await governor.reserveRequests(96, for: Fixture.sweep, now: Self.noon)

        // The payout needs all ten or it under-pays a list it cannot go back
        // over. Four are left.
        await #expect(throws: ChainError.requestBudgetCannotCover(requested: 10, remaining: 4)) {
            try await governor.reserveRequests(10, for: Fixture.sweep, now: Self.noon)
        }
        // Nothing was taken, so the refusal costs the day nothing.
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 96)
        // And nothing is paused: the four that are left belong to the sweep,
        // which reads one account at a time and can stop anywhere.
        #expect(await governor.pausedUntil(now: Self.noon) == nil)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 97)
    }

    @Test("A day with nothing left pauses whatever size the reservation was")
    internal func bulkOnASpentDayPauses() async throws {
        let governor = RequestGovernor(limit: 2)
        try await governor.reserveRequests(2, for: Fixture.sweep, now: Self.noon)
        await #expect(throws: ChainError.requestBudgetSpent(until: UTCDay.nextMidnight(after: Self.noon))) {
            try await governor.reserveRequests(5, for: Fixture.sweep, now: Self.noon)
        }
        #expect(await governor.snapshot(now: Self.noon).pauseReason == .budgetSpent)
    }

    @Test("A refusal to cover the work is not the provider refusing, and trips nothing")
    internal func bulkRefusalIsNotAQuotaRefusal() async throws {
        let refusal = ChainError.requestBudgetCannotCover(requested: 10, remaining: 4)
        #expect(ChainError.isProviderQuotaRefusal(refusal) == false)
        let governor = RequestGovernor(limit: 0)
        _ = await governor.recordRequestFailure(refusal, now: Self.noon)
        #expect(await governor.pausedUntil(now: Self.noon) == nil)
    }

    @Test("A reservation that leaps over the write interval is still written down (RUN-8.a)")
    internal func bulkReservationIsPersisted() async throws {
        let store = InMemoryRequestBudgetStore()
        let governor = RequestGovernor(limit: 1_000, persistEvery: 25, store: store, now: Self.noon)
        // 31 is not a multiple of 25, which is exactly how a restart used to
        // hand the day back a budget a payout had already spent.
        try await governor.reserveRequests(31, for: Fixture.sweep, now: Self.noon)
        await governor.flushPersistence()
        #expect(await store.storedUsage?.usedRequests == 31)
    }

    @Test("With no budget set, what is left is unlimited rather than nothing")
    internal func remainingWithoutABudget() async throws {
        let governor = RequestGovernor(limit: 0)
        #expect(await governor.remainingRequests(now: Self.noon) == nil)
        // Nothing to run out of, so a job of any size starts.
        try await governor.reserveRequests(10_000, for: Fixture.sweep, now: Self.noon)
        #expect(await governor.remainingRequests(now: Self.noon) == nil)
    }

    @Test("What is left is what is left of today, not of the day the counter last moved")
    internal func remainingRollsWithTheDay() async throws {
        let governor = RequestGovernor(limit: 10)
        try await governor.reserveRequests(10, for: Fixture.sweep, now: Self.noon)
        #expect(await governor.remainingRequests(now: Self.noon) == 0)
        #expect(await governor.remainingRequests(now: UTCDay.nextMidnight(after: Self.noon)) == 10)
    }

    @Test("The snapshot answers for today too, not for the day the counter last moved (SEE-1.b, SEE-9)")
    internal func theSnapshotRollsWithTheDay() async throws {
        let governor = RequestGovernor(
            limit: 10,
            share: CallerShareRule(dailyRequestBudget: 10, percent: 100, burstRequests: 10),
            now: Self.noon
        )
        try await governor.reserveRequests(10, for: Fixture.member(1), now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        #expect(await governor.snapshot(now: Self.noon).callerRefusalsToday == 1)

        // Five seconds past midnight, before anything has reserved anything.
        // Nothing rolls a counter but a reservation, and the gap is widest in
        // exactly this case: yesterday's budget was spent, so nothing is
        // reserving, so nothing rolls. A monitoring check reading the health
        // body here was told a whole fresh budget was gone.
        let justAfterMidnight = UTCDay.nextMidnight(after: Self.noon).addingTimeInterval(5)
        let snapshot = await governor.snapshot(now: justAfterMidnight)
        #expect(snapshot.usedRequests == 0)
        #expect(snapshot.remainingRequests == 10)
        #expect(snapshot.callerRequestsToday == 0)
        #expect(snapshot.callerRefusalsToday == 0)
        #expect(snapshot.dayStart == UTCDay.start(of: justAfterMidnight))
        #expect(snapshot.isPaused == false)
        // The two surfaces of one actor cannot disagree about what is left.
        #expect(await governor.remainingRequests(now: justAfterMidnight) == snapshot.remainingRequests)

        // And yesterday still reads as yesterday.
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 10)
    }

    @Test("Reserving nothing takes nothing and does not pause a spent day")
    internal func reservingNothingIsANoOp() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        try await governor.reserveRequests(0, for: Fixture.sweep, now: Self.noon)
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 1)
        #expect(await governor.pausedUntil(now: Self.noon) == nil)
    }

    @Test("A reservation that crosses several thresholds at once says so once")
    internal func bulkCrossesThresholdsOnce() async throws {
        let governor = RequestGovernor(limit: 100)
        try await governor.reserveRequests(95, for: Fixture.sweep, now: Self.noon)
        let crossings = await governor.notices().compactMap { notice -> Int? in
            if case .budgetThresholdCrossed(let percent, _, _) = notice.kind { return percent }
            return nil
        }
        // One line an operator reads, naming the highest mark passed, rather
        // than three lines about a single jump.
        #expect(crossings == [90])
    }

    // MARK: - The provider refusing

    @Test("A provider refusing on quota pauses everything, not just the caller that saw it")
    internal func providerRefusalPausesEverything() async throws {
        let governor = RequestGovernor(limit: 0)
        let refusal = ChainError.api(statusCode: 403, message: "daily quota exceeded")
        let reported = await governor.recordRequestFailure(refusal, now: Self.noon)
        #expect(
            reported as? ChainError
                == ChainError.providerRefusedQuota(until: UTCDay.nextMidnight(after: Self.noon))
        )
        await #expect(throws: ChainError.providerRefusedQuota(until: UTCDay.nextMidnight(after: Self.noon))) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        #expect(await governor.snapshot(now: Self.noon).pauseReason == .providerRefusedQuota)
    }

    @Test("An ordinary failure is handed back untouched and pauses nothing")
    internal func ordinaryFailureIsNotAPause() async throws {
        let governor = RequestGovernor(limit: 0)
        let failure = ChainError.network("connection reset")
        let reported = await governor.recordRequestFailure(failure, now: Self.noon)
        #expect(reported as? ChainError == failure)
        #expect(await governor.pausedUntil(now: Self.noon) == nil)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
    }

    @Test("A refusal that mentions no quota is not treated as one")
    internal func onlyQuotaRefusalsTrip() async {
        let governor = RequestGovernor(limit: 0)
        let forbidden = ChainError.api(statusCode: 403, message: "invalid token")
        _ = await governor.recordRequestFailure(forbidden, now: Self.noon)
        #expect(await governor.pausedUntil(now: Self.noon) == nil)
    }

    // MARK: - Lifting a pause by hand

    @Test("An operator can lift a pause that turned out to be wrong")
    internal func unpauseLetsWorkResume() async throws {
        let governor = RequestGovernor(limit: 0)
        _ = await governor.recordRequestFailure(
            ChainError.api(statusCode: 403, message: "quota"),
            now: Self.noon
        )
        #expect(await governor.unpause(now: Self.noon))
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        #expect(await governor.pausedUntil(now: Self.noon) == nil)
    }

    @Test("Lifting a pause does not hand back a budget that really is spent (RUN-10.a)")
    internal func unpauseDoesNotRefillTheBudget() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        #expect(await governor.unpause(now: Self.noon))
        // The budget is untouched by the unpause, so the very next request
        // pauses again rather than quietly granting a second day's budget.
        await #expect(throws: ChainError.requestBudgetSpent(until: UTCDay.nextMidnight(after: Self.noon))) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
    }

    @Test("Lifting a pause when nothing is paused says so instead of pretending it did something")
    internal func unpauseWithNothingPaused() async {
        let governor = RequestGovernor(limit: 0)
        #expect(await governor.unpause(now: Self.noon) == false)
    }

    /// The same snapshot with only the pause lifted.
    ///
    /// Comparing whole values rather than watching for the next throw is the
    /// point: a change that handed back *some* of the day would pass a test
    /// that only checked the next reservation still refused, whenever the
    /// amount handed back was smaller than what had already been spent.
    private static func withoutPause(_ snapshot: RequestBudgetSnapshot) -> RequestBudgetSnapshot {
        RequestBudgetSnapshot(
            usedRequests: snapshot.usedRequests,
            limit: snapshot.limit,
            remainingRequests: snapshot.remainingRequests,
            pausedUntil: nil,
            pauseReason: nil,
            dayStart: snapshot.dayStart,
            callerShareBurst: snapshot.callerShareBurst,
            throttledCallers: snapshot.throttledCallers,
            callerRequestsToday: snapshot.callerRequestsToday,
            callerRefusalsToday: snapshot.callerRefusalsToday
        )
    }

    @Test("Lifting a provider's pause with the day part spent returns none of it (RUN-10.a)")
    internal func unpauseAfterAProviderRefusalReturnsNothing() async throws {
        // The provider's pause is the interesting one. A budget-spent pause
        // arrives with the counter at its ceiling, where there is nothing to
        // gain; this one arrives with the counter anywhere at all, which is
        // what somebody working out how to farm requests would reach for.
        let governor = RequestGovernor(limit: 100)
        try await governor.reserveRequests(40, for: Fixture.sweep, now: Self.noon)
        _ = await governor.recordRequestFailure(
            ChainError.api(statusCode: 403, message: "quota exceeded"),
            now: Self.noon
        )
        let before = await governor.snapshot(now: Self.noon)
        #expect(before.pauseReason == .providerRefusedQuota)
        #expect(before.usedRequests == 40)

        #expect(await governor.unpause(now: Self.noon))
        let after = await governor.snapshot(now: Self.noon)
        // Everything except the pause, identical. This is what fails against
        // zeroing the counter, against subtracting any amount from it, and
        // against moving the day forward.
        #expect(after == Self.withoutPause(before))
        #expect(await governor.remainingRequests(now: Self.noon) == 60)

        // And the day still ends where it would have: the sixtieth further
        // request is allowed and the sixty-first is not.
        try await governor.reserveRequests(60, for: Fixture.sweep, now: Self.noon)
        await #expect(throws: ChainError.requestBudgetSpent(until: UTCDay.nextMidnight(after: Self.noon))) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
    }

    @Test("Lifting the same pause over and over is not a refund either (RUN-10.a)")
    internal func repeatedUnpausesReturnNothing() async throws {
        let governor = RequestGovernor(limit: 100)
        try await governor.reserveRequests(40, for: Fixture.sweep, now: Self.noon)
        _ = await governor.recordRequestFailure(
            ChainError.api(statusCode: 403, message: "quota exceeded"),
            now: Self.noon
        )
        #expect(await governor.unpause(now: Self.noon))
        let after = await governor.snapshot(now: Self.noon)

        // Nine more, at one pinned instant, so nothing can be explained away
        // by time passing. Lifting a pause that is not there is not a refund.
        for _ in 0..<9 {
            #expect(await governor.unpause(now: Self.noon) == false)
        }
        #expect(await governor.snapshot(now: Self.noon) == after)
        #expect(await governor.remainingRequests(now: Self.noon) == 60)
    }

    @Test("An unpause writes nothing down, so a restart cannot read a lowered count (RUN-10.a, RUN-8.b)")
    internal func unpauseWritesNothing() async throws {
        let store = InMemoryRequestBudgetStore()
        let governor = RequestGovernor(limit: 100, persistEvery: 1, store: store, now: Self.noon)
        try await governor.reserveRequests(40, for: Fixture.sweep, now: Self.noon)
        _ = await governor.recordRequestFailure(
            ChainError.api(statusCode: 403, message: "quota exceeded"),
            now: Self.noon
        )
        await governor.flushPersistence()
        let writesBefore = await store.writeCount
        let storedBefore = await store.storedUsage

        for _ in 0..<5 {
            _ = await governor.unpause(now: Self.noon)
        }
        await governor.flushPersistence()
        // Not one write. An unpause that "tidied up" by rewriting the day's
        // count would let a repeated unpause walk the persisted figure down.
        #expect(await store.writeCount == writesBefore)
        #expect(await store.storedUsage == storedBefore)

        // And a process coming back up reads the same count already spent.
        let restarted = RequestGovernor(limit: 100, persistEvery: 1, store: store, now: Self.noon)
        #expect(try await restarted.restoreFromStore(now: Self.noon))
        #expect(await restarted.snapshot(now: Self.noon).usedRequests == 40)
    }

    // MARK: - Surviving a restart

    @Test("A restart picks the day's count back up instead of starting over")
    internal func countSurvivesARestart() async throws {
        let store = InMemoryRequestBudgetStore()
        let before = RequestGovernor(limit: 10, persistEvery: 2, store: store, now: Self.noon)
        for _ in 0..<4 {
            try await before.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        await before.flushPersistence()
        #expect(await store.storedUsage?.usedRequests == 4)

        let after = RequestGovernor(limit: 10, persistEvery: 2, store: store, now: Self.noon)
        #expect(try await after.restoreFromStore(now: Self.noon))
        let snapshot = await after.snapshot(now: Self.noon)
        #expect(snapshot.usedRequests == 4)
        #expect(snapshot.remainingRequests == 6)
    }

    @Test("A crash loop cannot loosen the ceiling one restart at a time")
    internal func repeatedRestartsDoNotLoosenTheBudget() async throws {
        let store = InMemoryRequestBudgetStore()
        for _ in 0..<3 {
            let governor = RequestGovernor(limit: 9, persistEvery: 1, store: store, now: Self.noon)
            try await governor.restoreFromStore(now: Self.noon)
            for _ in 0..<3 {
                try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
            }
            await governor.flushPersistence()
        }
        let final = RequestGovernor(limit: 9, persistEvery: 1, store: store, now: Self.noon)
        try await final.restoreFromStore(now: Self.noon)
        #expect(await final.snapshot(now: Self.noon).usedRequests == 9)
        await #expect(throws: ChainError.self) {
            try await final.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
    }

    @Test("The count is written every so often rather than on every single request")
    internal func writesArePeriodic() async throws {
        let store = InMemoryRequestBudgetStore()
        let governor = RequestGovernor(limit: 100, persistEvery: 5, store: store, now: Self.noon)
        for _ in 0..<12 {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        await governor.flushPersistence()
        #expect(await store.writeCount == 2)
        #expect(await store.storedUsage?.usedRequests == 10)
    }

    @Test("The count is written the moment the budget runs out, not only on a schedule")
    internal func exhaustionIsWritten() async throws {
        let store = InMemoryRequestBudgetStore()
        let governor = RequestGovernor(limit: 3, persistEvery: 100, store: store, now: Self.noon)
        for _ in 0..<3 {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        await governor.flushPersistence()
        #expect(await store.storedUsage?.usedRequests == 3)
    }

    @Test("A count that cannot be read refuses to start rather than starting the day again")
    internal func unreadableCountRefuses() async throws {
        let store = InMemoryRequestBudgetStore()
        await store.failReads(with: ChainError.network("the row will not decode"))
        let governor = RequestGovernor(limit: 10, store: store, now: Self.noon)
        await #expect(throws: ChainError.network("the row will not decode")) {
            try await governor.restoreFromStore(now: Self.noon)
        }
    }

    @Test("Nothing written yet is not an error, it is simply a first run")
    internal func emptyStoreIsFine() async throws {
        let governor = RequestGovernor(limit: 10, store: InMemoryRequestBudgetStore(), now: Self.noon)
        #expect(try await governor.restoreFromStore(now: Self.noon) == false)
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 0)
    }

    @Test("Yesterday's count is left where it is rather than spent against today")
    internal func yesterdaysCountIsNotRestored() async throws {
        let yesterday = Self.noon.addingTimeInterval(-86_400)
        let store = InMemoryRequestBudgetStore(
            usage: RequestBudgetUsage(usedRequests: 9, dayStart: UTCDay.start(of: yesterday))
        )
        let governor = RequestGovernor(limit: 10, store: store, now: Self.noon)
        #expect(try await governor.restoreFromStore(now: Self.noon) == false)
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 0)
    }

    @Test("With nowhere to write the count, a restart really does start over, and nothing pretends otherwise")
    internal func noStoreMeansNoRestore() async throws {
        let governor = RequestGovernor(limit: 10, now: Self.noon)
        #expect(try await governor.restoreFromStore(now: Self.noon) == false)
    }

    // MARK: - What an operator reads afterwards

    @Test("A problem that started overnight is still there to read in the morning")
    internal func noticesAreKept() async throws {
        let governor = RequestGovernor(limit: 2)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        let notices = await governor.notices()
        #expect(notices.contains { $0.kind == .budgetSpent(until: UTCDay.nextMidnight(after: Self.noon)) })
        #expect(notices.contains { if case .budgetThresholdCrossed = $0.kind { return true } else { return false } })
    }

    @Test("A pause is announced once, not once for every request it refuses")
    internal func onePauseOneNotice() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        for _ in 0..<20 {
            await #expect(throws: ChainError.self) {
                try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
            }
        }
        let pauses = await governor.notices().filter {
            if case .budgetSpent = $0.kind { return true } else { return false }
        }
        #expect(pauses.count == 1)
    }

    @Test("Draining the notices hands them over once and leaves nothing behind")
    internal func noticesDrain() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }
        #expect(await governor.drainNotices().isEmpty == false)
        #expect(await governor.drainNotices().isEmpty)
    }

    @Test("A host that never reads its notices cannot grow them without limit")
    internal func noticesAreBounded() async throws {
        let governor = RequestGovernor(limit: 0)
        for index in 0..<(RequestGovernor.maxRetainedNotices + 10) {
            _ = await governor.recordRequestFailure(
                ChainError.api(statusCode: 403, message: "quota"),
                now: Self.noon.addingTimeInterval(Double(index))
            )
            _ = await governor.unpause(now: Self.noon.addingTimeInterval(Double(index)))
        }
        #expect(await governor.notices().count == RequestGovernor.maxRetainedNotices)
    }

    @Test("The status of the budget is one value, so no two surfaces can disagree")
    internal func snapshotSaysEverything() async throws {
        let governor = RequestGovernor(limit: 4)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.hasBudget)
        #expect(snapshot.usedRequests == 1)
        #expect(snapshot.limit == 4)
        #expect(snapshot.remainingRequests == 3)
        #expect(snapshot.percentUsed == 25)
        #expect(snapshot.isPaused == false)
        #expect(snapshot.dayStart == UTCDay.start(of: Self.noon))
    }

    @Test("With no budget set, the status says so rather than reading as nothing left")
    internal func snapshotWithoutABudget() async {
        let snapshot = await RequestGovernor(limit: 0).snapshot(now: Self.noon)
        #expect(snapshot.hasBudget == false)
        #expect(snapshot.percentUsed == nil)
    }
}
