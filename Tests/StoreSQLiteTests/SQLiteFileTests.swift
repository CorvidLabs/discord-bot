import CSQLite
import Foundation
import Reserve
import Store
import StoreSQLite
import Testing

@Suite("A store on a file")
struct SQLiteFileTests {

    // MARK: - The settings the promise rests on

    @Test("Every setting the durability promise rests on is in force on the connection that commits")
    func settingsAreInForce() async throws {
        try await withTemporaryDirectory { directory in
            let store = try await SQLiteStore.open(at: directory + "/bot.sqlite3")
            let settings = try await store.settingsInForce()
            #expect(settings["journal_mode"]?.lowercased() == "wal")
            // Two, not one. A write-ahead log is usually recommended with
            // `synchronous = NORMAL`, which flushes at a checkpoint rather than
            // at a commit, so a commit that returned can still be lost.
            #expect(settings["synchronous"] == "2")
            #expect(settings["foreign_keys"] == "1")
            #expect(settings["busy_timeout"] == "5000")
            await store.close()
        }
    }

    @Test("A setting that did not take names itself, what was asked for, and what is in force")
    func aRefusedSettingNamesItself() throws {
        let refusal = SQLiteStoreError.settingRefused(
            setting: "journal_mode",
            wanted: "wal",
            inForce: "delete"
        )
        let sentence = try #require(refusal.errorDescription)
        #expect(sentence.contains("journal_mode"))
        #expect(sentence.contains("wal"))
        #expect(sentence.contains("delete"))
    }

    // MARK: - Two of them

