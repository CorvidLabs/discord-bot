import Foundation
import Gating
import Testing
@testable import Chain

/// The join between what the chain said and what the rules decide.
///
/// Both modules were written for the same production incident and for a while
/// nothing connected them, which left the one line a host had to write as the
/// one line that brings the incident back: `.known(reading.valueEvenIfShort ??
/// 0)`. These tests are the join, and the one that matters is the last of the
/// first group: a member on the top rung, one pool unreadable, and the rung
/// still theirs.
@Suite("From a reading to a decision")
internal struct GatingBridgeTests {

    // MARK: - A short answer is not a smaller answer

    @Test("A complete reading is known, and a short one is unknown rather than smaller")
    internal func shortIsNotSmaller() {
        let whole: ChainReading<UInt64> = .complete(9_000)
        let short: ChainReading<UInt64> = .short(1_000, gaps: [.poolReservesUnavailable(poolId: "pair-one")])
        let nothing: ChainReading<UInt64> = .unavailable(gaps: [.requestFailed("timed out")])

        #expect(whole.gatingReading == .known(9_000))
        // Emphatically not `.known(1_000)`. The thousand was read and it is
        // not this person's balance.
        #expect(short.gatingReading == .unknown)
        #expect(nothing.gatingReading == .unknown)
    }

