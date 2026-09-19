@preconcurrency import Foundation
import Store

/// How an amount is written to a column.
///
/// **Eight bytes, big endian, in a BLOB.** Three reasons, in the order they
/// bite.
///
/// 1. SQLite's `INTEGER` is signed. Half of `UInt64` does not fit, and the half
///    that does not fit is the half the payout engine deliberately produces:
///    both `ReserveEpochRecord.claim` and `ReserveState.recordingSpend`
///    saturate to `UInt64.max` rather than wrapping, because a wrapped total
///    puts the largest holder in the server on no rung at all. An amount column
///    that cannot hold the saturated figure fails while somebody is being paid.
/// 2. Big endian bytes compare the same way the numbers do. SQLite orders BLOBs
///    with `memcmp`, so `ORDER BY` on this column is numeric order across the
///    whole range, which decimal text is not and a signed integer holding a
///    reinterpreted bit pattern certainly is not.
/// 3. An operator opening the file in something that is not this project sees a
///    blob rather than a negative number that is secretly a large positive one
///    (HOST-9). `hex(col)` reads it, and the column carries a `CHECK` so a
///    wrong-shaped write is refused by the database rather than discovered
///    later by an arithmetic that quietly used the wrong number.
public enum BaseUnits: Sendable {

    // MARK: - Properties

    /// Bytes in a stored amount.
    public static let width = 8

    // MARK: - Public Methods

    /// An amount as the bytes a column holds.
    public static func bytes(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var encoded = [UInt8](repeating: 0, count: width)
        var index = width - 1
        while index >= 0 {
            encoded[index] = UInt8(truncatingIfNeeded: remaining)
            remaining >>= 8
            index -= 1
        }
        return encoded
    }

    /// An amount as a bound value.
    public static func value(_ amount: UInt64) -> SQLValue {
        .blob(bytes(amount))
    }

    /// The amount a column holds, or a refusal.
    ///
    /// Throws rather than answering zero. A pool supply read as zero makes
    /// every share zero and every rung collapse, silently, which is worse than
    /// refusing to answer at all.
    public static func amount(_ bytes: [UInt8], row: String) throws -> UInt64 {
        guard bytes.count == width else {
            throw StoreError.unreadableRow(
                row: row,
                reason: "an amount is \(width) bytes and this one is \(bytes.count)"
            )
        }
        var value: UInt64 = 0
        for byte in bytes {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }
}
