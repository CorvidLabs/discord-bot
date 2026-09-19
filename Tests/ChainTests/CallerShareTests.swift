import Foundation
import Testing
@testable import Chain

/// One member's share of the day, and what it does not bound.
///
/// The criterion is RUN-11: no one member, however fast they type, can spend
/// the day's budget for reading the chain on their own. Everything here is
/// about one caller. Twenty members each staying inside their share can still
/// finish a small day between them, and nothing in this suite or in the
/// documentation may suggest otherwise: the day's budget is the backstop for
/// that, and this is the backstop for one person with a keyboard.
@Suite("One caller's share of the day")
internal struct CallerShareTests {

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    /// A budget of a thousand with a five percent share and a burst of ten,
    /// which is the shipped default at a size that is easy to check by hand.
    private static func governor(
        limit: UInt64 = 1_000,
        percent: Int = 5,
        burst: UInt64 = 10,
        store: (any RequestBudgetStore)? = nil
    ) -> RequestGovernor {
        RequestGovernor(
            limit: limit,
            persistEvery: 1,
            store: store,
            share: CallerShareRule(
                dailyRequestBudget: limit,
                percent: percent,
                burstRequests: burst
            ),
            now: noon
        )
    }

    // MARK: - The arithmetic, with no actor and no clock

