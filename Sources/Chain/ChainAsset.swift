import Foundation

/// The asset this layer reads balances of.
///
/// An operator brings their own. There is no default asset id, no default
/// symbol and, most importantly, **no default number of decimals**: the bot
/// this was taken from assumed six decimals in nine separate places, which
/// welded it to one token and would silently misreport every balance of an
/// asset with any other precision by a factor of ten per missing place.
///
/// Every figure in this layer is a whole number of the asset's smallest unit.
/// The asset is little more than the exchange rate between the number a person
/// says out loud and the number everything is actually computed in.
public struct ChainAsset: Sendable, Equatable, Hashable, Codable {

    // MARK: - Properties

    /// The on chain asset id.
    public let id: UInt64

    /// What the asset is called on a card.
    public let symbol: String

    /// Decimal places. Six means one whole unit is 1,000,000 smallest units.
    public let decimals: UInt8

    /// Smallest units in one whole unit: ten to the power of ``decimals``.
    public let baseUnitsPerWholeUnit: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: The on chain asset id. Zero is refused: on this chain zero names
    ///     the chain's own currency, which is not an asset an account opts into
    ///     and is not what this reads. An unset variable arriving here as zero
    ///     would otherwise report every member as holding nothing.
    ///   - symbol: The ticker shown to people.
    ///   - decimals: Decimal places, at most 19. Ten to the twentieth overflows
    ///     `UInt64`, so a larger value is refused here rather than trapping
    ///     somewhere downstream.
    public init(id: UInt64, symbol: String, decimals: UInt8) throws {
        guard id > 0 else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.assetId,
                value: "0",
                expected: "an asset id greater than zero"
            )
        }
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ChainConfigurationError.missing(variable: ChainEnvironment.assetSymbol)
        }
        guard decimals <= 19 else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.assetDecimals,
                value: String(decimals),
                expected: "0 to 19 decimal places"
            )
        }
        var scale: UInt64 = 1
        for _ in 0..<decimals {
            scale *= 10
        }
        self.id = id
        self.symbol = trimmed
        self.decimals = decimals
        self.baseUnitsPerWholeUnit = scale
    }

    // MARK: - Public Methods

    /// Whole units converted to smallest units.
    ///
    /// Throws rather than wrapping: a threshold that overflowed silently would
    /// be a threshold far below the one the operator typed, and everybody would
    /// clear it.
    public func baseUnits(whole: UInt64) throws -> UInt64 {
        let (product, overflow) = whole.multipliedReportingOverflow(by: baseUnitsPerWholeUnit)
        guard !overflow else {
            throw ChainConfigurationError.amountOverflows(whole: whole, decimals: decimals)
        }
        return product
    }

    /// Smallest units as whole units, rounded down.
    public func wholeUnits(baseUnits: UInt64) -> UInt64 {
        baseUnits / baseUnitsPerWholeUnit
    }

    /// The amount written out with every digit intact.
    public func format(_ baseUnits: UInt64) -> String {
        ChainFormatting.amount(baseUnits, decimals: Int(decimals))
    }

    /// The amount written out with the symbol after it.
    public func formatWithSymbol(_ baseUnits: UInt64) -> String {
        "\(format(baseUnits)) \(symbol)"
    }
}
