@preconcurrency import Foundation
import Reserve
import Store

extension StoreConformance {

    // MARK: - Internal Methods

    /// A run cut in the middle, resumed on the same store.
    ///
    /// Available to every backend, because nothing here needs the rows to
    /// outlive anything: it is the algorithm that is under test.
    internal func aCutRunPaysNobodyTwice(_ subject: StoreUnderTest) async throws {
        try await cutAndResume(.aCutRunPaysNobodyTwice, store: subject.store) { _ in nil }
    }

    /// The same run, cut, with the handle let go and the storage opened again
    /// before the resume.
    ///
    /// This is the promise stated as an assertion. Everything the first run
    /// claimed has to still be there when a handle that never saw its memory
    /// opens the storage, or the resume pays somebody a second time.
    internal func runDurability(
        _ behaviour: Behaviour,
        subject: StoreUnderTest,
        probe: any DurabilityProbe
    ) async throws {
        switch behaviour {
        case .aCutRunPaysNobodyTwiceAcrossAReopen:
            try await cutAndResume(behaviour, store: subject.store) { _ in
                try await probe.reopenAfterAbandoning()
            }

        case .aClaimIsOnTheStorageBeforeAPaymentIsAttempted:
            try await aClaimIsOnTheStorage(subject, probe: probe)

        default:
            try expect(false, behaviour, "this behaviour does not need a durability probe")
        }
    }

    // MARK: - Private Methods

    private func aClaimIsOnTheStorage(
        _ subject: StoreUnderTest,
        probe: any DurabilityProbe
    ) async throws {
        let behaviour = Behaviour.aClaimIsOnTheStorageBeforeAPaymentIsAttempted
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        try await store.prove(
            account: AccountRecord(
                memberKey: member.key,
                address: ConformanceFixture.account(1),
                provenAt: ConformanceFixture.instant(1),
                directBaseUnits: UInt64.max
            )
        )
        var claimed = ReserveEpochRecord(streamId: ConformanceFixture.streamId, epoch: 1)
        claimed.claim(
            entry: ReserveEpochEntry(
                recipientId: member.key.value,
                account: ConformanceFixture.account(1),
                units: 1,
                baseUnitsAmount: 7_000,
                claimedHoldingIds: [ConformanceFixture.holding(1)]
            ),
            at: ConformanceFixture.instant(2)
        )
        try await store.save(epoch: claimed)

        // The regression this catches is the one somebody introduces while
        // making an epoch loop faster: a write pushed into a detached task
        // still returns, and still reads back from the handle that queued it.
        // A second view of the same storage cannot see a write that has not
        // been committed.
        let onlooker = try await probe.independentView()
        let seen = try await onlooker.loadEpoch(streamId: claimed.streamId, epoch: 1)
        await onlooker.close()
        try expectEqual(
            seen,
            claimed,
            behaviour,
            "the claim a save returned for, as a second view of the storage sees it"
        )

        let reopened = try await probe.reopenAfterAbandoning()
        let afterwards = try await reopened.loadEpoch(streamId: claimed.streamId, epoch: 1)
        try expectEqual(afterwards, claimed, behaviour, "the claim after the handle was let go")
        try expectEqual(
            try await reopened.account(address: ConformanceFixture.account(1))?.directBaseUnits,
            UInt64.max,
            behaviour,
            "a saturated figure after the handle was let go"
        )
        try expectEqual(
            try await reopened.member(externalId: ConformanceFixture.externalId(1))?.key,
            member.key,
            behaviour,
            "the member's key after the handle was let go"
        )
        await reopened.close()
    }

