import Chain
import Foundation
import Gating
import Store
import StoreSQLite
@testable import Runtime

/// The pieces every suite here boots with, none of which touch anything.
///
/// The store is `SQLiteStore.inMemory()` or a file under the test's own
/// temporary directory, the chain is a stub, the chat is a spy, and the only
/// socket is a loopback bind on port zero. Nothing reaches a real chain, a
/// real server or a real account (RT-030, BUILD-2.b).
///
/// Every value below is an obvious label rather than anything that could be a
/// real account, asset or server, because a fixture that looks real ends up
/// pasted into an explorer by the next person to read it (ADOPT-7).
internal enum Fixture {

    // MARK: - Settings

    /// A complete set of settings, which loads with no refusal.
    ///
    /// - Parameters:
    ///   - storePath: Where the store would go.
    ///   - port: The port to bind. Zero lets the operating system choose.
    ///   - extras: Anything else to set, or a key mapped to nil to unset one.
    internal static func settings(
        storePath: String = "/tmp/runtime-tests-does-not-exist/store.db",
        port: String = "0",
        extras: [String: String?] = [:]
    ) -> Settings {
        var values: [String: String] = [
            TokenProfile.assetIdKey: "4242",
            TokenProfile.symbolKey: "TOKEN",
            TokenProfile.decimalsKey: "6",
            "TIER_1_NAME": "Bronze",
            "TIER_1_MIN": "100",
            "TIER_1_ROLE_ID": "role-bronze",
            "TIER_2_NAME": "Silver",
            "TIER_2_MIN": "1000",
            "TIER_2_ROLE_ID": "role-silver",
            ChainEnvironment.nodeURL: "https://node.example",
            RuntimeEnvironment.storePath: storePath,
            RuntimeEnvironment.healthPort: port,
            RuntimeEnvironment.healthAddress: "127.0.0.1"
        ]
        for (key, value) in extras {
            if let value {
                values[key] = value
            } else {
                values.removeValue(forKey: key)
            }
        }
        return Settings(values)
    }

    /// Every variable in the complete fixture, so a test can take one away at
    /// a time.
    ///
    /// A required family is here as its first member, because that is what
    /// the requirement actually is: `Gating` refuses without `TIER_1_NAME`
    /// and then without `TIER_1_MIN` for that rung, and a catalogue that
    /// marked the ladder optional would send an operator who set exactly what
    /// the listing flagged into two more refusals.
    internal static var requiredNames: [String] {
        [
            TokenProfile.assetIdKey,
            TokenProfile.symbolKey,
            TokenProfile.decimalsKey,
            TierConfiguration.firstRungKey,
            "TIER_1_MIN",
            ChainEnvironment.nodeURL,
            RuntimeEnvironment.storePath,
            RuntimeEnvironment.healthPort
        ]
    }

    // MARK: - Seams

    /// Seams that boot cleanly: a store in memory, a node that agrees, no
    /// chat and no probe.
    internal static func seams(
        output: RecordingOutput,
        store: any StoreOpening = InMemoryStoreOpener(),
        chain: any ChainSourceProviding = StubChainSource(),
        chat: (any ChatGateway)? = nil,
        spending: SpendCapability = .cannotSpend,
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) -> RuntimeSeams {
        RuntimeSeams(
            store: store,
            chain: chain,
            chat: chat,
            output: output,
            spending: spending,
            now: now
        )
    }
}

/// A store in memory, opened through the same seam the durable one uses.
internal struct InMemoryStoreOpener: StoreOpening {

    internal let migrations: [String]
    internal let createdFile: Bool

    internal init(migrations: [String] = ["0001-initial"], createdFile: Bool = false) {
        self.migrations = migrations
        self.createdFile = createdFile
    }

    internal func open(path: String) async throws -> OpenedStore {
        OpenedStore(
            store: try await SQLiteStore.inMemory(),
            migrationsApplied: migrations,
            createdFile: createdFile
        )
    }
}

/// A store that refuses, so the gate's two refusals can both be exercised.
internal struct RefusingStoreOpener: StoreOpening {

    internal let error: StoreGateError

    internal init(_ error: StoreGateError) {
        self.error = error
    }

    internal func open(path: String) async throws -> OpenedStore {
        throw error
    }
}

/// A node that answers whatever the test says it answers.
internal struct StubAccountDataSource: AccountDataSource {

    internal let assetDecimals: UInt64
    internal let failure: (any Error)?

    internal init(assetDecimals: UInt64 = 6, failure: (any Error)? = nil) {
        self.assetDecimals = assetDecimals
        self.failure = failure
    }

    internal func account(address: String) async throws -> ChainAccount {
        if let failure { throw failure }
        return ChainAccount(address: address, nativeBalance: 0, holdings: [])
    }

