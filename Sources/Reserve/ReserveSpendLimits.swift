import Foundation

/// What the paying account is allowed to move, in whole units.
///
/// Limits are the host's, not the reserve's: they belong to whatever holds the
/// money and they usually apply to everything it does, not only to this
/// schedule. The engine's only interest is checking an epoch against them
/// *before* the first payment rather than discovering the ceiling half way down
/// the list, because an epoch that paid a hundred and eleven of two hundred
/// recipients is exactly the half-finished payout the whole design exists to
/// prevent.
///
/// Whole units rather than smallest units because that is how such limits are
/// almost always written down, and because each payment is charged rounded up.
public struct ReserveSpendLimits: Sendable, Equatable {

    // MARK: - Properties

    /// Most one payment may move.
    public let maxPerPaymentWholeUnits: UInt64

    /// Most the account may move in one period.
    public let maxPerPeriodWholeUnits: UInt64

    /// What has already gone this period, from every source, not just this
    /// reserve. That is the point: an ordinary transfer earlier in the same
    /// period has already eaten some of the ceiling.
    public let spentThisPeriodWholeUnits: UInt64

    /// The period these figures describe.
    public let periodKey: String

    /// When the period rolls over, when the host knows.
    public let periodEnd: Date?

    // MARK: - Initializers

    public init(
        maxPerPaymentWholeUnits: UInt64,
        maxPerPeriodWholeUnits: UInt64,
        spentThisPeriodWholeUnits: UInt64,
        periodKey: String,
        periodEnd: Date? = nil
    ) {
        self.maxPerPaymentWholeUnits = maxPerPaymentWholeUnits
        self.maxPerPeriodWholeUnits = maxPerPeriodWholeUnits
        self.spentThisPeriodWholeUnits = spentThisPeriodWholeUnits
        self.periodKey = periodKey
        self.periodEnd = periodEnd
    }

    // MARK: - Public Methods

    /// What is left of this period's ceiling. Never negative.
    ///
    /// Measuring against this rather than the raw ceiling is the whole value of
    /// the type. A run that fits `maxPerPeriodWholeUnits` but not what is left
    /// of it will still be refused mid-list, which is the failure being avoided.
    public var remainingThisPeriodWholeUnits: UInt64 {
        maxPerPeriodWholeUnits >= spentThisPeriodWholeUnits
            ? maxPerPeriodWholeUnits - spentThisPeriodWholeUnits
            : 0
    }
}
