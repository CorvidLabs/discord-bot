@preconcurrency import Foundation
import Chain
import Reserve
import Store

extension StoreConformance {

    // MARK: - Internal Methods, the sweep baseline

    internal func anAbsentBaselineIsNil(_ subject: StoreUnderTest) async throws {
        let found = try await subject.store.loadRoleBaseline()
        try expect(
            found == nil,
            .anAbsentBaselineIsNil,
            "a store nobody has swept answered with \(String(describing: found))"
        )
    }

    internal func aBaselineRoundTrips(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let record = RoleBaselineRecord(
            verifiedMemberCount: 412,
            recordedAt: ConformanceFixture.instant(90)
        )
        try await store.save(roleBaseline: record)
        try expectEqual(
            try await store.loadRoleBaseline(),
            record,
            .aBaselineRoundTrips,
            "the baseline read back"
        )
        let later = RoleBaselineRecord(
            verifiedMemberCount: 430,
            recordedAt: ConformanceFixture.instant(180)
        )
        try await store.save(roleBaseline: later)
        try expectEqual(
            try await store.loadRoleBaseline(),
            later,
            .aBaselineRoundTrips,
            "the baseline after a second sweep"
        )
    }

    // MARK: - Internal Methods, the reserve seam

    internal func anAbsentReserveStateIsFresh(_ subject: StoreUnderTest) async throws {
        try expectEqual(
            try await subject.store.loadState(),
            ReserveState(),
            .anAbsentReserveStateIsFresh,
            "the state of a reserve nobody has run"
        )
    }

    internal func reserveStateRoundTrips(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        // The saturated figures are here because the engine produces them on
        // purpose: both `recordingSpend` and `claim` stop at the ceiling rather
        // than wrapping, and a column that cannot hold the ceiling takes the
        // process down while it is paying somebody.
        let state = ReserveState(
            scheduleId: "short",
            activatedAt: ConformanceFixture.instant(10),
            completedEpochs: ["a": 3, "b": UInt64.max],
            spentBaseUnits: ["a": UInt64(Int64.max) + 1, "b": UInt64.max],
            lastPeriodKeys: ["a": "2026-W07", "b": "2026-W08"]
        )
        try await store.save(state: state)
        try expectEqual(
            try await store.loadState(),
            state,
            .reserveStateRoundTrips,
            "the reserve's state read back"
        )

        // Saved twice, because a store that only writes a row once is a store
        // that fails on the second epoch.
        let moved = state
            .markingComplete(streamId: "a", epoch: 4)
            .recordingSpend(streamId: "a", baseUnits: 7)
        try await store.save(state: moved)
        try expectEqual(
            try await store.loadState(),
            moved,
            .reserveStateRoundTrips,
            "the reserve's state after a second write"
        )

        // The three maps are keyed separately and a real state has streams in
        // one of them and not the others: a stream that has claimed a period
        // but finished no epoch is the ordinary state of an epoch in flight. A
        // backend keeping one row per stream writes all three columns for
        // every stream it has heard of, so this is where a whole-value store
        // and a row-per-stream store stop agreeing.
        let uneven = ReserveState(
            scheduleId: "short",
            completedEpochs: ["a": 3],
            spentBaseUnits: ["b": 12],
            lastPeriodKeys: ["c": "2026-W09"]
        )
        try await store.save(state: uneven)
        try expectEqual(
            try await store.loadState(),
            uneven,
            .reserveStateRoundTrips,
            "a state whose three maps name different streams"
        )

        // And a stream entered as zero, which the value itself already answers
        // zero for. Both backends record the same thing, so both hand back the
        // same thing.
        let zeroed = ReserveState(
            completedEpochs: ["a": 0],
            spentBaseUnits: ["a": 0],
            lastPeriodKeys: ["a": "2026-W10"]
        )
        try await store.save(state: zeroed)
        try expectEqual(
            try await store.loadState(),
            StoreDate.recorded(zeroed),
            .reserveStateRoundTrips,
            "a state naming a stream that has done nothing"
        )
    }

    internal func anAbsentEpochIsUnpaid(_ subject: StoreUnderTest) async throws {
        let found = try await subject.store.loadEpoch(streamId: "a", epoch: 7)
        try expectEqual(
            found,
            ReserveEpochRecord(streamId: "a", epoch: 7),
            .anAbsentEpochIsUnpaid,
            "an epoch nobody has run"
        )
        try expect(
            !found.isComplete,
            .anAbsentEpochIsUnpaid,
            "an epoch nobody has run came back complete"
        )
    }