    internal func assetDetails(assetId: UInt64) async throws -> ChainAssetDetails {
        if let failure { throw failure }
        return ChainAssetDetails(
            id: assetId,
            creator: "CREATOR-ACCOUNT",
            decimals: assetDecimals,
            total: 1_000_000
        )
    }

    internal func isValidAddress(_ address: String) -> Bool {
        !address.isEmpty
    }
}

/// The chain seam, answering with a stub and never a probe.
internal struct StubChainSource: ChainSourceProviding {

    internal let assetDecimals: UInt64
    internal let failure: (any Error)?
    internal let probe: (any HTTPHeaderProbe)?

    internal init(
        assetDecimals: UInt64 = 6,
        failure: (any Error)? = nil,
        probe: (any HTTPHeaderProbe)? = nil
    ) {
        self.assetDecimals = assetDecimals
        self.failure = failure
        self.probe = probe
    }

    internal func dataSource(for configuration: ChainConfiguration) throws -> any AccountDataSource {
        StubAccountDataSource(assetDecimals: assetDecimals, failure: failure)
    }

    internal func proofProbe(for configuration: ChainConfiguration) -> (any HTTPHeaderProbe)? {
        probe
    }
}

/// A chat gateway that records what happened to it and in what order.
internal actor SpyChatGateway: ChatGateway {

    /// What was called, in the order it was called.
    internal private(set) var calls: [String] = []

    /// What the bind produced, when connect was reached.
    internal private(set) var boundWhenConnected: ListenerBound?

    internal init() {}

    internal func connect(afterBinding listener: ListenerBound) async throws {
        calls.append("connect")
        boundWhenConnected = listener
    }

    internal func roleIds(ofMember member: String) async throws -> Set<String> {
        calls.append("roleIds")
        return []
    }

    internal func setRoles(ofMember member: String, to roleIds: Set<String>) async throws {
        calls.append("setRoles")
    }

    internal func disconnect() async {
        calls.append("disconnect")
    }
}

/// A probe that counts how many times it was asked.
internal actor CountingHeaderProbe: HTTPHeaderProbe {

    /// How many times the probe was actually made.
    internal private(set) var probes = 0

    private let headers: [String: String]

    internal init(headers: [String: String] = ["x-served-by": "edge-1"]) {
        self.headers = headers
    }

    internal func probeHeaders() async throws -> [String: String] {
        probes += 1
        return headers
    }
}

/// A node that answers nothing until a test says so.
///
/// What the sixth gate waiting on somebody else's provider looks like from
/// inside a test, without waiting for a real timeout.
internal actor SlowNode {

    private var released = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    internal init() {}

    /// Returns once ``release()`` has been called.
    internal func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    /// Lets everything waiting carry on.
    internal func release() {
        released = true
        let resuming = waiting
        waiting = []
        for continuation in resuming {
            continuation.resume()
        }
    }
}

/// A data source that answers only once the test releases it.
internal struct BlockingAccountDataSource: AccountDataSource {

    internal let node: SlowNode

    internal func account(address: String) async throws -> ChainAccount {
        await node.waitForRelease()
        return ChainAccount(address: address, nativeBalance: 0, holdings: [])
    }

    internal func assetDetails(assetId: UInt64) async throws -> ChainAssetDetails {
        await node.waitForRelease()
        return ChainAssetDetails(id: assetId, creator: "CREATOR-ACCOUNT", decimals: 6, total: 1_000_000)
    }

    internal func isValidAddress(_ address: String) -> Bool {
        !address.isEmpty
    }
}

/// The chain seam over a node that answers only when the test lets it.
internal struct BlockingChainSource: ChainSourceProviding {

    internal let node: SlowNode

    internal func dataSource(for configuration: ChainConfiguration) throws -> any AccountDataSource {
        BlockingAccountDataSource(node: node)
    }

    internal func proofProbe(for configuration: ChainConfiguration) -> (any HTTPHeaderProbe)? {
        nil
    }
}

/// Somewhere for a callback to put what it was told.
internal actor Recorded<Value: Sendable> {

    /// What was recorded, or nil while nothing has been.
    internal private(set) var value: Value?

    internal init() {}

    /// Records one value.
    internal func record(_ value: Value) {
        self.value = value
    }
}

/// Waits for something to become true, or gives up.
///
/// Test code waiting on work another task does needs a bound, because a test
/// that hangs says far less than one that fails.
///
/// - Parameters:
///   - deadline: How long to keep asking.
///   - condition: What is being waited for.
/// - Returns: Whether it came true in time.
@discardableResult
internal func waitUntil(
    within deadline: Duration = .seconds(2),
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let started = ContinuousClock.now
    while ContinuousClock.now - started < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
