import Foundation
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

    // MARK: - What has no default

    @Test("Without an asset id it refuses to start and names the variable")
    internal func assetIdIsRequired() {
        #expect(throws: ChainConfigurationError.missing(variable: ChainEnvironment.assetId)) {
            _ = try ChainConfiguration.from(environment: [
                ChainEnvironment.assetSymbol: "TOKEN",
                ChainEnvironment.assetDecimals: "6",
                ChainEnvironment.nodeURL: "https://node.example"
            ])
        }
    }

    @Test("Without the asset's decimals it refuses rather than assuming six")
    internal func decimalsAreRequired() {
        #expect(throws: ChainConfigurationError.missing(variable: ChainEnvironment.assetDecimals)) {
            _ = try ChainConfiguration.from(environment: [
                ChainEnvironment.assetId: "4242",
                ChainEnvironment.assetSymbol: "TOKEN",
                ChainEnvironment.nodeURL: "https://node.example"
            ])
        }
    }

    @Test("Without a symbol it refuses rather than printing somebody else's word")
    internal func symbolIsRequired() {
        #expect(throws: ChainConfigurationError.missing(variable: ChainEnvironment.assetSymbol)) {
            _ = try ChainConfiguration.from(environment: [
                ChainEnvironment.assetId: "4242",
                ChainEnvironment.assetDecimals: "6",
                ChainEnvironment.nodeURL: "https://node.example"
            ])
        }
    }

    @Test("Without a node to read from it refuses and names the variable")
    internal func nodeIsRequired() {
        #expect(throws: ChainConfigurationError.missing(variable: ChainEnvironment.nodeURL)) {
            _ = try ChainConfiguration.from(environment: Self.minimal.filter {
                $0.key != ChainEnvironment.nodeURL
            })
        }
    }

    @Test("A variable set to blank counts as unset, because somebody meant to fill it in")
    internal func blankIsUnset() {
        #expect(throws: ChainConfigurationError.missing(variable: ChainEnvironment.assetSymbol)) {
            var environment = Self.minimal
            environment[ChainEnvironment.assetSymbol] = "   "
            return try ChainConfiguration.from(environment: environment)
        }
    }

    @Test("A node url that is not http refuses, naming what was expected")
    internal func nodeMustBeHTTP() {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.nodeURL,
            value: "ftp://node.example",
            expected: "an absolute http or https URL"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.nodeURL] = "ftp://node.example"
            return try ChainConfiguration.from(environment: environment)
        }
    }

    // MARK: - What has a default

    @Test("With only the required variables set, the brakes take their documented defaults")
    internal func defaults() throws {
        let configuration = try ChainConfiguration.from(environment: Self.minimal)
        #expect(configuration.asset.id == 4_242)
        #expect(configuration.asset.decimals == 6)
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
        environment[ChainEnvironment.verifyAssetDecimals] = "false"
        environment[ChainEnvironment.apiToken] = "a-token"

        let configuration = try ChainConfiguration.from(environment: environment)
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
    }

    @Test("A rate of zero refuses at boot rather than stalling every read later")
    internal func rateMustBePositive() {
        #expect(throws: ChainConfigurationError.self) {
            var environment = Self.minimal
            environment[ChainEnvironment.requestsPerSecond] = "0"
            return try ChainConfiguration.from(environment: environment)
        }
    }

    @Test("A rate the limiter could not hold one request at refuses at boot")
    internal func rateMustBeAtLeastOne() {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.requestsPerSecond,
            value: "0.5",
            expected: "a finite number of requests per second, one or more"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.requestsPerSecond] = "0.5"
            return try ChainConfiguration.from(environment: environment)
        }
    }

    @Test("A batch of nothing refuses at boot rather than reading nobody")
    internal func batchMustBePositive() {
        #expect(throws: ChainConfigurationError.self) {
            var environment = Self.minimal
            environment[ChainEnvironment.batchSize] = "0"
            return try ChainConfiguration.from(environment: environment)
        }
    }

    @Test("A cache lifetime that is not a number refuses and names the variable")
    internal func lifetimeMustParse() {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.poolCacheSeconds,
            value: "soon",
            expected: "a number of seconds, zero or more"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.poolCacheSeconds] = "soon"
            return try ChainConfiguration.from(environment: environment)
        }
    }

    @Test("A negative cache lifetime refuses rather than expiring in the past")
    internal func lifetimeMustNotBeNegative() {
        #expect(throws: ChainConfigurationError.self) {
            var environment = Self.minimal
            environment[ChainEnvironment.walletCacheSeconds] = "-5"
            return try ChainConfiguration.from(environment: environment)
        }
    }

    @Test("A budget that is not a whole number refuses and says what was expected")
    internal func budgetMustParse() {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.dailyRequestBudget,
            value: "lots",
            expected: "a whole number of requests, or 0 for no budget"
        )) {
            var environment = Self.minimal
            environment[ChainEnvironment.dailyRequestBudget] = "lots"
            return try ChainConfiguration.from(environment: environment)
        }
    }

    // MARK: - Pools

    @Test("A pool counting an asset it does not hold is refused at boot")
    internal func poolMustHoldWhatItCounts() {
        #expect(throws: ChainConfigurationError.poolCountsAnAssetItDoesNotHold(
            poolId: "wrong",
            assetId: 99
        )) {
            _ = try LiquidityPool(
                id: "wrong",
                name: "Wrong",
                poolTokenId: Fixture.poolTokenId,
                poolTokenDecimals: 6,
                assetA: PoolSide(assetId: Fixture.assetId, symbol: "TOKEN", decimals: 6),
                assetB: PoolSide(assetId: Fixture.pairedAssetId, symbol: "PAIR", decimals: 6),
                countedAssetId: 99
            )
        }
    }

    @Test("A pool with no pool token is refused, because an unset variable arrives as zero")
    internal func poolTokenRequired() {
        #expect(throws: ChainConfigurationError.self) {
            _ = try LiquidityPool(
                id: "unset",
                name: "Unset",
                poolTokenId: 0,
                poolTokenDecimals: 6,
                assetA: PoolSide(assetId: Fixture.assetId, symbol: "TOKEN", decimals: 6),
                assetB: PoolSide(assetId: Fixture.pairedAssetId, symbol: "PAIR", decimals: 6),
                countedAssetId: Fixture.assetId
            )
        }
    }

    @Test("Two pools sharing an id are refused rather than one of them vanishing")
    internal func duplicatePoolIdsRefused() throws {
        let pools = [try Fixture.pool(id: "same"), try Fixture.pool(id: "same")]
        #expect(throws: ChainConfigurationError.duplicatePoolId("same")) {
            try LiquidityPool.validate(pools)
        }
        #expect(throws: Never.self) {
            try LiquidityPool.validate([try Fixture.pool(id: "one"), try Fixture.pool(id: "two")])
        }
    }

    // MARK: - Fixtures

    private static let minimal: [String: String] = [
        ChainEnvironment.assetId: "4242",
        ChainEnvironment.assetSymbol: "TOKEN",
        ChainEnvironment.assetDecimals: "6",
        ChainEnvironment.nodeURL: "https://node.example"
    ]
}
