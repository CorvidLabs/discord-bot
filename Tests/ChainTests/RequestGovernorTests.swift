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
            try await governor.reserveRequest(now: Self.noon)
        }
        for _ in 0..<2 {
            try await governor.reserveRequest(now: Self.noon)
        }
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.usedRequests == 4)
        #expect(snapshot.remainingRequests == 0)
    }

    @Test("A spent budget refuses the next request before it leaves the process")
    internal func spentBudgetRefuses() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(now: Self.noon)
        await #expect(throws: ChainError.requestBudgetSpent(until: UTCDay.nextMidnight(after: Self.noon))) {
            try await governor.reserveRequest(now: Self.noon)
        }
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.isPaused)
        #expect(snapshot.pauseReason == .budgetSpent)
        #expect(snapshot.percentUsed == 100)
    }

    @Test("A pause ends by itself when the day rolls over")
    internal func pauseEndsWithTheDay() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(now: Self.noon)
        }
        let tomorrow = UTCDay.nextMidnight(after: Self.noon)
        try await governor.reserveRequest(now: tomorrow)
        let snapshot = await governor.snapshot(now: tomorrow)
        #expect(snapshot.isPaused == false)
        #expect(snapshot.usedRequests == 1)
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
            try await governor.reserveRequest(now: Self.noon)
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
        try await governor.reserveRequest(now: Self.noon)
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
        try await governor.reserveRequest(now: Self.noon)
        #expect(await governor.pausedUntil(now: Self.noon) == nil)
    }

    @Test("Lifting a pause does not hand back a budget that really is spent")
    internal func unpauseDoesNotRefillTheBudget() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(now: Self.noon)
        }
        #expect(await governor.unpause(now: Self.noon))
        // The budget is untouched by the unpause, so the very next request
        // pauses again rather than quietly granting a second day's budget.
        await #expect(throws: ChainError.requestBudgetSpent(until: UTCDay.nextMidnight(after: Self.noon))) {
            try await governor.reserveRequest(now: Self.noon)
        }
    }

    @Test("Lifting a pause when nothing is paused says so instead of pretending it did something")
    internal func unpauseWithNothingPaused() async {
        let governor = RequestGovernor(limit: 0)
        #expect(await governor.unpause(now: Self.noon) == false)
    }

    // MARK: - Surviving a restart

    @Test("A restart picks the day's count back up instead of starting over")
    internal func countSurvivesARestart() async throws {
        let store = InMemoryRequestBudgetStore()
        let before = RequestGovernor(limit: 10, persistEvery: 2, store: store, now: Self.noon)
        for _ in 0..<4 {
            try await before.reserveRequest(now: Self.noon)
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
                try await governor.reserveRequest(now: Self.noon)
            }
            await governor.flushPersistence()
        }
        let final = RequestGovernor(limit: 9, persistEvery: 1, store: store, now: Self.noon)
        try await final.restoreFromStore(now: Self.noon)
        #expect(await final.snapshot(now: Self.noon).usedRequests == 9)
        await #expect(throws: ChainError.self) {
            try await final.reserveRequest(now: Self.noon)
        }
    }

    @Test("The count is written every so often rather than on every single request")
    internal func writesArePeriodic() async throws {
        let store = InMemoryRequestBudgetStore()
        let governor = RequestGovernor(limit: 100, persistEvery: 5, store: store, now: Self.noon)
        for _ in 0..<12 {
            try await governor.reserveRequest(now: Self.noon)
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
            try await governor.reserveRequest(now: Self.noon)
        }
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(now: Self.noon)
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
        try await governor.reserveRequest(now: Self.noon)
        try await governor.reserveRequest(now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(now: Self.noon)
        }
        let notices = await governor.notices()
        #expect(notices.contains { $0.kind == .budgetSpent(until: UTCDay.nextMidnight(after: Self.noon)) })
        #expect(notices.contains { if case .budgetThresholdCrossed = $0.kind { return true } else { return false } })
    }

    @Test("A pause is announced once, not once for every request it refuses")
    internal func onePauseOneNotice() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(now: Self.noon)
        for _ in 0..<20 {
            await #expect(throws: ChainError.self) {
                try await governor.reserveRequest(now: Self.noon)
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
        try await governor.reserveRequest(now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(now: Self.noon)
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
        try await governor.reserveRequest(now: Self.noon)
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
