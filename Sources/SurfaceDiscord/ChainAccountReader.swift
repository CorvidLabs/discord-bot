@preconcurrency import Foundation
import Chain
import Gating
import Surface

/// Reads one account through the chain layer's brakes.
///
/// The limiter and the day's budget are the reader's, not this file's. What
/// this adds is the shape: a ``Chain/WalletCheck`` carries its own gaps, so a
/// pool whose reserves could not be read leaves that pool **out** of the
/// counted amounts rather than writing a zero into them, and the whole
/// reading comes back `short`. `short` becomes ``Gating/Reading/unknown``
/// one layer up, which holds a member's roles rather than demoting them for
/// a provider that blinked (`ROLE-1.a`).
public struct ChainAccountReader: AccountHoldingsReader {

    // MARK: - Properties

    /// The token the ladder is measured in.
    public let token: TokenProfile

    /// The pools an operator counts.
    public let pools: [LiquidityPool]

    /// The reader, with its limiter and its budget.
    private let reader: ChainReader

    // MARK: - Initializers

    /// - Parameters:
    ///   - reader: The reader, with its limiter and its budget.
    ///   - token: The token the ladder is measured in.
    ///   - pools: The pools an operator counts.
    public init(reader: ChainReader, token: TokenProfile, pools: [LiquidityPool]) {
        self.reader = reader
        self.token = token
        self.pools = pools
    }

    // MARK: - Public Methods

    public func check(address: String, for caller: RequestCaller) async throws -> WalletCheck {
        let holdings = try await reader.holdings(of: address, for: caller)

        var reserves: [String: PoolReserves] = [:]
        for pool in pools {
            // Only for a pool this account actually holds tokens of. Reading
            // reserves for a pool the member is not in spends the day's
            // budget to learn a zero that is already known.
            guard holdings.amount(of: pool.lpAssetId) > 0 else { continue }
            guard let read = try? await reader.poolReserves(pool: pool, for: caller) else { continue }
            reserves[pool.id] = read
        }

        return WalletCheck.read(
            address: address,
            holdings: holdings,
            token: token,
            pools: pools,
            reserves: reserves
        )
    }
}