    internal func anEpochRoundTrips(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let record = ReserveEpochRecord(
            streamId: ConformanceFixture.streamId,
            epoch: UInt64.max,
            paidAccounts: [3, 1, 2].map { ConformanceFixture.account($0) },
            paidRecipientIds: ["RECIPIENT-3", "RECIPIENT-1", "RECIPIENT-2"],
            claimedHoldingIds: [1, 2, 3].map { ConformanceFixture.holding($0) },
            paidBaseUnits: UInt64.max,
            startedAt: ConformanceFixture.instant(100),
            completedAt: ConformanceFixture.instant(200)
        )
        try await store.save(epoch: record)
        let read = try await store.loadEpoch(streamId: record.streamId, epoch: record.epoch)
        try expectEqual(read, record, .anEpochRoundTrips, "an epoch's record read back")
        // The order is part of the value. All three lists are append ordered,
        // and a store that returns one in the order its rows happened to come
        // out changes a record's equality.
        try expectEqual(
            read.paidAccounts,
            record.paidAccounts,
            .anEpochRoundTrips,
            "the order accounts were claimed in"
        )

        let second = ReserveEpochRecord(
            streamId: ConformanceFixture.streamId,
            epoch: 1,
            paidBaseUnits: 0
        )
        try await store.save(epoch: second)
        try expectEqual(
            try await store.loadEpoch(streamId: second.streamId, epoch: 1),
            second,
            .anEpochRoundTrips,
            "a second epoch of the same stream"
        )
        try expectEqual(
            try await store.loadEpoch(streamId: record.streamId, epoch: record.epoch),
            record,
            .anEpochRoundTrips,
            "the first epoch after a second was written"
        )

        // A list is a list, and a list may hold the same value twice.
        // ``ReserveEpochRecord/claim(entry:at:)`` cannot produce one, but all
        // three are public `var`s on a public struct, and a store that hands
        // back a shorter, reordered list than it was given is a save and a
        // load that disagree in silence.
        let repeated = ReserveEpochRecord(
            streamId: ConformanceFixture.streamId,
            epoch: 2,
            paidAccounts: [1, 1, 2].map { ConformanceFixture.account($0) },
            paidRecipientIds: ["RECIPIENT-1", "RECIPIENT-1"],
            claimedHoldingIds: [2, 1, 2].map { ConformanceFixture.holding($0) },
            paidBaseUnits: 5
        )
        try await store.save(epoch: repeated)
        try expectEqual(
            try await store.loadEpoch(streamId: repeated.streamId, epoch: 2),
            repeated,
            .anEpochRoundTrips,
            "a claim list holding the same value twice"
        )
    }

    internal func aReleasedClaimIsGone(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let entries = (1...3).map { index in
            ReserveEpochEntry(
                recipientId: "RECIPIENT-\(index)",
                account: ConformanceFixture.account(index),
                units: 1,
                baseUnitsAmount: 1_000,
                claimedHoldingIds: [ConformanceFixture.holding(index)]
            )
        }
        var record = ReserveEpochRecord(streamId: ConformanceFixture.streamId, epoch: 1)
        for entry in entries {
            record.claim(entry: entry, at: ConformanceFixture.instant(10))
        }
        try await store.save(epoch: record)

        // A refusal that provably moved nothing gives the slot back, and the
        // store has to lose it rather than keep a row the next run skips on.
        record.release(entry: entries[1])
        try await store.save(epoch: record)
        let read = try await store.loadEpoch(streamId: record.streamId, epoch: 1)
        try expectEqual(read, record, .aReleasedClaimIsGone, "the record after a release")
        try expect(
            !read.paidAccountSet.contains(entries[1].account),
            .aReleasedClaimIsGone,
            "a released account is still claimed"
        )
        try expect(
            !read.claimedHoldingIdSet.contains(ConformanceFixture.holding(2)),
            .aReleasedClaimIsGone,
            "a released holding is still claimed"
        )
        try expectEqual(
            read.paidBaseUnits,
            2_000,
            .aReleasedClaimIsGone,
            "the figure after a release"
        )

        // A list that changed in the middle without changing length. A store
        // that saves only what it thinks is new has to notice this, and the
        // cheap way of noticing, comparing the last entry, does not.
        var swapped = read
        swapped.paidAccounts = [ConformanceFixture.account(9)] + read.paidAccounts.dropFirst()
        swapped.claimedHoldingIds = [ConformanceFixture.holding(9)]
            + read.claimedHoldingIds.dropFirst()
        try await store.save(epoch: swapped)
        try expectEqual(
            try await store.loadEpoch(streamId: swapped.streamId, epoch: 1),
            swapped,
            .aReleasedClaimIsGone,
            "a claim list that changed in the middle at the same length"
        )

        // And emptied entirely, which is a different path again.
        var emptied = swapped
        emptied.paidAccounts = []
        emptied.paidRecipientIds = []
        emptied.claimedHoldingIds = []
        try await store.save(epoch: emptied)
        try expectEqual(
            try await store.loadEpoch(streamId: emptied.streamId, epoch: 1),
            emptied,
            .aReleasedClaimIsGone,
            "a claim list emptied entirely"
        )
    }

