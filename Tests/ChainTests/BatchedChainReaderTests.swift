import Foundation
import Testing
@testable import Chain

/// Reading a whole community at once.
@Suite("Reading many wallets")
internal struct BatchedChainReaderTests {

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Order

    @Test("The answers come back in the order the wallets were asked for")
    internal func orderIsPreserved() async throws {
        // A caller lining results up against the members they belong to has no
        // way of noticing that the list came back shuffled.
        let wallets = (0..<25).map { Fixture.wallet($0) }
        var accounts: [String: ChainAccount] = [:]
        for (index, wallet) in wallets.enumerated() {
            accounts[wallet] = Fixture.account(
                wallet,
                holdings: [Fixture.holding(Fixture.assetId, UInt64(index + 1))]
            )
        }
        let batched = try Self.batched(accounts: accounts, batchSize: 4)
        let results = await batched.check(wallets: wallets, pools: [], for: Fixture.sweep, now: Self.noon)
        #expect(results.map(\.address) == wallets)
        #expect(results.compactMap { $0.directBalance.completeValue } == (1...25).map(UInt64.init))
    }

    @Test("Asking about nobody reads nothing")
    internal func emptyListReadsNothing() async throws {
        let log = CallLog()
        let batched = try Self.batched(accounts: [:], log: log)
        #expect(await batched.check(wallets: [], pools: [], for: Fixture.sweep, now: Self.noon).isEmpty)
        #expect(await log.count == 0)
    }

    // MARK: - One bad wallet

    @Test("One wallet that could not be read does not make the others look wrong")
    internal func oneFailureIsContained() async throws {
        let batched = try Self.batched(
            accounts: [
                Fixture.wallet(1): Fixture.account(
                    Fixture.wallet(1),
                    holdings: [Fixture.holding(Fixture.assetId, 10)]
                )
            ],
            failures: [Fixture.wallet(2): ChainError.network("connection reset")]
        )
        let results = await batched.check(
            wallets: [Fixture.wallet(1), Fixture.wallet(2)],
            pools: [],
            for: Fixture.sweep,
            now: Self.noon
        )
        #expect(results[0].directBalance.completeValue == 10)
        #expect(results[1].directBalance.completeValue == nil)
        #expect(results[1].combinedBalance.isComplete == false)
    }

    @Test("A budget that runs out mid sweep marks the rest as unread rather than empty")
    internal func budgetRunningOutIsNotAnEmptyWallet() async throws {
        let governor = RequestGovernor(limit: 1)
        var accounts: [String: ChainAccount] = [:]
        for index in 0..<3 {
            accounts[Fixture.wallet(index)] = Fixture.account(Fixture.wallet(index))
        }
        let batched = try Self.batched(accounts: accounts, governor: governor, batchSize: 1)
        let results = await batched.check(
            wallets: (0..<3).map { Fixture.wallet($0) },
            pools: [],
            for: Fixture.sweep,
            now: Self.noon
        )
        #expect(results[0].combinedBalance.isComplete)
        #expect(results[1].holdings.gaps == [.budgetSpent])
        #expect(results[2].holdings.gaps == [.budgetSpent])
    }

    // MARK: - Pools

    @Test("A pool is read once for the whole sweep, not once for every member")
    internal func poolIsReadOncePerSweep() async throws {
        let log = CallLog()
        let pool = Fixture.pool()
        var accounts: [String: ChainAccount] = [
            Fixture.poolAccount: Fixture.account(
                Fixture.poolAccount,
                holdings: [
                    Fixture.holding(Fixture.assetId, 1_000_000),
                    Fixture.holding(Fixture.pairedAssetId, 500)
                ]
            )
        ]
        for index in 0..<10 {
            accounts[Fixture.wallet(index)] = Fixture.account(
                Fixture.wallet(index),
                holdings: [Fixture.holding(Fixture.lpAssetId, 100)]
            )
        }
        let batched = try Self.batched(
            accounts: accounts,
            assets: [
                Fixture.lpAssetId: Fixture.assetDetails(
                    id: Fixture.lpAssetId,
                    total: 1_000,
                    reserveAddress: Fixture.poolAccount
                )
            ],
            log: log
        )
        let results = await batched.check(
            wallets: (0..<10).map { Fixture.wallet($0) },
            pools: [pool],
            for: Fixture.sweep,
            now: Self.noon
        )
        #expect(results.allSatisfy { $0.liquidityAmount.completeValue == 100_000 })
        #expect(await log.count(of: "asset:\(Fixture.lpAssetId)") == 1)
        #expect(await log.count(of: "account:\(Fixture.poolAccount)") == 1)
    }

    @Test("A pool that could not be read leaves its providers short instead of poor")
    internal func unreadablePoolLeavesProvidersShort() async throws {
        let pool = Fixture.pool()
        let batched = try Self.batched(
            accounts: [
                Fixture.wallet(1): Fixture.account(
                    Fixture.wallet(1),
                    holdings: [Fixture.holding(Fixture.lpAssetId, 100)]
                )
            ],
            assets: [:],
            assetFailures: [Fixture.lpAssetId: ChainError.network("connection reset")]
        )
        let results = await batched.check(
            wallets: [Fixture.wallet(1)],
            pools: [pool],
            for: Fixture.sweep,
            now: Self.noon
        )
        #expect(results[0].liquidityAmount.gaps == [.poolReservesUnavailable(poolId: pool.id)])
        #expect(results[0].canDecideEntitlements == false)
    }

