import Foundation
import Testing
@testable import Gating

/// The pools a server counts, and the one answer about which token is in
/// them.
@Suite("Liquidity pools")
struct LiquidityConfigurationTests {

    // MARK: - Any number of pools

    @Test("A server brings its own pools, and adding one is a set of variables rather than a release")
    func poolsAreConfiguration() throws {
        let catalog = try LiquidityConfiguration.load(from: Fixture.environment(), token: try Fixture.token())
        #expect(catalog.pools.map(\.id) == [Fixture.usdPool, Fixture.eurPool])
        #expect(catalog.pool(id: Fixture.usdPool)?.name == "TOKEN/USD")
        #expect(catalog.pool(lpAssetId: 8_002)?.id == Fixture.eurPool)

        let none = try LiquidityConfiguration.load(from: [:], token: try Fixture.token())
        #expect(none.isEmpty)
        #expect(none.allRoleIds.isEmpty)
    }

    @Test("Each pool is told which asset is the gated one, rather than reaching for a global")
    func eachPoolCarriesTheTokenId() throws {
        // The original kept a global token id and, for a while, a second
        // literal in the pool table. When the two disagreed the pooled side
        // of every tier read as zero and every provider in the server was
        // demoted, which is exactly what ROLE-1.c is about. One answer,
        // written once, copied in at load.
        let token = try TokenProfile(assetId: 4_242, symbol: "OTHER", decimals: 2)
        let catalog = try LiquidityConfiguration.load(from: Fixture.environment(), token: token)
        #expect(catalog.pools.allSatisfy { $0.tokenAssetId == 4_242 })
    }

    @Test("A mistyped pool number drops it and the ones above it")
    func firstGapEndsTheCatalog() throws {
        let catalog = try LiquidityConfiguration.load(
            from: Fixture.environment(overriding: [
                "POOL_4_ID": "token_gbp",
                "POOL_4_LP_ASA": "8004",
                "POOL_4_PAIRED_ASA": "9004",
                "POOL_4_DECIMALS": "6"
            ]),
            token: try Fixture.token()
        )
        #expect(catalog.pools.map(\.id) == [Fixture.usdPool, Fixture.eurPool])
    }

    // MARK: - Refusals

    @Test("A pool that cannot be priced is refused at load, not skipped in silence")
    func bothSidesRequired() throws {
        // The original let either side be absent and then quietly skipped any
        // pool missing one, so a half-written pool counted for nothing and
        // said nothing about it.
        for key in ["POOL_1_LP_ASA", "POOL_1_PAIRED_ASA", "POOL_1_DECIMALS"] {
            do {
                _ = try LiquidityConfiguration.load(
                    from: Fixture.environment(removing: [key]),
                    token: try Fixture.token()
                )
                Issue.record("\(key) was not required")
            } catch let error as GatingConfigurationError {
                guard case .missing(let named, _) = error else {
                    Issue.record("\(key) refused for the wrong reason: \(error)")
                    continue
                }
                #expect(named == key)
            }
        }
    }

    @Test("Two pools sharing one LP token are refused, because a holding cannot be in both")
    func duplicateLPAssetRefused() throws {
        #expect(
            throws: GatingConfigurationError.duplicateAsset(
                assetId: 8_001,
                first: "POOL_1_LP_ASA",
                second: "POOL_2_LP_ASA"
            )
        ) {
            try LiquidityConfiguration.load(
                from: Fixture.environment(overriding: ["POOL_2_LP_ASA": "8001"]),
                token: try Fixture.token()
            )
        }
    }

    @Test("Two pools with one id are refused")
    func duplicateIdRefused() throws {
        #expect(
            throws: GatingConfigurationError.duplicateId(
                id: Fixture.usdPool,
                first: "POOL_1_ID",
                second: "POOL_2_ID"
            )
        ) {
            try LiquidityConfiguration.load(
                from: Fixture.environment(overriding: ["POOL_2_ID": "TOKEN_USD"]),
                token: try Fixture.token()
            )
        }
    }

    @Test("An LP token with more decimals than can be converted is refused")
    func absurdDecimalsRefused() throws {
        #expect(
            throws: GatingConfigurationError.unsupportedDecimals(key: "POOL_1_DECIMALS", value: 42)
        ) {
            try LiquidityConfiguration.load(
                from: Fixture.environment(overriding: ["POOL_1_DECIMALS": "42"]),
                token: try Fixture.token()
            )
        }
    }

    // MARK: - Badges

    @Test("A pool may have its own badge or none, and providing anywhere may earn one badge")
    func badges() throws {
        let catalog = try LiquidityConfiguration.load(from: Fixture.environment(), token: try Fixture.token())
        #expect(catalog.pool(id: Fixture.usdPool)?.roleId == Fixture.poolBadge)
        #expect(catalog.pool(id: Fixture.eurPool)?.roleId == nil)
        #expect(catalog.providerRoleId == Fixture.providerBadge)
        #expect(catalog.allRoleIds == [Fixture.poolBadge, Fixture.providerBadge])

        let unbadged = try LiquidityConfiguration.load(
            from: Fixture.environment(removing: ["LP_PROVIDER_ROLE_ID", "POOL_1_ROLE_ID"]),
            token: try Fixture.token()
        )
        #expect(unbadged.allRoleIds.isEmpty)
        #expect(unbadged.pools.count == 2)
    }

    // MARK: - Positions

    @Test("A position says both whether somebody provided and how much of the token it is worth")
    func positionsAnswerTwoQuestions() {
        let providing = LiquidityPosition(poolId: Fixture.usdPool, lpBaseUnits: 5, tokenBaseUnits: 0)
        let absent = LiquidityPosition(poolId: Fixture.usdPool, lpBaseUnits: 0, tokenBaseUnits: 0)
        // Holding LP worth nothing at this moment is still providing: the
        // badge is for having provided, not for the pool's price today.
        #expect(providing.isProviding)
        #expect(absent.isProviding == false)
    }
}
