import Foundation
import Testing
@testable import Chain

/// Not asking the chain the same question over and over.
@Suite("Remembering what a wallet held")
internal struct WalletCheckCacheTests {

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Reusing an answer

    @Test("A wallet read a moment ago is not read again")
    internal func cachedAnswerIsReused() async throws {
        let log = CallLog()
        let cache = try Self.cache(
            accounts: [
                Fixture.wallet(1): Fixture.account(
                    Fixture.wallet(1),
                    holdings: [Fixture.holding(Fixture.assetId, 42)]
                )
            ],
            log: log
        )
        _ = await cache.check(wallets: [Fixture.wallet(1)], for: Fixture.member(), now: Self.noon)
        let again = await cache.check(
            wallets: [Fixture.wallet(1)],
            for: Fixture.member(),
            now: Self.noon.addingTimeInterval(10)
        )
        #expect(again.first?.directBalance.completeValue == 42)
        #expect(await log.count == 1)
    }

    @Test("An answer past its lifetime is read again")
    internal func staleAnswerIsRefreshed() async throws {
        let log = CallLog()
        let cache = try Self.cache(
            accounts: [Fixture.wallet(1): Fixture.account(Fixture.wallet(1))],
            lifetimes: ChainCacheLifetimes(walletCheck: 30, walletCheckCooldown: 0),
            log: log
        )
        _ = await cache.check(wallets: [Fixture.wallet(1)], for: Fixture.member(), now: Self.noon)
        _ = await cache.check(
            wallets: [Fixture.wallet(1)],
            for: Fixture.member(),
            now: Self.noon.addingTimeInterval(31)
        )
        #expect(await log.count == 2)
    }

    // MARK: - What is never remembered

    @Test("A wallet that could not be read is never remembered as empty")
    internal func incompleteReadsAreNotRemembered() async throws {
        let log = CallLog()
        let cache = try Self.cache(
            accounts: [:],
            failures: [Fixture.wallet(1): ChainError.network("connection reset")],
            lifetimes: ChainCacheLifetimes(walletCheck: 300, walletCheckCooldown: 0),
            log: log
        )
        let first = await cache.check(wallets: [Fixture.wallet(1)], for: Fixture.member(), now: Self.noon)
        #expect(first.first?.combinedBalance.isComplete == false)
        // Asked again rather than served a failure for the next five minutes.
        _ = await cache.check(wallets: [Fixture.wallet(1)], for: Fixture.member(), now: Self.noon.addingTimeInterval(1))
        #expect(await log.count == 2)
        #expect(await cache.cachedCount == 0)
    }

