import Foundation

/// What one stream would spend over a whole schedule, and what it leaves behind.
///
/// Two figures here look like they should be the same and are deliberately not.
/// *Allocation in use* is the round number the denominator entitles the eligible
/// slots to. *Projected spend* is what will actually leave, which is smaller by
/// the rounding residue. Reporting only one of them is how a reserve ends up
/// with an unexplained balance nobody can account for.
public struct ReserveStreamProjection: Sendable, Equatable {

    // MARK: - Properties

    /// The stream projected.
    public let stream: ReserveStream

    /// The schedule projected over.
    public let schedule: ReserveSchedule

    /// Slots currently eligible, counted by the stream's rule.
    public let eligibleUnits: UInt64

    /// The fixed denominator. Never the eligible count.
    public let denominator: UInt64

    /// The whole allocation in smallest units.
    public let allocationBaseUnits: UInt64

    /// One slot's nominal share: what the denominator entitles it to.
    public let perUnitShareBaseUnits: UInt64

    /// What one slot is actually paid across the schedule.
    public let perUnitPaidBaseUnits: UInt64

    /// How that share is cut into epochs.
    public let split: ReserveEpochSplit

    /// `min(eligible, denominator) × perUnitShareBaseUnits`: the round figure.
    public let allocationInUseBaseUnits: UInt64

    /// `min(eligible, denominator) × perUnitPaidBaseUnits`: what really goes out.
    public let projectedSpendBaseUnits: UInt64

    /// Allocation in use minus projected spend: rounding that stays behind.
    public let projectedResidueBaseUnits: UInt64

    /// Allocation for slots nobody claims, plus anything the denominator itself
    /// would not divide. Stays in the reserve.
    public let unusedAllocationBaseUnits: UInt64

    /// Denominator slots no eligible unit claims.
    public let unusedSlots: UInt64

    /// Eligible units beyond the denominator. Non-zero means the stream cannot
    /// pay them all, and a live run will refuse rather than pay a short list.
    public let overflowUnits: UInt64

    /// What the denominator would not divide: `allocation % denominator`.
    ///
    /// Included in ``unusedAllocationBaseUnits``. Usually zero, and worth
    /// showing when it is not, because it is the one part of an unspent
    /// allocation that no arrival can ever claim.
    public let undividedAllocationBaseUnits: UInt64

    // MARK: - Initializers

    public init(
        stream: ReserveStream,
        schedule: ReserveSchedule,
        eligibleUnits: UInt64,
        denominator: UInt64,
        allocationBaseUnits: UInt64,
        perUnitShareBaseUnits: UInt64,
        perUnitPaidBaseUnits: UInt64,
        split: ReserveEpochSplit,
        allocationInUseBaseUnits: UInt64,
        projectedSpendBaseUnits: UInt64,
        projectedResidueBaseUnits: UInt64,
        unusedAllocationBaseUnits: UInt64,
        unusedSlots: UInt64,
        overflowUnits: UInt64,
        undividedAllocationBaseUnits: UInt64
    ) {
        self.stream = stream
        self.schedule = schedule
        self.eligibleUnits = eligibleUnits
        self.denominator = denominator
        self.allocationBaseUnits = allocationBaseUnits
        self.perUnitShareBaseUnits = perUnitShareBaseUnits
        self.perUnitPaidBaseUnits = perUnitPaidBaseUnits
        self.split = split
        self.allocationInUseBaseUnits = allocationInUseBaseUnits
        self.projectedSpendBaseUnits = projectedSpendBaseUnits
        self.projectedResidueBaseUnits = projectedResidueBaseUnits
        self.unusedAllocationBaseUnits = unusedAllocationBaseUnits
        self.unusedSlots = unusedSlots
        self.overflowUnits = overflowUnits
        self.undividedAllocationBaseUnits = undividedAllocationBaseUnits
    }

    // MARK: - Public Methods

    /// Everything that stays behind: unclaimed slots plus rounding residue.
    public var staysInReserveBaseUnits: UInt64 {
        let (sum, overflow) = unusedAllocationBaseUnits
            .addingReportingOverflow(projectedResidueBaseUnits)
        return overflow ? UInt64.max : sum
    }

    /// Smallest units one slot is paid in `epoch`.
    public func perUnitPayoutBaseUnits(epoch: UInt64) -> UInt64 {
        split.payout(epoch: epoch)
    }

    /// Smallest units the whole stream pays in `epoch` at the current count.
    public func epochSpendBaseUnits(epoch: UInt64) -> UInt64 {
        let payable = min(eligibleUnits, denominator)
        let (product, overflow) = split.payout(epoch: epoch).multipliedReportingOverflow(by: payable)
        return overflow ? UInt64.max : product
    }

    /// Whole units this stream's `epoch` charges against a whole-unit limit.
    ///
    /// The sum of the per-payment round-ups, not one round-up of the total.
    /// Rounding the total instead understates the charge by up to one whole unit
    /// per payee, on the very figure whose job is to warn about the limit.
    public func epochLimitCostWholeUnits(epoch: UInt64, asset: ReserveAsset) -> UInt64 {
        let perSlot = asset.wholeUnitsRoundingUp(baseUnits: perUnitPayoutBaseUnits(epoch: epoch))
        let slots = min(eligibleUnits, denominator)
        let (product, overflow) = perSlot.multipliedReportingOverflow(by: slots)
        return overflow ? UInt64.max : product
    }
}