    // MARK: - Internal Methods, the request budget seam

    internal func anAbsentBudgetIsNil(_ subject: StoreUnderTest) async throws {
        let found = try await subject.store.loadBudgetUsage()
        try expect(
            found == nil,
            .anAbsentBudgetIsNil,
            "a day nobody has counted answered with \(String(describing: found))"
        )
    }

    internal func theBudgetRoundTrips(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        for (index, used) in [UInt64(0), 25, UInt64(Int64.max) + 1, UInt64.max].enumerated() {
            let usage = RequestBudgetUsage(
                usedRequests: used,
                // The day moves with the count, because the seam stores the
                // day beside it rather than working it out on the way back. A
                // write that updated the count and left the day where it was
                // would pass against a fixed one, and a process starting the
                // next morning would be handed a fresh budget without a word.
                dayStart: ConformanceFixture.instant(index * 86_400)
            )
            try await store.saveBudgetUsage(usage)
            try expectEqual(
                try await store.loadBudgetUsage(),
                usage,
                .theBudgetRoundTrips,
                "a day counted at \(used)"
            )
        }
    }

    internal func instantsAreRecordedToTheSecond(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let ragged = Date(timeIntervalSince1970: 1_600_000_000.75)
        let whole = StoreDate.whole(ragged)
        try expectEqual(
            whole.timeIntervalSince1970,
            1_600_000_000,
            .instantsAreRecordedToTheSecond,
            "rounding down to the second"
        )

        try await store.save(state: ReserveState(scheduleId: "short", activatedAt: ragged))
        try expectEqual(
            try await store.loadState().activatedAt,
            whole,
            .instantsAreRecordedToTheSecond,
            "when the reserve was activated"
        )

        try await store.save(
            epoch: ReserveEpochRecord(
                streamId: "a",
                epoch: 1,
                startedAt: ragged,
                completedAt: ragged
            )
        )
        let epoch = try await store.loadEpoch(streamId: "a", epoch: 1)
        try expectEqual(epoch.startedAt, whole, .instantsAreRecordedToTheSecond, "when an epoch began")
        try expectEqual(epoch.completedAt, whole, .instantsAreRecordedToTheSecond, "when it finished")

        try await store.saveBudgetUsage(RequestBudgetUsage(usedRequests: 1, dayStart: ragged))
        try expectEqual(
            try await store.loadBudgetUsage()?.dayStart,
            whole,
            .instantsAreRecordedToTheSecond,
            "the day a count belongs to"
        )

        let member = try await store.admitMember(externalId: ConformanceFixture.externalId(1), at: ragged)
        try expectEqual(
            member.firstSeenAt,
            whole,
            .instantsAreRecordedToTheSecond,
            "when a member arrived"
        )
    }

    internal func reconciledSpendOnlyRises(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let stream = ConformanceFixture.streamId
        for epoch in UInt64(1)...2 {
            try await store.save(
                epoch: ReserveEpochRecord(
                    streamId: stream,
                    epoch: epoch,
                    paidBaseUnits: 1_000,
                    startedAt: ConformanceFixture.instant(0),
                    completedAt: ConformanceFixture.instant(10)
                )
            )
        }
        // The window the four-method seam leaves open: the epoch row landed and
        // the state save that would have recorded the spend did not.
        try await store.save(
            state: ReserveState(
                completedEpochs: [stream: 2],
                spentBaseUnits: [stream: 1_000]
            )
        )
        let raised = try await ReserveSpendReconciliation.reconcile(store: store, streamIds: [stream])
        try expectEqual(raised, [stream], .reconciledSpendOnlyRises, "streams put back in step")
        try expectEqual(
            try await store.loadState().spent(stream),
            2_000,
            .reconciledSpendOnlyRises,
            "the recomputed spend"
        )

        // Over-counted spend tightens the ceiling, which is the safe direction,
        // so a reconciliation must never talk it back down.
        try await store.save(
            state: ReserveState(
                completedEpochs: [stream: 2],
                spentBaseUnits: [stream: 9_999]
            )
        )
        let quiet = try await ReserveSpendReconciliation.reconcile(store: store, streamIds: [stream])
        try expectEqual(quiet, [], .reconciledSpendOnlyRises, "streams touched by a safe over-count")
        try expectEqual(
            try await store.loadState().spent(stream),
            9_999,
            .reconciledSpendOnlyRises,
            "the spend after a reconciliation that should have changed nothing"
        )
    }

