import Foundation
import Gating
import Testing
@testable import Chain

/// Reading one account, and everything that can go wrong doing it.
@Suite("Reading the chain")
internal struct ChainReaderTests {

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Ordinary reads

    @Test("A wallet's balance of the configured asset is what comes back")
    internal func readsABalance() async throws {
        let reader = try Self.reader(
            accounts: [
                Fixture.wallet(1): Fixture.account(
                    Fixture.wallet(1),
                    holdings: [Fixture.holding(Fixture.assetId, 7_500_000)]
                )
            ]
        )
        #expect(try await reader.balance(of: Fixture.wallet(1)) == 7_500_000)
    }

    @Test("A wallet that never opted in holds none of it, which the node is telling us")
    internal func notOptedInIsZero() async throws {
        let reader = try Self.reader(
            accounts: [Fixture.wallet(1): Fixture.account(Fixture.wallet(1))]
        )
        #expect(try await reader.balance(of: Fixture.wallet(1)) == 0)
    }

    @Test("An account the node has never heard of holds nothing, and that is a complete answer")
    internal func unknownAccountIsACompleteZero() async throws {
        // A 404 is the node answering, not the node failing. The reads that
        // never came back are the dangerous ones.
        let reader = try Self.reader(accounts: [:])
        #expect(try await reader.balance(of: Fixture.wallet(9)) == 0)
        #expect(try await reader.holdings(of: Fixture.wallet(9)).isEmpty)
    }

