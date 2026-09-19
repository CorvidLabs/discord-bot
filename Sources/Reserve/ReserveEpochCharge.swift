import Foundation

/// One measurement of a run against the ceiling the host stated.
///
/// **This is the spending period, and it is not the cadence period.** Two
/// different periods live in this module and confusing them is the reason this
/// value exists. The cadence period is the week or month that stops one
/// schedule being paid twice, and it is kept in
/// ``ReserveState/lastPeriodKeys``. The spending period is the one the host's
/// own ceiling belongs to, stated on ``ReserveSpendLimits/periodKey``, and it
/// is the one an operator is asking about when a payout that ran from Sunday
/// evening into Monday has to be reconciled against a weekly cap.
///
/// Before this, that question was answerable only by subtracting two
/// timestamps and guessing which side of the boundary the check happened on,
/// which is wrong in exactly the case somebody is looking it up for.
///
/// The figure recorded is the one the planner already computed for the limits
/// check, so no new arithmetic appears anywhere, and it is the figure the run
/// was **checked** for rather than the figure that went out. A run that was
/// measured for a hundred and paid eighty really did take a hundred of the
/// ceiling's headroom at the moment it was allowed to start, and the record
/// says which is which by keeping the two on different values.
///
/// What is deliberately **not** here is the headroom that was left in the
/// ceiling at the time. It is the host's own figure, it is reconstructible
/// from the host's spend record, and the criterion asks which period a job was
/// counted against rather than how close it came.
public struct ReserveEpochCharge: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// The period key of the limits this run was measured against, exactly as
    /// the host stated it.
    ///
    /// Never derived from a clock, from either of the record's timestamps or
    /// from the cadence key. A derived value would be a confident lie in the
    /// boundary case.
    public let periodKey: String

    /// Whole units the run was checked for, as the planner computed them for
    /// the limits check.
    public let checkedWholeUnits: UInt64

    /// When the measurement was taken.
    ///
    /// For a reader putting two charges of a resumed epoch in context. The
    /// order the charges are stored in, not this instant, is what says which
    /// came first.
    public let recordedAt: Date

    // MARK: - Initializers

    /// - Parameters:
    ///   - periodKey: The period the ceiling belonged to.
    ///   - checkedWholeUnits: What the run was measured as costing.
    ///   - recordedAt: When the measurement was taken.
    public init(periodKey: String, checkedWholeUnits: UInt64, recordedAt: Date) {
        self.periodKey = periodKey
        self.checkedWholeUnits = checkedWholeUnits
        self.recordedAt = recordedAt
    }
}
