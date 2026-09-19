@preconcurrency import Foundation

/// What a store refuses, and why.
///
/// Every case names the thing an operator or a caller has to change. None of
/// them is recoverable by trying again with the same arguments, which is why
/// none of them is a returned optional: an optional invites a `?? default`, and
/// the default for "the row would not parse" is the one that pays everybody
/// twice.
public enum StoreError: Error, LocalizedError, Sendable, Equatable {

    /// Another member has already proved this account.
    ///
    /// One account belongs to one member. Overwriting quietly would move
    /// somebody else's holdings onto a stranger's ladder, and the member whose
    /// account it was would be demoted by a sweep they never saw.
    case accountAlreadyProven(address: String)

    /// No member is on record under this key.
    case memberNotFound(key: String)

    /// A row exists and could not be read as the value it should hold.
    ///
    /// Thrown rather than answered with a fresh record. A ledger row that reads
    /// as blank looks like an epoch nobody was paid for.
    case unreadableRow(row: String, reason: String)

    /// Another process holds the store and would not let go.
    ///
    /// Two instances sharing one file can each run the same epoch and each pay
    /// everybody, and no in-process gate can see the second one. The wait is
    /// bounded rather than endless: a retry loop inside a payout is a payout
    /// that may outlive the process running it.
    case contended(afterMilliseconds: Int)

    /// The backend failed at something that should have worked.
    case backendFailure(operation: String, reason: String)

    /// A reconciliation was asked to walk more epochs than any schedule has.
    ///
    /// A refusal rather than a clamp, because a stored epoch number far beyond
    /// any real schedule means the state is wrong and walking a truncated range
    /// would answer with a spend figure that is quietly too small.
    case epochRangeTooLarge(streamId: String, epochs: UInt64, limit: UInt64)

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case .accountAlreadyProven(let address):
            return "The account ending \(Self.tail(address)) is already proved by another member. "
                + "One account belongs to one member, so it was left where it is."
        case .memberNotFound(let key):
            return "No member is on record under the key \(Self.tail(key))."
        case .unreadableRow(let row, let reason):
            return "The row \(row) could not be read (\(reason)). Nothing was assumed about what it "
                + "said, because a ledger row read as blank looks like an epoch nobody was paid for."
        case .contended(let milliseconds):
            return "Another process is holding the store and did not let go within \(milliseconds)ms. "
                + "Two instances sharing one store can pay the same epoch twice, so this refuses "
                + "rather than waits."
        case .backendFailure(let operation, let reason):
            return "The store failed at \(operation): \(reason)"
        case .epochRangeTooLarge(let streamId, let epochs, let limit):
            return "The stream \(streamId) says its next epoch is \(epochs), which is beyond the "
                + "\(limit) any schedule runs. The recorded state is wrong, so nothing was "
                + "recomputed from it."
        }
    }

    // MARK: - Private Methods

    /// The last few characters of an identifier, so a refusal a member may read
    /// names enough to act on without printing the whole of it.
    private static func tail(_ value: String) -> String {
        value.count <= 6 ? value : "\u{2026}" + String(value.suffix(6))
    }
}