    @Test("A failed request is raised rather than answered with a zero")
    internal func failedRequestThrows() async throws {
        let reader = try Self.reader(
            accounts: [:],
            failures: [Fixture.wallet(1): ChainError.network("connection reset")]
        )
        await #expect(throws: ChainError.network("connection reset")) {
            _ = try await reader.balance(of: Fixture.wallet(1))
        }
    }

    @Test("Checking an address costs nothing from the day's budget")
    internal func addressCheckCostsNothing() async throws {
        let governor = RequestGovernor(limit: 1)
        let reader = try Self.reader(accounts: [:], governor: governor)
        #expect(reader.isValidAddress(Fixture.wallet(1)))
        #expect(reader.isValidAddress("lower case") == false)
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 0)
    }

    // MARK: - The budget

    @Test("A spent budget refuses before the request leaves the process")
    internal func spentBudgetStopsTheRequest() async throws {
        let log = CallLog()
        let governor = RequestGovernor(limit: 1)
        let reader = try Self.reader(
            accounts: [Fixture.wallet(1): Fixture.account(Fixture.wallet(1))],
            governor: governor,
            log: log
        )
        _ = try await reader.balance(of: Fixture.wallet(1))
        await #expect(throws: ChainError.self) {
            _ = try await reader.balance(of: Fixture.wallet(1))
        }
        // One call, not two: the second never reached the node.
        #expect(await log.count == 1)
    }

    @Test("A provider refusing on quota pauses the reader, not just that one read")
    internal func quotaRefusalPausesTheReader() async throws {
        let governor = RequestGovernor(limit: 0)
        let reader = try Self.reader(
            accounts: [:],
            failures: [Fixture.wallet(1): ChainError.api(statusCode: 403, message: "daily quota exceeded")],
            governor: governor
        )
        await #expect(throws: ChainError.self) {
            _ = try await reader.balance(of: Fixture.wallet(1))
        }
        #expect(await reader.pausedUntil() != nil)
        #expect(await reader.budgetSnapshot().pauseReason == .providerRefusedQuota)
    }

    // MARK: - Checking the asset at boot

    @Test("An asset whose precision disagrees with the configuration refuses to start")
    internal func decimalsAreCheckedAtBoot() async throws {
        let reader = try Self.reader(
            accounts: [:],
            assets: [Fixture.assetId: Fixture.assetDetails(id: Fixture.assetId, decimals: 2)]
        )
        await #expect(throws: ChainError.assetDecimalsDisagree(
            assetId: Fixture.assetId,
            configured: 6,
            onChain: 2
        )) {
            try await reader.verifyAssetDecimals()
        }
    }

    @Test("An asset whose precision matches lets the process carry on")
    internal func matchingDecimalsPass() async throws {
        let reader = try Self.reader(
            accounts: [:],
            assets: [Fixture.assetId: Fixture.assetDetails(id: Fixture.assetId, decimals: 6)]
        )
        try await reader.verifyAssetDecimals()
    }

    @Test("An asset that does not exist on this node refuses to start")
    internal func missingAssetRefuses() async throws {
        let reader = try Self.reader(accounts: [:], assets: [:])
        await #expect(throws: ChainError.assetNotFound(assetId: Fixture.assetId)) {
            try await reader.verifyAssetDecimals()
        }
    }

    @Test("An operator who turns the check off spends no request on it")
    internal func checkCanBeTurnedOff() async throws {
        let log = CallLog()
        let reader = try Self.reader(
            accounts: [:],
            assets: [:],
            verifiesAssetDecimals: false,
            log: log
        )
        try await reader.verifyAssetDecimals()
        #expect(await log.count == 0)
    }

    // MARK: - Pools

    @Test("A pool's reserves are read from the account the pool token names")
    internal func readsPoolReserves() async throws {
        let pool = Fixture.pool()
        let reader = try Self.reader(
            accounts: [
                Fixture.poolAccount: Fixture.account(
                    Fixture.poolAccount,
                    holdings: [
                        Fixture.holding(Fixture.assetId, 4_000),
                        Fixture.holding(Fixture.pairedAssetId, 2_000),
                        Fixture.holding(Fixture.lpAssetId, 0)
                    ]
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
        let reserves = try await reader.poolReserves(pool: pool, now: Self.noon)
        #expect(reserves.countedAssetBalance == 4_000)
        #expect(reserves.otherAssetBalance == 2_000)
        #expect(reserves.circulatingPoolTokens == 1_000)
        #expect(reserves.readAt == Self.noon)
    }

    @Test("A pair against the chain's own currency reads the account balance, not a holding")
    internal func nativeCurrencySideIsReadFromTheAccount() async throws {
        let pool = Fixture.pool(id: "native", paired: LiquidityPool.nativeCurrencyAssetId)
        let reader = try Self.reader(
            accounts: [
                Fixture.poolAccount: Fixture.account(
                    Fixture.poolAccount,
                    holdings: [Fixture.holding(Fixture.assetId, 900)],
                    native: 12_345
                )
            ],
            assets: [
                Fixture.lpAssetId: Fixture.assetDetails(
                    id: Fixture.lpAssetId,
                    total: 100,
                    reserveAddress: Fixture.poolAccount
                )
            ]
        )
        let reserves = try await reader.poolReserves(pool: pool, now: Self.noon)
        #expect(reserves.otherAssetBalance == 12_345)
    }

    @Test("A pool token that names no account refuses rather than reporting an empty pool")
    internal func missingPoolAccountRefuses() async throws {
        let pool = Fixture.pool()
        let reader = try Self.reader(
            accounts: [:],
            assets: [Fixture.lpAssetId: Fixture.assetDetails(id: Fixture.lpAssetId)]
        )
        await #expect(throws: ChainError.poolAddressNotFound(poolId: pool.id)) {
            _ = try await reader.poolReserves(pool: pool, now: Self.noon)
        }
    }

    @Test("A pool whose reserve account the node has never heard of refuses rather than reading empty")
    internal func unknownPoolAccountRefuses() async throws {
        // A 404 on a member's wallet means they hold nothing and is a complete
        // answer. A 404 on a pool is not: read as an empty pool it makes every
        // provider's share nothing, completely, and the sweep demotes them.
        let pool = Fixture.pool()
        let reader = try Self.reader(
            accounts: [:],
            assets: [
                Fixture.lpAssetId: Fixture.assetDetails(
                    id: Fixture.lpAssetId,
                    reserveAddress: Fixture.poolAccount
                )
            ]
        )
        await #expect(throws: ChainError.api(statusCode: 404, message: "no accounts found for address")) {
            _ = try await reader.poolReserves(pool: pool, now: Self.noon)
        }
    }

    // MARK: - Addresses

    @Test("An address that could not be an address is refused before a request is spent on it")
    internal func malformedAddressCostsNothing() async throws {
        let log = CallLog()
        let governor = RequestGovernor(limit: 10)
        let reader = try Self.reader(accounts: [:], governor: governor, log: log)
        await #expect(throws: ChainError.invalidAddress("not an address")) {
            _ = try await reader.balance(of: "not an address")
        }
        #expect(await log.count == 0)
        #expect(await governor.snapshot(now: Self.noon).usedRequests == 0)
    }

    @Test("A pool that minted its token at the maximum counts only what is really out there")
    internal func circulatingSupplyOfAMaxMintedPool() {
        let unissued: UInt64 = 1_000
        let minted = UInt64.max
        #expect(ChainReader.circulatingSupply(total: minted, heldByPool: unissued) == minted - unissued)
        // An ordinary supply is taken at face value.
        #expect(ChainReader.circulatingSupply(total: 5_000, heldByPool: 1_000) == 5_000)
    }

    @Test("A pool holding more of its own token than was minted is survivable")
    internal func impossibleSupplyIsSurvivable() {
        #expect(ChainReader.circulatingSupply(total: UInt64.max, heldByPool: UInt64.max) == 0)
    }

    @Test("Reading a pool costs two requests, not four")
    internal func poolReadIsTwoRequests() async throws {
        let log = CallLog()
        let pool = Fixture.pool()
        let reader = try Self.reader(
            accounts: [Fixture.poolAccount: Fixture.account(Fixture.poolAccount)],
            assets: [
                Fixture.lpAssetId: Fixture.assetDetails(
                    id: Fixture.lpAssetId,
                    reserveAddress: Fixture.poolAccount
                )
            ],
            log: log
        )
        _ = try await reader.poolReserves(pool: pool, now: Self.noon)
        // The circulating supply comes out of the account already read rather
        // than costing a second pair of requests per pool per sweep.
        #expect(await log.count == 2)
    }

    // MARK: - Fixtures

    private static func reader(
        accounts: [String: ChainAccount],
        assets: [UInt64: ChainAssetDetails] = [:],
        failures: [String: any Error] = [:],
        governor: RequestGovernor? = nil,
        verifiesAssetDecimals: Bool = true,
        log: CallLog = CallLog()
    ) throws -> ChainReader {
        ChainReader(
            configuration: try Fixture.configuration(verifiesAssetDecimals: verifiesAssetDecimals),
            dataSource: StubAccountDataSource(
                accounts: accounts,
                assets: assets,
                failures: failures,
                log: log
            ),
            governor: governor ?? Fixture.openGovernor()
        )
    }
}
