import Foundation

/// One stream's slice of the reserve, as an exact fraction.
///
/// A fraction rather than a percentage or a decimal, because the reserve is
/// split once and then never again, and the split has to be provably exact. Two
/// streams at `70/100` and `30/100` of ten billion are seven billion and three
/// billion with nothing left over, and the configuration refuses to exist if
/// that is not true — see ``ReserveConfiguration``.
public struct ReserveShare: Sendable, Equatable, Hashable, Codable {

    // MARK: - Properties

    /// The top of the fraction.
    public let numerator: UInt64

    /// The bottom of the fraction. Never zero.
    public let denominator: UInt64

    // MARK: - Initializers

    /// `ReserveShare(70, of: 100)` is seventy percent.
    public init(_ numerator: UInt64, of denominator: UInt64) {
        self.numerator = numerator
        self.denominator = denominator
    }

    // MARK: - Public Methods

    /// `ReserveShare.percent(70)`.
    public static func percent(_ value: UInt64) -> ReserveShare {
        ReserveShare(value, of: 100)
    }

    /// The whole reserve, for a single-stream configuration.
    public static let whole = ReserveShare(1, of: 1)

    /// This fraction of `total`, or nil when it is not a whole number of them.
    ///
    /// Nil covers both refusals, and both are configuration mistakes worth
    /// stopping for: a fraction that leaves a remainder would lose smallest
    /// units nobody could later account for, and one that overflows would
    /// produce an allocation smaller than the one that was asked for.
    ///
    /// The division is done before the multiplication wherever it is exact,
    /// which keeps realistic reserves far away from the top of `UInt64`.
    public func amount(of total: UInt64) -> UInt64? {
        guard denominator > 0 else { return nil }
        let quotient = total / denominator
        if total % denominator == 0 {
            let (product, overflow) = quotient.multipliedReportingOverflow(by: numerator)
            return overflow ? nil : product
        }
        let (product, overflow) = total.multipliedReportingOverflow(by: numerator)
        guard !overflow, product % denominator == 0 else { return nil }
        return product / denominator
    }

    /// `70/100` for a card.
    public var description: String { "\(numerator)/\(denominator)" }
}