    @Test("A second store on the same file is refused before it can do anything")
    func aSecondStoreIsRefused() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let first = try await SQLiteStore.open(at: path)
            await #expect(throws: SQLiteStoreError.alreadyHeldByAnotherProcess(path: path)) {
                _ = try await SQLiteStore.open(at: path)
            }
            // And the lease really is given back, rather than held until the
            // process ends: an operator restarting the bot must not have to
            // reboot the box.
            await first.close()
            let second = try await SQLiteStore.open(at: path)
            await second.close()
        }
    }

    @Test("A read-only view takes no lease, so a store can be looked at while it runs")
    func anInspectorTakesNoLease() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let store = try await SQLiteStore.open(at: path)
            let member = try await store.admitMember(externalId: "EXTERNAL-0001", at: Date())
            let inspector = try await SQLiteStore.openInspector(at: path)
            #expect(try await inspector.member(key: member.key) == member)
            await inspector.close()
            await store.close()
        }
    }

    // MARK: - The schema

    @Test("Every migration has a reverse, and reversing them all leaves nothing behind")
    func everyMigrationHasAReverse() async throws {
        try await withTemporaryDirectory { directory in
            let store = try await SQLiteStore.open(at: directory + "/bot.sqlite3")
            #expect(try await store.tableNames().count > 1)
            try await store.revertEverySchemaStep()
            // The bookkeeping table is the only thing a reverted store keeps,
            // and it is empty. Anything else means a migration whose reverse is
            // a comment, which is how a store stops being steppable at all.
            #expect(try await store.tableNames() == ["schema_migrations"])
            await store.close()
        }
    }

    @Test("Every table carrying a member key deletes its rows with the member")
    func everyMemberOwnedTableCascades() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let store = try await SQLiteStore.open(at: path)
            await store.close()

            let schema = try RawSchema(path: path)
            defer { schema.close() }
            var offenders: [String] = []
            for table in schema.tables() where table != "members" {
                guard schema.columns(of: table).contains("member_key") else { continue }
                guard schema.cascadesToMembers(from: table) else {
                    offenders.append(table)
                    continue
                }
            }
            // A table added in two years is forgotten by the migration that
            // creates it, or this fails and names it.
            #expect(offenders == [])
        }
    }

    @Test("The ledger's claim rows deliberately do not cascade, and do not name a member column")
    func theLedgerDoesNotCascade() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let store = try await SQLiteStore.open(at: path)
            await store.close()

            let schema = try RawSchema(path: path)
            defer { schema.close() }
            // A slot already paid has to stay recorded after the member is
            // forgotten, or a resumed run pays it again. What makes that safe
            // is that the value stored is a key this instance drew.
            #expect(!schema.columns(of: "reserve_epoch_claims").contains("member_key"))
            #expect(!schema.cascadesToMembers(from: "reserve_epoch_claims"))
        }
    }

    @Test("A store this open invented rather than found says so")
    func aStoreThisOpenInventedSaysSo() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let first = try await SQLiteStore.open(at: path)
            #expect(await first.migrationReport.createdFile)
            try await first.save(
                epoch: ReserveEpochRecord(
                    streamId: "s",
                    epoch: 1,
                    paidBaseUnits: 7_000,
                    startedAt: Date(timeIntervalSince1970: 10),
                    completedAt: Date(timeIntervalSince1970: 20)
                )
            )
            try await first.save(state: ReserveState(completedEpochs: ["s": 1]))
            await first.close()

            let found = try await SQLiteStore.open(at: path)
            #expect(await found.migrationReport.createdFile == false)
            await found.close()

            // The morning this exists for: a volume that did not mount, a
            // mistyped path, a deleted file. The store comes back healthy and
            // empty, which reads as a reserve that has never paid anybody, and
            // the next run pays its first epoch a second time. The migration
            // report is otherwise identical to a genuine first boot, so this
            // flag is the only thing a host can refuse on.
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
            let invented = try await SQLiteStore.open(at: path)
            let report = await invented.migrationReport
            #expect(report.createdFile)
            #expect(report.applied.count == 2)
            #expect(try await invented.loadState().nextEpoch("s") == 1)
            await invented.close()
        }
    }

    @Test("A member key that is not a key is refused by the file, not skipped by the reader")
    func theFileRefusesAnAccountKeyThatIsNotAKey() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let store = try await SQLiteStore.open(at: path)
            let member = try await store.admitMember(externalId: "EXTERNAL-0001", at: Date())
            try await store.prove(
                account: AccountRecord(
                    memberKey: member.key,
                    address: "ACCOUNT-0001",
                    provenAt: Date(),
                    directBaseUnits: 5_000_000_000
                )
            )
            await store.close()

            // The surgery an operator actually does, in the tool the README
            // points at, which has foreign keys off by default. Without the
            // check on the column the row is simply accepted, and from then on
            // it is missing from its member's wallets, counted as a second
            // member by the sweep guard, and left behind by a forgetting: a
            // demotion, a raised baseline and rows that outlive the person.
            let schema = try RawSchema(path: path)
            defer { schema.close() }
            var refused = false
            do {
                try schema.execute(
                    """
                    PRAGMA foreign_keys = OFF;
                    UPDATE accounts SET member_key = 'not a key at all';
                    """
                )
            } catch {
                refused = true
            }
            #expect(refused)
        }
    }

    // MARK: - Upgrading

    @Test("A file holding a migration this build has never heard of stops the start")
    func aSchemaFromTheFutureIsRefused() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let store = try await SQLiteStore.open(at: path)
            await store.close()

            let schema = try RawSchema(path: path)
            try schema.execute(
                """
                INSERT INTO schema_migrations (version, name, checksum, applied_at)
                VALUES (99, 'written by something newer', 'ffffffffffffffff', 0);
                """
            )
            schema.close()

            await #expect(throws: SQLiteStoreError.schemaFromTheFuture(versions: [99])) {
                _ = try await SQLiteStore.open(at: path)
            }
        }
    }

    @Test("A migration applied from different text stops the start, though its number matches")
    func anEditedMigrationIsRefused() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let store = try await SQLiteStore.open(at: path)
            await store.close()

            let schema = try RawSchema(path: path)
            try schema.execute(
                "UPDATE schema_migrations SET checksum = '0000000000000000' WHERE version = 1;"
            )
            schema.close()

            // Two operators both reporting "version one" with different
            // schemas is what a version number alone cannot catch.
            var refused = false
            do {
                _ = try await SQLiteStore.open(at: path)
            } catch let error as SQLiteStoreError {
                if case .schemaDiverged(let version, _) = error {
                    refused = version == 1
                }
            }
            #expect(refused)
        }
    }

    @Test("A pending migration copies the file first, and says what it applied")
    func aPendingMigrationCopiesFirst() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let store = try await SQLiteStore.open(at: path)
            // A first run has nothing to copy, because there is nothing to
            // lose yet.
            #expect(await store.migrationReport.backupPath == nil)
            #expect(await store.migrationReport.applied.count == 2)
            await store.close()

            // Put the file back to where it was one version ago, which is what
            // an operator taking a new build actually has.
            let schema = try RawSchema(path: path)
            try schema.execute(
                """
                DROP TABLE request_budget;
                DROP TABLE reserve_epoch_claims;
                DROP TABLE reserve_epochs;
                DROP TABLE reserve_streams;
                DROP TABLE reserve_state;
                DELETE FROM schema_migrations WHERE version = 2;
                """
            )
            schema.close()

            #expect(try await SQLiteStore.pendingMigrations(at: path).count == 1)

            let upgraded = try await SQLiteStore.open(at: path)
            let report = await upgraded.migrationReport
            #expect(report.applied.count == 1)
            let backup = try #require(report.backupPath)
            // A schema change on SQLite rewrites tables and there is no undo
            // but the copy, so the copy is the rollback and it has to exist.
            #expect(FileManager.default.fileExists(atPath: backup))
            await upgraded.close()
        }
    }

    @Test("What a new build would change refuses the file its open would refuse")
    func aPendingReportRefusesWhatOpenWouldRefuse() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let store = try await SQLiteStore.open(at: path)
            await store.close()

            let schema = try RawSchema(path: path)
            try schema.execute(
                """
                INSERT INTO schema_migrations (version, name, checksum, applied_at)
                VALUES (99, 'written by something newer', 'ffffffffffffffff', 0);
                """
            )
            schema.close()

            // Answering "this upgrade changes nothing" for a file the same
            // build then refuses to open is the opposite of what an operator
            // points this at a copy for.
            await #expect(throws: SQLiteStoreError.schemaFromTheFuture(versions: [99])) {
                _ = try await SQLiteStore.pendingMigrations(at: path)
            }
        }
    }

    @Test("A file holding no schema yet is every migration pending, not a missing table")
    func aPendingReportOnAFileWithNoSchema() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/empty.sqlite3"
            #expect(FileManager.default.createFile(atPath: path, contents: Data()))
            let pending = try await SQLiteStore.pendingMigrations(at: path)
            #expect(pending.count == 2)
        }
    }

    // MARK: - Amounts

    @Test("Amounts sort by value across the whole range, which a signed column cannot")
    func amountsSortByValue() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let store = try await SQLiteStore.open(at: path)
            for (index, amount) in [UInt64.max, 1, UInt64(Int64.max) + 1, 0].enumerated() {
                try await store.save(
                    epoch: ReserveEpochRecord(
                        streamId: "s",
                        epoch: UInt64(index),
                        paidBaseUnits: amount
                    )
                )
            }
            await store.close()

            let schema = try RawSchema(path: path)
            defer { schema.close() }
            let ordered = schema.orderedAmountHex()
            // Eight bytes most significant first, so the database's own byte
            // comparison is unsigned numeric order. A signed integer column
            // holding the same bit patterns would put the two largest figures
            // first, as negatives.
            #expect(
                ordered == [
                    "0000000000000000",
                    "0000000000000001",
                    "8000000000000000",
                    "FFFFFFFFFFFFFFFF"
                ]
            )
        }
    }
}
