import Foundation

/// The whole reserve previewed at one moment, having moved nothing.
///
/// Built by ``ReserveConfiguration/audit(schedule:eligibleUnits:nextEpoch:spentBaseUnits:incompleteRecipients:potBaseUnits:limits:)``.
/// Everything on it is a figure an operator can read before deciding to go
/// ahead, which is the only moment at which any of it can still be changed.
public struct ReserveAudit: Sendable, Equatable {

    // MARK: - Properties

    /// What the reserve is denominated in.
    public let asset: ReserveAsset

    /// The whole reserve in smallest units.
    public let reserveBaseUnits: UInt64

    /// The chosen duration, or nil when nobody has chosen one yet.
    public let selectedSchedule: ReserveSchedule?

    /// The duration the figures below were computed with. Equal to
    /// ``selectedSchedule`` when there is one; otherwise an illustration, and
    /// the nil above is what says so.
    public let effectiveSchedule: ReserveSchedule

    /// One projection per configured stream, in configuration order.
    public let projections: [ReserveStreamProjection]

    /// The epoch each stream would pay next, keyed by stream id.
    public let nextEpoch: [String: UInt64]

    /// Smallest units already paid out of each allocation.
    public let spentBaseUnits: [String: UInt64]

    /// Recipients whose eligibility could not be read, per stream. Any is an
    /// abort for a live run.
    public let incompleteRecipients: [String: Int]

    /// What the paying account holds, or nil when it was not read.
    public let potBaseUnits: UInt64?

    /// Spending limits, or nil when they were not read.
    public let limits: ReserveSpendLimits?

    // MARK: - Initializers

    public init(
        asset: ReserveAsset,
        reserveBaseUnits: UInt64,
        selectedSchedule: ReserveSchedule?,
        effectiveSchedule: ReserveSchedule,
        projections: [ReserveStreamProjection],
        nextEpoch: [String: UInt64] = [:],
        spentBaseUnits: [String: UInt64] = [:],
        incompleteRecipients: [String: Int] = [:],
        potBaseUnits: UInt64? = nil,
        limits: ReserveSpendLimits? = nil
    ) {
        self.asset = asset
        self.reserveBaseUnits = reserveBaseUnits
        self.selectedSchedule = selectedSchedule
        self.effectiveSchedule = effectiveSchedule
        self.projections = projections
        self.nextEpoch = nextEpoch
        self.spentBaseUnits = spentBaseUnits
        self.incompleteRecipients = incompleteRecipients
        self.potBaseUnits = potBaseUnits
        self.limits = limits
    }

    // MARK: - Public Methods

    /// The projection for one stream, if it is configured.
    public func projection(_ streamId: String) -> ReserveStreamProjection? {
        projections.first { $0.stream.id == streamId }
    }

    /// Projected full-schedule spend across every stream.
    public var projectedSpendBaseUnits: UInt64 {
        projections.reduce(UInt64(0)) { saturatingAdd($0, $1.projectedSpendBaseUnits) }
    }

    /// Allocation in use across every stream: the round figure before rounding.
    public var allocationInUseBaseUnits: UInt64 {
        projections.reduce(UInt64(0)) { saturatingAdd($0, $1.allocationInUseBaseUnits) }
    }

    /// Rounding across every stream that is never paid.
    public var projectedResidueBaseUnits: UInt64 {
        projections.reduce(UInt64(0)) { saturatingAdd($0, $1.projectedResidueBaseUnits) }
    }

    /// Reserve minus the allocation in use.
    public var unusedReserveBaseUnits: UInt64 {
        reserveBaseUnits - min(allocationInUseBaseUnits, reserveBaseUnits)
    }

    /// Smallest units every stream pays in the epoch each is next due to run.
    public var nextEpochSpendBaseUnits: UInt64 {
        projections.reduce(UInt64(0)) { total, projection in
            saturatingAdd(total, projection.epochSpendBaseUnits(epoch: epoch(for: projection)))
        }
    }

    /// Whole units the next epoch charges against a whole-unit limit.
    ///
    /// The sum of the per-payment round-ups, because that is how the charge
    /// actually lands. One round-up of the total understates it by up to a whole
    /// unit per payee.
    public var nextEpochLimitCostWholeUnits: UInt64 {
        projections.reduce(UInt64(0)) { total, projection in
            saturatingAdd(
                total,
                projection.epochLimitCostWholeUnits(epoch: epoch(for: projection), asset: asset)
            )
        }
    }

    /// Epochs the pot can still cover at the current counts, or nil when the pot
    /// was not read or nothing is due.
    public var runwayEpochs: UInt64? {
        guard let potBaseUnits else { return nil }
        return ReserveConfiguration.runwayEpochs(
            potBaseUnits: potBaseUnits,
            epochSpendBaseUnits: nextEpochSpendBaseUnits
        )
    }

    /// Epochs of this schedule no stream has run yet.
    public var epochsRemaining: UInt64 {
        guard selectedSchedule != nil else { return 0 }
        // `nextEpoch` is caller-supplied, and `UInt64(0) - 1` traps and takes the
        // process with it.
        let done = projections
            .map { max(epoch(for: $0), 1) - 1 }
            .min() ?? 0
        return effectiveSchedule.epochCount > done ? effectiveSchedule.epochCount - done : 0
    }

    /// Recipients that could not be read, across every stream.
    public var totalIncompleteRecipients: Int {
        incompleteRecipients.values.reduce(0, +)
    }

    /// True when a live run would abort on an incomplete eligibility list.
    public var wouldAbortLiveRun: Bool { totalIncompleteRecipients > 0 }

    // MARK: - Private Methods

    private func epoch(for projection: ReserveStreamProjection) -> UInt64 {
        nextEpoch[projection.stream.id] ?? 1
    }

    private func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}
