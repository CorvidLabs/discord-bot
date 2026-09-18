import Foundation

/// What the reserve is denominated in.
///
/// The engine only ever deals in whole numbers of the smallest unit. An asset is
/// therefore little more than the exchange rate between the unit a person says
/// out loud ("seven million") and the unit everything is actually computed in
/// ("seven million times ten to the sixth"), plus enough information to write
/// one back out as the other without losing a digit.
///
/// The number of decimals is configuration. Hard-coding six, as the original
/// did, quietly welds the engine to one token.
public struct ReserveAsset: Sendable, Equatable, Hashable, Codable {

    // MARK: - Properties

    /// What the asset is called on a card: `USDC`, `credits`, `points`.
    public let symbol: String

    /// Decimal places. Six means one whole unit is 1,000,000 smallest units.
    public let decimals: UInt8

    /// Smallest units in one whole unit: ten to the power of `decimals`.
    public let baseUnitsPerWholeUnit: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - symbol: The ticker or name shown to people.
    ///   - decimals: Decimal places, at most 19. Ten to the twentieth overflows
    ///     `UInt64`, so a larger value is refused here rather than trapping
    ///     somewhere downstream.
    public init(symbol: String, decimals: UInt8) throws {
        guard decimals <= 19 else {
            throw ReserveConfigurationError.unsupportedDecimals(decimals)
        }
        var scale: UInt64 = 1
        for _ in 0..<decimals {
            scale *= 10
        }
        self.symbol = symbol
        self.decimals = decimals
        self.baseUnitsPerWholeUnit = scale
    }

    // MARK: - Public Methods

    /// Whole units converted to smallest units.
    ///
    /// Throws rather than wrapping: a reserve total that overflowed silently
    /// would be a ceiling far below the one the operator typed.
    public func baseUnits(whole: UInt64) throws -> UInt64 {
        let (product, overflow) = whole.multipliedReportingOverflow(by: baseUnitsPerWholeUnit)
        guard !overflow else {
            throw ReserveConfigurationError.amountOverflows(whole: whole, decimals: decimals)
        }
        return product
    }

    /// Smallest units as whole units, rounded **up**.
    ///
    /// For charging against a limit that counts whole units. Rounding up is not
    /// a detail: a payment of 269,230.76923 recorded as 269,230 spent lets a
    /// long run slip past its own ceiling a fraction at a time, on the very
    /// check whose job is to stop that.
    public func wholeUnitsRoundingUp(baseUnits: UInt64) -> UInt64 {
        let whole = baseUnits / baseUnitsPerWholeUnit
        return baseUnits % baseUnitsPerWholeUnit == 0 ? whole : whole + 1
    }

    /// The amount written out with every digit intact.
    public func format(_ baseUnits: UInt64) -> String {
        ReserveFormatting.amount(baseUnits, decimals: Int(decimals))
    }

    /// The amount written out with the symbol after it.
    public func formatWithSymbol(_ baseUnits: UInt64) -> String {
        "\(format(baseUnits)) \(symbol)"
    }
}
