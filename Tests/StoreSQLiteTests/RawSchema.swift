import CSQLite
import Foundation

/// Reading and editing a store's file from outside the store.
///
/// A test that asserts something about the schema has to look at the schema
/// rather than at the code that wrote it, or it is asserting that the code
/// agrees with itself. This opens the file the way an operator with the
/// `sqlite3` command would, which is also the claim HOST-9 makes about the
/// file being readable by something that is not this project.
final class RawSchema {

    // MARK: - Properties

    private var handle: OpaquePointer?

    // MARK: - Initializers

    init(path: String) throws {
        var opened: OpaquePointer?
        guard sqlite3_open_v2(path, &opened, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(opened)
            throw ProbeFailure(reason: "could not open \(path)")
        }
        handle = opened
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    // MARK: - Internal Methods

    func close() {
        sqlite3_close_v2(handle)
        handle = nil
    }

    func execute(_ statements: String) throws {
        guard sqlite3_exec(handle, statements, nil, nil, nil) == SQLITE_OK else {
            throw ProbeFailure(reason: String(cString: sqlite3_errmsg(handle)))
        }
    }

    func tables() -> [String] {
        rows("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
    }

    func columns(of table: String) -> [String] {
        rows("SELECT name FROM pragma_table_info('" + table + "')")
    }

    /// Whether every foreign key from `table` to the directory deletes with it.
    func cascadesToMembers(from table: String) -> Bool {
        let targets = rows(
            "SELECT \"table\" || '/' || on_delete FROM pragma_foreign_key_list('" + table + "')"
        )
        return targets.contains("members/CASCADE")
    }

    /// Every stored amount, as the database's own ordering puts them.
    func orderedAmountHex() -> [String] {
        rows("SELECT hex(paid_base_units) FROM reserve_epochs ORDER BY paid_base_units ASC")
    }

    // MARK: - Private Methods

    private func rows(_ sql: String) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                values.append(String(cString: text))
            }
        }
        return values
    }
}