    @Test("The same wallet twice in one list is one question, not two")
    internal func duplicatesAreAskedOnce() async throws {
        let log = CallLog()
        let cache = try Self.cache(
            accounts: [
                Fixture.wallet(1): Fixture.account(
                    Fixture.wallet(1),
                    holdings: [Fixture.holding(Fixture.assetId, 7)]
                )
            ],
            log: log
        )
        let results = await cache.check(
            wallets: [Fixture.wallet(1), Fixture.wallet(1)],
            for: Fixture.member(),
            now: Self.noon
        )
        // Both callers get their answer; the chain is asked once for it.
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.directBalance.completeValue == 7 })
        #expect(await log.count == 1)
    }

    // MARK: - The cooldown

    @Test("A wallet asked about a moment ago is left alone even when a fresh read is demanded")
    internal func cooldownBoundsForcedReads() async throws {
        let log = CallLog()
        let cache = try Self.cache(
            accounts: [Fixture.wallet(1): Fixture.account(Fixture.wallet(1))],
            lifetimes: ChainCacheLifetimes(walletCheck: 300, walletCheckCooldown: 60),
            log: log
        )
        _ = await cache.check(wallets: [Fixture.wallet(1)], for: Fixture.member(), now: Self.noon)
        #expect(await cache.isOnCooldown(Fixture.wallet(1), now: Self.noon.addingTimeInterval(30)))
        _ = await cache.check(
            wallets: [Fixture.wallet(1)],
            for: Fixture.member(),
            forceFresh: true,
            now: Self.noon.addingTimeInterval(30)
        )
        #expect(await log.count == 1)

        // Past the cooldown, a demanded fresh read is honoured.
        #expect(await cache.shouldCheck(Fixture.wallet(1), now: Self.noon.addingTimeInterval(61)))
        _ = await cache.check(
            wallets: [Fixture.wallet(1)],
            for: Fixture.member(),
            forceFresh: true,
            now: Self.noon.addingTimeInterval(61)
        )
        #expect(await log.count == 2)
    }

    @Test("Linking a wallet forgets what was known about it, so the answer is not five minutes old")
    internal func invalidationForcesAFreshRead() async throws {
        let log = CallLog()
        let cache = try Self.cache(
            accounts: [Fixture.wallet(1): Fixture.account(Fixture.wallet(1))],
            log: log
        )
        _ = await cache.check(wallets: [Fixture.wallet(1)], for: Fixture.member(), now: Self.noon)
        await cache.invalidate(Fixture.wallet(1))
        #expect(await cache.cachedCount == 0)
        _ = await cache.check(wallets: [Fixture.wallet(1)], for: Fixture.member(), now: Self.noon)
        #expect(await log.count == 2)
    }

    @Test("Everything can be forgotten at once")
    internal func invalidateAll() async throws {
        let cache = try Self.cache(
            accounts: [
                Fixture.wallet(1): Fixture.account(Fixture.wallet(1)),
                Fixture.wallet(2): Fixture.account(Fixture.wallet(2))
            ]
        )
        _ = await cache.check(wallets: [Fixture.wallet(1), Fixture.wallet(2)], for: Fixture.member(), now: Self.noon)
        #expect(await cache.cachedCount == 2)
        await cache.invalidateAll()
        #expect(await cache.cachedCount == 0)
        #expect(await cache.cooldownCount == 0)
    }

    @Test("A mix of remembered and new wallets comes back in the order asked for")
    internal func mixedAnswersKeepTheirOrder() async throws {
        let cache = try Self.cache(
            accounts: [
                Fixture.wallet(1): Fixture.account(
                    Fixture.wallet(1),
                    holdings: [Fixture.holding(Fixture.assetId, 1)]
                ),
                Fixture.wallet(2): Fixture.account(
                    Fixture.wallet(2),
                    holdings: [Fixture.holding(Fixture.assetId, 2)]
                )
            ]
        )
        _ = await cache.check(wallets: [Fixture.wallet(2)], for: Fixture.member(), now: Self.noon)
        let results = await cache.check(
            wallets: [Fixture.wallet(1), Fixture.wallet(2)],
            for: Fixture.member(),
            now: Self.noon.addingTimeInterval(1)
        )
        #expect(results.map(\.address) == [Fixture.wallet(1), Fixture.wallet(2)])
        #expect(results.compactMap { $0.directBalance.completeValue } == [1, 2])
    }

    // MARK: - Fixtures

    private static func cache(
        accounts: [String: ChainAccount],
        failures: [String: any Error] = [:],
        lifetimes: ChainCacheLifetimes = ChainCacheLifetimes(),
        log: CallLog = CallLog()
    ) throws -> WalletCheckCache {
        let configuration = try Fixture.configuration(
            limits: ChainLimits(requestsPerSecond: 10_000),
            cacheLifetimes: lifetimes
        )
        let reader = ChainReader(
            configuration: configuration,
            dataSource: StubAccountDataSource(accounts: accounts, failures: failures, log: log),
            governor: Fixture.openGovernor()
        )
        return WalletCheckCache(
            reader: BatchedChainReader(reader: reader),
            pools: [],
            lifetimes: lifetimes
        )
    }
}
