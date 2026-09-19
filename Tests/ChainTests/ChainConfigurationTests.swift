import Foundation
import Gating
import Testing
@testable import Chain

/// Setting it up, and finding out at boot when it is set up wrong.
///
/// Every refusal here names the variable to fix. An operator who has mistyped
/// something should be told which thing, in the message, at the moment the
/// process comes up, rather than finding out from a member asking why their
/// role disappeared.
@Suite("Setting the chain layer up")
internal struct ChainConfigurationTests {

    // MARK: - One token, read once

    @Test("The token is handed in rather than read again, so there is one asset id in the process")
    internal func tokenComesFromTheLayerAbove() throws {
        // What the ladder is measured in and what balances are read for are
        // the same value, loaded once. Setting the asset twice is what this
        // layer used to ask for, and two figures that disagreed would read
        // balances at one precision and decide tiers at another.
        let gating = try GatingConfiguration.load(from: Self.gatingEnvironment)
        let chain = try ChainConfiguration.load(token: gating.token, environment: Self.minimal)
        #expect(chain.token == gating.token)
        #expect(chain.token.assetId == 4_242)
        #expect(chain.token.decimals == 6)
        #expect(chain.token.symbol == "TOKEN")
    }

    @Test("An asset id of zero is refused, because an unset variable arrives as zero")
    internal func assetIdZeroRefused() throws {
        // Zero names the chain's own currency, which is not an asset anybody
        // opts into. A zero here would report every member as holding nothing.
        let unset = try TokenProfile(assetId: 0, symbol: "TOKEN", decimals: 6)
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: TokenProfile.assetIdKey,
            value: "0",
            expected: "an asset id greater than zero"
        )) {
            _ = try ChainConfiguration.load(token: unset, environment: Self.minimal)
        }
    }

    // MARK: - What has no default

    @Test("Without an asset id the token refuses to load and names the variable")
    internal func assetIdIsRequired() {
        #expect(throws: GatingConfigurationError.self) {
            _ = try TokenProfile.load(from: [
                TokenProfile.symbolKey: "TOKEN",
                TokenProfile.decimalsKey: "6"
            ])
        }
    }

    @Test("Without the token's decimals it refuses rather than assuming six")
    internal func decimalsAreRequired() {
        #expect(throws: GatingConfigurationError.self) {
            _ = try TokenProfile.load(from: [
                TokenProfile.assetIdKey: "4242",
                TokenProfile.symbolKey: "TOKEN"
            ])
        }
    }

    @Test("Without a symbol it refuses rather than printing somebody else's word")
    internal func symbolIsRequired() {
        #expect(throws: GatingConfigurationError.self) {
            _ = try TokenProfile.load(from: [
                TokenProfile.assetIdKey: "4242",
                TokenProfile.decimalsKey: "6"
            ])
        }
    }

    @Test("A blank symbol counts as unset rather than being printed as nothing")
    internal func blankSymbolRefused() {
        #expect(throws: GatingConfigurationError.self) {
            _ = try TokenProfile.load(from: [
                TokenProfile.assetIdKey: "4242",
                TokenProfile.symbolKey: "   ",
                TokenProfile.decimalsKey: "6"
            ])
        }
    }

    @Test("Without a node to read from it refuses and names the variable")
    internal func nodeIsRequired() throws {
        #expect(throws: ChainConfigurationError.missing(variable: ChainEnvironment.nodeURL)) {
            _ = try ChainConfiguration.load(
                token: try Fixture.token(),
                environment: Self.minimal.filter { $0.key != ChainEnvironment.nodeURL }
            )
        }
    }

    @Test("A variable set to blank counts as unset, because somebody meant to fill it in")
    internal func blankIsUnset() throws {
        #expect(throws: ChainConfigurationError.missing(variable: ChainEnvironment.nodeURL)) {
            var environment = Self.minimal
            environment[ChainEnvironment.nodeURL] = "   "
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    @Test("A node url that is not http refuses, naming what was expected")
    internal func nodeMustBeHTTP() throws {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.nodeURL,
            value: "ftp://node.example",
            expected: "an absolute http or https URL with a host"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.nodeURL] = "ftp://node.example"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    @Test("A node url with no host refuses at boot rather than failing every read later")
    internal func nodeMustHaveAHost() throws {
        // Checking the scheme and nothing else, which is what this used to
        // do, boots clean on `http://` and then turns every read of the chain
        // into a network error that names no variable. The layer above has
        // always required a host of a URL an operator writes down; the rule
        // is called now rather than stated twice and differently.
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.nodeURL,
            value: "http://",
            expected: "an absolute http or https URL with a host"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.nodeURL] = "http://"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    // MARK: - One set of rules for one environment

    @Test("A number written with digit separators is a number in both layers")
    internal func digitSeparatorsAreReadEverywhere() throws {
        // `TIER_1_MIN=100_000` has always loaded, on the stated grounds that
        // somebody typing a number with nine zeros in it will use separators.
        // `CHAIN_DAILY_REQUEST_BUDGET=100_000` used to be refused, and a daily
        // request budget is exactly such a number. One environment, one rule.
        var gating = Self.gatingEnvironment
        gating["TIER_1_MIN"] = "100_000"
        var chain = Self.minimal
        chain[ChainEnvironment.dailyRequestBudget] = "100_000"
        chain[ChainEnvironment.batchSize] = "1_000"

        let token = try TokenProfile.load(from: gating)
        let configuration = try ChainConfiguration.load(token: token, environment: chain)
        #expect(configuration.limits.dailyRequestBudget == 100_000)
        #expect(configuration.limits.batchSize == 1_000)
        #expect(try GatingConfiguration.load(from: gating).ladder.rungs.first?.minimumBaseUnits
            == token.baseUnits(whole: 100_000))
    }

    @Test("A variable written on the last line of a file is the value without its newline")
    internal func trailingNewlinesComeOffInBothLayers() throws {
        // Every one of these arrives from a file, and a file's last line ends
        // in a newline. This layer trimmed it and the layer above did not, so
        // the same line was a value here and a refusal there.
        var gating = Self.gatingEnvironment
        gating[TokenProfile.decimalsKey] = "6\n"
        gating["TIER_1_MIN"] = "100\n"
        var chain = Self.minimal
        chain[ChainEnvironment.nodeURL] = "https://node.example\n"
        chain[ChainEnvironment.batchSize] = "7\n"

        let token = try TokenProfile.load(from: gating)
        #expect(token.decimals == 6)
        #expect(throws: Never.self) { try GatingConfiguration.load(from: gating) }
        let configuration = try ChainConfiguration.load(token: token, environment: chain)
        #expect(configuration.limits.batchSize == 7)
        #expect(configuration.nodeURL.absoluteString == "https://node.example")
    }

    // MARK: - What has a default

    @Test("With only the required variables set, the brakes take their documented defaults")
    internal func defaults() throws {
        let configuration = try ChainConfiguration.load(token: try Fixture.token(), environment: Self.minimal)
        #expect(configuration.token.assetId == Fixture.assetId)
        #expect(configuration.token.decimals == 6)
        // Cautious, not one deployment's tuning: the default has to be safe
        // on the smallest free tier, and an operator raises it once they know
        // what their provider allows.
        #expect(configuration.limits.requestsPerSecond == 10)
        #expect(configuration.limits.batchSize == 50)
        // No budget unless an operator sets one: a ceiling nobody chose would
        // refuse work in a perfectly healthy deployment.
        #expect(configuration.limits.dailyRequestBudget == 0)
        #expect(configuration.limits.budgetPersistEvery == 25)
        #expect(configuration.cacheLifetimes.poolReserves == 60)
        #expect(configuration.cacheLifetimes.walletCheck == 300)
        #expect(configuration.cacheLifetimes.walletCheckCooldown == 60)
        #expect(configuration.cacheLifetimes.healthProbe == 30)
        #expect(configuration.proofHeaderNames.isEmpty)
        #expect(configuration.verifiesAssetDecimals)
        // The share one member may draw. Five percent and a burst of ten are
        // a judgement rather than a measurement, chosen to be safe on a small
        // budget, and they do nothing at all until a budget is set.
        #expect(configuration.limits.callerSharePercent == 5)
        #expect(configuration.limits.callerBurstRequests == 10)
        #expect(configuration.limits.callerShare == nil)
    }

    @Test("A share is only a share once there is a day's budget to take part of (RUN-11, ADOPT-1)")
    internal func theShareNeedsABudget() throws {
        var environment = Self.minimal
        environment[ChainEnvironment.dailyRequestBudget] = "10_000"
        let configured = try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        let share = try #require(configured.limits.callerShare)
        #expect(share.dailyShareRequests == 500)
        #expect(share.burstRequests == 10)

        // And zero is how an operator turns shares off, as every other zero in
        // this layer means off.
        environment[ChainEnvironment.callerSharePercent] = "0"
        let off = try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        #expect(off.limits.callerShare == nil)
    }

    @Test("A share above the whole day refuses at boot and names the variable (ADOPT-2)")
    internal func shareAboveOneHundredRefused() throws {
        // Refused rather than clamped: an operator who wrote 500 meant
        // something, and quietly turning it into "all of it" is the kind of
        // setting that is discovered a year later.
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.callerSharePercent,
            value: "500",
            expected: "a share of the day's budget from 0 to 100 percent, where 0 turns shares off"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.callerSharePercent] = "500"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    @Test("A share that is not a number, or a burst of nothing, refuses at boot (ADOPT-2)")
    internal func shareAndBurstMustBeUsable() throws {
        #expect(throws: ChainConfigurationError.self) {
            var environment = Self.minimal
            environment[ChainEnvironment.callerSharePercent] = "half"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.callerBurstRequests,
            value: "0",
            expected: "at least one request in a burst"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.callerBurstRequests] = "0"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    @Test("Limits built in Swift keep the range their own documentation states (RUN-11, ADOPT-2)")
    internal func theMemberwiseLimitsHoldTheirRange() {
        // The loader refuses both of these by name, because an operator wrote
        // them and is owed the refusal. This is the other door: a host
        // building limits in Swift, where neither failure is visible where it
        // is made. A percentage above a hundred reaches the share's
        // arithmetic, which can overflow and kill the process on a computed
        // property nowhere near the value that caused it.
        let tooMuch = ChainLimits(dailyRequestBudget: 1_000, callerSharePercent: 500)
        #expect(tooMuch.callerSharePercent == 100)
        #expect(tooMuch.callerShare?.dailyShareRequests == 1_000)

        // And a burst of nothing makes the rule nil, which switches the whole
        // guard off in silence: the shape of a bug nobody finds until one
        // member has spent the day.
        let noBurst = ChainLimits(dailyRequestBudget: 1_000, callerBurstRequests: 0)
        #expect(noBurst.callerBurstRequests == 1)
        #expect(noBurst.callerShare?.burstRequests == 1)

        // Zero percent still means off, which is what every other zero in
        // this layer means.
        #expect(ChainLimits(dailyRequestBudget: 1_000, callerSharePercent: 0).callerShare == nil)
        #expect(ChainLimits(dailyRequestBudget: 1_000, callerSharePercent: -5).callerSharePercent == 0)
    }

    @Test("Every number that used to be written into the source can be set")
    internal func everyKnobIsConfigurable() throws {
        var environment = Self.minimal
        environment[ChainEnvironment.requestsPerSecond] = "12.5"
        environment[ChainEnvironment.batchSize] = "7"
        environment[ChainEnvironment.dailyRequestBudget] = "4000"
        environment[ChainEnvironment.budgetPersistEvery] = "5"
        environment[ChainEnvironment.poolCacheSeconds] = "90"
        environment[ChainEnvironment.walletCacheSeconds] = "120"
        environment[ChainEnvironment.walletCooldownSeconds] = "15"
        environment[ChainEnvironment.healthProbeSeconds] = "10"
        environment[ChainEnvironment.proofHeaders] = "x-served-by, x-tier"
        environment[ChainEnvironment.callerSharePercent] = "20"
        environment[ChainEnvironment.callerBurstRequests] = "3"
        environment[ChainEnvironment.verifyAssetDecimals] = "false"
        environment[ChainEnvironment.apiToken] = "a-token"

        let configuration = try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        #expect(configuration.limits.requestsPerSecond == 12.5)
        #expect(configuration.limits.batchSize == 7)
        #expect(configuration.limits.dailyRequestBudget == 4_000)
        #expect(configuration.limits.budgetPersistEvery == 5)
        #expect(configuration.cacheLifetimes.poolReserves == 90)
        #expect(configuration.cacheLifetimes.walletCheck == 120)
        #expect(configuration.cacheLifetimes.walletCheckCooldown == 15)
        #expect(configuration.cacheLifetimes.healthProbe == 10)
        #expect(configuration.proofHeaderNames == ["x-served-by", "x-tier"])
        #expect(configuration.verifiesAssetDecimals == false)
        #expect(configuration.apiToken == "a-token")
        #expect(configuration.limits.callerSharePercent == 20)
        #expect(configuration.limits.callerBurstRequests == 3)
        #expect(configuration.limits.callerShare?.dailyShareRequests == 800)
        #expect(configuration.limits.callerShare?.burstRequests == 3)
    }

    @Test("A rate of zero refuses at boot rather than stalling every read later")
    internal func rateMustBePositive() throws {
        #expect(throws: ChainConfigurationError.self) {
            var environment = Self.minimal
            environment[ChainEnvironment.requestsPerSecond] = "0"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    @Test("A rate the limiter could not hold one request at refuses at boot")
    internal func rateMustBeAtLeastOne() throws {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.requestsPerSecond,
            value: "0.5",
            expected: "a finite number of requests per second, one or more"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.requestsPerSecond] = "0.5"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    @Test("A batch of nothing refuses at boot rather than reading nobody")
    internal func batchMustBePositive() throws {
        #expect(throws: ChainConfigurationError.self) {
            var environment = Self.minimal
            environment[ChainEnvironment.batchSize] = "0"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    @Test("A cache lifetime that is not a number refuses and names the variable")
    internal func lifetimeMustParse() throws {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.poolCacheSeconds,
            value: "soon",
            expected: "a number of seconds, zero or more"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.poolCacheSeconds] = "soon"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    @Test("A negative cache lifetime refuses rather than expiring in the past")
    internal func lifetimeMustNotBeNegative() throws {
        #expect(throws: ChainConfigurationError.self) {
            var environment = Self.minimal
            environment[ChainEnvironment.walletCacheSeconds] = "-5"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    @Test("A budget that is not a whole number refuses and says what was expected")
    internal func budgetMustParse() throws {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.dailyRequestBudget,
            value: "lots",
            expected: "a whole number of requests, or 0 for no budget"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.dailyRequestBudget] = "lots"
            return try ChainConfiguration.load(token: try Fixture.token(), environment: environment)
        }
    }

    // MARK: - Pools

    @Test("The pools an operator writes down are the pools this layer reads")
    internal func poolsComeFromTheVariablesAnOperatorCanSet() throws {
        // There is one `LiquidityPool` in the package and its loader is the
        // one reading `POOL_n_*`. This module used to declare a second, which
        // nothing could load: it wanted a symbol and a decimal count for each
        // side of the pair and no variable sets either, so a host wiring the
        // two layers together had to invent them. Going from what somebody
        // typed to a reading is the whole path, and it had no floor under it.
        var environment = Self.gatingEnvironment
        for (key, value) in Fixture.poolEnvironment() {
            environment[key] = value
        }
        let gating = try GatingConfiguration.load(from: environment)
        let pools = gating.pools.pools
        #expect(pools.count == 1)
        #expect(throws: Never.self) { try LiquidityPool.validate(pools) }

        let check = WalletCheck.read(
            address: Fixture.wallet(1),
            holdings: [Fixture.holding(Fixture.lpAssetId, 100_000)],
            token: gating.token,
            pools: pools,
            reserves: [pools[0].id: Fixture.reserves(pool: pools[0])]
        )
        #expect(check.liquidityAmount.completeValue == 100_000_000)
    }

    @Test("A pool with no LP token is refused, because an unset variable arrives as zero")
    internal func poolTokenRequired() {
        let unset = LiquidityPool(
            id: "unset",
            lpAssetId: 0,
            pairedAssetId: Fixture.pairedAssetId,
            decimals: 6,
            tokenAssetId: Fixture.assetId
        )
        #expect(throws: ChainConfigurationError.self) {
            try LiquidityPool.validate([unset])
        }
    }

    @Test("A pool whose own token is the counted token is refused, because it would count twice")
    internal func poolTokenMustNotBeTheCountedToken() {
        // A direct holding read once as a balance and once as a pool position
        // puts somebody on a rung they did not earn, and nothing about the
        // number looks wrong.
        let doubled = LiquidityPool(
            id: "doubled",
            lpAssetId: Fixture.assetId,
            pairedAssetId: Fixture.pairedAssetId,
            decimals: 6,
            tokenAssetId: Fixture.assetId
        )
        #expect(throws: ChainConfigurationError.self) {
            try LiquidityPool.validate([doubled])
        }
    }

    @Test("A pool paired with itself is refused, because there is no other side to value it against")
    internal func poolMustHaveTwoSides() {
        #expect(throws: ChainConfigurationError.self) {
            try LiquidityPool.validate([Fixture.pool(id: "self-paired", paired: Fixture.assetId)])
        }
    }

    @Test("Two pools sharing an id are refused rather than one of them vanishing")
    internal func duplicatePoolIdsRefused() throws {
        #expect(throws: ChainConfigurationError.duplicatePoolId("same")) {
            try LiquidityPool.validate([Fixture.pool(id: "same"), Fixture.pool(id: "same")])
        }
        #expect(throws: Never.self) {
            try LiquidityPool.validate([Fixture.pool(id: "one"), Fixture.pool(id: "two")])
        }
    }

    // MARK: - Fixtures

    /// Everything this layer needs and nothing about the asset: the token
    /// arrives as a value.
    private static let minimal: [String: String] = [
        ChainEnvironment.nodeURL: "https://node.example"
    ]

    /// What the layer above reads the one token from.
    private static let gatingEnvironment: [String: String] = [
        TokenProfile.assetIdKey: "4242",
        TokenProfile.symbolKey: "TOKEN",
        TokenProfile.decimalsKey: "6",
        "TIER_1_NAME": "Holder",
        "TIER_1_MIN": "100"
    ]
}
