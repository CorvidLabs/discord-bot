import Foundation

/// What one epoch of one stream has already paid.
///
/// This row is the no-double-pay guard, and the order in which it is written is
/// the single most important decision in the package.
///
/// **The claim is written before the payment is attempted, never after.** The
/// window between handing value over and recording that you did is where one
/// payment becomes two: the value has left, nothing on disk says so, and the
/// next run pays the same person again. Claiming first inverts the risk. A crash
/// now leaves a claim with no payment, which under-pays by one slot and leaves
/// the value in the reserve. That is the recoverable direction: an under-paid
/// slot can be paid next epoch; an over-paid one is gone.
public struct ReserveEpochRecord: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// The stream.
    public var streamId: String

    /// Epoch number, from 1.
    public var epoch: UInt64

    /// Accounts already paid this epoch.
    public var paidAccounts: [String]

    /// People already paid this epoch. A once-per-recipient stream pays a person
    /// once however many accounts they spread their holdings across.
    public var paidRecipientIds: [String]

    /// Holding ids already paid this epoch, wherever they sit now.
    public var claimedHoldingIds: [String]

    /// Smallest units already committed this epoch.
    public var paidBaseUnits: UInt64

    /// When the epoch first claimed anybody.
    public var startedAt: Date?

    /// When the epoch ran to the end, or nil while it is unfinished.
    public var completedAt: Date?

    // MARK: - Initializers

    public init(
        streamId: String,
        epoch: UInt64,
        paidAccounts: [String] = [],
        paidRecipientIds: [String] = [],
        claimedHoldingIds: [String] = [],
        paidBaseUnits: UInt64 = 0,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.streamId = streamId
        self.epoch = epoch
        self.paidAccounts = paidAccounts
        self.paidRecipientIds = paidRecipientIds
        self.claimedHoldingIds = claimedHoldingIds
        self.paidBaseUnits = paidBaseUnits
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    // MARK: - Public Methods

    /// Accounts paid, as a set.
    public var paidAccountSet: Set<String> { Set(paidAccounts) }

    /// People paid, as a set.
    public var paidRecipientIdSet: Set<String> { Set(paidRecipientIds) }

    /// Holdings claimed, as a set.
    public var claimedHoldingIdSet: Set<String> { Set(claimedHoldingIds) }

    /// True when the epoch ran to the end.
    public var isComplete: Bool { completedAt != nil }

    /// Claims one line's slots, to be called **before** the payment is attempted.
    public mutating func claim(entry: ReserveEpochEntry, at date: Date) {
        if startedAt == nil {
            startedAt = date
        }
        if !paidAccounts.contains(entry.account) {
            paidAccounts.append(entry.account)
        }
        if !paidRecipientIds.contains(entry.recipientId) {
            paidRecipientIds.append(entry.recipientId)
        }
        var claimed = claimedHoldingIdSet
        for holdingId in entry.claimedHoldingIds {
            claimed.insert(holdingId)
        }
        claimedHoldingIds = claimed.sorted()
        let (sum, overflow) = paidBaseUnits.addingReportingOverflow(entry.baseUnitsAmount)
        paidBaseUnits = overflow ? UInt64.max : sum
    }

    /// The record this epoch would end with if every entry were paid.
    ///
    /// For a rehearsal, which needs the finished shape of the row without
    /// writing any of it. Folded in one pass because ``claim(entry:at:)``
    /// re-sorts the claimed ids on every call, which is nothing for one payment
    /// and quadratic across several thousand.
    public func claimingAll(_ entries: [ReserveEpochEntry], at date: Date) -> ReserveEpochRecord {
        guard !entries.isEmpty else { return self }
        var copy = self
        var accounts = paidAccountSet
        var people = paidRecipientIdSet
        var claimed = claimedHoldingIdSet
        for entry in entries {
            if accounts.insert(entry.account).inserted {
                copy.paidAccounts.append(entry.account)
            }
            if people.insert(entry.recipientId).inserted {
                copy.paidRecipientIds.append(entry.recipientId)
            }
            for holdingId in entry.claimedHoldingIds {
                claimed.insert(holdingId)
            }
            let (sum, overflow) = copy.paidBaseUnits.addingReportingOverflow(entry.baseUnitsAmount)
            copy.paidBaseUnits = overflow ? UInt64.max : sum
        }
        copy.claimedHoldingIds = claimed.sorted()
        if copy.startedAt == nil {
            copy.startedAt = date
        }
        return copy
    }

    /// Gives a claim back after an attempt that provably moved nothing.
    ///
    /// Only for a refusal raised *before* anything was handed over, not opted
    /// in, frozen, over a limit, an unfunded account. An attempt that got no
    /// answer keeps its claim, because the value may have left. `startedAt` is
    /// deliberately kept: the epoch really did begin.
    public mutating func release(entry: ReserveEpochEntry) {
        paidAccounts.removeAll { $0 == entry.account }
        paidRecipientIds.removeAll { $0 == entry.recipientId }
        let giveBack = Set(entry.claimedHoldingIds)
        claimedHoldingIds = claimedHoldingIds.filter { !giveBack.contains($0) }
        paidBaseUnits = paidBaseUnits >= entry.baseUnitsAmount
            ? paidBaseUnits - entry.baseUnitsAmount
            : 0
    }
}
