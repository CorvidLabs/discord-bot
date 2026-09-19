import Foundation

/// The names of the environment variables this layer reads.
///
/// Held in one place so a refusal can name the exact variable to set, and so
/// the documentation and the error message cannot drift apart. An operator who
/// has set something wrong should never have to grep the source to find out
/// what it was called.
///
/// **There are no variables for the asset here.** Which asset, what it is
/// called and how many decimal places it has are read once, by
/// ``Gating/TokenProfile``, from `TOKEN_ASSET_ID`, `TOKEN_SYMBOL` and
/// `TOKEN_DECIMALS`, and handed to ``ChainConfiguration`` as a value. This
/// layer briefly had an asset id, a ticker and a decimals variable of its own,
/// which asked an operator to write the asset down twice and let them write it
/// down differently.
public enum ChainEnvironment: Sendable {

    // MARK: - The token

    /// Whether to read the token's decimals from the chain at boot and refuse
    /// to start when they disagree with the configured `TOKEN_DECIMALS`.
    /// Defaults to on.
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

    // MARK: - One caller's share of the day

    /// The share of the day's request budget one member may draw, as a
    /// percentage. Zero turns shares off, and above a hundred is refused.
    ///
    /// A percentage rather than a count because budgets differ by orders of
    /// magnitude between a free tier and a paid one, and one absolute number
    /// would be wrong at one end or the other. With no daily budget set there
    /// is no share at all, because there is no day's budget to take a part of.
    public static let callerSharePercent = "CHAIN_CALLER_SHARE_PERCENT"

    /// The most one member may take before their allowance has to refill.
    ///
    /// A burst as well as a rate, because "however fast they type" is a rate
    /// problem and a daily quota alone locks a member out for the rest of the
    /// day after a busy morning.
    public static let callerBurstRequests = "CHAIN_CALLER_BURST_REQUESTS"

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
