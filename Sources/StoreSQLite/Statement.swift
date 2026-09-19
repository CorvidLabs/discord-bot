import CSQLite
@preconcurrency import Foundation
import Store

/// One prepared statement, finalised when it goes out of scope.
///
/// Not `Sendable` and never stored: a statement is made, stepped and dropped
/// inside one method of the actor that owns the connection. That is the rule
/// that keeps the C pointers in here from outliving the handle they belong to,
/// and it is held by the type rather than by attention, because a non-Sendable
/// class cannot cross an isolation boundary without the compiler saying so.
internal final class Statement {

    // MARK: - Properties

    private var handle: OpaquePointer?
    private let text: String

    /// Tells SQLite to take its own copy of bound text and bytes.
    ///
    /// The alternative saves a copy and hands SQLite a pointer whose lifetime
    /// this code would then have to guarantee until the statement is finalised.
    /// That is the bug class in C interop that no test catches and that looks
    /// like a database fault rather than ours, so the copy is bought
    /// deliberately, once, here, for every binding in the package.
    private static let takeACopy = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )

    // MARK: - Initializers

    /// - Parameters:
    ///   - connection: The open handle.
    ///   - sql: The statement, which can only be a literal.
    internal init(connection: OpaquePointer?, sql: SQL) throws {
        self.text = sql.text
        var prepared: OpaquePointer?
        let code = sqlite3_prepare_v2(connection, sql.text, -1, &prepared, nil)
        guard code == SQLITE_OK, let prepared else {
            throw SQLiteStoreError.statementFailed(
                statement: sql.text,
                code: code,
                message: Statement.message(connection)
            )
        }
        self.handle = prepared
    }

    deinit {
        sqlite3_finalize(handle)
    }

    // MARK: - Internal Methods

    /// Binds every placeholder, in order, from one.
    internal func bind(_ values: [SQLValue]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .null:
                code = sqlite3_bind_null(handle, index)
            case .integer(let number):
                code = sqlite3_bind_int64(handle, index, number)
            case .text(let string):
                // The length is given rather than left to the first NUL. A
                // value carrying one would otherwise be cut short on the way
                // in, and two chat ids that match up to it would become one
                // member holding the other one's wallets.
                code = sqlite3_bind_text(
                    handle,
                    index,
                    string,
                    Int32(string.utf8.count),
                    Statement.takeACopy
                )
            case .blob(let bytes):
                code = bytes.withUnsafeBufferPointer { buffer in
                    sqlite3_bind_blob(
                        handle,
                        index,
                        buffer.baseAddress,
                        Int32(buffer.count),
                        Statement.takeACopy
                    )
                }
            }
            guard code == SQLITE_OK else {
                throw SQLiteStoreError.statementFailed(
                    statement: text,
                    code: code,
                    message: "could not bind value \(index)"
                )
            }
        }
    }

    /// Steps once.
    /// - Returns: Whether a row is now available.
    internal func step() throws -> Bool {
        let code = sqlite3_step(handle)
        switch code {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            throw SQLiteStoreError.statementFailed(
                statement: text,
                code: code,
                message: Statement.message(sqlite3_db_handle(handle))
            )
        }
    }

    /// Steps to the end, for a statement that answers nothing.
    internal func run() throws {
        while try step() {}
    }

    /// Whether the column is null.
    internal func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(handle, column) == SQLITE_NULL
    }

    /// A bounded integer column.
    internal func integer(_ column: Int32) -> Int64 {
        sqlite3_column_int64(handle, column)
    }

    /// A bounded integer column, or a refusal naming the row.
    ///
    /// The type is asked for rather than assumed. `sqlite3_column_int64` on a
    /// column holding text answers zero and reports nothing, so a count read
    /// that way is a row that exists, cannot be read, and comes back as the
    /// most dangerous number in the file.
    internal func requiredInteger(_ column: Int32, row: String) throws -> Int64 {
        guard sqlite3_column_type(handle, column) == SQLITE_INTEGER else {
            throw StoreError.unreadableRow(
                row: row,
                reason: "a whole-number column held something that is not one"
            )
        }
        return sqlite3_column_int64(handle, column)
    }

    /// A text column, copied out immediately.
    ///
    /// Copied before anything else happens to the statement, because the
    /// pointer SQLite hands back is only valid until the next step or reset,
    /// and copied to the length the column reports rather than to its first
    /// NUL, which would cut a value short on the way back out.
    internal func text(_ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(handle, column) else { return nil }
        let count = Int(sqlite3_column_bytes(handle, column))
        return String(decoding: UnsafeBufferPointer(start: pointer, count: count), as: UTF8.self)
    }

    /// A blob column, copied out immediately.
    internal func bytes(_ column: Int32) -> [UInt8]? {
        let count = Int(sqlite3_column_bytes(handle, column))
        guard let pointer = sqlite3_column_blob(handle, column) else { return nil }
        return [UInt8](UnsafeRawBufferPointer(start: pointer, count: count))
    }

    /// An amount column, or a refusal naming the row.
    internal func amount(_ column: Int32, row: String) throws -> UInt64 {
        guard let bytes = bytes(column) else {
            throw StoreError.unreadableRow(row: row, reason: "an amount column held nothing")
        }
        return try BaseUnits.amount(bytes, row: row)
    }

    /// An instant column, or nil, or a refusal naming the row.
    ///
    /// Nil means the column is null and nothing else. An instant that will not
    /// read as a whole number throws rather than coming back as the first
    /// second of 1970, which is a day every reader of it would then decide
    /// belongs to somebody else.
    internal func instant(_ column: Int32, row: String) throws -> Date? {
        guard !isNull(column) else { return nil }
        return StoreDate.date(seconds: try requiredInteger(column, row: row))
    }

    /// An instant column that has to be there, or a refusal naming the row.
    internal func requiredInstant(_ column: Int32, row: String) throws -> Date {
        guard let value = try instant(column, row: row) else {
            throw StoreError.unreadableRow(row: row, reason: "an instant column held nothing")
        }
        return value
    }

    /// A text column, or a refusal naming the row.
    internal func requiredText(_ column: Int32, row: String) throws -> String {
        guard let value = text(column) else {
            throw StoreError.unreadableRow(row: row, reason: "a text column held nothing")
        }
        return value
    }

    // MARK: - Private Methods

    /// The last message the handle recorded, for an error a person will read.
    private static func message(_ connection: OpaquePointer?) -> String {
        guard let raw = sqlite3_errmsg(connection) else { return "no message" }
        return String(cString: raw)
    }
}
