import Foundation
import Testing
@testable import Reserve

/// A payer that records what it was asked to do, and what the ledger already
/// said when it was asked.
///
/// The second part is the interesting one. It reads the epoch row at the moment
/// it is asked to pay, which is the only honest way to test that the claim was
/// written *first* rather than merely that it was written.
private actor RecordingPayer: ReservePayer {

    enum Behaviour: Sendable, Equatable {
        /// Pays, and hands back a reference.
        case succeed
        /// Refuses, provably having moved nothing.
        case refuse(String)
        /// Fails in a way that might have moved something.
        case fail(String)
    }

    struct Attempt: Sendable, Equatable {
        let account: String
        /// Whether the ledger already recorded the claim when pay was called.
        let claimAlreadyOnDisk: Bool
        /// Whether the spend was already recorded when pay was called.
        let spendAlreadyOnDisk: Bool
    }

    private let store: InMemoryReserveStore
    private var behaviours: [String: Behaviour]
    private var limitsValue: ReserveSpendLimits?
    private var availableValue: UInt64?
    private(set) var attempts: [Attempt] = []

    init(
        store: InMemoryReserveStore,
        behaviours: [String: Behaviour] = [:],
        limits: ReserveSpendLimits? = nil,
        available: UInt64? = nil
    ) {
        self.store = store
        self.behaviours = behaviours
        self.limitsValue = limits
        self.availableValue = available
    }

    func pay(entry: ReserveEpochEntry, streamId: String, epoch: UInt64) async throws -> String {
        let record = try await store.loadEpoch(streamId: streamId, epoch: epoch)
        let state = try await store.loadState()
        attempts.append(
            Attempt(
                account: entry.account,
                claimAlreadyOnDisk: record.paidAccountSet.contains(entry.account),
                spendAlreadyOnDisk: state.spent(streamId) >= entry.baseUnitsAmount
            )
        )
        switch behaviours[entry.account] ?? .succeed {
        case .succeed:
            return "REF-\(entry.account)"
        case .refuse(let reason):
            throw ReservePaymentRefusal(reason: reason)
        case .fail(let reason):
            throw PayerFailure(reason: reason)
        }
    }

    func spendLimits() async throws -> ReserveSpendLimits? { limitsValue }

    func availableBaseUnits() async throws -> UInt64? { availableValue }

    var paidAccounts: [String] { attempts.map(\.account) }
}

/// A failure that might have moved value, so the claim must be kept.
private struct PayerFailure: Error, LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// The four guards, exercised end to end against a real store and a fake payer.
@Suite("Reserve runner")
struct ReserveRunnerTests {

    private static let now = Date(timeIntervalSince1970: 1_758_000_000)
    private static let week = ReservePeriod.isoWeek(now)

    private func holders(_ count: Int) -> ReserveRecipientList {
        ReserveRecipientList(
            streamId: Fixture.members,
            recipients: (1...count).map { Fixture.holder($0) }
        )
    }

    private func activated(
        store: InMemoryReserveStore,
        scheduleId: String = "6m"
    ) async throws -> Void {
        try await store.save(
            state: try ReserveState().selecting(scheduleId: scheduleId, at: Self.now)
        )
    }

    // MARK: - Guard 1: one epoch at a time

    @Test("The gate admits one holder and refuses the next (RESERVE-1.f, RESERVE-6.f)")
    func gateRefusesASecondHolder() async {
        let gate = ReserveGate()
        #expect(await gate.acquire())
        #expect(await gate.busy)
        // Refused, not queued: a second payout that waits its turn is a second
        // payout nobody asked for.
        #expect(await gate.acquire() == false)
        await gate.release()
        #expect(await gate.busy == false)
        #expect(await gate.acquire())
    }

