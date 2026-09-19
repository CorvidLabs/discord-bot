import Foundation
import Testing
@testable import Reserve

/// The ledger's own rules: locking the duration, advancing an epoch, claiming
/// and releasing, and refusing to read a broken row as an unpaid one.
@Suite("Reserve state")
struct ReserveStateTests {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Choosing and locking the duration

    @Test("The duration is chosen before the schedule starts and fixed after (RESERVE-2.c)")
    func scheduleLocking() throws {
        let fresh = ReserveState()
        #expect(fresh.scheduleId == nil)
        #expect(throws: ReserveError.scheduleNotSelected) {
            try fresh.requireScheduleId()
        }

        let selected = try fresh.selecting(scheduleId: "6m", at: Self.now)
        #expect(selected.scheduleId == "6m")
        #expect(selected.isLockable)

        // Still changeable while nothing has paid.
        let changed = try selected.selecting(scheduleId: "1y", at: Self.now)
        #expect(changed.scheduleId == "1y")

        let started = changed.markingComplete(streamId: Fixture.members, epoch: 1)
        #expect(started.isLockable == false)
        #expect(throws: ReserveError.scheduleLocked(scheduleId: "1y", paidEpochs: 1)) {
            try started.selecting(scheduleId: "6m", at: Self.now)
        }
    }

    // MARK: - Advancing

    @Test("The next epoch advances only when one runs to the end")
    func epochAdvances() {
        var state = ReserveState(scheduleId: "6m")
        #expect(state.nextEpoch(Fixture.members) == 1)
        state = state.recordingSpend(streamId: Fixture.members, baseUnits: 5)
        // Value committed, epoch not closed: the same epoch is retried.
        #expect(state.nextEpoch(Fixture.members) == 1)
        #expect(state.spent(Fixture.members) == 5)
        state = state.markingComplete(streamId: Fixture.members, epoch: 1)
        #expect(state.nextEpoch(Fixture.members) == 2)
        // The other stream is untouched.
        #expect(state.nextEpoch(Fixture.passes) == 1)
    }

    @Test("An epoch can be finished but never skipped (RESERVE-6.d)")
    func epochsCannotBeSkipped() {
        let fresh = ReserveState(scheduleId: "6m")
        // Closing the last epoch first once marked every earlier one finished
        // and forfeited the whole schedule without paying anybody.
        #expect(fresh.markingComplete(streamId: Fixture.members, epoch: 26).nextEpoch(Fixture.members) == 1)
        #expect(fresh.markingComplete(streamId: Fixture.members, epoch: 5).completedEpochs(Fixture.members) == 0)
        let advanced = fresh.markingComplete(streamId: Fixture.members, epoch: 1)
        #expect(advanced.nextEpoch(Fixture.members) == 2)
        // Re-closing the epoch just closed is a no-op, not a second advance.
        #expect(advanced.markingComplete(streamId: Fixture.members, epoch: 1).nextEpoch(Fixture.members) == 2)
    }

    @Test("Spend is given back with a claim, so the ceiling cannot drift low")
    func spendReleased() {
        let state = ReserveState(scheduleId: "6m")
            .recordingSpend(streamId: Fixture.members, baseUnits: 100)
        #expect(state.spent(Fixture.members) == 100)
        #expect(
            state.releasingSpend(streamId: Fixture.members, baseUnits: 100)
                .spent(Fixture.members) == 0
        )
        // Never below zero, whatever order the writes land in.
        #expect(
            state.releasingSpend(streamId: Fixture.members, baseUnits: 500)
                .spent(Fixture.members) == 0
        )
    }

    @Test("A period is claimed per stream, so one stream does not block another")
    func periodClaims() {
        let state = ReserveState(scheduleId: "6m")
            .claimingPeriod(streamId: Fixture.members, periodKey: "2026-W38")
        #expect(state.lastPeriodKey(Fixture.members) == "2026-W38")
        #expect(state.lastPeriodKey(Fixture.passes) == nil)
    }

    // MARK: - Claiming and releasing

    @Test("A claim is given back when the payment provably moved nothing (RESERVE-6.b)")
    func claimReleasedOnRefusal() {
        var record = Fixture.epoch(Fixture.members, 1)
        let entry = ReserveEpochEntry(
            recipientId: "R1",
            account: "ACCOUNT-A",
            units: 1,
            baseUnitsAmount: 269_230_769_230,
            claimedHoldingIds: ["H7", "H8"]
        )
        record.claim(entry: entry, at: Date(timeIntervalSince1970: 5))
        #expect(record.paidAccounts == ["ACCOUNT-A"])
        #expect(record.paidRecipientIds == ["R1"])
        #expect(record.claimedHoldingIds == ["H7", "H8"])
        #expect(record.paidBaseUnits == 269_230_769_230)

        record.release(entry: entry)
        #expect(record.paidAccounts.isEmpty)
        #expect(record.paidRecipientIds.isEmpty)
        #expect(record.claimedHoldingIds.isEmpty)
        #expect(record.paidBaseUnits == 0)
        // `startedAt` is deliberately kept: the epoch really did begin.
        #expect(record.startedAt != nil)
    }

    @Test("Claiming twice does not double-count an account or a person")
    func claimIsIdempotentPerAccount() {
        var record = Fixture.epoch(Fixture.passes, 1)
        let entry = ReserveEpochEntry(
            recipientId: "R1",
            account: "ACCOUNT-A",
            units: 1,
            baseUnitsAmount: 10,
            claimedHoldingIds: ["H1"]
        )
        record.claim(entry: entry, at: Date(timeIntervalSince1970: 1))
        record.claim(entry: entry, at: Date(timeIntervalSince1970: 2))
        #expect(record.paidAccounts == ["ACCOUNT-A"])
        #expect(record.paidRecipientIds == ["R1"])
        #expect(record.claimedHoldingIds == ["H1"])
        // The amount is *not* idempotent, and should not be: two claims mean
        // two intended payments, and over-counting spend is the safe direction.
        #expect(record.paidBaseUnits == 20)
        // The first claim's timestamp is the one that stands.
        #expect(record.startedAt == Date(timeIntervalSince1970: 1))
    }

    @Test("Folding a whole plan in one pass matches claiming one at a time")
    func claimingAllMatchesClaimingEach() {
        let entries = (1...20).map { index in
            ReserveEpochEntry(
                recipientId: "R\(index)",
                account: Fixture.account(index),
                units: 1,
                baseUnitsAmount: 7,
                claimedHoldingIds: ["H-\(index)"]
            )
        }
        let at = Date(timeIntervalSince1970: 3)
        var oneByOne = Fixture.epoch(Fixture.members, 1)
        for entry in entries {
            oneByOne.claim(entry: entry, at: at)
        }
        let folded = Fixture.epoch(Fixture.members, 1).claimingAll(entries, at: at)
        #expect(folded == oneByOne)
        #expect(folded.paidBaseUnits == 140)
        // An empty plan changes nothing at all, including the start time.
        #expect(Fixture.epoch(Fixture.members, 1).claimingAll([], at: at).startedAt == nil)
    }

    @Test("A finished epoch says so")
    func completion() {
        var record = Fixture.epoch(Fixture.members, 1)
        #expect(record.isComplete == false)
        record.completedAt = Self.now
        #expect(record.isComplete)
    }

    // MARK: - Coding

    @Test("State and epoch records survive a round trip through text")
    func codingRoundTrip() throws {
        let state = ReserveState(
            scheduleId: "1y",
            activatedAt: Self.now,
            completedEpochs: [Fixture.members: 3],
            spentBaseUnits: [Fixture.members: 807_692_307_846],
            lastPeriodKeys: [Fixture.members: "2026-W38"]
        )
        let decoded = try ReserveCoding.decode(
            ReserveState.self,
            from: try ReserveCoding.encode(state)
        )
        #expect(decoded == state)

        var record = Fixture.epoch(Fixture.passes, 4)
        record.claim(
            entry: ReserveEpochEntry(
                recipientId: "R1",
                account: "ACCOUNT-A",
                units: 2,
                baseUnitsAmount: 100,
                claimedHoldingIds: ["H9", "H7"]
            ),
            at: Date(timeIntervalSince1970: 5)
        )
        let decodedRecord = try ReserveCoding.decode(
            ReserveEpochRecord.self,
            from: try ReserveCoding.encode(record)
        )
        #expect(decodedRecord == record)
        #expect(decodedRecord.claimedHoldingIds == ["H7", "H9"])
        #expect(decodedRecord.paidBaseUnits == 100)
    }

    @Test("An unreadable row throws rather than reading as an unpaid epoch (RESERVE-6.e)")
    func corruptRowThrows() {
        #expect(throws: (any Error).self) {
            try ReserveCoding.decode(ReserveState.self, from: "{ not json")
        }
        #expect(throws: (any Error).self) {
            try ReserveCoding.decode(ReserveEpochRecord.self, from: "")
        }
    }
}
