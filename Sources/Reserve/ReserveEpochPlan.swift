import Foundation

/// Why a recipient was left out of a planned epoch.
///
/// Every exclusion has a named reason rather than a silent absence, because
/// "why was I not paid" is the question this package exists to be able to
/// answer.
public enum ReserveSkipReason: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// This account already took a payment in this epoch.
    case accountAlreadyPaid
    /// This person was already paid this epoch on another account, and the
    /// stream pays once per recipient.
    case recipientAlreadyPaid
    /// Every qualifying thing on this account was already paid this epoch,
    /// somewhere else.
    case holdingsAlreadyClaimed
    /// This account holds nothing that qualifies.
    case holdsNothing
}

/// One account's line in a planned epoch.
public struct ReserveEpochEntry: Sendable, Equatable, Hashable, Codable {

    // MARK: - Properties

    /// The person being paid.
    public let recipientId: String

    /// Where the payment goes.
    public let account: String

    /// Slots this line claims. One for a once-per-recipient stream; the number
    /// of unclaimed holdings for a per-unit stream.
    public let units: UInt64

    /// Smallest units this line pays.
    public let baseUnitsAmount: UInt64

    /// The holding ids this line consumes for the epoch.
    ///
    /// Always *all* of the unclaimed qualifying holdings, even on a
    /// once-per-recipient stream that only paid for one slot. Claiming only the
    /// one that was paid for would leave the rest free to buy a second payment
    /// after a transfer.
    ///
    /// On a once-per-recipient stream that is every holding the **person** has,
    /// on every account of theirs, not only on the account being paid. Their
    /// other accounts are skipped and claim nothing of their own, so this is
    /// the only handle the ledger keeps on the rest of them once the recipient
    /// id stops naming anybody.
    public let claimedHoldingIds: [String]

    // MARK: - Initializers

    public init(
        recipientId: String,
        account: String,
        units: UInt64,
        baseUnitsAmount: UInt64,
        claimedHoldingIds: [String]
    ) {
        self.recipientId = recipientId
        self.account = account
        self.units = units
        self.baseUnitsAmount = baseUnitsAmount
        self.claimedHoldingIds = claimedHoldingIds
    }
}

/// A recipient left out of a plan, and why.
public struct ReserveSkippedRecipient: Sendable, Equatable, Hashable, Codable {

    // MARK: - Properties

    /// The person left out.
    public let recipientId: String

    /// The account that was considered.
    public let account: String

    /// Why.
    public let reason: ReserveSkipReason

    // MARK: - Initializers

    public init(recipientId: String, account: String, reason: ReserveSkipReason) {
        self.recipientId = recipientId
        self.account = account
        self.reason = reason
    }
}

/// One planned epoch: who is paid, how much, and what it consumes.
///
/// A plan is inert. Building one sends nothing, writes nothing and claims
/// nothing, which is what makes it safe to build one purely to look at.
public struct ReserveEpochPlan: Sendable, Equatable {

    // MARK: - Properties

    /// The stream being paid.
    public let streamId: String

    /// The duration this epoch belongs to.
    public let schedule: ReserveSchedule

    /// Epoch number, from 1.
    public let epoch: UInt64

    /// Smallest units one slot is paid this epoch.
    public let perUnitBaseUnits: UInt64

    /// The lines to pay, in account order.
    public let entries: [ReserveEpochEntry]

    /// Recipients left out, with reasons.
    public let skipped: [ReserveSkippedRecipient]

    // MARK: - Initializers

    public init(
        streamId: String,
        schedule: ReserveSchedule,
        epoch: UInt64,
        perUnitBaseUnits: UInt64,
        entries: [ReserveEpochEntry],
        skipped: [ReserveSkippedRecipient]
    ) {
        self.streamId = streamId
        self.schedule = schedule
        self.epoch = epoch
        self.perUnitBaseUnits = perUnitBaseUnits
        self.entries = entries
        self.skipped = skipped
    }

    // MARK: - Public Methods

    /// Smallest units the whole epoch pays.
    public var totalBaseUnits: UInt64 {
        entries.reduce(UInt64(0)) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(entry.baseUnitsAmount)
            return overflow ? UInt64.max : sum
        }
    }

    /// Slots this epoch claims.
    public var totalUnits: UInt64 {
        entries.reduce(UInt64(0)) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(entry.units)
            return overflow ? UInt64.max : sum
        }
    }

    /// Whole units the epoch charges against a whole-unit limit, rounded up per
    /// payment rather than once on the total.
    public func limitCostWholeUnits(asset: ReserveAsset) -> UInt64 {
        entries.reduce(UInt64(0)) { total, entry in
            let cost = asset.wholeUnitsRoundingUp(baseUnits: entry.baseUnitsAmount)
            let (sum, overflow) = total.addingReportingOverflow(cost)
            return overflow ? UInt64.max : sum
        }
    }
}
