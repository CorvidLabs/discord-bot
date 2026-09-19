import Foundation

/// Why this layer refused to start.
///
/// Every case names the variable an operator has to set or correct. Finding out
/// the setup is wrong at boot, from a message naming the thing to fix, is the
/// whole point: the alternative is a bot that comes up looking healthy and
/// tells a member they hold nothing.
public enum ChainConfigurationError: Error, Equatable, LocalizedError, Sendable {

    /// A required variable is not set. There is deliberately no fallback.
    case missing(variable: String)

    /// A variable is set to something this cannot use.
    case invalidValue(variable: String, value: String, expected: String)

    /// Whole units times the asset's scale does not fit in `UInt64`.
    case amountOverflows(whole: UInt64, decimals: UInt8)

    /// A pool names an asset that is neither of its two sides.
    case poolCountsAnAssetItDoesNotHold(poolId: String, assetId: UInt64)

    /// Two pools share an id, so one of them would be silently dropped.
    case duplicatePoolId(String)

    public var errorDescription: String? {
        switch self {
        case .missing(let variable):
            return "\(variable) is required and is not set. There is no default: a default here would be "
                + "somebody else's asset, and every balance read would be wrong rather than absent."
        case .invalidValue(let variable, let value, let expected):
            return "\(variable) is set to `\(value)`, which is not usable. Expected \(expected)."
        case .amountOverflows(let whole, let decimals):
            return "\(ChainFormatting.grouped(whole)) whole units at \(decimals) decimal places does not fit "
                + "in a 64 bit count of smallest units."
        case .poolCountsAnAssetItDoesNotHold(let poolId, let assetId):
            return "Pool `\(poolId)` is configured to count asset \(assetId) toward a balance, but that asset "
                + "is neither side of the pair. Nothing would ever be counted from it."
        case .duplicatePoolId(let poolId):
            return "Two pools are configured with the id `\(poolId)`. Give each pool its own id."
        }
    }
}
