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

    /// When the period these figures describe rolls over, when the host knows.
    ///
    /// Read by ``ReservePlanner/requireWithinLimits(plan:limits:now:)``, which
    /// refuses an epoch whose limits describe a period that has already ended.
    /// That is the one thing about the boundary this module can prove, and the
    /// distinction is worth being exact about.
    ///
    /// It cannot refuse an epoch that will not *finish* before the rollover:
    /// how long a list takes is a function of the host's payer, its network and
    /// its retries, none of which exist on this side of ``ReservePayer``.
    /// Refusing on an estimate would turn a guess into a payout that does not
    /// happen, which is worse than the thing being guarded against.
    ///
    /// It also does not need to. The whole epoch was checked against what is
    /// left of this period, which is at most one period's ceiling, so the part
    /// of a long run that lands after the rollover cannot by itself cross the
    /// next period's ceiling either. What no figure available before the run
    /// can rule out is the host's *own* other spending in that next period, and
    /// no field here would change that.
    ///
    /// What it does catch is the real one. A host that computes these figures
    /// from a stored total, or caches them, can hand over a `spentThisPeriod`
    /// belonging to a period that is over. Too high refuses an epoch that
    /// should have run; too low passes an epoch the host then refuses part way
    /// down the list, which is the half-finished payout. Nil means the host
    /// does not know when its period ends, and then nothing is checked.
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

    /// Whether these figures still describe the period `now` falls in.
    ///
    /// True when the host did not say when its period ends: an unstated
    /// boundary is not an expired one, and refusing every host that leaves
    /// ``periodEnd`` nil would refuse most of them.
    ///
    /// - Parameter now: The instant the run is starting at, as a parameter.
    ///   The module reads no clock of its own.
    public func describesPeriod(at now: Date) -> Bool {
        guard let periodEnd else { return true }
        return now < periodEnd
    }
}
