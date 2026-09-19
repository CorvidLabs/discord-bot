import CSQLite
import Foundation
import Store
import StoreSQLite
import StoreTestKit

/// A directory under the system temporary directory, removed when the body
/// ends.
///
/// A scoped closure rather than a fixture with a teardown, because the testing
/// framework has no teardown and a store that leaves files behind is a store
/// whose tests eventually fill somebody's disk. A killed process leaves a
/// directory the operating system reclaims.
func withTemporaryDirectory<Output>(
    _ body: (String) async throws -> Output
) async throws -> Output {
    let directory = NSTemporaryDirectory() + "store-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(
        atPath: directory,
        withIntermediateDirectories: true
    )
    do {
        let output = try await body(directory)
        try? FileManager.default.removeItem(atPath: directory)
        return output
    } catch {
        try? FileManager.default.removeItem(atPath: directory)
        throw error
    }
}

/// Writing rows the store's own writer refuses to write.
///
/// It reaches the file through its own connection rather than through a method
/// on the store, deliberately. A corruption probe has to get past the checks
/// that exist to stop exactly this, and a store that offered a way to do that
/// would be shipping the hole it is being tested for.
struct SQLiteFileCorruptionProbe: CorruptionProbe {

    // MARK: - Properties

    let path: String

    // MARK: - Internal Methods

    func corruptReserveEpoch(streamId: String, epoch: UInt64) async throws {
        try run(
            """
            PRAGMA ignore_check_constraints = ON;
            UPDATE reserve_epochs SET paid_base_units = x'0102';
            """
        )
    }

    func corruptBudgetUsage() async throws {
        try run(
            """
            PRAGMA ignore_check_constraints = ON;
            UPDATE request_budget SET used_requests = x'0102';
            """
        )
    }

    func corruptAccount(address: String) async throws {
        try run(
            """
            PRAGMA foreign_keys = OFF;
            PRAGMA ignore_check_constraints = ON;
            UPDATE accounts SET member_key = 'not a key at all';
            """
        )
    }

    func corruptReserveState() async throws {
        try run(
            """
            PRAGMA ignore_check_constraints = ON;
            UPDATE reserve_streams SET completed_epochs = x'0102';
            """
        )
    }

    func corruptRoleBaseline() async throws {
        try run(
            """
            PRAGMA ignore_check_constraints = ON;
            UPDATE role_baseline SET verified_member_count = 'not a count';
            """
        )
    }

    // MARK: - Private Methods

    private func run(_ statements: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(handle)
            throw ProbeFailure(reason: "the file at \(path) could not be opened to corrupt it")
        }
        defer { sqlite3_close_v2(handle) }
        guard sqlite3_exec(handle, statements, nil, nil, nil) == SQLITE_OK else {
            throw ProbeFailure(reason: String(cString: sqlite3_errmsg(handle)))
        }
    }
}

/// Looking at a store from somewhere other than the handle that wrote to it.
///
/// An actor because it has to remember which handle is current: a behaviour
/// that lets go and reopens three times would otherwise try to open a file the
/// second handle is still holding, and be refused by the lease.
actor SQLiteFileDurabilityProbe: DurabilityProbe {

    // MARK: - Properties

    private let path: String
    private var current: SQLiteStore

    // MARK: - Initializers

    init(path: String, store: SQLiteStore) {
        self.path = path
        self.current = store
    }

    // MARK: - Internal Methods

    func reopenAfterAbandoning() async throws -> any BotStore {
        await current.abandon()
        let next = try await SQLiteStore.open(at: path)
        current = next
        return next
    }

    func independentView() async throws -> any BotStore {
        try await SQLiteStore.openInspector(at: path)
    }
}

/// Something a probe could not do.
struct ProbeFailure: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

extension StoreConformance {

    /// The suite, pointed at a store on a file in `directory`.
    static func sqliteFile(in directory: String) -> StoreConformance {
        StoreConformance(backend: "sqlite on a file") {
            let path = directory + "/" + UUID().uuidString + ".sqlite3"
            let store = try await SQLiteStore.open(at: path)
            return StoreUnderTest(
                store: store,
                corruption: SQLiteFileCorruptionProbe(path: path),
                durability: SQLiteFileDurabilityProbe(path: path, store: store)
            )
        }
    }

    /// The suite, pointed at a store that lives in memory.
    ///
    /// The same schema, the same statements and the same reader, with no file
    /// anywhere. It offers neither probe: there is nothing to corrupt from
    /// outside and nothing that outlives the handle.
    static func sqliteInMemory() -> StoreConformance {
        StoreConformance(backend: "sqlite in memory") {
            StoreUnderTest(store: try await SQLiteStore.inMemory())
        }
    }
}
