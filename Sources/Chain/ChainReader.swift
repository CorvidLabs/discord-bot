import Foundation

/// Reading the chain, one account at a time, behind the day's budget.
///
/// Every request this makes is reserved from ``RequestGovernor`` before it
/// leaves and reported to it if it fails, so the budget is the whole process
/// rather than this type's share of it. Nothing here retries: a provider that
/// has refused once because its quota is spent will refuse again, and asking
/// it in a loop is how a bot turns a bad morning into a bad day.
public actor ChainReader {

    // MARK: - Properties

    /// What this reads, and how hard.
    public let configuration: ChainConfiguration

    private let dataSource: any AccountDataSource
    private let governor: RequestGovernor

    // MARK: - Initializers

    /// - Parameters:
    ///   - configuration: What this reads, and how hard.
    ///   - dataSource: Where readings come from. A test supplies its own.
    ///   - governor: The day's budget, shared with everything else that reads
    ///     or signs. Sharing it is the point: a private one is only right in a
    ///     test.
    public init(
        configuration: ChainConfiguration,
        dataSource: any AccountDataSource,
        governor: RequestGovernor
    ) {
        self.configuration = configuration
        self.dataSource = dataSource
        self.governor = governor
    }

    // MARK: - Public Methods

    /// The asset balances are read for.
    public nonisolated var asset: ChainAsset { configuration.asset }

    /// Whether a string is a canonical address. Costs nothing from the budget.
    public nonisolated func isValidAddress(_ address: String) -> Bool {
        dataSource.isValidAddress(address)
    }

    /// Reads the asset's precision from the chain and refuses to carry on when
    /// it disagrees with what was configured.
    ///
    /// Called once at boot, deliberately, and worth the one request it costs.
    /// Configured decimals are what every balance in the process is divided by:
    /// get them wrong and a member holding one whole unit is shown as holding a
    /// million, tiers are decided on the wrong number, and nothing anywhere
    /// looks broken. Finding out at boot from a message naming the two numbers
    /// is the difference between a five minute fix and a week of confusion.
    public func verifyAssetDecimals() async throws {
        guard configuration.verifiesAssetDecimals else { return }
        let details = try await assetDetails(configuration.asset.id)
        guard details.decimals == UInt64(configuration.asset.decimals) else {
            throw ChainError.assetDecimalsDisagree(
                assetId: configuration.asset.id,
                configured: configuration.asset.decimals,
                onChain: details.decimals
            )
        }
    }

    /// Everything one account holds.
    ///
    /// An account the node has never heard of holds nothing, and that is a
    /// **complete** answer rather than a failed read: the node told us. It is
    /// the reads that do not come back at all that must never be treated as a
    /// zero.
    public func account(_ address: String) async throws -> ChainAccount {
        do {
            return try await requireAccount(address)
        } catch {
            guard ChainError.isNotFound(error) else { throw error }
            return ChainAccount(address: address, nativeBalance: 0, holdings: [])
        }
    }

    /// How much of the configured asset an account holds.
    public func balance(of address: String) async throws -> UInt64 {
        try await account(address).holdings.amount(of: configuration.asset.id)
    }

    /// Everything an account has opted into, held or not.
    public func holdings(of address: String) async throws -> [ChainHolding] {
        try await account(address).holdings
    }

    /// The assets an account created.
    public func createdAssets(of address: String) async throws -> [ChainAssetDetails] {
        try await account(address).createdAssets
    }

    /// What the chain says about one asset.
    public func assetDetails(_ assetId: UInt64) async throws -> ChainAssetDetails {
        try await run { try await self.dataSource.assetDetails(assetId: assetId) }
    }

    /// How much of a pool's token an account holds.
    public func poolTokenBalance(of address: String, poolTokenId: UInt64) async throws -> UInt64 {
        try await holdings(of: address).amount(of: poolTokenId)
    }

    /// What a pool holds, and how many of its tokens are in circulation.
    ///
    /// Two requests: the pool token's own record, which names the account
    /// holding the pool, and that account. The circulating supply is worked out
    /// from the account that was already read rather than read again, which
    /// used to cost two further requests per pool per sweep for a number
    /// already in hand.
    public func poolReserves(pool: LiquidityPool, now: Date = Date()) async throws -> PoolReserves {
        let poolToken = try await assetDetails(pool.poolTokenId)
        guard let poolAddress = poolToken.reserveAddress else {
            throw ChainError.poolAddressNotFound(poolId: pool.id)
        }
        // Deliberately **not** through ``account(_:)``. That helper answers a
        // 404 with an empty account, which is the truth for a member's wallet
        // and a lie about a pool: an empty pool is a complete reading, every
        // provider's share of it works out to nothing, and the sweep demotes
        // the people who put the liquidity there. A pool that cannot be read
        // has to stay unread, so that it is absent from the reserves and its
        // holders come back short rather than poor.
        let poolAccount = try await requireAccount(poolAddress)
        return PoolReserves(
            pool: pool,
            poolAddress: poolAddress,
            assetABalance: balance(in: poolAccount, of: pool.assetA),
            assetBBalance: balance(in: poolAccount, of: pool.assetB),
            circulatingPoolTokens: Self.circulatingSupply(
                total: poolToken.total,
                heldByPool: poolAccount.holdings.amount(of: pool.poolTokenId)
            ),
            readAt: now
        )
    }

    /// What has been spent of today's request budget.
    public func budgetSnapshot(now: Date = Date()) async -> RequestBudgetSnapshot {
        await governor.snapshot(now: now)
    }

    /// When reads and signing resume, or nil when nothing is paused.
    public func pausedUntil(now: Date = Date()) async -> Date? {
        await governor.pausedUntil(now: now)
    }

    // MARK: - Internal Methods

    /// Pool tokens actually in somebody's hands.
    ///
    /// A pool that minted its token at the largest number the chain can hold
    /// keeps the unissued remainder in its own account, so the supply figure on
    /// the asset is not the supply anybody holds. Dividing a provider's holding
    /// by that figure instead of by the circulating one makes every share round
    /// to zero, and every provider's balance disappear.
    ///
    /// The test for "minted at the maximum" is a wide band rather than an
    /// equality, because pools do not all mint exactly the largest value.
    internal static func circulatingSupply(total: UInt64, heldByPool: UInt64) -> UInt64 {
        let nearMaximum = UInt64.max - 1_000_000_000_000_000_000
        guard total > nearMaximum else { return total }
        return total >= heldByPool ? total - heldByPool : 0
    }

    // MARK: - Private Methods

    /// One account, read with no answer invented for it.
    ///
    /// The address is checked here rather than inside the request, so a typo
    /// costs nothing from the day's budget: a malformed address cannot name an
    /// account, and the request spent finding that out is a request a real
    /// wallet needed later in the same sweep.
    private func requireAccount(_ address: String) async throws -> ChainAccount {
        guard dataSource.isValidAddress(address) else {
            throw ChainError.invalidAddress(address)
        }
        return try await run { try await self.dataSource.account(address: address) }
    }

    /// A side's balance in the pool's own account. The chain's own currency is
    /// an account balance rather than a holding, so it is read differently.
    private func balance(in account: ChainAccount, of side: PoolSide) -> UInt64 {
        side.isNativeCurrency ? account.nativeBalance : account.holdings.amount(of: side.assetId)
    }

    /// Reserves one request, makes it, and reports a provider refusal.
    private func run<Output: Sendable>(
        _ operation: @Sendable () async throws -> Output
    ) async throws -> Output {
        try await governor.reserveRequest()
        do {
            return try await operation()
        } catch {
            throw await governor.recordRequestFailure(error)
        }
    }
}
