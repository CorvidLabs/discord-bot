@preconcurrency import Foundation

/// What opening or using a SQLite store refuses, and what to change.
///
/// Every case names the thing an operator can act on at two in the morning.
/// None of them says "database error".
public enum SQLiteStoreError: Error, LocalizedError, Sendable, Equatable {

    /// The library on this machine was built without thread safety.
    case libraryNotThreadsafe(version: String)

    /// The library on this machine is older than the features relied on here.
    case libraryTooOld(found: String, needs: String)

    /// The file could not be opened.
    case cannotOpen(path: String, reason: String)

    /// A setting the durability promise rests on is not in force.
    ///
    /// Asking for a setting and getting it are different things: a read-only
    /// directory, a filesystem without shared memory, or a network mount all
    /// accept the request and leave the old value in place. Every one of them
    /// is read back, and a mismatch stops the process rather than leaving it
    /// running with a promise it cannot keep.
    case settingRefused(setting: String, wanted: String, inForce: String)

    /// Another process is holding this store.
    ///
    /// Refused before anything else happens. Two instances sharing one file can
    /// each run the same epoch and each pay everybody, and the gate that
    /// serialises payout runs lives inside one process and cannot see the
    /// other.
    case alreadyHeldByAnotherProcess(path: String)

    /// The file holds migrations this build has never heard of.
    ///
    /// A newer version wrote it. Running anyway means reading a table that may
    /// have lost a column or gained a constraint, and in this product that can
    /// mean paying somebody twice.
    case schemaFromTheFuture(versions: [Int])

    /// A migration already applied is not the migration this build ships.
    ///
    /// Two operators both reporting "version seven" with different schemas is
    /// the failure a version number alone cannot catch, so the text of each
    /// migration is fingerprinted when it is applied and checked on every
    /// start.
    case schemaDiverged(version: Int, name: String)

    /// The copy taken before a migration failed, so the migration did not run.
    case backupFailed(path: String, reason: String)

    /// A statement failed.
    case statementFailed(statement: String, code: Int32, message: String)

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case .libraryNotThreadsafe(let version):
            return "The SQLite on this machine (\(version)) was built without thread safety, so "
                + "nothing here can promise a write will not be interleaved. Install a threadsafe "
                + "build, or run on a machine with one."
        case .libraryTooOld(let found, let needs):
            return "The SQLite on this machine is \(found) and at least \(needs) is needed. "
                + "Upgrade the system library."
        case .cannotOpen(let path, let reason):
            return "The store at \(path) could not be opened: \(reason)"
        case .settingRefused(let setting, let wanted, let inForce):
            return "\(setting) was set to \(wanted) and reads back as \(inForce). A save cannot be "
                + "promised durable on this volume, so nothing was opened. This is usually a "
                + "network filesystem or a directory the process cannot write to."
        case .alreadyHeldByAnotherProcess(let path):
            return "Another process is already holding the store at \(path). Two instances sharing "
                + "one store can pay the same week twice, so this one refused to start. Stop the "
                + "other instance, or give this one its own store."
        case .schemaFromTheFuture(let versions):
            return "The store holds migrations this build does not know about "
                + "(\(versions.map(String.init).joined(separator: ", "))). It was written by a "
                + "newer version. Run that version, or restore the copy it took before upgrading."
        case .schemaDiverged(let version, let name):
            return "Migration \(version) (\(name)) was applied from a different version of its own "
                + "text. This store and this build disagree about what the schema is. Restore the "
                + "copy taken before the upgrade rather than migrating on top of it."
        case .backupFailed(let path, let reason):
            return "The copy at \(path) could not be taken (\(reason)), so the migration did not "
                + "run. A schema change on SQLite rewrites tables and there is no undo but the copy."
        case .statementFailed(let statement, let code, let message):
            return "A statement failed (\(code): \(message)): \(statement)"
        }
    }
}
