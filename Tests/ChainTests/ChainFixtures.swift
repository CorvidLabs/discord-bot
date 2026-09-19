import Foundation
@testable import Chain

/// The pieces the suites read the chain with, none of which touch a network.
///
/// Every address here is an obvious label rather than anything that could be a
/// real account on any chain, and every asset id is small. A fixture that looks
/// like somebody's real wallet ends up pasted into an explorer by the next
/// person to read it.
internal enum Fixture {

    // MARK: - Ids

    /// The asset an operator has configured. Small, and nobody's.
    internal static let assetId: UInt64 = 4_242

    /// A pool token id.
    internal static let poolTokenId: UInt64 = 5_150

    /// The other side of the pair.
    internal static let pairedAssetId: UInt64 = 7_007

    /// An asset from a collection a role might depend on.
    internal static let collectibleId: UInt64 = 9_001

    // MARK: - Labels

    /// An obviously fake wallet label.
    internal static func wallet(_ index: Int) -> String {
        String(format: "WALLET-%04d", index)
    }

    /// The account a pool's reserves sit in.
    internal static let poolAccount = "POOL-ACCOUNT"

    // MARK: - Pieces

    internal static func asset(decimals: UInt8 = 6) throws -> ChainAsset {
        try ChainAsset(id: assetId, symbol: "TOKEN", decimals: decimals)
    }

    internal static func nodeURL() throws -> URL {
        guard let url = URL(string: "https://node.example") else {
            throw ChainError.network("the fixture's node url would not parse")
        }
        return url
    }

    internal static func configuration(
        decimals: UInt8 = 6,
        limits: ChainLimits = ChainLimits(),
        cacheLifetimes: ChainCacheLifetimes = ChainCacheLifetimes(),
        proofHeaderNames: [String] = [],
        verifiesAssetDecimals: Bool = true
    ) throws -> ChainConfiguration {
        try ChainConfiguration(
            asset: try asset(decimals: decimals),
            nodeURL: try nodeURL(),
            limits: limits,
            cacheLifetimes: cacheLifetimes,
            proofHeaderNames: proofHeaderNames,
            verifiesAssetDecimals: verifiesAssetDecimals
        )
    }

    internal static func pool(id: String = "pair-one") throws -> LiquidityPool {
        try LiquidityPool(
            id: id,
            name: "TOKEN / PAIR",
            poolTokenId: poolTokenId,
            poolTokenDecimals: 6,
            assetA: PoolSide(assetId: assetId, symbol: "TOKEN", decimals: 6),
            assetB: PoolSide(assetId: pairedAssetId, symbol: "PAIR", decimals: 6),
            countedAssetId: assetId
        )
    }

    /// A pool holding a round amount of each side, so a share is easy to check
    /// by hand.
    internal static func reserves(
        pool: LiquidityPool,
        counted: UInt64 = 1_000_000_000,
        other: UInt64 = 2_000_000,
        circulating: UInt64 = 1_000_000,
        at: Date = Date(timeIntervalSince1970: 0)
    ) -> PoolReserves {
        PoolReserves(
            pool: pool,
            poolAddress: poolAccount,
            assetABalance: counted,
            assetBBalance: other,
            circulatingPoolTokens: circulating,
            readAt: at
        )
    }

    internal static func holding(_ assetId: UInt64, _ amount: UInt64) -> ChainHolding {
        ChainHolding(assetId: assetId, amount: amount)
    }

    internal static func account(
        _ address: String,
        holdings: [ChainHolding] = [],
        native: UInt64 = 100_000,
        createdAssets: [ChainAssetDetails] = []
    ) -> ChainAccount {
        ChainAccount(
            address: address,
            nativeBalance: native,
            holdings: holdings,
            createdAssets: createdAssets
        )
    }

    internal static func assetDetails(
        id: UInt64,
        decimals: UInt64 = 6,
        total: UInt64 = 1_000_000_000,
        reserveAddress: String? = nil
    ) -> ChainAssetDetails {
        ChainAssetDetails(
            id: id,
            creator: "CREATOR-ACCOUNT",
            decimals: decimals,
            total: total,
            unitName: "TOKEN",
            name: "Token",
            url: nil,
            reserveAddress: reserveAddress
        )
    }