    @Test("A run is refused while another holds the gate (RESERVE-1.f, RESERVE-9.b)")
    func runRefusedWhileGateHeld() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(store: store)
        let gate = ReserveGate()
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: gate
        )

        #expect(await gate.acquire())
        await #expect(throws: ReserveError.alreadyRunning) {
            _ = try await runner.run(
                streamId: Fixture.members,
                recipients: holders(2),
                periodKey: Self.week,
                now: Self.now
            )
        }
        // Nothing was attempted and nothing was written.
        #expect(await payer.attempts.isEmpty)
        await gate.release()

        // With the gate free the same run goes through.
        let outcome = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(2),
            periodKey: Self.week,
            now: Self.now
        )
        #expect(outcome.paidCount == 2)
        // And the gate was handed back afterwards.
        #expect(await gate.busy == false)
    }

    @Test("The gate is handed back even when a run refuses")
    func gateReleasedOnFailure() async throws {
        let store = InMemoryReserveStore()
        let payer = RecordingPayer(store: store)
        let gate = ReserveGate()
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: gate
        )
        // No schedule chosen, so the run refuses on the way in.
        await #expect(throws: ReserveError.scheduleNotSelected) {
            _ = try await runner.run(
                streamId: Fixture.members,
                recipients: holders(1),
                periodKey: Self.week,
                now: Self.now
            )
        }
        #expect(await gate.busy == false)
    }

    // MARK: - Guard 2: one epoch per period

    @Test("A stream that already paid this period is refused (RESERVE-1.g)")
    func periodGate() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(store: store)
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )

        let first = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(2),
            periodKey: Self.week,
            now: Self.now
        )
        #expect(first.epoch == 1)
        #expect(first.isComplete)

        await #expect(
            throws: ReserveError.periodAlreadyPaid(streamId: Fixture.members, periodKey: Self.week)
        ) {
            _ = try await runner.run(
                streamId: Fixture.members,
                recipients: holders(2),
                periodKey: Self.week,
                now: Self.now
            )
        }
        // Nothing beyond the first epoch was attempted.
        #expect(await payer.attempts.count == 2)

        // The next period pays the next epoch, at the identical figure.
        let second = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(2),
            periodKey: "2026-W99",
            now: Self.now
        )
        #expect(second.epoch == 2)
        #expect(second.perUnitBaseUnits == first.perUnitBaseUnits)
    }

    @Test("One stream's period claim does not block another stream")
    func periodIsPerStream() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(store: store)
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )
        _ = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(1),
            periodKey: Self.week,
            now: Self.now
        )
        let passes = ReserveRecipientList(
            streamId: Fixture.passes,
            recipients: [ReserveRecipient(id: "R9", account: "ACCOUNT-9", holdingIds: ["H9"])]
        )
        let outcome = try await runner.run(
            streamId: Fixture.passes,
            recipients: passes,
            periodKey: Self.week,
            now: Self.now
        )
        #expect(outcome.epoch == 1)
        #expect(outcome.paidCount == 1)
    }

    // MARK: - Guard 3: claim before pay

    @Test("The claim is on disk before the payment is attempted (RESERVE-6.a, RESERVE-9.b)")
    func claimIsWrittenBeforePaying() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(store: store)
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )

        let outcome = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(3),
            periodKey: Self.week,
            now: Self.now
        )
        #expect(outcome.paidCount == 3)

        let attempts = await payer.attempts
        #expect(attempts.count == 3)
        // Every single payment saw its own claim, and its own spend, already
        // durable before it was asked to move anything.
        #expect(attempts.filter(\.claimAlreadyOnDisk).count == 3)
        #expect(attempts.filter(\.spendAlreadyOnDisk).count == 3)
    }

    @Test("A refusal gives the slot back; a failure keeps it (RESERVE-6.b)")
    func refusalReleasesFailureKeeps() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(
            store: store,
            behaviours: [
                Fixture.account(2): .refuse("not set up to receive"),
                Fixture.account(3): .fail("no answer from the network")
            ]
        )
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )

        let outcome = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(3),
            periodKey: Self.week,
            now: Self.now
        )
        #expect(outcome.paidCount == 1)
        #expect(outcome.failed.count == 2)
        #expect(outcome.isClean == false)

        let released = outcome.failed.first { $0.entry.account == Fixture.account(2) }
        let kept = outcome.failed.first { $0.entry.account == Fixture.account(3) }
        #expect(released?.claimReleased == true)
        #expect(kept?.claimReleased == false)

        let record = try await store.loadEpoch(streamId: Fixture.members, epoch: 1)
        // The refused slot is free again; the uncertain one stays claimed so
        // nobody can be paid twice for it.
        #expect(record.paidAccountSet.contains(Fixture.account(2)) == false)
        #expect(record.paidAccountSet.contains(Fixture.account(3)))
        // Only the payment that actually happened, plus the uncertain one, are
        // counted against the allocation. Over-counting is the safe direction.
        let state = try await store.loadState()
        #expect(state.spent(Fixture.members) == 269_230_769_230 * 2)
        #expect(outcome.paidBaseUnits == 269_230_769_230)
    }

    @Test("An epoch is finished, not left open, when some payments failed")
    func epochClosesDespiteFailures() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(
            store: store,
            behaviours: [Fixture.account(1): .fail("no answer")]
        )
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )
        let outcome = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(2),
            periodKey: Self.week,
            now: Self.now
        )
        #expect(outcome.isComplete)
        #expect(try await store.loadEpoch(streamId: Fixture.members, epoch: 1).isComplete)
        #expect(try await store.loadState().nextEpoch(Fixture.members) == 2)
    }

    // MARK: - Guard 4: limits before the first payment

    @Test("An epoch over the limits is refused before anything is paid (RESERVE-7.d)")
    func limitsRefuseBeforeFirstPayment() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(
            store: store,
            limits: ReserveSpendLimits(
                maxPerPaymentWholeUnits: 1_000,
                maxPerPeriodWholeUnits: 30_000_000,
                spentThisPeriodWholeUnits: 0,
                periodKey: Self.week
            )
        )
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )

        await #expect(throws: ReserveError.overPaymentLimit(requested: 269_231, limit: 1_000)) {
            _ = try await runner.run(
                streamId: Fixture.members,
                recipients: holders(5),
                periodKey: Self.week,
                now: Self.now
            )
        }
        // Not one payment was attempted, and the epoch is untouched.
        #expect(await payer.attempts.isEmpty)
        #expect(try await store.loadEpoch(streamId: Fixture.members, epoch: 1).paidAccounts.isEmpty)
        #expect(try await store.loadState().nextEpoch(Fixture.members) == 1)
    }

    @Test("The period limit is measured against what is left of it (RESERVE-7.d)")
    func limitsUseWhatIsLeft() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        // Two payments charge 2 × 269,231 = 538,462. The raw ceiling is ample;
        // what is left of it is not.
        let payer = RecordingPayer(
            store: store,
            limits: ReserveSpendLimits(
                maxPerPaymentWholeUnits: 300_000,
                maxPerPeriodWholeUnits: 30_000_000,
                spentThisPeriodWholeUnits: 29_900_000,
                periodKey: Self.week
            )
        )
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )
        await #expect(throws: (any Error).self) {
            _ = try await runner.run(
                streamId: Fixture.members,
                recipients: holders(2),
                periodKey: Self.week,
                now: Self.now
            )
        }
        #expect(await payer.attempts.isEmpty)
    }

    // MARK: - Incomplete lists

    @Test("An incomplete list pays nobody and leaves no trace (RESERVE-7.e)")
    func incompleteListPaysNobody() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(store: store)
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )
        let holey = ReserveRecipientList(
            streamId: Fixture.members,
            recipients: [Fixture.holder(1)],
            incompleteRecipientIds: ["R2"]
        )
        await #expect(throws: ReserveError.incompleteRecipients(1)) {
            _ = try await runner.run(
                streamId: Fixture.members,
                recipients: holey,
                periodKey: Self.week,
                now: Self.now
            )
        }
        #expect(await payer.attempts.isEmpty)
        #expect(try await store.loadState().nextEpoch(Fixture.members) == 1)
    }

    // MARK: - Activation, preview, rehearsal

    @Test("Activating records the duration and refuses a second choice once paid (RESERVE-2.c)")
    func activateThenLock() async throws {
        let store = InMemoryReserveStore()
        let payer = RecordingPayer(store: store)
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )

        let state = try await runner.activate(scheduleId: "1y", now: Self.now)
        #expect(state.scheduleId == "1y")
        #expect(try await runner.state().scheduleId == "1y")

        // Still changeable before the first epoch pays.
        _ = try await runner.activate(scheduleId: "6m", now: Self.now)
        #expect(try await runner.state().scheduleId == "6m")

        // An unconfigured duration is refused rather than stored.
        await #expect(throws: ReserveError.unknownSchedule("3m")) {
            _ = try await runner.activate(scheduleId: "3m", now: Self.now)
        }

        _ = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(1),
            periodKey: Self.week,
            now: Self.now
        )
        await #expect(throws: ReserveError.scheduleLocked(scheduleId: "6m", paidEpochs: 1)) {
            _ = try await runner.activate(scheduleId: "1y", now: Self.now)
        }
    }

    @Test("The preview reads the ledger and moves nothing (RESERVE-7.a)")
    func auditReadsTheLedger() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(store: store, available: Fixture.whole(412_000_000))
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )
        _ = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(1),
            periodKey: Self.week,
            now: Self.now
        )

        let audit = try await runner.audit(eligible: [Fixture.members: holders(1)])
        #expect(audit.selectedSchedule?.id == "6m")
        #expect(audit.nextEpoch[Fixture.members] == 2)
        #expect(audit.nextEpoch[Fixture.passes] == 1)
        #expect(audit.projection(Fixture.members)?.eligibleUnits == 1)
        #expect(audit.projection(Fixture.passes)?.eligibleUnits == 0)
        #expect(audit.spentBaseUnits[Fixture.members] == 269_230_769_230)
        #expect(audit.potBaseUnits == Fixture.whole(412_000_000))
        // Reading the preview attempted no further payments.
        #expect(await payer.attempts.count == 1)
    }

    @Test("A rehearsal plans through the same guards and writes nothing (RESERVE-7.a)")
    func rehearsalWritesNothing() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(store: store)
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )

        let before = await store.rowCount
        let plan = try await runner.rehearse(streamId: Fixture.members, recipients: holders(4))
        #expect(plan.entries.count == 4)
        #expect(plan.perUnitBaseUnits == 269_230_769_230)
        #expect(plan.totalBaseUnits == 269_230_769_230 * 4)
        // Nothing attempted, nothing written, no epoch closed.
        #expect(await payer.attempts.isEmpty)
        #expect(await store.rowCount == before)
        #expect(try await store.loadEpoch(streamId: Fixture.members, epoch: 1).paidAccounts.isEmpty)

        // And the real run that follows still pays everybody: the rehearsal left
        // nothing behind that would make it skip somebody.
        let outcome = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(4),
            periodKey: Self.week,
            now: Self.now
        )
        #expect(outcome.paidCount == 4)
        #expect(outcome.paidBaseUnits == plan.totalBaseUnits)
    }

    @Test("A rehearsal refuses exactly where the real run would (RESERVE-7.a)")
    func rehearsalRefusesLikeTheRun() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(
            store: store,
            limits: ReserveSpendLimits(
                maxPerPaymentWholeUnits: 10,
                maxPerPeriodWholeUnits: 10,
                spentThisPeriodWholeUnits: 0,
                periodKey: Self.week
            )
        )
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )
        await #expect(throws: ReserveError.overPaymentLimit(requested: 269_231, limit: 10)) {
            _ = try await runner.rehearse(streamId: Fixture.members, recipients: holders(1))
        }
    }

    // MARK: - Running out

    @Test("A schedule that has run out of epochs refuses rather than wrapping")
    func scheduleRunsOut() async throws {
        let store = InMemoryReserveStore()
        // A one-epoch schedule makes the boundary cheap to reach.
        let reserve = try ReserveConfiguration(
            asset: try Fixture.asset(),
            totalWholeUnits: 1_000,
            streams: [
                ReserveStream(id: "only", share: .whole, denominator: 10, rule: .oncePerRecipient)
            ],
            schedules: [ReserveSchedule(id: "one", epochCount: 1)]
        )
        try await store.save(state: try ReserveState().selecting(scheduleId: "one", at: Self.now))
        let payer = RecordingPayer(store: store)
        let runner = ReserveRunner(
            configuration: reserve,
            store: store,
            payer: payer,
            gate: ReserveGate()
        )
        let list = ReserveRecipientList(
            streamId: "only",
            recipients: [ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1"])]
        )
        let first = try await runner.run(
            streamId: "only",
            recipients: list,
            periodKey: "P1",
            now: Self.now
        )
        #expect(first.epoch == 1)
        #expect(first.paidBaseUnits == Fixture.whole(100))

        await #expect(throws: ReserveError.scheduleComplete(streamId: "only", epochs: 1)) {
            _ = try await runner.run(
                streamId: "only",
                recipients: list,
                periodKey: "P2",
                now: Self.now
            )
        }
    }

    @Test("An unknown stream is refused by the runner, not planned around")
    func unknownStreamRefused() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(store: store)
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )
        await #expect(throws: ReserveError.unknownStream("nope")) {
            _ = try await runner.run(
                streamId: "nope",
                recipients: ReserveRecipientList(streamId: "nope", recipients: []),
                periodKey: Self.week,
                now: Self.now
            )
        }
    }

    // MARK: - The whole way through

    @Test("A finished run leaves receipts, a closed epoch and a claimed period")
    func happyPath() async throws {
        let store = InMemoryReserveStore()
        try await activated(store: store)
        let payer = RecordingPayer(store: store)
        let runner = ReserveRunner(
            configuration: try Fixture.reserve(),
            store: store,
            payer: payer,
            gate: ReserveGate()
        )

        let outcome = try await runner.run(
            streamId: Fixture.members,
            recipients: holders(3),
            periodKey: Self.week,
            now: Self.now
        )
        #expect(outcome.streamId == Fixture.members)
        #expect(outcome.epoch == 1)
        #expect(outcome.periodKey == Self.week)
        #expect(outcome.isClean)
        #expect(outcome.paidUnits == 3)
        #expect(outcome.paidBaseUnits == 269_230_769_230 * 3)
        // Every payment carries evidence rather than an assurance.
        #expect(outcome.paid.map(\.reference) == [
            "REF-\(Fixture.account(1))",
            "REF-\(Fixture.account(2))",
            "REF-\(Fixture.account(3))"
        ])

        let state = try await store.loadState()
        #expect(state.nextEpoch(Fixture.members) == 2)
        #expect(state.lastPeriodKey(Fixture.members) == Self.week)
        #expect(state.spent(Fixture.members) == 269_230_769_230 * 3)

        let record = try await store.loadEpoch(streamId: Fixture.members, epoch: 1)
        #expect(record.isComplete)
        #expect(record.paidRecipientIds.count == 3)
        #expect(record.startedAt == Self.now)
    }
}