    // MARK: - Internal Methods, an unreadable row

    internal func runCorruption(
        _ behaviour: Behaviour,
        subject: StoreUnderTest,
        probe: any CorruptionProbe
    ) async throws {
        let store = subject.store
        switch behaviour {
        case .anUnreadableEpochThrows:
            try await store.save(
                epoch: ReserveEpochRecord(
                    streamId: ConformanceFixture.streamId,
                    epoch: 1,
                    paidAccounts: [ConformanceFixture.account(1)],
                    paidBaseUnits: 500
                )
            )
            try await probe.corruptReserveEpoch(streamId: ConformanceFixture.streamId, epoch: 1)
            // The failure this rules out: a row that reads as blank looks like
            // an epoch nobody was paid for, and the next run pays all of it
            // again.
            var read: ReserveEpochRecord?
            do {
                read = try await store.loadEpoch(streamId: ConformanceFixture.streamId, epoch: 1)
            } catch {
                read = nil
            }
            try expect(
                read == nil,
                behaviour,
                "an unreadable epoch came back as \(String(describing: read)) instead of throwing"
            )

        case .anUnreadableBudgetThrows:
            try await store.saveBudgetUsage(
                RequestBudgetUsage(usedRequests: 10, dayStart: ConformanceFixture.instant(0))
            )
            try await probe.corruptBudgetUsage()
            var threw = false
            do {
                _ = try await store.loadBudgetUsage()
            } catch {
                threw = true
            }
            try expect(
                threw,
                behaviour,
                "an unreadable count read as never written, which hands the process a fresh budget"
            )

        case .anUnreadableAccountThrows:
            let member = try await store.admitMember(
                externalId: ConformanceFixture.externalId(1),
                at: ConformanceFixture.instant(0)
            )
            let address = ConformanceFixture.account(1)
            try await store.prove(
                account: AccountRecord(
                    memberKey: member.key,
                    address: address,
                    provenAt: ConformanceFixture.instant(1),
                    directBaseUnits: 5
                )
            )
            try await probe.corruptAccount(address: address)
            try await expectRefusal(
                behaviour,
                "an unreadable account read as absent, which takes every rung off somebody"
            ) {
                _ = try await store.account(address: address)
            }
            // The same row, read the way the sweep guard reads it. A key that
            // is not a key, counted as one more member, raises the very
            // baseline a collapse is measured against, and that count is the
            // guard's whole input.
            try await expectRefusal(
                behaviour,
                "an unreadable key was counted as a member rather than refused"
            ) {
                _ = try await store.verifiedMemberCount()
            }

        case .anUnreadableStateThrows:
            try await store.save(
                state: ReserveState(
                    scheduleId: "short",
                    completedEpochs: [ConformanceFixture.streamId: 2],
                    spentBaseUnits: [ConformanceFixture.streamId: 9_000],
                    lastPeriodKeys: [ConformanceFixture.streamId: "PERIOD-2"]
                )
            )
            try await probe.corruptReserveState()
            // Read as a fresh reserve this is two guards gone at once: the
            // period this stream already paid in, and the value it has already
            // committed against the allocation.
            try await expectRefusal(
                behaviour,
                "an unreadable state read as a fresh reserve, which unclaims a period already paid"
            ) {
                _ = try await store.loadState()
            }

        case .anUnreadableBaselineThrows:
            try await store.save(
                roleBaseline: RoleBaselineRecord(
                    verifiedMemberCount: 120,
                    recordedAt: ConformanceFixture.instant(0)
                )
            )
            try await probe.corruptRoleBaseline()
            // The one with nothing behind it. Read as nothing this is a first
            // run, a first run is allowed to sweep, and a sweep that believes
            // nobody is verified takes every managed role off every member.
            try await expectRefusal(
                behaviour,
                "an unreadable baseline read as a first run, which arms the sweep it exists to stop"
            ) {
                _ = try await store.loadRoleBaseline()
            }

        default:
            try expect(false, behaviour, "this behaviour does not need a corruption probe")
        }
    }
}
