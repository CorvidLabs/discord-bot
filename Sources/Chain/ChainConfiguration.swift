import Foundation

/// Everything this layer needs to know before it reads anything.
///
/// The bot this was ported from had these numbers written into the source: a
/// rate tuned for one commercial provider's published ceiling here, a batch of
/// fifty there, a five minute cache in a third file and a one minute cache in a
/// fourth. None of them were wrong for that deployment and all of them were
/// wrong for somebody else's provider. They are configuration here, and the
/// defaults are the cautious end rather than that deployment's tuning: the
/// first run of this belongs to somebody pointing it at a free tier, and an
/// operator who knows what their provider allows can say so in one variable.
/// Every one of them is validated at boot, so a typo is a refusal that names
/// the variable rather than a bot that behaves oddly in a month.
public struct ChainConfiguration: Sendable, Equatable {

    // MARK: - Properties

    /// The asset balances are read for.
    public let asset: ChainAsset

    /// The node to read from.
    public let nodeURL: URL

    /// The node's API token, when it needs one.
    public let apiToken: String?

    /// The two brakes, and how work is batched.
    public let limits: ChainLimits

    /// How long each cached answer stays usable.
    public let cacheLifetimes: ChainCacheLifetimes

    /// Response headers copied onto a health answer as proof of which provider
    /// served the request.
    public let proofHeaderNames: [String]

    /// Whether to read the asset's decimals from the chain at boot and refuse
    /// to start when they disagree with what was configured.
    public let verifiesAssetDecimals: Bool

    // MARK: - Initializers

    /// - Parameters:
    ///   - asset: The asset balances are read for.
    ///   - nodeURL: An absolute `http` or `https` URL.
    ///   - apiToken: The node's token, when it needs one.
    ///   - limits: The two brakes. Defaults are conservative.
    ///   - cacheLifetimes: How long cached answers stay usable.
    ///   - proofHeaderNames: Response headers to copy onto a health answer.
    ///   - verifiesAssetDecimals: Whether boot checks the configured decimals
    ///     against the chain.
    public init(
        asset: ChainAsset,
        nodeURL: URL,
        apiToken: String? = nil,
        limits: ChainLimits = ChainLimits(),
        cacheLifetimes: ChainCacheLifetimes = ChainCacheLifetimes(),
        proofHeaderNames: [String] = [],
        verifiesAssetDecimals: Bool = true
    ) throws {
        guard let scheme = nodeURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.nodeURL,
                value: nodeURL.absoluteString,
                expected: "an absolute http or https URL"
            )
        }
        self.asset = asset
        self.nodeURL = nodeURL
        self.apiToken = apiToken
        self.limits = limits
        self.cacheLifetimes = cacheLifetimes
        self.proofHeaderNames = proofHeaderNames.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.verifiesAssetDecimals = verifiesAssetDecimals
    }

    // MARK: - Public Methods

    /// Reads the whole configuration out of a set of environment variables.
    ///
    /// Takes the variables as a dictionary rather than reaching for
    /// `ProcessInfo` itself, so every refusal below is reachable from a test.
    /// Use ``fromProcessEnvironment()`` in a host.
    ///
    /// A missing required variable is an error naming it, so that an operator
    /// finds out they have set it up wrong before their members do. A missing
    /// optional variable takes the documented default, never somebody else's
    /// value.
    public static func from(environment: [String: String]) throws -> ChainConfiguration {
        let asset = try ChainAsset(
            id: try required(environment, ChainEnvironment.assetId, parse: UInt64.init, expected: "a whole number"),
            symbol: try requiredString(environment, ChainEnvironment.assetSymbol),
            decimals: try required(
                environment,
                ChainEnvironment.assetDecimals,
                parse: UInt8.init,
                expected: "0 to 19 decimal places"
            )
        )
        let raw = try requiredString(environment, ChainEnvironment.nodeURL)
        guard let url = URL(string: raw) else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.nodeURL,
                value: raw,
                expected: "an absolute http or https URL"
            )
        }
        return try ChainConfiguration(
            asset: asset,
            nodeURL: url,
            apiToken: value(environment, ChainEnvironment.apiToken),
            limits: try ChainLimits(environment: environment),
            cacheLifetimes: try ChainCacheLifetimes(environment: environment),
            proofHeaderNames: (value(environment, ChainEnvironment.proofHeaders) ?? "")
                .split(separator: ",")
                .map { String($0) },
            verifiesAssetDecimals: try optionalBool(
                environment,
                ChainEnvironment.verifyAssetDecimals,
                default: true
            )
        )
    }

    /// Reads the configuration out of the process environment.
    public static func fromProcessEnvironment() throws -> ChainConfiguration {
        try from(environment: ProcessInfo.processInfo.environment)
    }

    // MARK: - Internal Methods

    /// A variable's value, with surrounding whitespace removed, or nil when it
    /// is unset or blank.
    ///
    /// Blank counts as unset because a variable set to the empty string in a
    /// deployment file is somebody having meant to fill it in.
    internal static func value(_ environment: [String: String], _ name: String) -> String? {
        guard let raw = environment[name] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    internal static func requiredString(_ environment: [String: String], _ name: String) throws -> String {
        guard let found = value(environment, name) else {
            throw ChainConfigurationError.missing(variable: name)
        }
        return found
    }

    internal static func required<Value>(
        _ environment: [String: String],
        _ name: String,
        parse: (String) -> Value?,
        expected: String
    ) throws -> Value {
        let raw = try requiredString(environment, name)
        guard let parsed = parse(raw) else {
            throw ChainConfigurationError.invalidValue(variable: name, value: raw, expected: expected)
        }
        return parsed
    }

    internal static func optional<Value>(
        _ environment: [String: String],
        _ name: String,
        parse: (String) -> Value?,
        expected: String,
        default fallback: Value
    ) throws -> Value {
        guard let raw = value(environment, name) else { return fallback }
        guard let parsed = parse(raw) else {
            throw ChainConfigurationError.invalidValue(variable: name, value: raw, expected: expected)
        }
        return parsed
    }

    internal static func optionalBool(
        _ environment: [String: String],
        _ name: String,
        default fallback: Bool
    ) throws -> Bool {
        try optional(
            environment,
            name,
            parse: { raw in
                switch raw.lowercased() {
                case "1", "true", "yes", "on": return true
                case "0", "false", "no", "off": return false
                default: return nil
                }
            },
            expected: "true or false",
            default: fallback
        )
    }
}

