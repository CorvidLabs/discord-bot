import Foundation

/// Works out what one epoch still owes.
///
/// Pure. Hand it recipients and what the epoch has already paid and it answers
/// what is left. No clock, no network, no storage — which is what makes every
/// rule below something a test can pin rather than something a comment claims.
public struct ReservePlanner: Sendable {

    // MARK: - Properties

    /// The reserve being paid out.
    public let configuration: ReserveConfiguration

    // MARK: - Initializers

    public init(configuration: ReserveConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Public Methods

    /// Eligible slots in a recipient list, under one rule.
    ///
    /// A once-per-recipient stream counts **people**: one slot each, however
    /// many things they hold and however many accounts they spread them across.
    /// Counting accounts instead would pay somebody five times for splitting
    /// five holdings across five accounts and once for keeping them together,
    /// which is a five-fold exploit for anybody who noticed.
    ///
    /// A per-unit stream counts the things themselves. A holding id that a stale
    /// read shows on two accounts is counted once either way, so a preview
    /// cannot over-state what an epoch will pay.
    public static func eligibleUnits(
        rule: ReservePayoutRule,
        recipients: [ReserveRecipient]
    ) -> UInt64 {
        let holding = recipients.filter { !$0.holdsNothing }
        switch rule {
        case .oncePerRecipient:
            return UInt64(Set(holding.map(\.id)).count)
        case .oncePerHeldUnit:
            var seen: Set<String> = []
            for recipient in holding {
                for holdingId in recipient.holdingIds {
                    seen.insert(holdingId)
                }
            }
            return UInt64(seen.count)
        }
    }

    /// Eligible slots for a configured stream.
    public func eligibleUnits(streamId: String, recipients: [ReserveRecipient]) throws -> UInt64 {
        Self.eligibleUnits(rule: try configuration.stream(streamId).rule, recipients: recipients)
    }

    /// Plans what one epoch still owes.
    ///
    /// The epoch record guards two different mistakes at once. An account
    /// already paid is skipped, which makes re-running a half-finished epoch
    /// safe. A holding already paid is skipped too, which is what stops a thing
    /// moving between two known accounts and being paid twice in the same epoch.
    ///
    /// - Parameters:
    ///   - streamId: The stream to plan.
    ///   - schedule: The chosen duration.
    ///   - epoch: Epoch number, from 1.
    ///   - recipients: Every readable account and what it holds.
    ///   - record: What this epoch has already paid.
    public func planEpoch(
        streamId: String,
        schedule: ReserveSchedule,
        epoch: UInt64,
        recipients: [ReserveRecipient],
        record: ReserveEpochRecord
    ) throws -> ReserveEpochPlan {
        guard epoch >= 1, epoch <= schedule.epochCount else {
            throw ReserveError.epochOutOfRange(epoch: epoch, count: schedule.epochCount)
        }
        let stream = try configuration.stream(streamId)
        let perUnit = try configuration
            .epochSplit(streamId: streamId, schedule: schedule)
            .payout(epoch: epoch)

        // All three are `var` and all three are updated as the plan is built. A
        // `let` here would only catch what a *previous* run paid, so two rows
        // for one account — or one person's two accounts — would both be paid
        // inside a single plan.
        var paidAccounts = record.paidAccountSet
        var paidRecipients = record.paidRecipientIdSet
        var claimed = record.claimedHoldingIdSet

        var entries: [ReserveEpochEntry] = []
        var skipped: [ReserveSkippedRecipient] = []

        // Deterministic order: the same facts always produce the same plan,
        // which is what makes a contested holding resolve the same way twice and
        // lets a test name the winner.
        let ordered = recipients.sorted {
            if $0.account != $1.account { return $0.account < $1.account }
            return $0.id < $1.id
        }

        for recipient in ordered {
            guard !recipient.holdsNothing else {
                skipped.append(
                    ReserveSkippedRecipient(
                        recipientId: recipient.id,
                        account: recipient.account,
                        reason: .holdsNothing
                    )
                )
                continue
            }
            guard !paidAccounts.contains(recipient.account) else {
                skipped.append(
                    ReserveSkippedRecipient(
                        recipientId: recipient.id,
                        account: recipient.account,
                        reason: .accountAlreadyPaid
                    )
                )
                continue
            }
            // A once-per-recipient stream pays a person once per epoch. A
            // per-unit stream pays per holding, so a person's second account is
            // a second line there.
            if stream.rule == .oncePerRecipient, paidRecipients.contains(recipient.id) {
                skipped.append(
                    ReserveSkippedRecipient(
                        recipientId: recipient.id,
                        account: recipient.account,
                        reason: .recipientAlreadyPaid
                    )
                )
                continue
            }
            let unclaimed = recipient.holdingIds.filter { !claimed.contains($0) }
            guard !unclaimed.isEmpty else {
                skipped.append(
                    ReserveSkippedRecipient(
                        recipientId: recipient.id,
                        account: recipient.account,
                        reason: .holdingsAlreadyClaimed
                    )
                )
                continue
            }
            // A once-per-recipient stream collapses an account's holdings into
            // one slot; a per-unit stream pays each. Either way *all* of them are
            // claimed, so a transfer later in the epoch cannot buy a second
            // payment.
            let units: UInt64 = stream.rule == .oncePerRecipient ? 1 : UInt64(unclaimed.count)
            let (amount, overflow) = perUnit.multipliedReportingOverflow(by: units)
            guard !overflow else {
                throw ReserveError.allocationExhausted(
                    streamId: streamId,
                    spent: record.paidBaseUnits,
                    allocation: try configuration.allocationBaseUnits(streamId)
                )
            }
            for holdingId in unclaimed {
                claimed.insert(holdingId)
            }
            paidAccounts.insert(recipient.account)
            paidRecipients.insert(recipient.id)
            entries.append(
                ReserveEpochEntry(
                    recipientId: recipient.id,
                    account: recipient.account,
                    units: units,
                    baseUnitsAmount: amount,
                    claimedHoldingIds: unclaimed
                )
            )
        }

        return ReserveEpochPlan(
            streamId: streamId,
            schedule: schedule,
            epoch: epoch,
            perUnitBaseUnits: perUnit,
            entries: entries,
            skipped: skipped
        )
    }

    /// Plans an epoch and refuses it if it would cross a denominator, an
    /// allocation, or an epoch that is already finished.
    ///
    /// This, not ``planEpoch(streamId:schedule:epoch:recipients:record:)``, is
    /// what a live run plans through. An epoch with nobody left to pay is
    /// refused rather than reported as a success, because "paid nobody" and
    /// "succeeded" should never be the same outcome.
    public func planGuardedEpoch(
        streamId: String,
        schedule: ReserveSchedule,
        epoch: UInt64,
        recipients: [ReserveRecipient],
        record: ReserveEpochRecord,
        alreadySpentBaseUnits: UInt64
    ) throws -> ReserveEpochPlan {
        guard !record.isComplete else {
            throw ReserveError.epochAlreadyPaid(streamId: streamId, epoch: epoch)
        }
        try configuration.requireWithinDenominator(
            streamId: streamId,
            eligibleUnits: try eligibleUnits(streamId: streamId, recipients: recipients)
        )
        let plan = try planEpoch(
            streamId: streamId,
            schedule: schedule,
            epoch: epoch,
            recipients: recipients,
            record: record
        )
        try configuration.requireWithinAllocation(
            streamId: streamId,
            alreadySpentBaseUnits: alreadySpentBaseUnits,
            plannedBaseUnits: plan.totalBaseUnits
        )
        guard !plan.entries.isEmpty else {
            throw ReserveError.nothingToPay(streamId: streamId, epoch: epoch)
        }
        return plan
    }

    /// Refuses an epoch the paying account's limits cannot carry.
    ///
    /// Checked before the first payment, never discovered on the twelfth. The
    /// period limit is measured against what is *left* of it rather than the raw
    /// ceiling, because something else may already have spent part of it.
    public func requireWithinLimits(plan: ReserveEpochPlan, limits: ReserveSpendLimits) throws {
        for entry in plan.entries {
            let cost = configuration.asset.wholeUnitsRoundingUp(baseUnits: entry.baseUnitsAmount)
            if cost > limits.maxPerPaymentWholeUnits {
                throw ReserveError.overPaymentLimit(
                    requested: cost,
                    limit: limits.maxPerPaymentWholeUnits
                )
            }
        }
        let total = plan.limitCostWholeUnits(asset: configuration.asset)
        if total > limits.remainingThisPeriodWholeUnits {
            throw ReserveError.overPeriodLimit(
                total: total,
                remaining: limits.remainingThisPeriodWholeUnits,
                limit: limits.maxPerPeriodWholeUnits
            )
        }
    }
}