    @Test("A pool whose reserve account is not there leaves its providers short, not empty")
    internal func missingPoolAccountLeavesProvidersShort() async throws {
        // The pool token names an account the node answers 404 for. Treating
        // that as an empty pool is the incident this module is built around: a
        // failed read presented as a complete zero, and every provider demoted
        // for providing liquidity.
        let pool = Fixture.pool()
        let batched = try Self.batched(
            accounts: [
                Fixture.wallet(1): Fixture.account(
                    Fixture.wallet(1),
                    holdings: [Fixture.holding(Fixture.lpAssetId, 100)]
                )
            ],
            assets: [
                Fixture.lpAssetId: Fixture.assetDetails(
                    id: Fixture.lpAssetId,
                    total: 1_000,
                    reserveAddress: Fixture.poolAccount
                )
            ]
        )
        let results = await batched.check(
            wallets: [Fixture.wallet(1)],
            pools: [pool],
            for: Fixture.sweep,
            now: Self.noon
        )
        #expect(results[0].liquidityAmount.gaps == [.poolReservesUnavailable(poolId: pool.id)])
        #expect(results[0].liquidityAmount.completeValue == nil)
        #expect(results[0].canDecideEntitlements == false)
    }

    @Test("Reserves are reused until their lifetime is up, then read again")
    internal func reservesAreCachedForTheirLifetime() async throws {
        let log = CallLog()
        let pool = Fixture.pool()
        let batched = try Self.batched(
            accounts: [Fixture.poolAccount: Fixture.account(Fixture.poolAccount)],
            assets: [
                Fixture.lpAssetId: Fixture.assetDetails(
                    id: Fixture.lpAssetId,
                    reserveAddress: Fixture.poolAccount
                )
            ],
            cacheLifetimes: ChainCacheLifetimes(poolReserves: 60),
            log: log
        )
        _ = try await batched.poolReserves(pool: pool, for: Fixture.sweep, now: Self.noon)
        _ = try await batched.poolReserves(pool: pool, for: Fixture.sweep, now: Self.noon.addingTimeInterval(59))
        #expect(await log.count == 2)
        _ = try await batched.poolReserves(pool: pool, for: Fixture.sweep, now: Self.noon.addingTimeInterval(61))
        #expect(await log.count == 4)
        #expect(await batched.cachedReservesCount == 1)
    }

    @Test("Clearing the cached reserves makes the next read a fresh one")
    internal func clearingTheCache() async throws {
        let pool = Fixture.pool()
        let batched = try Self.batched(
            accounts: [Fixture.poolAccount: Fixture.account(Fixture.poolAccount)],
            assets: [
                Fixture.lpAssetId: Fixture.assetDetails(
                    id: Fixture.lpAssetId,
                    reserveAddress: Fixture.poolAccount
                )
            ]
        )
        _ = try await batched.poolReserves(pool: pool, for: Fixture.sweep, now: Self.noon)
        #expect(await batched.cachedReservesCount == 1)
        await batched.clearReservesCache()
        #expect(await batched.cachedReservesCount == 0)
    }

    @Test("Once the provider has refused, the remaining pools are not asked")
    internal func quotaRefusalStopsTheRemainingPools() async throws {
        let log = CallLog()
        let pools = [Fixture.pool(id: "one"), Fixture.pool(id: "two")]
        let batched = try Self.batched(
            accounts: [:],
            assetFailures: [
                Fixture.lpAssetId: ChainError.api(statusCode: 403, message: "daily quota exceeded")
            ],
            log: log
        )
        let found = await batched.reserves(pools: pools, for: Fixture.sweep, now: Self.noon)
        #expect(found.isEmpty)
        // One attempt, not one per pool: every further attempt costs a request
        // this process has already been told it may not make.
        #expect(await log.count == 1)
    }

    // MARK: - Fixtures

    private static func batched(
        accounts: [String: ChainAccount],
        assets: [UInt64: ChainAssetDetails] = [:],
        failures: [String: any Error] = [:],
        assetFailures: [UInt64: any Error] = [:],
        governor: RequestGovernor? = nil,
        batchSize: Int = 50,
        cacheLifetimes: ChainCacheLifetimes = ChainCacheLifetimes(),
        log: CallLog = CallLog()
    ) throws -> BatchedChainReader {
        let configuration = try Fixture.configuration(
            limits: ChainLimits(requestsPerSecond: 10_000, batchSize: batchSize),
            cacheLifetimes: cacheLifetimes
        )
        return BatchedChainReader(
            reader: ChainReader(
                configuration: configuration,
                dataSource: StubAccountDataSource(
                    accounts: accounts,
                    assets: assets,
                    failures: failures,
                    assetFailures: assetFailures,
                    log: log
                ),
                governor: governor ?? Fixture.openGovernor()
            )
        )
    }
}
