@preconcurrency import Foundation
import Chain
import Gating
import Reserve
import Store

/// The store, on the SQLite the operating system already ships.
///
/// ## What makes the durability promise true
///
/// `ReserveStore` promises that a save is on storage before it returns, because
/// a claim written before a payment is what turns a crash into an under-payment
/// rather than a double one. Four things make that sentence true here, and each
/// is checked rather than believed.
///
/// 1. **One connection.** Every setting below is per connection. A pool is a
///    pool in which one handle has them and the rest commit without waiting for
///    the disk, which is a hole nothing above would ever notice.
/// 2. **The settings, on that connection, read back.** Write-ahead logging,
///    `synchronous = FULL` rather than the usually recommended `NORMAL`, and
///    `fullfsync` so a flush on Darwin actually reaches the drive. Each one is
///    read back and a mismatch stops the start.
/// 3. **A save is one committed transaction and nothing is deferred.** The
///    write scope takes a **synchronous** body, so a payment, which is `async`,
///    cannot be moved inside it and a claim cannot be committed after the value
///    has moved. That ordering is a compile error rather than a review note.
/// 4. **A volume that cannot promise a flush is refused**, not worked around.
///
/// What none of that can do is detect a disk that acknowledges a flush it has
/// not performed. That is the honest limit, and it belongs to whoever chooses
/// the machine rather than to this file.
///
/// ## What stops two of these
///
/// An exclusive lease on a sibling file, taken before anything else. The gate
/// that serialises payout runs is an actor and cannot see another process, so
/// two instances on one file would each pay the same week. The lease is why
/// they cannot.
public actor SQLiteStore: BotStore {

    // MARK: - Properties

    private let connection: Connection
    private let lease: InstanceLease?
    private let isReadOnly: Bool

    /// What this handle last wrote as an epoch's claim rows, keyed by stream
    /// and epoch.
    ///
    /// A memo of its own writes rather than a cache of the file, which is what
    /// makes it safe: one process holds the store, because the lease refuses a
    /// second writer and the read-only view cannot write. It is what lets a
    /// save send only the difference to disk instead of rewriting a list that
    /// grows with every recipient paid. An entry it does not have is not a
    /// guess: the rows are written out in full.
    internal var lastWrittenClaims: [String: [Int64: [String]]] = [:]

    /// What the migration run at open did, so a host can log it.
    public let migrationReport: MigrationReport

    /// What a migration run did.
    public struct MigrationReport: Sendable, Equatable {

        /// Migrations that were applied, named.
        public let applied: [String]

        /// Where the copy taken before them went, or nil because none ran.
        public let backupPath: String?

        /// Whether there was no store at this path and this open made one.
        ///
        /// **A host that expects a store to be there should refuse to boot on
        /// this.** SQLite makes the file when it is missing, the migrations
        /// then run on it, and everything reads as a first boot: the reserve
        /// has finished no epoch, no period is claimed, and the next run pays
        /// epoch one all over again. A volume that did not mount, a mistyped
        /// path and a deleted file all arrive looking exactly like a genuine
        /// first boot, and this is the one thing that tells them apart.
        ///
        /// Always false for a store in memory and for a read-only view, which
        /// have no file to have found or made.
        public let createdFile: Bool

        // MARK: - Initializers

        /// - Parameters:
        ///   - applied: Migrations that were applied, named.
        ///   - backupPath: Where the copy taken before them went.
        ///   - createdFile: Whether this open made the store rather than found
        ///     it.
        public init(applied: [String], backupPath: String?, createdFile: Bool) {
            self.applied = applied
            self.backupPath = backupPath
            self.createdFile = createdFile
        }
    }

    // MARK: - Initializers

    private init(connection: Connection, lease: InstanceLease?, isReadOnly: Bool, report: MigrationReport) {
        self.connection = connection
        self.lease = lease
        self.isReadOnly = isReadOnly
        self.migrationReport = report
    }

    /// Opens a store on a file, and refuses rather than starting degraded.
    ///
    /// The only way to get a writable store, so there is no moment in which a
    /// caller holds one whose file has not been brought up to date.
    ///
    /// The path arrives as a parameter and this target reads no environment
    /// variable of its own, which is what stops a test quietly finding an
    /// operator's live file (BUILD-2.a).
    public static func open(at path: String) async throws -> SQLiteStore {
        // Asked before anything touches the path, because opening the handle
        // is what answers it and by then the answer is yes. The report a host
        // reads is otherwise identical whether the store was found or invented
        // a moment ago, and an invented one reads as a reserve that has never
        // paid anybody.
        let createdFile = !FileManager.default.fileExists(atPath: path)
        try DurableVolume.require(path: path)
        // Before the handle, and long before anything announces itself to a
        // chat gateway: a duplicate that identified first would take the live
        // instance's session with it on the way out.
        let lease = try InstanceLease(storePath: path)
        do {
            let connection = try Connection(path: path)
            let report = try SchemaMigrator.migrate(connection: connection, storePath: path)
            return SQLiteStore(
                connection: connection,
                lease: lease,
                isReadOnly: false,
                report: MigrationReport(
                    applied: report.applied,
                    backupPath: report.backupPath,
                    createdFile: createdFile
                )
            )
        } catch {
            lease.release()
            throw error
        }
    }

    /// A store that lives in memory, with the same schema and the same code
    /// path.
    ///
    /// For a test that is about behaviour rather than about a file, and for
    /// trying things out. It takes no lease and copies nothing, because there
    /// is nothing for a second process to find.
    public static func inMemory() async throws -> SQLiteStore {
        let connection = try Connection(path: nil)
        let report = try SchemaMigrator.migrate(connection: connection, storePath: nil)
        return SQLiteStore(
            connection: connection,
            lease: nil,
            isReadOnly: false,
            report: MigrationReport(
                applied: report.applied,
                backupPath: report.backupPath,
                createdFile: false
            )
        )
    }

    /// A second, read-only view of a store, taking no lease.
    ///
    /// The only way to ask the file itself whether a write that returned is
    /// really there, which is the one durability claim that cannot be proved
    /// from inside the handle that made it. It cannot write, so it can never be
    /// the second writer the lease exists to refuse, and it migrates nothing.
    public static func openInspector(at path: String) async throws -> SQLiteStore {
        let connection = try Connection(path: path, readOnly: true)
        return SQLiteStore(
            connection: connection,
            lease: nil,
            isReadOnly: true,
            report: MigrationReport(applied: [], backupPath: nil, createdFile: false)
        )
    }

    /// What a new build would change about a file, without changing it.
    ///
    /// So an operator can point the new build at a copy and be told what is
    /// coming, rather than finding out during the upgrade (RUN-9).
    public static func pendingMigrations(at path: String) async throws -> [String] {
        let connection = try Connection(path: path, readOnly: true)
        defer { connection.close() }
        return try SchemaMigrator.pending(connection: connection)
    }

    // MARK: - Public Methods, lifecycle

    public func close() async {
        connection.close()
        lease?.release()
    }

    /// Lets the file go without a tidy shutdown, the way a stopped process
    /// does.
    ///
    /// The handle is dropped rather than closed and the log is left exactly as
    /// it stands, so opening the same file again reads what a restart after a
    /// kill would read. Nothing in a running bot calls this. It exists so a
    /// test can prove that a claim reached storage before a payment was
    /// attempted, which is otherwise a sentence in a document.
    public func abandon() {
        connection.abandon()
        lease?.release()
    }

    /// Reverses every migration, for a test that proves each one has a reverse.
    ///
    /// Not a rollback for an operator, and it is not offered as one: it throws
    /// the rows away. What an operator rolls back to is the copy the migrator
    /// takes before it changes anything.
    public func revertEverySchemaStep() throws {
        try SchemaMigrator.revertAll(connection: connection)
        // The rows the memo describes have just been dropped, and a memo
        // describing rows that are gone is worse than none.
        lastWrittenClaims = [:]
    }

    /// The settings the durability promise rests on, as they actually are.
    ///
    /// Read from the one connection that does the committing, because that is
    /// the only connection whose settings mean anything. Offered so an
    /// instance can state what it is rather than only promising it (HOST-5.a),
    /// and so the claim in this type's documentation is one somebody can check
    /// on the machine it is running on.
    public func settingsInForce() throws -> [String: String] {
        var settings: [String: String] = [:]
        settings["journal_mode"] = try handle.firstText("PRAGMA journal_mode") ?? "unknown"
        settings["synchronous"] = (try handle.firstInteger("PRAGMA synchronous"))
            .map(String.init) ?? "unknown"
        settings["foreign_keys"] = (try handle.firstInteger("PRAGMA foreign_keys"))
            .map(String.init) ?? "unknown"
        settings["busy_timeout"] = (try handle.firstInteger("PRAGMA busy_timeout"))
            .map(String.init) ?? "unknown"
        settings["sqlite_version"] = Connection.libraryVersion
        return settings
    }

    /// Every table the file holds, for a test that reads the schema back.
    public func tableNames() throws -> [String] {
        var names: [String] = []
        let statement = try connection.prepare(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
        )
        while try statement.step() {
            if let name = statement.text(0) { names.append(name) }
        }
        return names
    }

    // MARK: - Internal Methods

    /// Everything in `body`, committed together or not at all.
    internal func write<Output>(_ body: (Connection) throws -> Output) throws -> Output {
        try connection.write(body)
    }

    /// The handle, for a read that needs no transaction.
    internal var handle: Connection { connection }
}
