import Foundation
import Gating

/// Turning whole tokens into smallest units when the number is an **amount**
/// rather than a **threshold**.
///
/// There is one token in this package, ``Gating/TokenProfile``, and the layer
/// above reads it from the environment once. This layer reuses it rather than
/// carrying a second asset of its own: two representations meant an operator
/// set the asset id twice and could set them differently, and two `decimals`
/// that disagreed would compute balances and thresholds at different
/// precisions. One decimal place out is a factor of ten on every rung of the
/// ladder.
///
/// What is **not** shared is the overflow behaviour, and the difference is
/// deliberate on both sides:
///
/// - ``Gating/TokenProfile/baseUnits(whole:)`` **saturates**. Its callers are
///   ladder thresholds. An operator who types too many zeros gets a rung
///   nobody reaches, which is visible in the server and fixable in a minute; a
///   wrapped `UInt64` would give them a rung everybody reaches, which is
///   neither.
/// - ``amountBaseUnits(whole:)`` below **throws**. Its callers are amounts. An
///   amount that saturated to `UInt64.max` would be a number nobody asked for,
///   and quietly clamping one is how a figure a person typed stops being the
///   figure the code uses.
///
/// The two are named apart rather than overloaded, because an overload picked
/// by context is exactly the wrong way to choose between refusing and
/// clamping.
extension TokenProfile {

    // MARK: - Public Methods

    /// Whole tokens converted to smallest units, refusing an amount that will
    /// not fit.
    ///
    /// Throws rather than saturating: see the note on this extension. Use
    /// ``Gating/TokenProfile/baseUnits(whole:)`` for a threshold, where a
    /// number too large is better as a rung nobody reaches than as a refusal.
    ///
    /// - Parameter whole: The amount, in whole tokens.
    /// - Returns: The same amount in the token's smallest unit.
    /// - Throws: ``ChainConfigurationError/amountOverflows(whole:decimals:)``
    ///   when the product does not fit in `UInt64`.
    public func amountBaseUnits(whole: UInt64) throws -> UInt64 {
        let (product, overflow) = whole.multipliedReportingOverflow(by: baseUnitsPerWholeUnit)
        guard !overflow else {
            throw ChainConfigurationError.amountOverflows(whole: whole, decimals: decimals)
        }
        return product
    }

    /// Smallest units as whole tokens, rounded down.
    ///
    /// Rounded down rather than to nearest, so a figure shown to a member is
    /// never more of the token than they hold.
    ///
    /// - Parameter baseUnits: The amount, in the token's smallest unit.
    /// - Returns: The whole tokens in it.
    public func wholeUnits(baseUnits: UInt64) -> UInt64 {
        baseUnits / baseUnitsPerWholeUnit
    }
}
