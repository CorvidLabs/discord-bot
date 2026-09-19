import Foundation
@testable import Gating

/// A server shaped like a real one, written the way an operator would write
/// it.
///
/// Three rungs, two collections (one badge, one count ladder), two pools (one
/// with its own badge, one without), a verified role and one administrator.
/// The shape matters more than the names: it is the combination that has a
/// role for every branch of the decision and a fact for every kind of unread.
enum Fixture {

    // MARK: - Ids

    static let bronze = "role-bronze"
    static let silver = "role-silver"
    static let gold = "role-gold"
    static let passBadge = "role-pass"
    static let palOne = "role-pal-1"
    static let palTen = "role-pal-10"
    static let palFifty = "role-pal-50"
    static let poolBadge = "role-pool-usd"
    static let providerBadge = "role-lp"
    static let verified = "role-verified"

    static let passes = "passes"
    static let pals = "pals"
    static let usdPool = "token_usd"
    static let eurPool = "token_eur"

    // MARK: - The environment

    /// What the operator wrote down.
    static let base: [String: String] = [
        "TOKEN_ASSET_ID": "7001",
        "TOKEN_SYMBOL": "TOKEN",
        "TOKEN_NAME": "Example Token",
        "TOKEN_DECIMALS": "6",
        "TOKEN_LOGO_URL": "https://example.com/logo.png",
        "TOKEN_CARD_COLOR": "#3355ff",
        "TOKEN_LINK_1_LABEL": "Exchange",
        "TOKEN_LINK_1_URL": "https://example.com/swap",

        "TIER_1_NAME": "Bronze",
        "TIER_1_MIN": "100",
        "TIER_1_EMOJI": "[b]",
        "TIER_1_ROLE_ID": bronze,
        "TIER_2_NAME": "Silver",
        "TIER_2_MIN": "1000",
        "TIER_2_ROLE_ID": silver,
        "TIER_3_NAME": "Gold",
        "TIER_3_MIN": "10000",
        "TIER_3_ROLE_ID": gold,

        "COLLECTION_1_ID": passes,
        "COLLECTION_1_NAME": "Passes",
        "COLLECTION_1_CREATOR": "CREATOR-PASSES",
        "COLLECTION_1_NAME_PREFIX": "Pass",
        "COLLECTION_1_ROLE_ID": passBadge,
        "COLLECTION_2_ID": pals,
        "COLLECTION_2_NAME": "Pals",
        "COLLECTION_2_CREATOR": "CREATOR-PALS",
        "COLLECTION_2_UNIT_NAME": "pal",
        "COLLECTION_2_COUNT_1_MIN": "1",
        "COLLECTION_2_COUNT_1_ROLE_ID": palOne,
        "COLLECTION_2_COUNT_2_MIN": "10",
        "COLLECTION_2_COUNT_2_ROLE_ID": palTen,
        "COLLECTION_2_COUNT_3_MIN": "50",
        "COLLECTION_2_COUNT_3_ROLE_ID": palFifty,

        "POOL_1_ID": usdPool,
        "POOL_1_NAME": "TOKEN/USD",
        "POOL_1_LP_ASA": "8001",
        "POOL_1_PAIRED_ASA": "9001",
        "POOL_1_DECIMALS": "6",
        "POOL_1_ROLE_ID": poolBadge,
        "POOL_2_ID": eurPool,
        "POOL_2_NAME": "TOKEN/EUR",
        "POOL_2_LP_ASA": "8002",
        "POOL_2_PAIRED_ASA": "9002",
        "POOL_2_DECIMALS": "6",
        "LP_PROVIDER_ROLE_ID": providerBadge,

        "VERIFIED_ROLE_ID": verified,
        "ADMIN_WALLET_1": "ADMIN-ONE"
    ]

    /// The environment with some variables changed or taken out.
    static func environment(
        overriding overrides: [String: String] = [:],
        removing removed: [String] = []
    ) -> [String: String] {
        var environment = base
        for key in removed {
            environment.removeValue(forKey: key)
        }
        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }

    // MARK: - Pieces

    static func token(decimals: UInt8 = 6) throws -> TokenProfile {
        try TokenProfile(assetId: 7001, symbol: "TOKEN", decimals: decimals)
    }

    static func configuration(
        overriding overrides: [String: String] = [:],
        removing removed: [String] = []
    ) throws -> GatingConfiguration {
        try GatingConfiguration.load(from: environment(overriding: overrides, removing: removed))
    }

    /// Whole tokens as base units at the fixture's six decimals.
    static func whole(_ amount: UInt64) -> UInt64 {
        amount * 1_000_000
    }

    /// A position holding `tokens` whole tokens' worth of the gated asset.
    static func position(_ poolId: String, lp: UInt64 = 1, tokens: UInt64) -> LiquidityPosition {
        LiquidityPosition(poolId: poolId, lpBaseUnits: lp, tokenBaseUnits: whole(tokens))
    }

    /// A member whose every fact was read.
    static func member(
        id: String = "member-1",
        direct: UInt64,
        positions: [LiquidityPosition] = [],
        passes passCount: Int = 0,
        pals palCount: Int = 0
    ) -> MemberHoldings {
        MemberHoldings(
            memberId: id,
            isVerified: true,
            directBalance: .known(whole(direct)),
            liquidityPositions: .known(positions),
            collectionCounts: [
                Fixture.passes: .known(passCount),
                Fixture.pals: .known(palCount)
            ]
        )
    }
}
