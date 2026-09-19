import CSQLite
@preconcurrency import Foundation
import Store

/// One handle on one SQLite database.
///
/// **There is one of these per store, and that is the single most important
/// line in this file.** Every setting the durability promise rests on is a
/// per-connection setting, so a pool of handles is a pool in which one handle
/// has them and the others do not, and the others commit without waiting for
/// the disk. One handle, set once, read back once, and the actor above is what
/// serialises everything through it.
///
/// Not `Sendable`, deliberately. It is a property of an actor and it never
/// leaves, so the compiler rather than a reviewer is what keeps the C pointer
/// on one task at a time.
internal final class Connection {

    // MARK: - Properties

    /// How long a write waits for another process before giving up.
    ///
    /// Bounded rather than endless. An unbounded retry in the middle of a
    /// payout is a payout that may outlive the process running it, and the
    /// caller would rather be told than left waiting.
    internal static let busyTimeoutMilliseconds = 5_000

    /// The oldest library this code is written against.
    ///
    /// `wal_checkpoint(TRUNCATE)` and the online backup interface both predate
    /// it comfortably; the floor is here so the failure is a sentence rather
    /// than an unexplained error code on an old machine.
    internal static let oldestSupportedVersion = 3_024_000

    private var handle: OpaquePointer?

    /// Where the database lives, or nil when it lives in memory.
    internal let path: String?

    // MARK: - Initializers

