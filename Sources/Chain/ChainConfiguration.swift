import Foundation
import Gating

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
///
/// The **token is not one of them**. It is handed in, already read, as
/// ``Gating/TokenProfile``, so the asset id, ticker and decimal places are
/// read from the environment in exactly one place in the whole package. This
/// layer briefly carried its own asset id, ticker and decimals variables
/// beside the ladder's `TOKEN_*` ones: an operator had to write the asset down
/// twice and could write it down differently, and two `decimals` that
/// disagreed would read balances at one precision and decide tiers at another,
/// which is a factor of ten per missing place on every rung of the ladder.
public struct ChainConfiguration: Sendable, Equatable {

    // MARK: - Properties

    /// The token balances are read for, as the layer above loaded it.
    public let token: TokenProfile

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
    ///   - token: The token balances are read for, already loaded by the layer
    ///     above. Its asset id may not be zero: on this chain zero names the
    ///     chain's own currency, which is not an asset an account opts into
    ///     and is not what this reads. An unset variable arriving here as zero
    ///     would otherwise report every member as holding nothing.
    ///   - nodeURL: An absolute `http` or `https` URL.
    ///   - apiToken: The node's token, when it needs one.
    ///   - limits: The two brakes. Defaults are conservative.
    ///   - cacheLifetimes: How long cached answers stay usable.
    ///   - proofHeaderNames: Response headers to copy onto a health answer.
    ///   - verifiesAssetDecimals: Whether boot checks the configured decimals
    ///     against the chain.
    public init(
        token: TokenProfile,
        nodeURL: URL,
        apiToken: String? = nil,
        limits: ChainLimits = ChainLimits(),
        cacheLifetimes: ChainCacheLifetimes = ChainCacheLifetimes(),
        proofHeaderNames: [String] = [],
        verifiesAssetDecimals: Bool = true
    ) throws {
        // Zero is refused here rather than in `TokenProfile`, because it is a
        // fact about this chain rather than about a ladder: a community whose
        // ladder is measured in the chain's own currency is a coherent thing
        // to configure, and a community whose *balances are read from an
        // asset* with id zero is not.
        guard token.assetId > 0 else {
            throw ChainConfigurationError.invalidValue(
                variable: TokenProfile.assetIdKey,
                value: "0",
                expected: "an asset id greater than zero"
            )
        }
        // The same rule the layer above applies to every URL an operator
        // writes down, called rather than restated. Checking the scheme alone,
        // which is what this used to do, accepts `http://`: the process boots
        // clean, every read then fails as a network error, and nothing
        // anywhere names the variable that is wrong.
        guard NumberedEnvironment.isLinkableURL(nodeURL.absoluteString) else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.nodeURL,
                value: nodeURL.absoluteString,
                expected: "an absolute http or https URL with a host"
            )
        }
        self.token = token
        self.nodeURL = nodeURL
        self.apiToken = apiToken
        self.limits = limits
        self.cacheLifetimes = cacheLifetimes
        self.proofHeaderNames = proofHeaderNames.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.verifiesAssetDecimals = verifiesAssetDecimals
    }

    // MARK: - Public Methods

    /// Reads the chain-layer configuration out of a set of environment
    /// variables, around a token that has already been read.
    ///
    /// The token is a **parameter**, not something read here. A host loads it
    /// once with ``Gating/TokenProfile/load(from:)`` and hands the same value
    /// to both layers, so there is one asset id, one ticker and one number of
    /// decimal places in the process.
    ///
    /// Takes the variables as a dictionary rather than reaching for
    /// `ProcessInfo` itself, so every refusal below is reachable from a test.
    /// Use ``loadFromProcessEnvironment(token:)`` in a host.
    ///
    /// A missing required variable is an error naming it, so that an operator
    /// finds out they have set it up wrong before their members do. A missing
    /// optional variable takes the documented default, never somebody else's
    /// value.
    ///
    /// - Parameters:
    ///   - token: The token balances are read for.
    ///   - environment: The variables to read.
    public static func load(
        token: TokenProfile,
        environment: [String: String]
    ) throws -> ChainConfiguration {
        let raw = try requiredString(environment, ChainEnvironment.nodeURL)
        guard let url = URL(string: raw) else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.nodeURL,
                value: raw,
                expected: "an absolute http or https URL with a host"
            )
        }
        return try ChainConfiguration(
            token: token,
            nodeURL: url,
            apiToken: value(environment, ChainEnvironment.apiToken),
            limits: try ChainLimits(environment: environment),
            cacheLifetimes: try ChainCacheLifetimes(environment: environment),
            proofHeaderNames: (value(environment, ChainEnvironment.proofHeaders) ?? "")
                .split(separator: ",")
                .map(String.init),
            verifiesAssetDecimals: try optionalBool(
                environment,
                ChainEnvironment.verifyAssetDecimals,
                default: true
            )
        )
    }

    /// Reads the configuration out of the process environment, around a token
    /// the host has already loaded.
    ///
    /// - Parameter token: The token balances are read for.
    public static func loadFromProcessEnvironment(token: TokenProfile) throws -> ChainConfiguration {
        try load(token: token, environment: ProcessInfo.processInfo.environment)
    }

    // MARK: - Internal Methods

    /// A variable's value, with surrounding whitespace removed, or nil when it
    /// is unset or blank.
    ///
    /// Blank counts as unset because a variable set to the empty string in a
    /// deployment file is somebody having meant to fill it in.
    ///
    /// Delegated to ``Gating/NumberedEnvironment/nonEmpty(_:_:)`` rather than
    /// spelled out again, so the two layers cannot disagree about what "set"
    /// means. They did: this one trimmed newlines and the layer above did not,
    /// so a variable with the trailing newline a file gives it was a value
    /// here and a refusal one layer down. An operator has one environment, not
    /// one per module, and should not have to know which module reads which
    /// line.
    internal static func value(_ environment: [String: String], _ name: String) -> String? {
        NumberedEnvironment.nonEmpty(name) { environment[$0] }
    }

    /// A variable that has to be set to something.
    internal static func requiredString(_ environment: [String: String], _ name: String) throws -> String {
        guard let found = value(environment, name) else {
            throw ChainConfigurationError.missing(variable: name)
        }
        return found
    }

    /// A variable with a default, parsed by the caller.
    ///
    /// Digit separators come out before `parse` sees the value, by
    /// ``Gating/NumberedEnvironment/withoutDigitSeparators(_:)``, which is the
    /// one place that rule lives. The ladder above has always allowed
    /// `TIER_1_MIN=100_000`, on the stated grounds that somebody typing a
    /// number with nine zeros in it will use separators and should not be
    /// punished for it, and a daily request budget is exactly such a number;
    /// this layer used to refuse it. One environment, one rule.
    ///
    /// The refusal stays a ``ChainConfigurationError`` rather than becoming
    /// the layer above's, because each one carries the sentence saying what
    /// *this* variable expected, and "a batch of at least one wallet" is worth
    /// more to the person reading it than "is not a whole number".
    internal static func optional<Value>(
        _ environment: [String: String],
        _ name: String,
        parse: (String) -> Value?,
        expected: String,
        default fallback: Value
    ) throws -> Value {
        guard let raw = value(environment, name) else { return fallback }
        guard let parsed = parse(NumberedEnvironment.withoutDigitSeparators(raw)) else {
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

    /// The share of the day's budget one member's caller may draw, as a
    /// percentage. Zero turns shares off.
    ///
    /// Five by default, which is a judgement rather than a measurement: it is
    /// chosen to be safe on a small budget, and the first operator to run this
    /// at scale will have a better number than this default does. With no
    /// daily budget set it does nothing, because there is no day's budget to
    /// take a part of.
    public let callerSharePercent: Int

    /// The most one member's caller may take before their allowance has to
    /// refill. Clamped to the day's share when it is larger.
    public let callerBurstRequests: UInt64

    /// One caller's share, or nil when there is no share at all.
    ///
    /// Derived rather than configured, so the two settings and the day's
    /// budget cannot drift apart into a share nobody wrote down.
    public var callerShare: CallerShareRule? {
        CallerShareRule(
            dailyRequestBudget: dailyRequestBudget,
            percent: callerSharePercent,
            burstRequests: callerBurstRequests
        )
    }

    // MARK: - Initializers

    /// - Parameters:
    ///   - requestsPerSecond: One or more, and finite. Anything smaller is
    ///     raised to one by the limiter: a bucket that cannot hold a single
    ///     request hands none out, and its callers wait rather than fail.
    ///   - batchSize: Must be at least one.
    ///   - dailyRequestBudget: Zero means no budget.
    ///   - budgetPersistEvery: Must be at least one.
    ///   - callerSharePercent: Zero to one hundred, and held there. Zero turns
    ///     shares off.
    ///   - callerBurstRequests: At least one, and held there.
    public init(
        requestsPerSecond: Double = 10,
        batchSize: Int = 50,
        dailyRequestBudget: UInt64 = 0,
        budgetPersistEvery: UInt64 = 25,
        callerSharePercent: Int = 5,
        callerBurstRequests: UInt64 = 10
    ) {
        self.requestsPerSecond = requestsPerSecond
        self.batchSize = batchSize
        self.dailyRequestBudget = dailyRequestBudget
        self.budgetPersistEvery = budgetPersistEvery
        // The two share settings are held inside the range the parameters
        // above promise, because neither failure is visible where it is made.
        // A percentage above a hundred reaches `CallerShareRule` as a
        // multiplication that can overflow and kill the process on a computed
        // property, nowhere near the value that caused it, and a burst of
        // nothing makes the rule nil, which switches the whole guard off in
        // silence. The loader refuses both by name, because an operator wrote
        // those and is owed the refusal; a caller writing Swift is owed the
        // range its own documentation states.
        self.callerSharePercent = Swift.min(Swift.max(callerSharePercent, 0), 100)
        self.callerBurstRequests = Swift.max(callerBurstRequests, 1)
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
        // Above a hundred is refused rather than clamped: a host that wrote
        // 500 meant something, and quietly turning it into "all of it" is the
        // kind of setting that is discovered a year later.
        let sharePercent = try ChainConfiguration.optional(
            environment,
            ChainEnvironment.callerSharePercent,
            parse: Int.init,
            expected: "a share of the day's budget from 0 to 100 percent, where 0 turns shares off",
            default: 5
        )
        guard sharePercent >= 0, sharePercent <= 100 else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.callerSharePercent,
                value: String(sharePercent),
                expected: "a share of the day's budget from 0 to 100 percent, where 0 turns shares off"
            )
        }
        let burst = try ChainConfiguration.optional(
            environment,
            ChainEnvironment.callerBurstRequests,
            parse: UInt64.init,
            expected: "at least one request in a burst",
            default: 10
        )
        guard burst >= 1 else {
            throw ChainConfigurationError.invalidValue(
                variable: ChainEnvironment.callerBurstRequests,
                value: String(burst),
                expected: "at least one request in a burst"
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
            budgetPersistEvery: persistEvery,
            callerSharePercent: sharePercent,
            callerBurstRequests: burst
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
