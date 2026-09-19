import Foundation
import Testing
@testable import Reserve

/// Who gets paid, how much, and who does not.
///
/// These are the tests that would fail if a guard were removed, which is the
/// only real measure of whether a guard is doing anything.
@Suite("Reserve planning")
struct ReservePlanningTests {

    private static let epochStart = Date(timeIntervalSince1970: 0)
    private static let now = Date(timeIntervalSince1970: 1_758_000_000)

    // MARK: - Counting eligible slots

    @Test("A once-per-recipient stream counts people; a per-unit stream counts things (RESERVE-4.a, RESERVE-4.b)")
    func eligibleUnitCounting() {
        let recipients = [
            ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1", "H2", "H3"]),
            ReserveRecipient(id: "R1", account: "ACCOUNT-B", holdingIds: ["H4"]),
            ReserveRecipient(id: "R2", account: "ACCOUNT-C", holdingIds: [])
        ]
        // R1 holds things on two accounts: one person, one slot.
        #expect(
            ReservePlanner.eligibleUnits(rule: .oncePerRecipient, recipients: recipients) == 1
        )
        #expect(ReservePlanner.eligibleUnits(rule: .oncePerHeldUnit, recipients: recipients) == 4)

        // A stale read showing the same thing on two accounts counts it once, so
        // a preview cannot over-state what an epoch will pay.
        let duplicated = [
            ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1"]),
            ReserveRecipient(id: "R2", account: "ACCOUNT-B", holdingIds: ["H1"])
        ]
        #expect(ReservePlanner.eligibleUnits(rule: .oncePerHeldUnit, recipients: duplicated) == 1)
    }

    // MARK: - Once per recipient

    @Test("An account holding three things is paid once by a once-per-recipient stream (RESERVE-4.a)")
    func multipleHoldingsOnePayment() throws {
        let planner = try Fixture.planner()
        let plan = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: [
                ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H11", "H12", "H13"])
            ],
            record: Fixture.epoch(Fixture.members, 1)
        )
        #expect(plan.entries.count == 1)
        #expect(plan.entries.first?.units == 1)
        #expect(plan.entries.first?.baseUnitsAmount == 269_230_769_230)
        #expect(plan.totalBaseUnits == 269_230_769_230)
        // All three are claimed even though one slot was paid, so none of them
        // can buy a second payment later in the epoch.
        #expect(plan.entries.first?.claimedHoldingIds == ["H11", "H12", "H13"])
    }

    @Test("A person is paid once however many accounts they split across (RESERVE-4.a)")
    func recipientPaidOncePerEpoch() throws {
        let planner = try Fixture.planner()
        // Five things in five accounts, all one person. Paying per account would
        // pay them five times for splitting and once for keeping them together:
        // a five-fold exploit for anybody who noticed.
        let split = (1...5).map { index in
            ReserveRecipient(id: "R1", account: Fixture.account(index), holdingIds: ["H\(index)"])
        }
        #expect(ReservePlanner.eligibleUnits(rule: .oncePerRecipient, recipients: split) == 1)
        let plan = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: split,
            record: Fixture.epoch(Fixture.members, 1)
        )
        #expect(plan.entries.count == 1)
        #expect(plan.totalBaseUnits == 269_230_769_230)
        #expect(plan.skipped.map(\.reason) == Array(repeating: .recipientAlreadyPaid, count: 4))

        // Consolidated into one account: the same single payment.
        let consolidated = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: [
                ReserveRecipient(
                    id: "R1",
                    account: Fixture.account(1),
                    holdingIds: ["H1", "H2", "H3", "H4", "H5"]
                )
            ],
            record: Fixture.epoch(Fixture.members, 1)
        )
        #expect(consolidated.totalBaseUnits == plan.totalBaseUnits)
    }

    @Test("A new eligible recipient leaves the existing payment alone (RESERVE-3.b)")
    func newRecipientDoesNotDilute() throws {
        let planner = try Fixture.planner()
        let alone = [ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1"])]
        let crowded = alone + (0..<900).map { index in
            ReserveRecipient(
                id: "R\(index + 2)",
                account: "ACCOUNT-B\(index)",
                holdingIds: ["H\(index + 100)"]
            )
        }
        func paymentForA(_ recipients: [ReserveRecipient]) throws -> UInt64? {
            try planner.planEpoch(
                streamId: Fixture.members,
                schedule: Fixture.sixMonths(),
                epoch: 7,
                recipients: recipients,
                record: Fixture.epoch(Fixture.members, 7)
            )
            .entries
            .first { $0.account == "ACCOUNT-A" }?
            .baseUnitsAmount
        }
        let before = try paymentForA(alone)
        let after = try paymentForA(crowded)
        #expect(before == after)
        #expect(before == 269_230_769_230)
    }

    // MARK: - Per held unit

    @Test("An account with five things gets five shares (RESERVE-4.b)")
    func perUnitPaysPerHolding() throws {
        let planner = try Fixture.planner()
        let plan = try planner.planEpoch(
            streamId: Fixture.passes,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: [
                ReserveRecipient(
                    id: "R1",
                    account: "ACCOUNT-A",
                    holdingIds: ["H1", "H2", "H3", "H4", "H5"]
                )
            ],
            record: Fixture.epoch(Fixture.passes, 1)
        )
        #expect(plan.entries.count == 1)
        #expect(plan.entries.first?.units == 5)
        #expect(plan.entries.first?.baseUnitsAmount == 28_170_072_115 * 5)
    }

    @Test("A per-unit stream still pays a person per thing across every account (RESERVE-4.b)")
    func perUnitNotCappedByRecipient() throws {
        let planner = try Fixture.planner()
        let split = (1...3).map { index in
            ReserveRecipient(id: "R1", account: Fixture.account(index), holdingIds: ["H\(index)"])
        }
        #expect(ReservePlanner.eligibleUnits(rule: .oncePerHeldUnit, recipients: split) == 3)
        let plan = try planner.planEpoch(
            streamId: Fixture.passes,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: split,
            record: Fixture.epoch(Fixture.passes, 1)
        )
        #expect(plan.entries.count == 3)
        #expect(plan.totalUnits == 3)
    }

    @Test("A full denominator of holdings plans one epoch inside the allocation")
    func fullCollectionEpoch() throws {
        let planner = try Fixture.planner()
        let recipients = (0..<4_096).map { index in
            ReserveRecipient(
                id: "R\(index)",
                account: Fixture.account(index),
                holdingIds: ["H-\(index + 1)"]
            )
        }
        #expect(ReservePlanner.eligibleUnits(rule: .oncePerHeldUnit, recipients: recipients) == 4_096)
        let plan = try planner.planGuardedEpoch(
            streamId: Fixture.passes,
            schedule: Fixture.oneYear(),
            epoch: 1,
            recipients: recipients,
            record: Fixture.epoch(Fixture.passes, 1),
            alreadySpentBaseUnits: 0
        )
        #expect(plan.entries.count == 4_096)
        #expect(plan.totalUnits == 4_096)
        #expect(plan.totalBaseUnits == 14_085_036_057 * 4_096)
        #expect(plan.totalBaseUnits < (try planner.configuration.allocationBaseUnits(Fixture.passes)))
    }

    // MARK: - The transfer guard

    @Test("A holding moving mid-epoch cannot be paid twice (RESERVE-4.c, RESERVE-9.b)")
    func transferCannotDoublePay() throws {
        let planner = try Fixture.planner()
        var record = Fixture.epoch(Fixture.members, 3)
        let first = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 3,
            recipients: [ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H42"])],
            record: record
        )
        #expect(first.entries.count == 1)
        for entry in first.entries {
            record.claim(entry: entry, at: Self.epochStart)
        }
        #expect(record.claimedHoldingIds == ["H42"])

        // H42 is now on somebody else's known account, in the same epoch.
        let second = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 3,
            recipients: [ReserveRecipient(id: "R2", account: "ACCOUNT-B", holdingIds: ["H42"])],
            record: record
        )
        #expect(second.entries.isEmpty)
        #expect(second.skipped.map(\.reason) == [.holdingsAlreadyClaimed])
        #expect(second.totalBaseUnits == 0)
    }

    @Test("Re-running a half-finished epoch skips what it already paid (RESERVE-6.c)")
    func rerunSkipsPaid() throws {
        let planner = try Fixture.planner()
        let recipients = [
            ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1"]),
            ReserveRecipient(id: "R2", account: "ACCOUNT-B", holdingIds: ["H2"])
        ]
        var record = Fixture.epoch(Fixture.members, 1)
        let full = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.oneYear(),
            epoch: 1,
            recipients: recipients,
            record: record
        )
        #expect(full.entries.count == 2)
        // Only the first payment got away before the run stopped.
        if let first = full.entries.first {
            record.claim(entry: first, at: Self.epochStart)
        }
        let retry = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.oneYear(),
            epoch: 1,
            recipients: recipients,
            record: record
        )
        #expect(retry.entries.map(\.account) == ["ACCOUNT-B"])
        #expect(retry.skipped.map(\.reason) == [.accountAlreadyPaid])
    }

    @Test("Two rows for one account cannot both be paid in a single plan")
    func duplicateAccountRowsPaidOnce() throws {
        let planner = try Fixture.planner()
        // The guard once read a set captured before the loop, so it only caught
        // accounts a *previous* run had paid.
        let plan = try planner.planEpoch(
            streamId: Fixture.passes,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: [
                ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H10"]),
                ReserveRecipient(id: "R2", account: "ACCOUNT-A", holdingIds: ["H11"])
            ],
            record: Fixture.epoch(Fixture.passes, 1)
        )
        #expect(plan.entries.count == 1)
        #expect(plan.skipped.map(\.reason) == [.accountAlreadyPaid])
    }

    @Test("Holding in a known account is the whole eligibility rule (RESERVE-4.d)")
    func eligibilityIsHolding() throws {
        let planner = try Fixture.planner()
        let plan = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: [
                ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H7"]),
                ReserveRecipient(id: "R2", account: "ACCOUNT-B", holdingIds: [])
            ],
            record: Fixture.epoch(Fixture.members, 1)
        )
        #expect(plan.entries.map(\.account) == ["ACCOUNT-A"])
        #expect(plan.skipped.map(\.reason) == [.holdsNothing])
    }

    @Test("Epochs between a handover and the new holder being known pay nobody (RESERVE-4.e)")
    func handoverEpochsArePaidToNobody() throws {
        let planner = try Fixture.planner()
        var epochOne = Fixture.epoch(Fixture.members, 1)
        let paid = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            recipients: [ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H42"])],
            record: epochOne
        )
        #expect(paid.entries.count == 1)
        for entry in paid.entries {
            epochOne.claim(entry: entry, at: Self.epochStart)
        }

        // Epoch 2: sold, and the buyer is not known yet. Nobody is a candidate.
        #expect(throws: ReserveError.nothingToPay(streamId: Fixture.members, epoch: 2)) {
            try planner.planGuardedEpoch(
                streamId: Fixture.members,
                schedule: Fixture.sixMonths(),
                epoch: 2,
                recipients: [],
                record: Fixture.epoch(Fixture.members, 2),
                alreadySpentBaseUnits: epochOne.paidBaseUnits
            )
        }

        // Epoch 3: the buyer is known and is paid the same flat figure. The
        // epoch nobody could receive is simply never paid to anybody.
        let resumed = try planner.planEpoch(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 3,
            recipients: [ReserveRecipient(id: "R2", account: "ACCOUNT-B", holdingIds: ["H42"])],
            record: Fixture.epoch(Fixture.members, 3)
        )
        #expect(resumed.entries.first?.account == "ACCOUNT-B")
        #expect(resumed.entries.first?.baseUnitsAmount == 269_230_769_230)
        // Two of three epochs paid for this holding; epoch 2 stayed behind.
        #expect(epochOne.paidBaseUnits + resumed.totalBaseUnits == 269_230_769_230 * 2)
    }

    @Test("A plan is deterministic, so the same facts name the same winner")
    func planIsDeterministic() throws {
        let planner = try Fixture.planner()
        let contested = [
            ReserveRecipient(id: "R2", account: "ACCOUNT-Z", holdingIds: ["H1"]),
            ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1"])
        ]
        for _ in 0..<5 {
            let plan = try planner.planEpoch(
                streamId: Fixture.passes,
                schedule: Fixture.sixMonths(),
                epoch: 1,
                recipients: contested.shuffled(),
                record: Fixture.epoch(Fixture.passes, 1)
            )
            #expect(plan.entries.map(\.account) == ["ACCOUNT-A"])
            #expect(plan.skipped.map(\.account) == ["ACCOUNT-Z"])
        }
    }

    // MARK: - Guards

    @Test("More eligible units than slots refuses rather than overspending (RESERVE-3.d)")
    func denominatorGuard() throws {
        let reserve = try Fixture.reserve()
        #expect(
            throws: ReserveError.tooManyUnits(
                streamId: Fixture.members,
                eligible: 1_001,
                denominator: 1_000
            )
        ) {
            try reserve.requireWithinDenominator(streamId: Fixture.members, eligibleUnits: 1_001)
        }
        #expect(throws: Never.self) {
            try reserve.requireWithinDenominator(streamId: Fixture.members, eligibleUnits: 1_000)
        }
    }

    @Test("A plan that would cross the allocation is refused (RESERVE-1.d)")
    func allocationGuard() throws {
        let reserve = try Fixture.reserve()
        let allocation = try reserve.allocationBaseUnits(Fixture.members)
        #expect(throws: Never.self) {
            try reserve.requireWithinAllocation(
                streamId: Fixture.members,
                alreadySpentBaseUnits: allocation - 10,
                plannedBaseUnits: 10
            )
        }
        #expect(
            throws: ReserveError.allocationExhausted(
                streamId: Fixture.members,
                spent: allocation - 10,
                allocation: allocation
            )
        ) {
            try reserve.requireWithinAllocation(
                streamId: Fixture.members,
                alreadySpentBaseUnits: allocation - 10,
                plannedBaseUnits: 11
            )
        }
        // An overflowing addition is refused too, not wrapped into "fits".
        #expect(throws: (any Error).self) {
            try reserve.requireWithinAllocation(
                streamId: Fixture.members,
                alreadySpentBaseUnits: UInt64.max,
                plannedBaseUnits: 1
            )
        }
    }

    @Test("A finished epoch cannot be paid a second time (RESERVE-6.d)")
    func closedEpochRefuses() throws {
        let planner = try Fixture.planner()
        var record = Fixture.epoch(Fixture.members, 2)
        record.completedAt = Self.epochStart
        #expect(throws: ReserveError.epochAlreadyPaid(streamId: Fixture.members, epoch: 2)) {
            try planner.planGuardedEpoch(
                streamId: Fixture.members,
                schedule: Fixture.sixMonths(),
                epoch: 2,
                recipients: [ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1"])],
                record: record,
                alreadySpentBaseUnits: 0
            )
        }
    }

    @Test("An epoch with nobody left to pay refuses rather than reporting success")
    func emptyEpochRefuses() throws {
        let planner = try Fixture.planner()
        #expect(throws: ReserveError.nothingToPay(streamId: Fixture.passes, epoch: 1)) {
            try planner.planGuardedEpoch(
                streamId: Fixture.passes,
                schedule: Fixture.sixMonths(),
                epoch: 1,
                recipients: [],
                record: Fixture.epoch(Fixture.passes, 1),
                alreadySpentBaseUnits: 0
            )
        }
    }

    @Test("An epoch outside the schedule is refused by the planner too")
    func planEpochRangeChecked() throws {
        let planner = try Fixture.planner()
        #expect(throws: ReserveError.epochOutOfRange(epoch: 27, count: 26)) {
            try planner.planEpoch(
                streamId: Fixture.members,
                schedule: Fixture.sixMonths(),
                epoch: 27,
                recipients: [],
                record: Fixture.epoch(Fixture.members, 27)
            )
        }
    }

    // MARK: - Limits

    @Test("The limits are checked before the first payment, not on the twelfth (RESERVE-7.d)")
    func limitPreflight() throws {
        let planner = try Fixture.planner()
        let entries = (1...200).map { index in
            ReserveEpochEntry(
                recipientId: "R\(index)",
                account: "ACCOUNT-\(index)",
                units: 1,
                baseUnitsAmount: 269_230_769_230,
                claimedHoldingIds: ["H\(index)"]
            )
        }
        let plan = ReserveEpochPlan(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            perUnitBaseUnits: 269_230_769_230,
            entries: entries,
            skipped: []
        )
        // Each payment is rounded up, so the epoch charges 200 × 269,231.
        #expect(plan.limitCostWholeUnits(asset: planner.configuration.asset) == 269_231 * 200)

        func limits(perPayment: UInt64, perPeriod: UInt64, spent: UInt64) -> ReserveSpendLimits {
            ReserveSpendLimits(
                maxPerPaymentWholeUnits: perPayment,
                maxPerPeriodWholeUnits: perPeriod,
                spentThisPeriodWholeUnits: spent,
                periodKey: "2026-W38"
            )
        }
        // A tight per-payment limit: the very first payment would abort.
        #expect(throws: ReserveError.overPaymentLimit(requested: 269_231, limit: 1_000)) {
            try planner.requireWithinLimits(
                plan: plan,
                limits: limits(perPayment: 1_000, perPeriod: 400_000_000, spent: 0),
                now: Self.now
            )
        }
        // Fits the raw period ceiling, but the period is already part spent,
        // which is exactly the combination the remaining-based check exists for.
        #expect(throws: (any Error).self) {
            try planner.requireWithinLimits(
                plan: plan,
                limits: limits(perPayment: 300_000, perPeriod: 60_000_000, spent: 10_000_000),
                now: Self.now
            )
        }
        #expect(throws: Never.self) {
            try planner.requireWithinLimits(
                plan: plan,
                limits: limits(perPayment: 300_000, perPeriod: 400_000_000, spent: 10_000_000),
                now: Self.now
            )
        }
    }

    @Test("A ceiling is checked for being current before it is checked for being big enough")
    func expiredLimitsCheckedFirst() throws {
        let planner = try Fixture.planner()
        let plan = ReserveEpochPlan(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1,
            perUnitBaseUnits: 269_230_769_230,
            entries: [
                ReserveEpochEntry(
                    recipientId: "R1",
                    account: "ACCOUNT-0001",
                    units: 1,
                    baseUnitsAmount: 269_230_769_230,
                    claimedHoldingIds: ["H1"]
                )
            ],
            skipped: []
        )
        func limits(endingAt periodEnd: Date) -> ReserveSpendLimits {
            ReserveSpendLimits(
                maxPerPaymentWholeUnits: 1,
                maxPerPeriodWholeUnits: 1,
                spentThisPeriodWholeUnits: 0,
                periodKey: "2026-W38",
                periodEnd: periodEnd
            )
        }
        // The period ends on the instant the run starts, so the run is in the
        // next one. The size checks would refuse this plan too, and the point
        // is that they are not what answers: a stale ceiling is refused for
        // being stale, whichever way its numbers happen to fall.
        #expect(
            throws: ReserveError.spendLimitsExpired(
                periodKey: "2026-W38",
                periodEnd: Self.now,
                now: Self.now
            )
        ) {
            try planner.requireWithinLimits(plan: plan, limits: limits(endingAt: Self.now), now: Self.now)
        }
        // A second before the boundary the figures still describe the period
        // the run is in, and the ordinary size check answers.
        #expect(throws: ReserveError.overPaymentLimit(requested: 269_231, limit: 1)) {
            try planner.requireWithinLimits(
                plan: plan,
                limits: limits(endingAt: Self.now.addingTimeInterval(1)),
                now: Self.now
            )
        }
    }

    @Test("Limits with no stated end are never called expired")
    func undatedLimitsAreNotExpired() {
        let undated = ReserveSpendLimits(
            maxPerPaymentWholeUnits: 10,
            maxPerPeriodWholeUnits: 100,
            spentThisPeriodWholeUnits: 0,
            periodKey: "2026-W38"
        )
        #expect(undated.describesPeriod(at: Self.now))
        #expect(undated.describesPeriod(at: Self.now.addingTimeInterval(10_000_000)))
    }

    @Test("What is left of a period never goes below zero")
    func remainingNeverNegative() {
        let overspent = ReserveSpendLimits(
            maxPerPaymentWholeUnits: 10,
            maxPerPeriodWholeUnits: 100,
            spentThisPeriodWholeUnits: 500,
            periodKey: "2026-W38"
        )
        #expect(overspent.remainingThisPeriodWholeUnits == 0)
    }

    // MARK: - Recipient lists

    @Test("An incomplete list pays nobody (RESERVE-7.e)")
    func incompleteListAborts() {
        let list = ReserveRecipientList(
            streamId: Fixture.members,
            recipients: [ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1"])],
            incompleteRecipientIds: ["R2", "R3"],
            ineligibleCount: 4
        )
        #expect(list.wouldAbortLiveRun)
        #expect(throws: ReserveError.incompleteRecipients(2)) {
            try list.requireComplete()
        }
    }

    @Test("A complete list hands its recipients over and reports who is eligible")
    func completeListPasses() throws {
        let list = ReserveRecipientList(
            streamId: Fixture.members,
            recipients: [
                ReserveRecipient(id: "R1", account: "ACCOUNT-A", holdingIds: ["H1"]),
                ReserveRecipient(id: "R2", account: "ACCOUNT-B", holdingIds: [])
            ],
            ineligibleCount: 1
        )
        #expect(list.wouldAbortLiveRun == false)
        #expect(try list.requireComplete().count == 2)
        #expect(list.eligibleRecipientIds == ["R1"])
        #expect(list.eligibleUnits(rule: .oncePerRecipient) == 1)
    }

    @Test("Holding ids are deduplicated and sorted, so a plan is reproducible")
    func recipientNormalizesHoldings() {
        let recipient = ReserveRecipient(
            id: "R1",
            account: "ACCOUNT-A",
            holdingIds: ["H3", "H1", "H3", "H2"]
        )
        #expect(recipient.holdingIds == ["H1", "H2", "H3"])
        #expect(recipient.holdsNothing == false)
        #expect(ReserveRecipient(id: "R2", account: "ACCOUNT-B", holdingIds: []).holdsNothing)
    }
}
