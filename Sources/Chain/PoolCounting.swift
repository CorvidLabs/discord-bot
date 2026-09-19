import Foundation
import Gating

/// What reading a pool needs to know about it, on top of what the operator
/// wrote down.
///
/// The pool itself is ``Gating/LiquidityPool``, loaded from `POOL_n_*` by
/// ``Gating/LiquidityConfiguration``, and there is deliberately **no second
/// pool type here**. This module shipped one briefly. It named the two sides
/// of the pair `assetA` and `assetB` and gave each a symbol and a decimal
/// count, none of which any file in this module ever read, and none of which
/// an operator had a variable to write down. A host wiring the two layers
/// together had to invent a symbol and a precision for the paired side, which
/// is exactly what the field forbidding assumed precision was there to stop,
/// and the two types disagreed about what an id was: one slugged it, the other
/// took it as a free-form dictionary key, so a host that built a pool with a
/// display id got a pool lookup that returned nil for ever and a badge that
/// was never granted.
///
/// One pool, written down once, in the module whose loader reads it. The
/// mapping into this layer's vocabulary is fixed here rather than at each call
/// site: ``Gating/LiquidityPool/lpAssetId`` is the pool's own token,
/// ``Gating/LiquidityPool/tokenAssetId`` is the side that counts toward a
/// member's balance, and ``Gating/LiquidityPool/pairedAssetId`` is the other
/// side.
extension LiquidityPool {

    // MARK: - Properties

    /// The asset id that names the chain's own currency rather than an asset.
    ///
    /// Zero, on this chain. The currency is an account balance rather than a
    /// holding, so a pool paired against it has to be read from a different
    /// field of the same account.
    public static let nativeCurrencyAssetId: UInt64 = 0

    // MARK: - Public Methods

    /// Whether a side of a pair is the chain's own currency.
    ///
    /// - Parameter assetId: The side's asset id.
    public static func isNativeCurrency(_ assetId: UInt64) -> Bool {
        assetId == nativeCurrencyAssetId
    }

    /// Refuses a catalogue of pools this layer could not read honestly.
    ///
    /// A host calls this at boot, against the catalogue the operator wrote, so
    /// that a mistake is a refusal naming the pool rather than a badge nobody
    /// is ever granted and nobody can explain (ADOPT-2). Every case below
    /// reads as an ordinary quiet answer at run time, which is the whole
    /// reason it is refused up front:
    ///
    /// - A pool token of zero is an unset variable. No account holds asset
    ///   zero as a holding, so every provider in that pool reads as providing
    ///   nothing.
    /// - A pool whose own token **is** the counted token would count a
    ///   member's direct holding a second time as a pool position, putting
    ///   them on a rung they did not earn.
    /// - A pool paired with itself has no other side to value a position
    ///   against.
    /// - Two pools sharing an id: the second overwrites the first everywhere a
    ///   pool is looked up by id, and the pool that vanishes takes its
    ///   providers' balances with it.
    ///
    /// - Parameter pools: Every pool the operator configured.
    public static func validate(_ pools: [LiquidityPool]) throws {
        var seen: Set<String> = []
        for pool in pools {
            guard pool.lpAssetId > 0 else {
                throw ChainConfigurationError.invalidValue(
                    variable: "pool `\(pool.id)` LP asset id",
                    value: "0",
                    expected: "the asset id of the pool's own LP token"
                )
            }
            guard pool.lpAssetId != pool.tokenAssetId else {
                throw ChainConfigurationError.invalidValue(
                    variable: "pool `\(pool.id)` LP asset id",
                    value: String(pool.lpAssetId),
                    expected: "an asset id that is not the counted token, which a pool position "
                        + "would otherwise count a second time"
                )
            }
            guard pool.pairedAssetId != pool.tokenAssetId else {
                throw ChainConfigurationError.invalidValue(
                    variable: "pool `\(pool.id)` paired asset id",
                    value: String(pool.pairedAssetId),
                    expected: "the asset the counted token is paired with, which cannot be the "
                        + "counted token itself"
                )
            }
            guard seen.insert(pool.id).inserted else {
                throw ChainConfigurationError.duplicatePoolId(pool.id)
            }
        }
    }
}
