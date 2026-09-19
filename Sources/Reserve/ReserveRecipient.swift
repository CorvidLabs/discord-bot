import Foundation

/// One account, who it belongs to, and what it is currently known to hold.
///
/// The holding **ids** matter as much as the count, and that is not obvious. A
/// count is enough to work out what to pay; only the ids can tell you that the
/// thing being paid for is the same thing that was already paid for on a
/// different account earlier in the same epoch. Without them, moving a held unit
/// between two known accounts mid-epoch buys a second payment.
public struct ReserveRecipient: Sendable, Equatable, Hashable, Codable, Identifiable {

    // MARK: - Properties

    /// The person. Two accounts owned by one person share this.
    public let id: String

    /// Where a payment for this row would go.
    public let account: String

    /// Ids of the qualifying things this account is known to hold, unique and
    /// sorted so a plan built from the same facts is byte-for-byte the same.
    public let holdingIds: [String]

    // MARK: - Initializers

    public init(id: String, account: String, holdingIds: [String]) {
        self.id = id
        self.account = account
        self.holdingIds = Array(Set(holdingIds)).sorted()
    }

    // MARK: - Public Methods

    /// True when this account holds nothing that qualifies.
    public var holdsNothing: Bool { holdingIds.isEmpty }
}

/// Who is payable for one stream, and who could not be read.
///
/// The second list is the important one. A recipient whose holdings could not be
/// read is *unknown*, not empty, and the difference decides whether anybody gets
/// paid at all: a list with holes in it pays a short list, a short payout cannot
/// be undone, and it looks like favouritism to everybody who was missed.
public struct ReserveRecipientList: Sendable, Equatable {

    // MARK: - Properties

    /// The stream this list is for.
    public let streamId: String

    /// Every account that could be read, with what it holds.
    public let recipients: [ReserveRecipient]

    /// People with at least one account that could not be read.
    public let incompleteRecipientIds: [String]

    /// People read successfully who hold nothing qualifying.
    public let ineligibleCount: Int

    // MARK: - Initializers

    public init(
        streamId: String,
        recipients: [ReserveRecipient],
        incompleteRecipientIds: [String] = [],
        ineligibleCount: Int = 0
    ) {
        self.streamId = streamId
        self.recipients = recipients
        self.incompleteRecipientIds = incompleteRecipientIds
        self.ineligibleCount = ineligibleCount
    }

    // MARK: - Public Methods

    /// True when a live run from this list would abort.
    public var wouldAbortLiveRun: Bool { !incompleteRecipientIds.isEmpty }

    /// People with at least one payable account.
    public var eligibleRecipientIds: [String] {
        Array(Set(recipients.filter { !$0.holdsNothing }.map(\.id))).sorted()
    }

    /// Eligible slots under a stream's rule.
    public func eligibleUnits(rule: ReservePayoutRule) -> UInt64 {
        ReservePlanner.eligibleUnits(rule: rule, recipients: recipients)
    }

    /// The recipients, or a refusal when anything could not be read.
    public func requireComplete() throws -> [ReserveRecipient] {
        guard incompleteRecipientIds.isEmpty else {
            throw ReserveError.incompleteRecipients(incompleteRecipientIds.count)
        }
        return recipients
    }
}
