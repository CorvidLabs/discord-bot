import Chain
import Foundation
import Gating
import Store
@testable import Sweep

/// A server shaped like a real one: three rungs, one collection with a
/// badge, one pool with a badge, a verified role, and a hand-granted role
/// the bot knows nothing about.
///
/// The combination matters more than the names. It has a role for every
/// branch of the decision and a fact for every kind of unread, which is what
/// lets one fixture exercise the hold, the demotion and the orphan pass.
enum Fixture {

    // MARK: - Ids

    static let bronze = "role-bronze"
    static let silver = "role-silver"
    static let gold = "role-gold"
    static let passBadge = "role-pass"
    static let poolBadge = "role-pool"
    static let providerBadge = "role-provider"
    static let verified = "role-verified"

    /// A role a moderator hands out by hand. Nothing configured mentions it.
    static let handGranted = "role-moderator"

    static let passes = "passes"
    static let pool = "token_usd"

    static let tokenAsset: UInt64 = 7001
    static let poolAsset: UInt64 = 8001
    static let pairedAsset: UInt64 = 9001
    static let passAsset: UInt64 = 5001

    // MARK: - Configuration

    static let environment: [String: String] = [
        "TOKEN_ASSET_ID": "7001",
        "TOKEN_SYMBOL": "TOKEN",
        "TOKEN_NAME": "Example Token",
        "TOKEN_DECIMALS": "6",

        "TIER_1_NAME": "Bronze",
        "TIER_1_MIN": "100",
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

        "POOL_1_ID": pool,
        "POOL_1_NAME": "TOKEN/USD",
        "POOL_1_LP_ASA": "8001",
        "POOL_1_PAIRED_ASA": "9001",
        "POOL_1_DECIMALS": "6",
        "POOL_1_ROLE_ID": poolBadge,
        "LP_PROVIDER_ROLE_ID": providerBadge,

        "VERIFIED_ROLE_ID": verified
    ]

    static func configuration(
        overriding overrides: [String: String] = [:],
        removing removed: [String] = []
    ) throws -> GatingConfiguration {
        var values = environment
        for key in removed {
            values.removeValue(forKey: key)
        }
        for (key, value) in overrides {
            values[key] = value
        }
        return try GatingConfiguration.load(from: values)
    }

    /// Whole tokens as base units at the fixture's six decimals.
    static func whole(_ amount: UInt64) -> UInt64 {
        amount * 1_000_000
    }

    /// The catalogue that says which asset is a pass.
    static let catalogue = StaticCollectionRegistry(assets: [passAsset: passes])

    // MARK: - Members

    static func member(externalId: String, addresses: [String], at instant: Date = .distantPast) -> SweptMember {
        let key = MemberKey.mint()
        return SweptMember(
            member: MemberRecord(key: key, externalId: externalId, firstSeenAt: instant),
            accounts: addresses.map { AccountRecord(memberKey: key, address: $0, provenAt: instant) }
        )
    }

    /// A member admitted to a real store, with their accounts proved, so
    /// the write-back path has rows to write to.
    static func admit(
        _ store: InMemoryStore,
        externalId: String,
        addresses: [String],
        at instant: Date = Date(timeIntervalSince1970: 1_600_000_000)
    ) async throws -> SweptMember {
        let record = try await store.admitMember(externalId: externalId, at: instant)
        var accounts: [AccountRecord] = []
        for address in addresses {
            let account = AccountRecord(memberKey: record.key, address: address, provenAt: instant)
            try await store.prove(account: account)
            accounts.append(account)
        }
        return SweptMember(member: record, accounts: accounts)
    }

    // MARK: - Readings

    /// A wallet read right through: the token, optionally a pass, and no
    /// pool position.
    static func read(_ address: String, tokens: UInt64, passes passCount: Int = 0) -> WalletCheck {
        var holdings = [ChainHolding(assetId: tokenAsset, amount: whole(tokens))]
        for index in 0..<passCount {
            holdings.append(ChainHolding(assetId: passAsset + UInt64(index), amount: 1))
        }
        return WalletCheck(
            address: address,
            holdings: .complete(holdings),
            directBalance: .complete(whole(tokens)),
            liquidityAmount: .complete(0),
            poolTokenBalances: [pool: 0],
            poolCountedAmounts: [pool: 0]
        )
    }

    /// A wallet nobody could read at all.
    static func unreadable(_ address: String) -> WalletCheck {
        WalletCheck.unreadable(address: address, gap: .requestFailed("provider refused"))
    }

    /// A wallet whose token balance read but whose pool could not be
    /// converted into an amount, which is the reading that demoted a room
    /// full of liquidity providers.
    static func shortLiquidity(_ address: String, tokens: UInt64) -> WalletCheck {
        WalletCheck(
            address: address,
            holdings: .complete([
                ChainHolding(assetId: tokenAsset, amount: whole(tokens)),
                ChainHolding(assetId: poolAsset, amount: 500)
            ]),
            directBalance: .complete(whole(tokens)),
            liquidityAmount: .short(0, gaps: [.poolReservesUnavailable(poolId: pool)]),
            poolTokenBalances: [pool: 500],
            poolCountedAmounts: [:]
        )
    }
}