/// The two brakes on how hard the chain is read, and how work is batched.
///
/// **Both brakes are needed, and they measure different things.** The limiter
/// bounds requests per second, which is what a provider's own rate limit cares
/// about. The budget bounds requests per UTC day. At the limiter's rate a free
/// daily quota is reachable in minutes, and the provider's refusal only arrives
/// once the quota is already spent, which is far too late to do anything about.
public struct ChainLimits: Sendable, Equatable {

    // MARK: - Properties

    /// Requests per second the limiter allows.
    ///
    /// Conservative on purpose. Raise it to whatever your provider publishes,
    /// leaving a little headroom: running at exactly the published rate turns a
    /// clock difference of a few milliseconds into a refusal. The shipped
    /// default is low enough to be safe on the smallest free tier, because that
    /// is what the first person to try this will point it at, and a default
    /// nobody chose should not be the thing that spends their quota.
    public let requestsPerSecond: Double

    /// How many wallets are read in parallel per batch.
    public let batchSize: Int

    /// Requests permitted per UTC day, counting reads **and** signing, so the
    /// number is the whole process rather than one code path. Zero means no
    /// budget.
    ///
    /// Zero by default because a budget an operator did not choose would refuse
    /// work in a healthy deployment, and only the operator knows what their
    /// provider allows. Anybody on a metered or free tier should set it.
    public let dailyRequestBudget: UInt64

    /// How many requests pass between writes of the day's counter. A crash
    /// loses at most this many requests of the day's count.
    public let budgetPersistEvery: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - requestsPerSecond: One or more, and finite. Anything smaller is
    ///     raised to one by the limiter: a bucket that cannot hold a single
    ///     request hands none out, and its callers wait rather than fail.
    ///   - batchSize: Must be at least one.
    ///   - dailyRequestBudget: Zero means no budget.
    ///   - budgetPersistEvery: Must be at least one.
    public init(
        requestsPerSecond: Double = 10,
        batchSize: Int = 50,
        dailyRequestBudget: UInt64 = 0,
        budgetPersistEvery: UInt64 = 25
    ) {
        self.requestsPerSecond = requestsPerSecond
        self.batchSize = batchSize
        self.dailyRequestBudget = dailyRequestBudget
        self.budgetPersistEvery = budgetPersistEvery
    }

