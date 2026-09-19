import Foundation

/// One asset an account holds.
public struct ChainHolding: Sendable, Equatable, Hashable, Codable {

    // MARK: - Properties

    /// The asset's on chain id.
    public let assetId: UInt64

    /// How much of it, in the asset's smallest unit.
    public let amount: UInt64

    /// Whether the holding is frozen by the asset's manager.
    public let isFrozen: Bool

    // MARK: - Initializers

    /// One holding, as a node reported it.
    public init(assetId: UInt64, amount: UInt64, isFrozen: Bool = false) {
        self.assetId = assetId
        self.amount = amount
        self.isFrozen = isFrozen
    }
}

/// What an account holds, as one read of the chain returned it.
public struct ChainAccount: Sendable, Equatable {

    // MARK: - Properties

    /// The account's address.
    public let address: String

    /// The chain's own currency, in its smallest unit. Fees and the minimum
    /// balance come out of this; nothing in this layer pays anybody with it.
    public let nativeBalance: UInt64

    /// Every asset the account has opted into, including the ones it holds
    /// none of.
    public let holdings: [ChainHolding]

    /// Assets this account created, when the read included them.
    public let createdAssets: [ChainAssetDetails]

    // MARK: - Initializers

    /// One account, as a single read of it returned it.
    public init(
        address: String,
        nativeBalance: UInt64,
        holdings: [ChainHolding],
        createdAssets: [ChainAssetDetails] = []
    ) {
        self.address = address
        self.nativeBalance = nativeBalance
        self.holdings = holdings
        self.createdAssets = createdAssets
    }
}

/// What the chain says about an asset.
public struct ChainAssetDetails: Sendable, Equatable {

    // MARK: - Properties

    /// The asset's on chain id.
    public let id: UInt64

    /// The account that created it.
    public let creator: String

    /// Decimal places, as the chain has them.
    ///
    /// Kept as the chain's own width rather than narrowed on the way in, so
    /// that comparing it with the configured value compares what is really
    /// there. A nonsensical value from a node is a disagreement to report, not
    /// something to quietly truncate.
    public let decimals: UInt64

    /// The whole supply, in the asset's smallest unit.
    public let total: UInt64

    /// The short name, when it has one.
    public let unitName: String?

    /// The long name, when it has one.
    public let name: String?

    /// The asset's url, when it has one.
    public let url: String?

    /// The account named as the asset's reserve, when it has one. For a pool
    /// token this is the account holding the pool.
    public let reserveAddress: String?

    // MARK: - Initializers

    /// One asset's record, as a node reported it.
    public init(
        id: UInt64,
        creator: String,
        decimals: UInt64,
        total: UInt64,
        unitName: String? = nil,
        name: String? = nil,
        url: String? = nil,
        reserveAddress: String? = nil
    ) {
        self.id = id
        self.creator = creator
        self.decimals = decimals
        self.total = total
        self.unitName = unitName
        self.name = name
        self.url = url
        self.reserveAddress = reserveAddress
    }
}

/// Where readings of the chain come from.
///
/// A seam rather than a concrete client, and the reason is specific: in the bot
/// this was ported from, the money adjacent code talked to a real node through
/// a concrete type, so **not one of its failure paths had ever been run**. The
/// paths that matter here are all failures. A node that answers 404, a node
/// that refuses on quota, a list that arrives half read: each of those decides
/// whether somebody keeps a role, and each of them is reachable from a test
/// only because this protocol exists.
public protocol AccountDataSource: Sendable {

    /// Everything one account holds, in one request.
    ///
    /// One request rather than one per asset, because a member with fifty
    /// opt-ins would otherwise cost fifty requests of the day's budget to read
    /// once.
    func account(address: String) async throws -> ChainAccount

    /// What the chain says about one asset.
    func assetDetails(assetId: UInt64) async throws -> ChainAssetDetails

    /// Whether a string is a canonical address on this chain.
    ///
    /// Checked before a request goes out, so a typo costs nothing from the
    /// day's budget.
    func isValidAddress(_ address: String) -> Bool
}

extension Array where Element == ChainHolding {

    /// How much of `assetId` this account holds, or zero when it has not opted
    /// in.
    ///
    /// Only ever called on a list that was really read. Calling it on a list
    /// that failed to arrive is the mistake ``ChainReading`` exists to make
    /// hard.
    public func amount(of assetId: UInt64) -> UInt64 {
        first { $0.assetId == assetId }?.amount ?? 0
    }

    /// The assets actually held. An opt-in with a zero balance is not a
    /// holding: somebody who opted into a collection and never received one
    /// does not hold anything from it.
    public var positiveBalanceAssetIds: [UInt64] {
        filter { $0.amount > 0 }.map(\.assetId)
    }
}
