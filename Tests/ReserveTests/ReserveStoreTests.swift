import Foundation
import Testing
@testable import Reserve

/// The ledger against a store.
///
/// The arithmetic suites pin what is pure. This one pins the half that is not:
/// whether the guard the whole design rests on actually survives a write and a
/// read. A guard that is only correct in memory is not a guard.
///
/// The in-memory store keeps its rows as encoded text, so these exercise the
/// same encode/decode path a database-backed store would.
@Suite("Reserve store")
struct ReserveStoreTests {

    private static let epochStart = Date(timeIntervalSince1970: 0)

    // MARK: - Empty reads

    @Test("A fresh store has no schedule and pays nothing (RESERVE-8.c)")
    func freshStoreIsEmpty() async throws {
        let store = InMemoryReserveStore()
        let state = try await store.loadState()
        #expect(state.scheduleId == nil)
        #expect(state.paidEpochs == 0)
        #expect(state.nextEpoch(Fixture.members) == 1)
        #expect(state.spent(Fixture.passes) == 0)
        #expect(throws: ReserveError.scheduleNotSelected) {
            try state.requireScheduleId()
        }
    }

    @Test("An epoch nobody has run reads as unpaid, not as missing")
    func unknownEpochReadsUnpaid() async throws {
        let store = InMemoryReserveStore()
        let record = try await store.loadEpoch(streamId: Fixture.passes, epoch: 9)
        #expect(record.streamId == Fixture.passes)
        #expect(record.epoch == 9)
        #expect(record.paidAccounts.isEmpty)
        #expect(record.claimedHoldingIds.isEmpty)
        #expect(record.isComplete == false)
    }

    // MARK: - Round trips

    @Test("The chosen duration and the spend survive a write and a read")
    func stateRoundTrips() async throws {
        let store = InMemoryReserveStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.save(state: try ReserveState().selecting(scheduleId: "6m", at: now))

        var reloaded = try await store.loadState()
        #expect(reloaded.scheduleId == "6m")
        #expect(reloaded.isLockable)

        reloaded = reloaded.recordingSpend(streamId: Fixture.members, baseUnits: 269_230_769_230)
        reloaded = reloaded.markingComplete(streamId: Fixture.members, epoch: 1)
        try await store.save(state: reloaded)

        let after = try await store.loadState()
        #expect(after.nextEpoch(Fixture.members) == 2)
        #expect(after.nextEpoch(Fixture.passes) == 1)
        #expect(after.spent(Fixture.members) == 269_230_769_230)
        // The duration is fixed now that an epoch has paid.
        #expect(after.isLockable == false)
        #expect(throws: ReserveError.scheduleLocked(scheduleId: "6m", paidEpochs: 1)) {
            try after.selecting(scheduleId: "1y", at: now)
        }
    }

    @Test("The period key survives a write, so a period cannot pay twice (RESERVE-1.g)")
    func periodKeyRoundTrips() async throws {
        let store = InMemoryReserveStore()
        let week = ReservePeriod.isoWeek(Date(timeIntervalSince1970: 1_758_000_000))
        try await store.save(
            state: try ReserveState()
                .selecting(scheduleId: "6m", at: Self.epochStart)
                .markingComplete(streamId: Fixture.members, epoch: 1)
                .claimingPeriod(streamId: Fixture.members, periodKey: week)
        )
        let reloaded = try await store.loadState()
        #expect(reloaded.lastPeriodKey(Fixture.members) == week)
        // The other stream is untouched: it may still pay this period.
        #expect(reloaded.lastPeriodKey(Fixture.passes) == nil)
        #expect(reloaded.nextEpoch(Fixture.members) == 2)
    }

    @Test("Each stream and epoch keeps its own row")
    func rowsAreScoped() async throws {
        let store = InMemoryReserveStore()
        var members = Fixture.epoch(Fixture.members, 1)
        members.paidAccounts = ["ACCOUNT-A"]
        try await store.save(epoch: members)

        #expect(try await store.loadEpoch(streamId: Fixture.passes, epoch: 1).paidAccounts.isEmpty)
        #expect(try await store.loadEpoch(streamId: Fixture.members, epoch: 2).paidAccounts.isEmpty)
        #expect(
            try await store.loadEpoch(streamId: Fixture.members, epoch: 1).paidAccounts
                == ["ACCOUNT-A"]
        )
    }

    // MARK: - Surviving a restart

    @Test("A restart cannot pay an epoch's account twice (RESERVE-6.a, RESERVE-6.c)")
    func ledgerSurvivesARestart() async throws {
        let store = InMemoryReserveStore()
        let planner = try Fixture.planner()
        let recipients = [
            ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H42"]),
            ReserveRecipient(id: "R2", account: "ACCOUNT-B", holdingIds: ["H43"])
        ]
        var record = try await store.loadEpoch(streamId: Fixture.members, epoch: 1)
        let plan = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: recipients,
            record: record
        )
        #expect(plan.entries.count == 2)

        // Only the first payment got away before the process died.
        if let first = plan.entries.first {
            record.claim(entry: first, at: Self.epochStart)
            try await store.save(epoch: record)
        }

        // A fresh read, as a restarted process would do.
        let reloaded = try await store.loadEpoch(streamId: Fixture.members, epoch: 1)
        #expect(reloaded.paidAccounts == ["ACCOUNT-A"])
        #expect(reloaded.claimedHoldingIds == ["H42"])
        #expect(reloaded.paidBaseUnits == 269_230_769_230)

        let retry = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: recipients,
            record: reloaded
        )
        #expect(retry.entries.map(\.account) == ["ACCOUNT-B"])
        #expect(retry.skipped.map(\.reason) == [.accountAlreadyPaid])

        // And the holding already paid for cannot be paid on a new account
        // inside the same epoch, however the holdings moved underneath.
        let afterTransfer = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: [ReserveRecipient(id: "R3", account: "ACCOUNT-C", holdingIds: ["H42"])],
            record: reloaded
        )
        #expect(afterTransfer.entries.isEmpty)
        #expect(afterTransfer.skipped.map(\.reason) == [.holdingsAlreadyClaimed])
    }

    @Test("A person paid on one account is skipped on their other after a restart")
    func recipientClaimSurvivesARestart() async throws {
        let store = InMemoryReserveStore()
        let planner = try Fixture.planner()
        let recipients = [
            ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H11"]),
            ReserveRecipient(id: "R1", account: "ACCOUNT-B", holdingIds: ["H12"])
        ]
        var record = try await store.loadEpoch(streamId: Fixture.members, epoch: 1)
        let plan = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: recipients,
            record: record
        )
        #expect(plan.entries.count == 1)
        if let only = plan.entries.first {
            record.claim(entry: only, at: Self.epochStart)
            try await store.save(epoch: record)
        }

        let reloaded = try await store.loadEpoch(streamId: Fixture.members, epoch: 1)
        #expect(reloaded.paidRecipientIds == ["R1"])
        let retry = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: recipients,
            record: reloaded
        )
        #expect(retry.entries.isEmpty)
        #expect(retry.skipped.contains { $0.reason == .recipientAlreadyPaid })
    }

    @Test("A finished epoch stays finished across a restart")
    func closedEpochStaysClosed() async throws {
        let store = InMemoryReserveStore()
        let planner = try Fixture.planner()
        var record = try await store.loadEpoch(streamId: Fixture.members, epoch: 4)
        record.completedAt = Date(timeIntervalSince1970: 10)
        try await store.save(epoch: record)

        let reloaded = try await store.loadEpoch(streamId: Fixture.members, epoch: 4)
        #expect(reloaded.isComplete)
        #expect(throws: ReserveError.epochAlreadyPaid(streamId: Fixture.members, epoch: 4)) {
            try planner.planGuardedEpoch(
                streamId: Fixture.members,
                schedule: Fixture.sixMonths(),
                epoch: 4,
                recipients: [ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1"])],
                record: reloaded,
                alreadySpentBaseUnits: 0
            )
        }
    }

    // MARK: - Which ceiling an epoch was charged against

    @Test("A record written before charges existed loads as charged to nothing (ADOPT-5)")
    func aRecordFromAnOlderBuildHasNoCharges() async throws {
        let store = InMemoryReserveStore()
        // Exactly what the build before this one wrote: every key it had, and
        // no `charges`. Synthesised decoding of a non-optional array throws on
        // a missing key, and a throw here would stop every run of the stream
        // until somebody edited the database, because an epoch row that cannot
        // be read refuses rather than reading as unpaid.
        await store.setRaw(
            key: InMemoryReserveStore.epochKey(streamId: Fixture.members, epoch: 3),
            value: """
                {"streamId":"members","epoch":3,"paidAccounts":["ACCOUNT-A"],
                "paidRecipientIds":["R1"],"claimedHoldingIds":["H-1"],
                "paidBaseUnits":1000,"startedAt":10,"completedAt":20}
                """
        )
        let record = try await store.loadEpoch(streamId: Fixture.members, epoch: 3)
        #expect(record.charges.isEmpty)
        #expect(record.chargedPeriodKeys.isEmpty)
        // Everything else still read, and the period was not invented from
        // either timestamp, which is the arithmetic SPEND-9.c abolishes.
        #expect(record.paidAccounts == ["ACCOUNT-A"])
        #expect(record.startedAt == Date(timeIntervalSince1970: 10))
    }

    @Test("A key that is genuinely missing still refuses, so only charges are forgiving")
    func onlyTheChargesKeyIsOptional() async throws {
        let store = InMemoryReserveStore()
        await store.setRaw(
            key: InMemoryReserveStore.epochKey(streamId: Fixture.members, epoch: 4),
            value: """
                {"streamId":"members","epoch":4,"paidRecipientIds":[],
                "claimedHoldingIds":[],"paidBaseUnits":0}
                """
        )
        await #expect(throws: (any Error).self) {
            _ = try await store.loadEpoch(streamId: Fixture.members, epoch: 4)
        }
    }

    @Test("The ceilings a record was measured against survive a write and a read (SPEND-9.c)")
    func chargesRoundTrip() async throws {
        let store = InMemoryReserveStore()
        var record = Fixture.epoch(Fixture.members, 2)
        record.recordCharge(
            periodKey: "2026-W38",
            checkedWholeUnits: 269_230_770,
            at: Date(timeIntervalSince1970: 100)
        )
        try await store.save(epoch: record)
        record.recordCharge(
            periodKey: "2026-W39",
            checkedWholeUnits: 12,
            at: Date(timeIntervalSince1970: 700_000)
        )
        try await store.save(epoch: record)

        let reloaded = try await store.loadEpoch(streamId: Fixture.members, epoch: 2)
        #expect(reloaded.charges == record.charges)
        #expect(reloaded.chargedPeriodKeys == ["2026-W38", "2026-W39"])
        #expect(reloaded.charges.map(\.checkedWholeUnits) == [269_230_770, 12])
    }

    // MARK: - Broken rows

    @Test("A row that will not parse refuses rather than reading as unpaid (RESERVE-6.e)")
    func corruptRowRefuses() async throws {
        let store = InMemoryReserveStore()
        await store.setRaw(
            key: InMemoryReserveStore.epochKey(streamId: Fixture.members, epoch: 1),
            value: "{ not json"
        )
        await #expect(throws: (any Error).self) {
            _ = try await store.loadEpoch(streamId: Fixture.members, epoch: 1)
        }

        await store.setRaw(key: InMemoryReserveStore.stateKey, value: "{ also not json")
        await #expect(throws: (any Error).self) {
            _ = try await store.loadState()
        }
    }

    @Test("Row keys are stable and scoped to a stream and an epoch")
    func rowKeys() {
        #expect(InMemoryReserveStore.stateKey == "reserve.state")
        #expect(
            InMemoryReserveStore.epochKey(streamId: "members", epoch: 7) == "reserve.epoch.members.7"
        )
        #expect(
            InMemoryReserveStore.epochKey(streamId: "passes", epoch: 1) == "reserve.epoch.passes.1"
        )
    }
}
