import Foundation
import Gating

/// Reads many wallets at once, at a rate the provider will tolerate.
///
/// Two things happen here that do not happen one wallet at a time. Wallets are
/// read in parallel in batches, because a community of two thousand read one
/// after another takes longer than the interval between sweeps. And a pool's
/// reserves are read once for the whole run rather than once per wallet, which
/// is the difference between a handful of requests and one per member.
///
/// The order of the answers matches the order of the wallets asked for. That
/// sounds like a detail and is not: a caller lining results up against the
/// members they belong to has no way of noticing that the list came back
/// shuffled.
public actor BatchedChainReader {

    // MARK: - Properties

    private let reader: ChainReader
    private let limiter: RequestRateLimiter
    private let configuration: ChainConfiguration
    private var reservesCache: ExpiringMap<String, PoolReserves>

    // MARK: - Initializers

    /// - Parameters:
    ///   - reader: The single wallet reader everything goes through.
    ///   - limiter: The per second brake. One per process, shared, or this
    ///     builds its own at the configured rate.
    public init(reader: ChainReader, limiter: RequestRateLimiter? = nil) {
        self.reader = reader
        self.configuration = reader.configuration
        self.limiter = limiter ?? RequestRateLimiter(limits: reader.configuration.limits)
        self.reservesCache = ExpiringMap(lifetime: reader.configuration.cacheLifetimes.poolReserves)
    }

    // MARK: - Public Methods

    /// A pool's reserves, reading them only when the cached ones are past their
    /// lifetime.
    public func poolReserves(pool: LiquidityPool, now: Date = Date()) async throws -> PoolReserves {
        if let cached = reservesCache.value(for: pool.id, now: now) {
            return cached
        }
        // Two requests per pool: the pool token's record and the pool account.
        await limiter.acquire(count: 2)
        let reserves = try await reader.poolReserves(pool: pool, now: now)
        reservesCache.set(reserves, for: pool.id, now: now)
        return reserves
    }

    /// Reserves for every pool that could be read.
    ///
    /// A pool that cannot be read is **absent** from the result rather than
    /// present with zeroes, so that a wallet holding its token comes back short
    /// rather than poorer. Stops early once the provider has refused on quota:
    /// the rest of the pools will refuse too, and each attempt costs a request
    /// this process has already been told it may not make.
    public func reserves(for pools: [LiquidityPool], now: Date = Date()) async -> [String: PoolReserves] {
        var found: [String: PoolReserves] = [:]
        for pool in pools {
            do {
                found[pool.id] = try await poolReserves(pool: pool, now: now)
            } catch {
                if ChainError.isProviderQuotaRefusal(error) { break }
            }
        }
        return found
    }

    /// Reads every wallet, in batches, and says of each one what could not be
    /// established.
    ///
    /// - Parameters:
    ///   - wallets: The wallets to read, in the order the answers are wanted.
    ///   - pools: The pools to count. Empty means direct holdings only.
    ///   - now: Injected so a test pins cache lifetimes.
    public func check(
        wallets: [String],
        pools: [LiquidityPool],
        now: Date = Date()
    ) async -> [WalletCheck] {
        guard !wallets.isEmpty else { return [] }
        let reserves = pools.isEmpty ? [:] : await self.reserves(for: pools, now: now)
        let token = configuration.token
        let reader = self.reader
        let limiter = self.limiter
        var results: [WalletCheck] = []
        results.reserveCapacity(wallets.count)

        // Batched rather than all at once: a task group holding one suspended
        // task per member of a large community is a lot of live requests, and
        // the provider notices the burst even when the limiter is keeping to
        // the rate.
        for batch in wallets.chunked(into: configuration.limits.batchSize) {
            let batchResults = await withTaskGroup(of: (Int, WalletCheck).self) { group in
                for (offset, wallet) in batch.enumerated() {
                    group.addTask {
                        await limiter.acquire()
                        do {
                            let holdings = try await reader.holdings(of: wallet)
                            return (
                                offset,
                                WalletCheck.read(
                                    address: wallet,
                                    holdings: holdings,
                                    token: token,
                                    pools: pools,
                                    reserves: reserves
                                )
                            )
                        } catch {
                            return (offset, WalletCheck.unreadable(address: wallet, gap: Self.gap(for: error)))
                        }
                    }
                }
                var collected: [(Int, WalletCheck)] = []
                collected.reserveCapacity(batch.count)
                for await result in group {
                    collected.append(result)
                }
                return collected.sorted { $0.0 < $1.0 }.map(\.1)
            }
            results.append(contentsOf: batchResults)
        }
        return results
    }

    /// Drops every cached set of reserves, so the next read is fresh.
    public func clearReservesCache() {
        reservesCache.removeAll()
    }

    /// How many sets of reserves are cached, usable or not.
    public var cachedReservesCount: Int { reservesCache.count }

    // MARK: - Internal Methods

    /// Which gap an error leaves behind.
    ///
    /// A budget or quota refusal is worth telling apart from an ordinary
    /// failure: it means every other wallet in the sweep has the same gap, and
    /// the run is not worth repeating until tomorrow.
    internal static func gap(for error: any Error) -> ChainReadGap {
        ChainError.isProviderQuotaRefusal(error)
            ? .budgetSpent
            : .requestFailed(error.localizedDescription)
    }
}

extension Array {

    /// The array in runs of at most `size`, keeping order.
    internal func chunked(into size: Int) -> [[Element]] {
        let step = Swift.max(size, 1)
        return stride(from: 0, to: count, by: step).map {
            Array(self[$0..<Swift.min($0 + step, count)])
        }
    }
}
