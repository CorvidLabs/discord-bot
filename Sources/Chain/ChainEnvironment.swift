import Foundation

/// The names of the environment variables this layer reads.
///
/// Held in one place so a refusal can name the exact variable to set, and so
/// the documentation and the error message cannot drift apart. An operator who
/// has set something wrong should never have to grep the source to find out
/// what it was called.
public enum ChainEnvironment: Sendable {

    // MARK: - The asset

    /// The on chain id of the asset balances are read for. Required.
    public static let assetId = "CHAIN_ASSET_ID"

    /// The ticker shown to people. Required, because a default would be
    /// somebody else's word appearing in a stranger's server.
    public static let assetSymbol = "CHAIN_ASSET_SYMBOL"

    /// The asset's decimal places. Required, and deliberately never six by
    /// default.
    public static let assetDecimals = "CHAIN_ASSET_DECIMALS"

    /// Whether to read the asset's decimals from the chain at boot and refuse
    /// to start when they disagree with ``assetDecimals``. Defaults to on.
    public static let verifyAssetDecimals = "CHAIN_VERIFY_ASSET_DECIMALS"

    // MARK: - The node

    /// The node this reads from. Required.
    public static let nodeURL = "CHAIN_NODE_URL"

    /// The node's API token, when it needs one.
    public static let apiToken = "CHAIN_API_TOKEN"

    /// Response header names copied onto a health answer as proof of which
    /// provider actually served the request. Comma separated, empty by default.
    public static let proofHeaders = "CHAIN_PROOF_HEADERS"

    // MARK: - The two brakes

    /// Requests per second the limiter allows.
    public static let requestsPerSecond = "CHAIN_REQUESTS_PER_SECOND"

    /// Requests permitted per UTC day. Zero means no budget.
    ///
    /// A **budget** counts requests. It is not a spending cap and must never be
    /// called one: the catalogue this was ported from had to retire a criterion
    /// because one word covered both, and a reader took the daily request
    /// budget and the weekly spending cap for the same thing.
    public static let dailyRequestBudget = "CHAIN_DAILY_REQUEST_BUDGET"

    /// How many requests pass between writes of the day's counter.
    public static let budgetPersistEvery = "CHAIN_BUDGET_PERSIST_EVERY"

    /// How many wallets are read in parallel per batch.
    public static let batchSize = "CHAIN_BATCH_SIZE"

    // MARK: - Cache lifetimes

    /// Seconds a pool's reserves stay usable before they are read again.
    public static let poolCacheSeconds = "CHAIN_POOL_CACHE_SECONDS"

    /// Seconds a completed wallet reading stays usable.
    public static let walletCacheSeconds = "CHAIN_WALLET_CACHE_SECONDS"

    /// Seconds before the same wallet may be read again on demand.
    public static let walletCooldownSeconds = "CHAIN_WALLET_COOLDOWN_SECONDS"

    /// Seconds a health probe's answer is reused.
    public static let healthProbeSeconds = "CHAIN_HEALTH_PROBE_CACHE_SECONDS"
}