    /// Reads the limits from environment variables, refusing anything unusable.
    public init(environment: [String: String]) throws {
        let requestsPerSecond = try ChainConfiguration.optional(
            environment,
            ChainEnvironment.requestsPerSecond,
            parse: Double.init,
            expected: "a finite number of requests per second, one or more",
            default: 10
        )
        // One or more, not merely above zero. Below a single request a second
        // the limiter's bucket cannot hold the request its caller is waiting
        // for, and waiting is all that caller does.
        guard requestsPerSecond >= 1, requestsPerSecond.isFinite else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.requestsPerSecond,
                value: String(requestsPerSecond),
                expected: "a finite number of requests per second, one or more"
            )
        }
        let batchSize = try ChainConfiguration.optional(
            environment,
            ChainEnvironment.batchSize,
            parse: Int.init,
            expected: "a batch of at least one wallet",
            default: 50
        )
        guard batchSize >= 1 else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.batchSize,
                value: String(batchSize),
                expected: "a batch of at least one wallet"
            )
        }
        let persistEvery = try ChainConfiguration.optional(
            environment,
            ChainEnvironment.budgetPersistEvery,
            parse: UInt64.init,
            expected: "at least one request between writes",
            default: 25
        )
        guard persistEvery >= 1 else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.budgetPersistEvery,
                value: String(persistEvery),
                expected: "at least one request between writes"
            )
        }
        self.init(
            requestsPerSecond: requestsPerSecond,
            batchSize: batchSize,
            dailyRequestBudget: try ChainConfiguration.optional(
                environment,
                ChainEnvironment.dailyRequestBudget,
                parse: UInt64.init,
                expected: "a whole number of requests, or 0 for no budget",
                default: 0
            ),
            budgetPersistEvery: persistEvery
        )
    }
}

/// How long each cached answer stays usable.
///
/// Every one of these was a literal in the bot this came from. They are the
/// difference between a command that answers instantly and a command that
/// spends the day's request budget on autocomplete.
public struct ChainCacheLifetimes: Sendable, Equatable {

    // MARK: - Properties

    /// Seconds a pool's reserves stay usable. Reserves move with every trade,
    /// so this is short.
    public let poolReserves: TimeInterval

    /// Seconds a completed wallet reading stays usable.
    public let walletCheck: TimeInterval

    /// Seconds before the same wallet may be read again on demand.
    ///
    /// Separate from ``walletCheck`` on purpose: the cache answers a question
    /// cheaply, the cooldown refuses to ask the chain the same question over
    /// and over because somebody is typing in a channel.
    public let walletCheckCooldown: TimeInterval

    /// Seconds a health probe's answer is reused, so a monitoring check every
    /// few seconds does not become traffic to the node.
    public let healthProbe: TimeInterval

    // MARK: - Initializers

    /// - Parameters:
    ///   - poolReserves: Seconds. Zero means never cached.
    ///   - walletCheck: Seconds. Zero means never cached.
    ///   - walletCheckCooldown: Seconds. Zero means no cooldown.
    ///   - healthProbe: Seconds. Zero means probe every time.
    public init(
        poolReserves: TimeInterval = 60,
        walletCheck: TimeInterval = 300,
        walletCheckCooldown: TimeInterval = 60,
        healthProbe: TimeInterval = 30
    ) {
        self.poolReserves = poolReserves
        self.walletCheck = walletCheck
        self.walletCheckCooldown = walletCheckCooldown
        self.healthProbe = healthProbe
    }

    /// Reads the lifetimes from environment variables, refusing a negative one.
    public init(environment: [String: String]) throws {
        func seconds(_ name: String, _ fallback: TimeInterval) throws -> TimeInterval {
            let parsed = try ChainConfiguration.optional(
                environment,
                name,
                parse: TimeInterval.init,
                expected: "a number of seconds, zero or more",
                default: fallback
            )
            guard parsed >= 0, parsed.isFinite else {
                throw ChainConfigurationError.invalidValue(
                    variable: name,
                    value: String(parsed),
                    expected: "a number of seconds, zero or more"
                )
            }
            return parsed
        }
        self.init(
            poolReserves: try seconds(ChainEnvironment.poolCacheSeconds, 60),
            walletCheck: try seconds(ChainEnvironment.walletCacheSeconds, 300),
            walletCheckCooldown: try seconds(ChainEnvironment.walletCooldownSeconds, 60),
            healthProbe: try seconds(ChainEnvironment.healthProbeSeconds, 30)
        )
    }
}
