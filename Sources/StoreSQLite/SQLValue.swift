@preconcurrency import Foundation

/// Everything that can be bound to a statement or read out of a row.
///
/// **There is no floating point case, and there never will be.** Money in this
/// package is an integer of the asset's smallest unit, and a store that could
/// carry a `Double` is a store where one careless column turns 10,000,000,000
/// into something that does not add up. A reader that meets a `REAL` column
/// refuses rather than converting it.
public enum SQLValue: Sendable, Hashable {

    /// No value.
    case null

    /// A bounded count: rows, members, a version. Never an amount.
    case integer(Int64)

    /// Text.
    case text(String)

    /// Bytes. Amounts live here, eight of them, most significant first.
    case blob([UInt8])
}