    /// Runs three epochs, cutting each one at a different save, and checks the
    /// only thing that actually matters afterwards.
    ///
    /// The assertion is deliberately not "everybody was paid". A cut between
    /// the claim and the payment under-pays by one slot on purpose, and that
    /// slot's value stays in the reserve. What must never happen is a second
    /// payment, so the check is on the union of everything the payer was asked
    /// to do across both halves of every epoch: no account twice, no holding
    /// twice.
    private func cutAndResume(
        _ behaviour: Behaviour,
        store: any BotStore,
        resume: @Sendable (any BotStore) async throws -> (any BotStore)?
    ) async throws {
        let configuration = try ConformanceFixture.reserve()
        let payer = RecordingPayer()
        let recipients = ConformanceFixture.recipients(Array(1...5))

        var current = store
        var didReopen = false
        try await ReserveRunner(configuration: configuration, store: current, payer: payer)
            .activate(scheduleId: "short", now: ConformanceFixture.instant(0))

        // One cut per epoch: before the second entry's claim lands, just after
        // a claim lands and before its spend is recorded, and in the middle of
        // the fourth entry.
        let cuts: [(epoch: UInt64, save: Int, moment: CuttingReserveStore.Moment)] = [
            (1, 3, .insteadOfWriting),
            (2, 6, .afterWriting),
            (3, 7, .insteadOfWriting)
        ]
        for cut in cuts {
            await payer.reset()
            let cadenceKey = "PERIOD-\(cut.epoch)"

            var cutShort = false
            do {
                _ = try await ReserveRunner(
                    configuration: configuration,
                    store: CuttingReserveStore(
                        inner: current,
                        cutAfterSaves: cut.save,
                        moment: cut.moment
                    ),
                    payer: payer
                ).run(
                    streamId: ConformanceFixture.streamId,
                    recipients: recipients,
                    cadencePeriodKey: cadenceKey,
                    now: ConformanceFixture.instant(Int(cut.epoch) * 1_000)
                )
            } catch is CutShort {
                cutShort = true
            }
            try expect(cutShort, behaviour, "the run was not cut short at save \(cut.save)")

            if let reopened = try await resume(current) {
                current = reopened
                didReopen = true
            }

            let outcome = try await ReserveRunner(
                configuration: configuration,
                store: current,
                payer: payer
            ).run(
                streamId: ConformanceFixture.streamId,
                recipients: recipients,
                cadencePeriodKey: cadenceKey,
                now: ConformanceFixture.instant(Int(cut.epoch) * 1_000 + 60)
            )
            try expectEqual(
                outcome.epoch,
                cut.epoch,
                behaviour,
                "the epoch the resumed run finished"
            )
            try expect(outcome.isComplete, behaviour, "the resumed run did not close the epoch")

            let duplicateAccounts = await payer.duplicateAccounts
            try expectEqual(
                duplicateAccounts,
                [],
                behaviour,
                "accounts paid twice across the cut at save \(cut.save)"
            )
            let duplicateHoldings = await payer.duplicateHoldingIds
            try expectEqual(
                duplicateHoldings,
                [],
                behaviour,
                "holdings paid for twice across the cut at save \(cut.save)"
            )
            let paid = await payer.paidAccounts
            try expect(
                Set(paid).isSubset(of: Set(recipients.recipients.map(\.account))),
                behaviour,
                "somebody was paid who was not on the list: \(paid)"
            )
            try expect(
                !paid.isEmpty,
                behaviour,
                "nobody at all was paid, so the assertion about duplicates proves nothing"
            )
        }

        // Running the same period again is refused whatever the store did, so
        // a retry after a finished epoch cannot spend the schedule in an
        // afternoon.
        var refused = false
        do {
            _ = try await ReserveRunner(configuration: configuration, store: current, payer: payer)
                .run(
                    streamId: ConformanceFixture.streamId,
                    recipients: recipients,
                    cadencePeriodKey: "PERIOD-3",
                    now: ConformanceFixture.instant(9_000)
                )
        } catch {
            refused = true
        }
        try expect(refused, behaviour, "a period that had already paid was allowed to pay again")

        // Only a store this function opened is closed here. The one it was
        // handed belongs to the caller, which closes it after every behaviour.
        if didReopen {
            await current.close()
        }
    }
}
