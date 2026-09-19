@preconcurrency import Foundation

/// Bringing a file up to the schema this build knows, or refusing to.
///
/// The order below is the whole of it, and every step is a refusal rather than
/// a guess, because the person on the other side of a bad guess has one copy of
/// their members' data and it is this file.
internal enum SchemaMigrator {

    // MARK: - Properties

    /// What a migration run did, for the log a person reads afterwards.
    internal struct Report: Sendable, Equatable {

        /// Migrations that were pending, named before they ran.
        internal let applied: [String]

        /// Where the copy taken first went, or nil because nothing was
        /// pending.
        internal let backupPath: String?
    }

    // MARK: - Internal Methods

    /// Applies whatever is pending, having first refused everything that
    /// should be refused.
    ///
    /// - Parameters:
    ///   - connection: The open handle.
    ///   - storePath: The file, or nil for a database in memory, which has
    ///     nothing to copy and nothing to restore.
    internal static func migrate(connection: Connection, storePath: String?) throws -> Report {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                checksum TEXT NOT NULL,
                applied_at INTEGER NOT NULL
            )
            """
        )

        let applied = try appliedMigrations(connection: connection)
        try refuseAFileThisBuildCannotRead(applied: applied)

        let pending = Schema.migrations
            .filter { applied[$0.version] == nil }
            .sorted { $0.version < $1.version }
        guard !pending.isEmpty else {
            return Report(applied: [], backupPath: nil)
        }

        // A schema change on SQLite rewrites tables, and there is no undo but a
        // copy. The copy is taken before anything runs, and a copy that cannot
        // be taken stops the migration rather than being skipped.
        var backupPath: String?
        if let storePath, !applied.isEmpty {
            let highest = applied.keys.max() ?? 0
            let destination = "\(storePath).pre-\(highest).bak"
            try? FileManager.default.removeItem(atPath: destination)
            try connection.checkpoint()
            try connection.backup(to: destination)
            backupPath = destination
        }

        for migration in pending {
            // One transaction per migration, so a failure part way through the
            // fourth leaves the first three applied and recorded rather than a
            // schema nobody can name.
            try connection.write { handle in
                for statement in migration.up {
                    try handle.execute(statement)
                }
                try handle.execute(
                    """
                    INSERT INTO schema_migrations (version, name, checksum, applied_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    [
                        .integer(Int64(migration.version)),
                        .text(migration.name),
                        .text(migration.checksum),
                        .integer(Int64(Date().timeIntervalSince1970.rounded(.down)))
                    ]
                )
            }
        }

        return Report(
            applied: pending.map { "\($0.version): \($0.name)" },
            backupPath: backupPath
        )
    }

    /// What is pending, without applying any of it.
    ///
    /// So an operator can point a new build at a copy of their file and be told
    /// what would change before they take the new build (RUN-9, BUILD-5).
    internal static func pending(connection: Connection) throws -> [String] {
        // A file that holds no schema yet is every migration pending. This is
        // the call an operator makes on a copy before taking a new build, so
        // failing on the easiest case with a message about a missing table is
        // the one answer it must not give.
        guard try holdsBookkeeping(connection: connection) else {
            return named(Schema.migrations)
        }
        let applied = try appliedMigrations(connection: connection)
        // The same two refusals `migrate` makes, for the same reasons. A file
        // written by something newer answered "this upgrade changes nothing"
        // here and was then refused at the door by `open`, which is the
        // opposite of what an operator asked this question for (RUN-9).
        try refuseAFileThisBuildCannotRead(applied: applied)
        return named(Schema.migrations.filter { applied[$0.version] == nil })
    }

    /// Undoes every applied migration, newest first.
    ///
    /// **Not a rollback path for an operator**, and it is not offered as one.
    /// A store that has run has rows in it, and stepping the schema back throws
    /// them away. It exists so a test can assert that every migration really
    /// does have a reverse, which is what stops the first one whose reverse is
    /// a comment. What an operator rolls back to is the copy the migrator took.
    internal static func revertAll(connection: Connection) throws {
        let applied = try appliedMigrations(connection: connection)
        let order = Schema.migrations
            .filter { applied[$0.version] != nil }
            .sorted { $0.version > $1.version }
        for migration in order {
            try connection.write { handle in
                for statement in migration.down {
                    try handle.execute(statement)
                }
                try handle.execute(
                    "DELETE FROM schema_migrations WHERE version = ?",
                    [.integer(Int64(migration.version))]
                )
            }
        }
    }

    // MARK: - Private Methods

    /// One row of `schema_migrations`.
    private struct AppliedMigration: Sendable {
        let name: String
        let checksum: String
    }

    /// Refuses a file this build has no business reading.
    ///
    /// A file written by a newer build is not something to try anyway. An
    /// older binary against a newer schema reads a table that may have lost a
    /// column or gained a constraint, and here that can mean paying somebody
    /// twice. A version number cannot catch a migration edited after it
    /// shipped, because the number does not change; the text's fingerprint
    /// does.
    private static func refuseAFileThisBuildCannotRead(
        applied: [Int: AppliedMigration]
    ) throws {
        let shipped = Dictionary(
            uniqueKeysWithValues: Schema.migrations.map { ($0.version, $0) }
        )
        let unknown = applied.keys.filter { shipped[$0] == nil }.sorted()
        guard unknown.isEmpty else {
            throw SQLiteStoreError.schemaFromTheFuture(versions: unknown)
        }
        for (version, record) in applied {
            guard let migration = shipped[version] else { continue }
            guard record.checksum == migration.checksum else {
                throw SQLiteStoreError.schemaDiverged(version: version, name: migration.name)
            }
        }
    }

    /// Whether the file has the table that records what has been applied.
    private static func holdsBookkeeping(connection: Connection) throws -> Bool {
        try connection.firstText(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations'"
        ) != nil
    }

    /// Migrations in order, named the way a report names them.
    private static func named(_ migrations: [SchemaMigration]) -> [String] {
        migrations
            .sorted { $0.version < $1.version }
            .map { "\($0.version): \($0.name)" }
    }

    private static func appliedMigrations(
        connection: Connection
    ) throws -> [Int: AppliedMigration] {
        var rows: [Int: AppliedMigration] = [:]
        let statement = try connection.prepare(
            "SELECT version, name, checksum FROM schema_migrations"
        )
        while try statement.step() {
            let version = Int(statement.integer(0))
            rows[version] = AppliedMigration(
                name: try statement.requiredText(1, row: "schema_migrations"),
                checksum: try statement.requiredText(2, row: "schema_migrations")
            )
        }
        return rows
    }
}
