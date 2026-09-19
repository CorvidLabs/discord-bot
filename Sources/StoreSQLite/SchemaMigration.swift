@preconcurrency import Foundation

/// One step of the schema, with the statements that make it and the statements
/// that unmake it.
///
/// Both halves are required. A migration whose `down` is a comment is a
/// migration nobody can step back over, and a store accumulates those until
/// stepping back is not a thing the software can do at all. A test applies
/// every one of these and then reverses every one of them, and asserts the
/// database is empty afterwards, which is what stops the first empty `down`.
internal struct SchemaMigration: Sendable {

    // MARK: - Properties

    /// Which step this is, from one.
    internal let version: Int

    /// What it does, in a few words, for the row it writes and for a log.
    internal let name: String

    /// The statements that apply it.
    internal let up: [SQL]

    /// The statements that undo it, newest object first.
    internal let down: [SQL]

    // MARK: - Public Methods

    /// A fingerprint of the migration's own text.
    ///
    /// A version number alone cannot catch two operators both reporting
    /// "version four" whose files are not the same, because a migration edited
    /// after it shipped keeps its number. The text is fingerprinted when it is
    /// applied and checked on every start, so an edited migration is a refusal
    /// rather than a schema nobody can reason about.
    ///
    /// FNV-1a, sixty four bits, because this is a change detector and not a
    /// security boundary: an operator who wants to edit the row can, and the
    /// point is to catch the accident rather than the adversary.
    internal var checksum: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x1000_0000_01b3
        for byte in Array(name.utf8) + up.flatMap({ Array($0.text.utf8) }) {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        let digits = String(hash, radix: 16, uppercase: false)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