    /// Opens the database and puts every durability setting in force.
    ///
    /// - Parameters:
    ///   - path: The file, or nil for a database in memory.
    ///   - readOnly: Opens a view that cannot write, for looking at a store
    ///     another handle is holding.
    internal init(path: String?, readOnly: Bool = false) throws {
        guard sqlite3_threadsafe() != 0 else {
            throw SQLiteStoreError.libraryNotThreadsafe(version: Connection.libraryVersion)
        }
        guard sqlite3_libversion_number() >= Connection.oldestSupportedVersion else {
            throw SQLiteStoreError.libraryTooOld(found: Connection.libraryVersion, needs: "3.24.0")
        }
        self.path = path

        let target = path ?? ":memory:"
        // FULLMUTEX rather than NOMUTEX: the actor above already serialises
        // every call, so the mutex costs nothing that is measurable here and
        // it is the second belt if somebody ever holds this outside one.
        var flags = SQLITE_OPEN_FULLMUTEX
        flags |= readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var opened: OpaquePointer?
        let code = sqlite3_open_v2(target, &opened, flags, nil)
        guard code == SQLITE_OK, let opened else {
            let reason = opened.map { Connection.message($0) } ?? "code \(code)"
            sqlite3_close_v2(opened)
            throw SQLiteStoreError.cannotOpen(path: target, reason: reason)
        }
        self.handle = opened
        do {
            try applySettings(isFile: path != nil, readOnly: readOnly)
        } catch {
            sqlite3_close_v2(self.handle)
            self.handle = nil
            throw error
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    // MARK: - Internal Methods

    /// The library's version, for a message a person will read.
    internal static var libraryVersion: String {
        String(cString: sqlite3_libversion())
    }

    /// Runs one statement that answers nothing.
    internal func execute(_ sql: SQL, _ values: [SQLValue] = []) throws {
        let statement = try Statement(connection: handle, sql: sql)
        try statement.bind(values)
        try statement.run()
    }

    /// Prepares one statement.
    internal func prepare(_ sql: SQL, _ values: [SQLValue] = []) throws -> Statement {
        let statement = try Statement(connection: handle, sql: sql)
        try statement.bind(values)
        return statement
    }

    /// The first column of the first row, as text, or nil when there is no row.
    internal func firstText(_ sql: SQL, _ values: [SQLValue] = []) throws -> String? {
        let statement = try prepare(sql, values)
        guard try statement.step() else { return nil }
        return statement.text(0)
    }

    /// The first column of the first row, as a count.
    internal func firstInteger(_ sql: SQL, _ values: [SQLValue] = []) throws -> Int64? {
        let statement = try prepare(sql, values)
        guard try statement.step() else { return nil }
        return statement.integer(0)
    }

    /// Rows changed by the last statement.
    internal var changes: Int {
        Int(sqlite3_changes(handle))
    }

    /// Everything in `body`, committed together or not at all.
    ///
    /// **The body is synchronous, and that is the point.** A payment is `async`,
    /// so no refactor can move one inside a transaction, hold a transaction
    /// across a network call, or commit a claim after the value has moved. The
    /// rule that the claim is written first stops being a sentence in a comment
    /// and becomes something the compiler enforces.
    ///
    /// There is deliberately no public begin, commit or rollback. "Forgot to
    /// commit" is not expressible.
    internal func write<Output>(_ body: (Connection) throws -> Output) throws -> Output {
        // IMMEDIATE rather than DEFERRED: the write lock is taken up front, so
        // a second process is refused at the start of the transaction rather
        // than part way through one that then has to be unwound.
        try execute("BEGIN IMMEDIATE")
        do {
            let output = try body(self)
            try execute("COMMIT")
            return output
        } catch {
            // A rollback that itself fails must not replace the real error,
            // which is the one naming what actually went wrong.
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Copies the database to another path, through SQLite's own backup
    /// interface.
    ///
    /// Not a file copy. A file copy of a database in write-ahead mode has to
    /// catch the sibling log as well, and catching both at one instant is not
    /// something a copy can promise. The backup interface reads a consistent
    /// database whatever is in the log.
    internal func backup(to destinationPath: String) throws {
        let destination = try Connection(path: destinationPath)
        guard
            let session = sqlite3_backup_init(destination.handle, "main", handle, "main")
        else {
            throw SQLiteStoreError.backupFailed(
                path: destinationPath,
                reason: Connection.message(destination.handle)
            )
        }
        let stepped = sqlite3_backup_step(session, -1)
        let finished = sqlite3_backup_finish(session)
        guard stepped == SQLITE_DONE, finished == SQLITE_OK else {
            throw SQLiteStoreError.backupFailed(
                path: destinationPath,
                reason: "backup returned \(stepped) and finished with \(finished)"
            )
        }
    }

    /// Writes the log back into the database and truncates it.
    internal func checkpoint() throws {
        _ = try? firstInteger("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    /// Lets the handle go without a tidy shutdown, the way a stopped process
    /// does.
    ///
    /// The handle is dropped rather than closed, so nothing is flushed, nothing
    /// is checkpointed and the log is left exactly as a killed process leaves
    /// it. The descriptor is reclaimed by the operating system, which is what
    /// happens after a kill too. Nothing in a running bot calls this: it exists
    /// so a test can ask the file whether a save that returned is really there.
    internal func abandon() {
        handle = nil
    }

    /// Closes tidily.
    internal func close() {
        sqlite3_close_v2(handle)
        handle = nil
    }

    // MARK: - Private Methods

    /// Puts every setting in force and reads each one back.
    ///
    /// Asking is not getting. A read-only directory, a filesystem without
    /// shared memory and a network mount all accept the request and leave the
    /// old value in place, and the process then runs believing a promise it
    /// cannot keep. Each one is read back and a mismatch stops the start.
    private func applySettings(isFile: Bool, readOnly: Bool) throws {
        try execute("PRAGMA busy_timeout = 5000")
        try execute("PRAGMA foreign_keys = ON")

        // Darwin's `fsync` returns before the drive has flushed its own cache.
        // `fullfsync` is what actually asks for the flush, and it is a no-op
        // elsewhere rather than an error, so it is set unconditionally.
        try execute("PRAGMA fullfsync = 1")

        guard !readOnly else { return }

        if isFile {
            let journal = try firstText("PRAGMA journal_mode = WAL")
            guard journal?.lowercased() == "wal" else {
                throw SQLiteStoreError.settingRefused(
                    setting: "journal_mode",
                    wanted: "wal",
                    inForce: journal ?? "nothing"
                )
            }
        }

        // FULL, not the NORMAL usually recommended alongside a write-ahead log.
        // NORMAL flushes at a checkpoint rather than at a commit, so a commit
        // that returned can still be lost to a power cut, and a commit that
        // returned is exactly what the claim-before-pay discipline relies on.
        try execute("PRAGMA synchronous = FULL")
        let synchronous = try firstInteger("PRAGMA synchronous")
        guard synchronous == 2 else {
            throw SQLiteStoreError.settingRefused(
                setting: "synchronous",
                wanted: "2 (full)",
                inForce: synchronous.map(String.init) ?? "nothing"
            )
        }

        let foreignKeys = try firstInteger("PRAGMA foreign_keys")
        guard foreignKeys == 1 else {
            throw SQLiteStoreError.settingRefused(
                setting: "foreign_keys",
                wanted: "1 (on)",
                inForce: foreignKeys.map(String.init) ?? "nothing"
            )
        }
    }

    /// The last message the handle recorded.
    private static func message(_ connection: OpaquePointer?) -> String {
        guard let raw = sqlite3_errmsg(connection) else { return "no message" }
        return String(cString: raw)
    }
}