    /// A governor with no budget, for suites that are not about the budget.
    internal static func openGovernor() -> RequestGovernor {
        RequestGovernor(limit: 0)
    }
}

/// What a data source was asked for, in order.
internal actor CallLog {

    // MARK: - Properties

    internal private(set) var calls: [String] = []

    // MARK: - Internal Methods

    internal func record(_ call: String) {
        calls.append(call)
    }

    internal var count: Int { calls.count }

    internal func count(of call: String) -> Int {
        calls.filter { $0 == call }.count
    }
}

/// A chain that answers whatever a test tells it to.
///
/// The failure paths are the point. Reading a balance that works is one line
/// of code; what the sweep does when the node refuses, times out, or has never
/// heard of an account is the part that decides whether somebody keeps a role.
internal struct StubAccountDataSource: AccountDataSource {

    // MARK: - Properties

    internal let accounts: [String: ChainAccount]
    internal let assets: [UInt64: ChainAssetDetails]
    internal let failures: [String: any Error]
    internal let assetFailures: [UInt64: any Error]
    internal let log: CallLog

    // MARK: - Initializers

    internal init(
        accounts: [String: ChainAccount] = [:],
        assets: [UInt64: ChainAssetDetails] = [:],
        failures: [String: any Error] = [:],
        assetFailures: [UInt64: any Error] = [:],
        log: CallLog = CallLog()
    ) {
        self.accounts = accounts
        self.assets = assets
        self.failures = failures
        self.assetFailures = assetFailures
        self.log = log
    }

    // MARK: - Internal Methods

    internal func account(address: String) async throws -> ChainAccount {
        await log.record("account:\(address)")
        if let failure = failures[address] { throw failure }
        guard let account = accounts[address] else {
            throw ChainError.api(statusCode: 404, message: "no accounts found for address")
        }
        return account
    }

    internal func assetDetails(assetId: UInt64) async throws -> ChainAssetDetails {
        await log.record("asset:\(assetId)")
        if let failure = assetFailures[assetId] { throw failure }
        guard let details = assets[assetId] else {
            throw ChainError.assetNotFound(assetId: assetId)
        }
        return details
    }

    internal func isValidAddress(_ address: String) -> Bool {
        !address.isEmpty && address.uppercased() == address
    }
}

/// A probe that works and then stops working.
///
/// Needed because the interesting rule is about one probe over time: a fresh
/// instance has nothing cached to go stale, so asking a new one whether it
/// serves stale proof answers nothing at all.
internal struct FadingHeaderProbe: HTTPHeaderProbe {

    // MARK: - Properties

    internal let headers: [String: String]
    internal let failure: any Error
    internal let successes: Int
    internal let log: CallLog

    // MARK: - Initializers

    internal init(
        headers: [String: String],
        failure: any Error,
        successes: Int = 1,
        log: CallLog = CallLog()
    ) {
        self.headers = headers
        self.failure = failure
        self.successes = successes
        self.log = log
    }

    // MARK: - Internal Methods

    internal func probeHeaders() async throws -> [String: String] {
        await log.record("probe")
        guard await log.count <= successes else { throw failure }
        return headers
    }
}

/// A probe that answers with whatever headers a test gives it, or throws.
internal struct StubHeaderProbe: HTTPHeaderProbe {

    // MARK: - Properties

    internal let headers: [String: String]
    internal let failure: (any Error)?
    internal let log: CallLog

    // MARK: - Initializers

    internal init(
        headers: [String: String] = [:],
        failure: (any Error)? = nil,
        log: CallLog = CallLog()
    ) {
        self.headers = headers
        self.failure = failure
        self.log = log
    }

    // MARK: - Internal Methods

    internal func probeHeaders() async throws -> [String: String] {
        await log.record("probe")
        if let failure { throw failure }
        return headers
    }
}