    @Test("A share is a percentage of the day, spread over the day, with a burst on top (RUN-11)")
    internal func theRuleIsAPercentageAndABurst() throws {
        let rule = try #require(
            CallerShareRule(dailyRequestBudget: 86_400, percent: 50, burstRequests: 10)
        )
        #expect(rule.dailyShareRequests == 43_200)
        #expect(rule.burstRequests == 10)
        // Half of a day's 86,400 requests, spread over 86,400 seconds.
        #expect(rule.refillPerSecond == 0.5)
    }

    @Test("A burst larger than the whole day's share is clamped to it, not refused (RUN-11)")
    internal func aBurstLargerThanTheShareIsClamped() throws {
        let rule = try #require(
            CallerShareRule(dailyRequestBudget: 100, percent: 5, burstRequests: 1_000)
        )
        #expect(rule.dailyShareRequests == 5)
        #expect(rule.burstRequests == 5)
    }

    @Test("A percentage of a small budget still leaves one request rather than none")
    internal func aTinyShareIsHeldAtOneRequest() throws {
        let rule = try #require(
            CallerShareRule(dailyRequestBudget: 10, percent: 5, burstRequests: 10)
        )
        // Half a request rounds to nothing, and a share of nothing would
        // refuse every member every time. The day's budget is still the
        // backstop.
        #expect(rule.dailyShareRequests == 1)
        #expect(rule.burstRequests == 1)
    }

    @Test("There is no share with no budget, and none when the percentage is zero (RUN-11)")
    internal func noBudgetOrZeroPercentMeansNoRule() {
        #expect(CallerShareRule(dailyRequestBudget: 0, percent: 5, burstRequests: 10) == nil)
        #expect(CallerShareRule(dailyRequestBudget: 1_000, percent: 0, burstRequests: 10) == nil)
        #expect(CallerShareRule(dailyRequestBudget: 1_000, percent: 5, burstRequests: 0) == nil)
    }

    @Test("An allowance refills towards its burst and no further, however long the wait")
    internal func anAllowanceRefillsOnlyToItsBurst() throws {
        let rule = try #require(
            CallerShareRule(dailyRequestBudget: 86_400, percent: 100, burstRequests: 10)
        )
        var share = rule.freshAllowance(at: Self.noon)
        let tookTheLot = share.take(10, at: Self.noon)
        #expect(tookTheLot)
        #expect(share.remaining(at: Self.noon) == 0)

        // One a second at this rule, so five seconds is five back.
        #expect(share.remaining(at: Self.noon.addingTimeInterval(5)) == 5)
        // And a whole idle day banks a burst, never the day.
        #expect(share.remaining(at: Self.noon.addingTimeInterval(86_400)) == 10)
        #expect(share.isFull(at: Self.noon.addingTimeInterval(86_400)))
    }

    @Test("A clock that went backwards grants no refill, then or once it is corrected")
    internal func timeGoingBackwardsGrantsNothing() throws {
        let rule = try #require(
            CallerShareRule(dailyRequestBudget: 86_400, percent: 100, burstRequests: 10)
        )
        var share = rule.freshAllowance(at: Self.noon)
        let tookTheLot = share.take(10, at: Self.noon)
        #expect(tookTheLot)
        #expect(share.remaining(at: Self.noon.addingTimeInterval(-3_600)) == 0)

        // The instant of the step is the easy half. The step is only a
        // problem afterwards: a refused call at the stepped clock must not
        // move the point the next refill is measured from, or the hour is
        // counted twice and a spent caller has their whole burst back.
        let refused = share.take(1, at: Self.noon.addingTimeInterval(-3_600))
        #expect(!refused)
        // Three seconds after they were emptied, at this rule, is three.
        #expect(share.remaining(at: Self.noon.addingTimeInterval(3)) == 3)
    }

    // MARK: - One member cannot spend the day

    @Test("A member spending their share is refused while the day still has plenty (RUN-11)")
    internal func oneMemberCannotSpendTheDay() async throws {
        let governor = Self.governor()
        for _ in 0..<10 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }

        let snapshot = await governor.snapshot(now: Self.noon)
        // The day's counter shows what they really took and not a request
        // more: a refusal at the share spends nothing.
        #expect(snapshot.usedRequests == 10)
        #expect(snapshot.remainingRequests == 990)
        #expect(snapshot.callerRequestsToday == 10)
        #expect(snapshot.callerRefusalsToday == 1)
    }

    @Test("The refusal says when the next request is allowed, and names nobody (RUN-11, HOST-2)")
    internal func theRefusalSaysWhenAndNamesNobody() async throws {
        let governor = Self.governor()
        for _ in 0..<10 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        var refusal: ChainError?
        do {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        } catch let error as ChainError {
            refusal = error
        }
        let error = try #require(refusal)
        guard case .callerShareSpent(let requested, let remaining, let nextAllowedAt) = error else {
            Issue.record("a share refusal should be its own error, not \(error)")
            return
        }
        #expect(requested == 1)
        #expect(remaining == 0)
        // Refilling, not the next UTC midnight. A share that only came back at
        // midnight locks a member out for the rest of the day after a busy
        // morning, which reads to them as the bot being broken.
        #expect(nextAllowedAt > Self.noon)
        #expect(nextAllowedAt < UTCDay.nextMidnight(after: Self.noon))

        // Nothing that could identify the caller reaches the words an operator
        // or a host will log.
        let sentence = try #require(error.errorDescription)
        #expect(!sentence.contains("MEMBER-KEY"))
    }

    @Test("A member at their share leaves everybody else working at the same instant (RUN-11)")
    internal func oneCallerRefusedLeavesTheRestWorking() async throws {
        let governor = Self.governor()
        for _ in 0..<10 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }

        // A second member, at the same instant, is served.
        try await governor.reserveRequest(for: Fixture.member(2), now: Self.noon)
        // And so is the instance's own work, which carries no share at all: a
        // sweep is not a person and cannot type fast, and rationing it to one
        // member's share would break the product's main job to protect it.
        try await governor.reserveRequests(500, for: Fixture.sweep, now: Self.noon)
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 511)
    }

    @Test("Reaching a share is not a pause, however many times it happens (RUN-11, SEE-5)")
    internal func aShareRefusalPausesNothingAndSaysNothing() async throws {
        let governor = Self.governor()
        for _ in 0..<10 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        for _ in 0..<2_000 {
            await #expect(throws: ChainError.self) {
                try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
            }
        }
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.isPaused == false)
        #expect(snapshot.pauseReason == nil)
        #expect(snapshot.usedRequests == 10)
        // Not one notice. Two thousand copies of one member's refusal would
        // push a pause announcement out of the buffer an operator drains at
        // exactly the moment things are already bad.
        #expect(await governor.notices().isEmpty)
        #expect(snapshot.callerRefusalsToday == 2_000)
    }

    @Test("A pause is answered before a share, so everybody hears the same story (RUN-11, SEE-11)")
    internal func thePauseIsCheckedBeforeTheShare() async throws {
        let governor = Self.governor()
        for _ in 0..<10 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        _ = await governor.recordRequestFailure(
            ChainError.api(statusCode: 403, message: "quota exceeded"),
            now: Self.noon
        )
        // The member is at their share and the instance is refusing everybody.
        // Telling them their share is spent would send them away with the
        // wrong story, and the wrong thing to do about it.
        let until = UTCDay.nextMidnight(after: Self.noon)
        await #expect(throws: ChainError.providerRefusedQuota(until: until)) {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
    }

    @Test("An indivisible job larger than what is left takes nothing from anybody (RUN-11)")
    internal func anAllOrNothingJobOverTheShareTakesNothing() async throws {
        let governor = Self.governor()
        try await governor.reserveRequests(4, for: Fixture.member(1), now: Self.noon)
        #expect(await governor.snapshot(now: Self.noon).callerRequestsToday == 4)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequests(7, for: Fixture.member(1), now: Self.noon)
        }
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.usedRequests == 4)
        // The caller keeps what they had left, so the refusal cost them
        // nothing either.
        try await governor.reserveRequests(6, for: Fixture.member(1), now: Self.noon)
        let after = await governor.snapshot(now: Self.noon)
        #expect(after.usedRequests == 10)
        // What members took is a part of the day's count, not a tally beside
        // it: the refused job is in neither.
        #expect(after.callerRequestsToday == 10)
    }

    @Test("A job no burst can ever hold is refused with no date rather than a false one (RUN-11)")
    internal func aJobLargerThanTheBurstIsRefusedWithNoDate() async throws {
        let governor = Self.governor()
        var refusal: ChainError?
        do {
            try await governor.reserveRequests(20, for: Fixture.member(1), now: Self.noon)
        } catch let error as ChainError {
            refusal = error
        }
        let error = try #require(refusal)
        // An allowance never holds more than its burst, so no instant exists
        // at which this would be served. A refusal carrying one sends a host
        // away to retry at a moment where it is refused identically, forever.
        guard case .callerShareCannotCover(let requested, let burst) = error else {
            Issue.record("a job larger than any burst should say so, not \(error)")
            return
        }
        #expect(requested == 20)
        #expect(burst == 10)
        let sentence = try #require(error.errorDescription)
        #expect(!sentence.contains("MEMBER-KEY"))

        // Nothing was taken from the caller or from the day, so the member is
        // still free to ask for something that fits.
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.usedRequests == 0)
        #expect(snapshot.callerRefusalsToday == 1)
        try await governor.reserveRequests(10, for: Fixture.member(1), now: Self.noon)
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 10)
    }

    @Test("A clock stepped backwards hands a spent caller nothing back afterwards (RUN-11)")
    internal func aBackwardsClockHandsBackNothing() async throws {
        // A day's share of 86,400 at one a second, so the arithmetic below is
        // readable: three seconds honestly earns three requests.
        let governor = Self.governor(limit: 86_400, percent: 100, burst: 10)
        for _ in 0..<10 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }

        // NTP, a resumed virtual machine or an operator steps the clock back
        // an hour, and the member's client retries once into it.
        let steppedBack = Self.noon.addingTimeInterval(-3_600)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: steppedBack)
        }

        // The clock is corrected. The hour that never passed must not be paid
        // out as a refill: a limiter that hands out free requests when the
        // clock is stepped backwards is the one thing a limiter exists to
        // prevent, and the refused call above is where it would be written in.
        let corrected = Self.noon.addingTimeInterval(3)
        for _ in 0..<3 {
            try await governor.reserveRequest(for: Fixture.member(1), now: corrected)
        }
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: corrected)
        }
        #expect(await governor.snapshot(now: corrected).usedRequests == 13)
    }

    @Test("A share comes back during the day rather than at midnight (RUN-11)")
    internal func aShareRefillsDuringTheDay() async throws {
        // A thousand a day at fifty percent is five hundred for one caller,
        // which is one request roughly every 173 seconds.
        let governor = Self.governor(percent: 50, burst: 5)
        for _ in 0..<5 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        // Six minutes later there is more than one request back.
        let later = Self.noon.addingTimeInterval(360)
        try await governor.reserveRequest(for: Fixture.member(1), now: later)
        #expect(await governor.snapshot(now: later).usedRequests == 6)
    }

    // MARK: - With no budget there is no share

    @Test("With no daily budget nobody is ever refused by a share (RUN-11)")
    internal func noBudgetMeansNoShare() async throws {
        let governor = RequestGovernor(limit: 0)
        for _ in 0..<1_000 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.hasCallerShare == false)
        #expect(snapshot.callerShareBurst == 0)
        #expect(snapshot.throttledCallers == 0)
        #expect(snapshot.usedRequests == 1_000)
    }

    @Test("A share configured against no budget is no share at all (RUN-11)")
    internal func aShareNeedsADayToBeAShareOf() async throws {
        // The rule cannot even be built without a budget, and the governor
        // refuses to hold one when the limit is zero, so the two cannot drift
        // into a share of nothing that refuses everybody.
        let governor = RequestGovernor(
            limit: 0,
            share: CallerShareRule(dailyRequestBudget: 1_000, percent: 5, burstRequests: 10)
        )
        for _ in 0..<50 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        #expect(await governor.snapshot(now: Self.noon).callerShareBurst == 0)
    }

    // MARK: - What an operator sees

    @Test("Throttling is visible in the snapshot every other figure comes from (RUN-11, SEE-9)")
    internal func throttlingIsVisibleInTheSnapshot() async throws {
        let governor = Self.governor()
        try await governor.reserveRequests(4, for: Fixture.member(1), now: Self.noon)
        try await governor.reserveRequests(2, for: Fixture.member(2), now: Self.noon)
        try await governor.reserveRequests(9, for: Fixture.sweep, now: Self.noon)

        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.callerShareBurst == 10)
        #expect(snapshot.throttledCallers == 2)
        // How much of the day the shares have taken between them, so an
        // operator can tell members apart from the instance's own work.
        #expect(snapshot.callerRequestsToday == 6)
        #expect(snapshot.usedRequests == 15)

        // A count, never a list of who.
        let report = ChainHealthReport(components: [], budget: snapshot)
        #expect(report.jsonBody.contains("\"throttled_callers\":2"))
        #expect(!report.jsonBody.contains("MEMBER-KEY"))
    }

    @Test("A health body says whether anybody was refused, not only who is holding (RUN-11, SEE-9)")
    internal func theHealthBodySaysWhetherAnybodyWasRefused() async throws {
        let governor = Self.governor()
        try await governor.reserveRequests(4, for: Fixture.member(1), now: Self.noon)
        let quiet = ChainHealthReport(components: [], budget: await governor.snapshot(now: Self.noon))
        // Four requests inside one refill interval puts a caller in the count
        // above, and nobody has been turned away. An operator reading that
        // count as "throttling is happening" is reading ordinary use.
        #expect(quiet.jsonBody.contains("\"throttled_callers\":1"))
        #expect(!quiet.jsonBody.contains("caller_refusals"))

        for _ in 0..<6 {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        let refused = ChainHealthReport(components: [], budget: await governor.snapshot(now: Self.noon))
        // A share refusal writes no notice on purpose, so if this figure does
        // not reach the body there is nowhere at all a monitoring check can
        // see that a member is being turned away.
        #expect(refused.jsonBody.contains("\"caller_refusals\":1"))
        #expect(!refused.jsonBody.contains("MEMBER-KEY"))
    }

    @Test("The share figures start again with the UTC day (RUN-11)")
    internal func theShareFiguresRollWithTheDay() async throws {
        let governor = Self.governor()
        try await governor.reserveRequests(10, for: Fixture.member(1), now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        let tomorrow = UTCDay.nextMidnight(after: Self.noon)
        try await governor.reserveRequest(for: Fixture.member(1), now: tomorrow)
        let snapshot = await governor.snapshot(now: tomorrow)
        #expect(snapshot.callerRefusalsToday == 0)
        #expect(snapshot.callerRequestsToday == 1)
    }

    // MARK: - The tracking is bounded

    @Test("A caller whose share has refilled is forgotten (RUN-11, RUN-8.b)")
    internal func aRefilledCallerIsForgotten() async throws {
        let governor = Self.governor()
        try await governor.reserveRequests(10, for: Fixture.member(1), now: Self.noon)
        #expect(await governor.trackedCallerCount() == 1)

        // A day later that caller's allowance has refilled to its burst,
        // which makes them indistinguishable from somebody nobody has ever
        // heard of, so holding a row for them buys nothing. The sweep happens
        // when the next caller arrives, because sweeping on every arrival is
        // quadratic in the number of callers.
        let tomorrow = Self.noon.addingTimeInterval(86_400)
        try await governor.reserveRequest(for: Fixture.member(2), now: tomorrow)
        #expect(await governor.trackedCallerCount() == 1)
        #expect(await governor.snapshot(now: tomorrow).throttledCallers == 1)

        // And forgetting them hands them nothing they had not already earned:
        // a fresh allowance is a full one, which is what refilling had
        // restored anyway.
        try await governor.reserveRequests(10, for: Fixture.member(1), now: tomorrow)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: tomorrow)
        }
    }

    @Test("At the bound a newcomer is refused, and nobody drawing is evicted (RUN-11)")
    internal func atTheBoundANewcomerIsRefused() async throws {
        let governor = Self.governor(limit: 1_000_000, percent: 5, burst: 10)
        // Every one of them is part way through their allowance, so none of
        // them can be swept.
        for index in 0..<RequestGovernor.maxTrackedCallers {
            try await governor.reserveRequest(for: Fixture.member(index), now: Self.noon)
        }
        #expect(await governor.trackedCallerCount() == RequestGovernor.maxTrackedCallers)

        // Admitting them untracked is the hole this exists to close, and
        // evicting somebody who is drawing would hand that person a fresh
        // allowance, which is the exploit.
        var refusal: ChainError?
        do {
            try await governor.reserveRequest(
                for: Fixture.member(RequestGovernor.maxTrackedCallers),
                now: Self.noon
            )
        } catch let error as ChainError {
            refusal = error
        }
        let error = try #require(refusal)
        guard case .callerShareSpent(_, _, let nextAllowedAt) = error else {
            Issue.record("a caller refused at the bound should read as a spent share, not \(error)")
            return
        }
        // A slot comes free as soon as any tracked caller has refilled, which
        // the sweep notices within a minute. Telling this member to come back
        // at midnight is the fifteen hour lockout a refilling allowance exists
        // to avoid, arriving through the one door that skips the allowance.
        #expect(nextAllowedAt == Self.noon.addingTimeInterval(RequestGovernor.allowanceSweepSeconds))
        #expect(nextAllowedAt < UTCDay.nextMidnight(after: Self.noon))
        // The caller who was already drawing still holds exactly what they had
        // left, rather than having been moved aside and given a new one.
        for _ in 0..<9 {
            try await governor.reserveRequest(for: Fixture.member(0), now: Self.noon)
        }
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(0), now: Self.noon)
        }
        #expect(await governor.trackedCallerCount() == RequestGovernor.maxTrackedCallers)
    }

    @Test("Reaching the bound is one notice, not one per refused caller (RUN-11, SEE-5)")
    internal func theBoundIsAnnouncedOnce() async throws {
        let governor = Self.governor(limit: 1_000_000, percent: 5, burst: 10)
        for index in 0..<RequestGovernor.maxTrackedCallers {
            try await governor.reserveRequest(for: Fixture.member(index), now: Self.noon)
        }
        for offset in 0..<50 {
            await #expect(throws: ChainError.self) {
                try await governor.reserveRequest(
                    for: Fixture.member(RequestGovernor.maxTrackedCallers + offset),
                    now: Self.noon
                )
            }
        }
        let notices = await governor.notices()
        #expect(notices.count == 1)
        #expect(notices.first?.kind == .callerTrackingFull(tracked: RequestGovernor.maxTrackedCallers))
    }

    // MARK: - What a restart and an unpause do not hand back

    @Test("Lifting a pause returns no part of a caller's share either (RUN-10.a, RUN-11)")
    internal func unpauseReturnsNoShare() async throws {
        let governor = Self.governor()
        try await governor.reserveRequests(10, for: Fixture.member(1), now: Self.noon)
        _ = await governor.recordRequestFailure(
            ChainError.api(statusCode: 403, message: "quota exceeded"),
            now: Self.noon
        )
        #expect(await governor.unpause(now: Self.noon))

        // The plausible and wrong thing for the next person to write is "give
        // everybody their allowance back when the operator lifts a pause". The
        // share lives in the same actor, so this is where that would happen.
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        let snapshot = await governor.snapshot(now: Self.noon)
        #expect(snapshot.usedRequests == 10)
        #expect(snapshot.throttledCallers == 1)
    }

    @Test("A restart hands a caller one fresh burst and no more of the day (RUN-11, RUN-8.b)")
    internal func aRestartHandsBackOneBurstAtMost() async throws {
        let store = InMemoryRequestBudgetStore()
        let before = Self.governor(store: store)
        try await before.reserveRequests(10, for: Fixture.member(1), now: Self.noon)
        await before.flushPersistence()
        await #expect(throws: ChainError.self) {
            try await before.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }

        // The allowance is in memory and does not survive, which is the stated
        // cost of not putting a row and a write in front of every read. What
        // does survive is the day's own count, so no restart trick creates
        // requests out of nothing.
        let after = Self.governor(store: store)
        #expect(try await after.restoreFromStore(now: Self.noon))
        #expect(await after.snapshot(now: Self.noon).usedRequests == 10)

        try await after.reserveRequests(10, for: Fixture.member(1), now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await after.reserveRequest(for: Fixture.member(1), now: Self.noon)
        }
        #expect(await after.snapshot(now: Self.noon).usedRequests == 20)
    }
}
