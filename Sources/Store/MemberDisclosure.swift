@preconcurrency import Foundation

/// Everything one instance holds about one member, in the shape a person can
/// be shown before they decide anything (VERIFY-6, VERIFY-7.a).
///
/// It is assembled from the store rather than written by hand, so a table
/// added later is either in here or is a bug a test can name. A forgetting
/// somebody can check first is a different promise from one they have to
/// believe.
public struct MemberDisclosure: Sendable, Equatable {

    // MARK: - Properties

    /// The directory row: the key, the chat account id, and when they arrived.
    public let member: MemberRecord

    /// Every account they proved, oldest first, with the figures last read.
    public let accounts: [AccountRecord]

    /// What survives a forgetting, in sentences a member reads rather than
    /// table names (VERIFY-7.b).
    ///
    /// Written as data rather than as prose in a card, because the honest list
    /// is short, and a card that composes its own version of it drifts from
    /// what the store actually does.
    public let retainedAfterForgetting: [String]

    // MARK: - Initializers

    /// - Parameters:
    ///   - member: The directory row.
    ///   - accounts: Every account they proved, oldest first.
    ///   - retainedAfterForgetting: What survives, in plain sentences.
    public init(
        member: MemberRecord,
        accounts: [AccountRecord],
        retainedAfterForgetting: [String]
    ) {
        self.member = member
        self.accounts = accounts
        self.retainedAfterForgetting = retainedAfterForgetting
    }

    // MARK: - Public Methods

    /// What every instance owes a member about the payout ledger.
    ///
    /// Shared rather than retyped per backend, so the two implementations
    /// cannot come to disagree about what actually survives.
    public static let payoutLedgerSentence =
        "The record of a payment already made keeps the amount, the wallet it went to, the ids of "
        + "the things it paid for, and the random name this instance drew for you. That wallet and "
        + "those ids are already public on the chain. Nothing that came from the chat client is "
        + "kept, and once your directory entry is deleted the random name refers to nobody."
}

/// What a forgetting did.
///
/// The counts are the point. A forgetting reported as "done" with no numbers is
/// one a member has to believe, and the number a member is most entitled to see
/// is the one from the table somebody forgot to wire up.
public struct ForgetOutcome: Sendable, Equatable {

    // MARK: - Properties

    /// The member who was forgotten.
    public let memberKey: MemberKey

    /// Rows removed, by table, so what happened can be shown rather than
    /// summarised.
    public let cleared: [String: Int]

    // MARK: - Initializers

    /// - Parameters:
    ///   - memberKey: The member who was forgotten.
    ///   - cleared: Rows removed, by table.
    public init(memberKey: MemberKey, cleared: [String: Int]) {
        self.memberKey = memberKey
        self.cleared = cleared
    }

    // MARK: - Public Methods

    /// Rows removed across every table.
    public var clearedRowCount: Int {
        cleared.values.reduce(0, +)
    }

    /// Tables that gave something up, in a stable order.
    public var clearedTables: [String] {
        cleared.filter { $0.value > 0 }.keys.sorted()
    }
}