    @Test("A member on the top rung keeps it when one pool's reserves cannot be read")
    internal func oneUnreadablePoolDoesNotDemote() throws {
        // The incident, at the seam. A provider error lasting a minute makes
        // the pool figure short; a total built with `?? 0` reads as a member
        // who sold up, and the sweep takes every rung off somebody who did
        // nothing.
        let configuration = try Self.configuration()
        let pool = configuration.pools.pools[0]
        let onTopRung = try Self.check(
            directWholeTokens: 5_000,
            poolTokens: 100_000,
            reserves: [:],
            configuration: configuration
        )
        let holdings = MemberHoldings.fromChain(
            memberId: "member-1",
            isVerified: true,
            checks: [onTopRung],
            pools: configuration.pools.pools
        )
        #expect(holdings.combinedBalance == .unknown)

        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: holdings,
            currentRoleIds: ["role-holder", "role-elite", "role-lp"]
        )
        #expect(decision.revoked.isEmpty)
        #expect(decision.target.contains("role-elite"))
        #expect(decision.target.contains("role-holder"))
        #expect(decision.held.contains("role-elite"))
        #expect(decision.unknowns.contains(.liquidityPositions))
        #expect(pool.roleId == "role-lp-pair-one")
    }

    @Test("With every pool read, the same holdings decide the rung they have earned")
    internal func aWholeReadingDecidesTheRung() throws {
        let configuration = try Self.configuration()
        let pool = configuration.pools.pools[0]
        let read = try Self.check(
            directWholeTokens: 5_000,
            poolTokens: 100_000,
            reserves: [pool.id: Fixture.reserves(pool: pool)],
            configuration: configuration
        )
        let holdings = MemberHoldings.fromChain(
            memberId: "member-1",
            isVerified: true,
            checks: [read],
            pools: configuration.pools.pools
        )
        // 5,000 whole tokens held directly, plus a tenth of a pool holding
        // 1,000 whole tokens of the counted side.
        #expect(holdings.combinedBalance == .known(5_100_000_000))

        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: holdings,
            currentRoleIds: []
        )
        #expect(decision.granted.contains("role-elite"))
        #expect(decision.granted.contains("role-holder"))
        #expect(decision.granted.contains("role-lp"))
        #expect(decision.granted.contains("role-lp-pair-one"))
        #expect(decision.unknowns.isEmpty)
    }

    @Test("A wallet that could not be read at all holds every rung rather than losing them")
    internal func oneUnreadableWalletDoesNotDemote() throws {
        let configuration = try Self.configuration()
        let pool = configuration.pools.pools[0]
        let checks = [
            try Self.check(
                directWholeTokens: 5_000,
                poolTokens: 0,
                reserves: [pool.id: Fixture.reserves(pool: pool)],
                configuration: configuration
            ),
            WalletCheck.unreadable(address: Fixture.wallet(2), gap: .requestFailed("timed out"))
        ]
        let holdings = MemberHoldings.fromChain(
            memberId: "member-1",
            isVerified: true,
            checks: checks,
            pools: configuration.pools.pools
        )
        #expect(holdings.directBalance == .unknown)
        #expect(holdings.liquidityPositions == .unknown)

        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: holdings,
            currentRoleIds: ["role-elite"]
        )
        #expect(decision.revoked.isEmpty)
        #expect(decision.target.contains("role-elite"))
    }

    // MARK: - Building the member

    @Test("No wallets at all is unknown, not a member holding nothing")
    internal func noWalletsIsUnknown() throws {
        let configuration = try Self.configuration()
        let holdings = MemberHoldings.fromChain(
            memberId: "member-1",
            isVerified: true,
            checks: [],
            pools: configuration.pools.pools
        )
        #expect(holdings.directBalance == .unknown)
        #expect(holdings.liquidityPositions == .unknown)
        // A member who provably has no account says so, and it is read
        // rather than unread.
        let unlinked = MemberHoldings.unlinked(memberId: "member-1", configuration: configuration)
        #expect(unlinked.directBalance == .known(0))
    }

    @Test("Positions are summed across every wallet a member has verified")
    internal func positionsAreSummedAcrossWallets() throws {
        let configuration = try Self.configuration()
        let pool = configuration.pools.pools[0]
        let reserves = [pool.id: Fixture.reserves(pool: pool)]
        let checks = [
            try Self.check(
                directWholeTokens: 0,
                poolTokens: 60_000,
                reserves: reserves,
                configuration: configuration,
                address: Fixture.wallet(1)
            ),
            try Self.check(
                directWholeTokens: 0,
                poolTokens: 40_000,
                reserves: reserves,
                configuration: configuration,
                address: Fixture.wallet(2)
            )
        ]
        let holdings = MemberHoldings.fromChain(
            memberId: "member-1",
            isVerified: true,
            checks: checks,
            pools: configuration.pools.pools
        )
        #expect(holdings.position(inPool: pool.id) == .known(
            LiquidityPosition(poolId: pool.id, lpBaseUnits: 100_000, tokenBaseUnits: 100_000_000)
        ))
    }

    @Test("A pool the member is in none of is left out, and reads as a zero position")
    internal func absentPoolsAreZeroPositions() throws {
        let configuration = try Self.configuration()
        let pool = configuration.pools.pools[0]
        let check = try Self.check(
            directWholeTokens: 10,
            poolTokens: 0,
            reserves: [:],
            configuration: configuration
        )
        let holdings = MemberHoldings.fromChain(
            memberId: "member-1",
            isVerified: true,
            checks: [check],
            pools: configuration.pools.pools
        )
        #expect(holdings.liquidityPositions == .known([]))
        #expect(holdings.isProvidingLiquidity == .known(false))
        #expect(holdings.position(inPool: pool.id) == .known(
            LiquidityPosition(poolId: pool.id, lpBaseUnits: 0, tokenBaseUnits: 0)
        ))
    }

    // MARK: - Collections

    @Test("A collection nobody looked up holds its roles rather than losing them")
    internal func anUnansweredRegistryDecidesNothing() throws {
        let configuration = try Self.configuration(withCollection: true)
        let check = try Self.check(
            directWholeTokens: 10,
            poolTokens: 0,
            reserves: [:],
            configuration: configuration,
            extraHoldings: [Fixture.holding(Fixture.collectibleId, 1)]
        )
        let holdings = MemberHoldings.fromChain(
            memberId: "member-1",
            isVerified: true,
            checks: [check],
            pools: configuration.pools.pools,
            collections: configuration.collections
        )
        #expect(holdings.count(ofCollection: "passes") == .unknown)

        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: holdings,
            currentRoleIds: ["role-pass"]
        )
        #expect(decision.revoked.isEmpty)
        #expect(decision.target.contains("role-pass"))
        #expect(decision.unknowns.contains(.collection(id: "passes")))
    }

    @Test("A registry that answered counts what the wallets really hold")
    internal func anAnswerFromTheRegistryIsCounted() throws {
        let configuration = try Self.configuration(withCollection: true)
        let check = try Self.check(
            directWholeTokens: 10,
            poolTokens: 0,
            reserves: [:],
            configuration: configuration,
            extraHoldings: [
                Fixture.holding(Fixture.collectibleId, 1),
                // Opted in and holding none of it, which is not holding one.
                Fixture.holding(Fixture.collectibleId + 1, 0)
            ]
        )
        let holdings = MemberHoldings.fromChain(
            memberId: "member-1",
            isVerified: true,
            checks: [check],
            pools: configuration.pools.pools,
            collections: configuration.collections,
            assetCollections: .known([
                Fixture.collectibleId: "passes",
                Fixture.collectibleId + 1: "passes"
            ])
        )
        #expect(holdings.count(ofCollection: "passes") == .known(1))
        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: holdings,
            currentRoleIds: []
        )
        #expect(decision.granted.contains("role-pass"))
    }

    // MARK: - Fixtures

    /// A server with a two rung ladder, one pool and optionally one
    /// collection, all read from the variables an operator writes.
    private static func configuration(withCollection: Bool = false) throws -> GatingConfiguration {
        var environment: [String: String] = [
            TokenProfile.assetIdKey: String(Fixture.assetId),
            TokenProfile.symbolKey: "TOKEN",
            TokenProfile.decimalsKey: "6",
            "TIER_1_NAME": "Holder",
            "TIER_1_MIN": "100",
            "TIER_1_ROLE_ID": "role-holder",
            "TIER_2_NAME": "Elite",
            "TIER_2_MIN": "1_000",
            "TIER_2_ROLE_ID": "role-elite",
            LiquidityConfiguration.providerRoleKey: "role-lp"
        ]
        for (key, value) in Fixture.poolEnvironment() {
            environment[key] = value
        }
        if withCollection {
            environment["COLLECTION_1_ID"] = "passes"
            environment["COLLECTION_1_NAME"] = "Passes"
            environment["COLLECTION_1_CREATOR"] = "CREATOR-ACCOUNT"
            environment["COLLECTION_1_ROLE_ID"] = "role-pass"
        }
        return try GatingConfiguration.load(from: environment)
    }

    /// One wallet, read.
    private static func check(
        directWholeTokens: UInt64,
        poolTokens: UInt64,
        reserves: [String: PoolReserves],
        configuration: GatingConfiguration,
        address: String = Fixture.wallet(1),
        extraHoldings: [ChainHolding] = []
    ) throws -> WalletCheck {
        var holdings = extraHoldings
        holdings.append(
            Fixture.holding(
                Fixture.assetId,
                try configuration.token.amountBaseUnits(whole: directWholeTokens)
            )
        )
        holdings.append(Fixture.holding(Fixture.lpAssetId, poolTokens))
        return WalletCheck.read(
            address: address,
            holdings: holdings,
            token: configuration.token,
            pools: configuration.pools.pools,
            reserves: reserves
        )
    }
}
