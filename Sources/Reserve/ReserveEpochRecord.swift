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

    /// The ceilings this epoch was measured against, in the order they were
    /// charged.
    ///
    /// A list rather than one value, because an epoch cut off on Sunday and
    /// resumed on Monday really was measured against two weeks' ceilings, and
    /// a record naming only the first would be a confident lie in the one
    /// situation an operator opens it for. An ordinary epoch holds exactly
    /// one, and an epoch run for a host that stated no ceiling holds none:
    /// nothing anywhere invents one.
    public var charges: [ReserveEpochCharge]

    // MARK: - Initializers

    public init(
        streamId: String,
        epoch: UInt64,
        paidAccounts: [String] = [],
        paidRecipientIds: [String] = [],
        claimedHoldingIds: [String] = [],
        paidBaseUnits: UInt64 = 0,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        charges: [ReserveEpochCharge] = []
    ) {
        self.streamId = streamId
        self.epoch = epoch
        self.paidAccounts = paidAccounts
        self.paidRecipientIds = paidRecipientIds
        self.claimedHoldingIds = claimedHoldingIds
        self.paidBaseUnits = paidBaseUnits
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.charges = charges
    }

    // MARK: - Coding

    /// The keys a record is written under.
    ///
    /// Spelled out rather than synthesised because ``init(from:)`` below has to
    /// be written by hand, and a synthesised key set beside a hand written
    /// decoder is two things that can drift apart. Private, because what a row
    /// is called on disk is this type's business and a host that needs the
    /// names has a store rather than a key set.
    private enum CodingKeys: String, CodingKey {

        /// The stream.
        case streamId

        /// The epoch number.
        case epoch

        /// Accounts already paid.
        case paidAccounts

        /// People already paid.
        case paidRecipientIds

        /// Holdings already paid for.
        case claimedHoldingIds

        /// Smallest units already committed.
        case paidBaseUnits

        /// When the epoch first claimed anybody.
        case startedAt

        /// When the epoch ran to the end.
        case completedAt

        /// The ceilings the epoch was measured against.
        case charges
    }

    /// Reads a record, treating a missing list of charges as no charges.
    ///
    /// **Only that key, and deliberately.** Synthesised decoding of a
    /// non-optional array throws on a missing key, and here that throw is not
    /// harmless: the rule everywhere else is that an epoch row which cannot be
    /// read throws rather than reading as unpaid, so a row written by a build
    /// from before this field existed would stop every run of that stream
    /// until somebody edited the database (ADOPT-5). Every other key still
    /// throws when it is missing, because a row with no `paidAccounts` really
    /// is a row nobody can trust.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.streamId = try container.decode(String.self, forKey: .streamId)
        self.epoch = try container.decode(UInt64.self, forKey: .epoch)
        self.paidAccounts = try container.decode([String].self, forKey: .paidAccounts)
        self.paidRecipientIds = try container.decode([String].self, forKey: .paidRecipientIds)
        self.claimedHoldingIds = try container.decode([String].self, forKey: .claimedHoldingIds)
        self.paidBaseUnits = try container.decode(UInt64.self, forKey: .paidBaseUnits)
        self.startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.charges = try container.decodeIfPresent([ReserveEpochCharge].self, forKey: .charges) ?? []
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

    /// The periods this epoch was charged against, in the order they were
    /// charged.
    ///
    /// For a reader that wants the answer without walking the charges. Empty
    /// means no ceiling was in force, never that the period is unknown: a host
    /// that states no limits produces no charge.
    public var chargedPeriodKeys: [String] { charges.map(\.periodKey) }

    /// Records that this run was measured against a ceiling, to be called
    /// **before** the first payment of the run is attempted.
    ///
    /// Appends rather than overwrites. A resumed epoch names both periods, in
    /// the order they were charged, because it really was measured twice; an
    /// implementation that replaced the value would answer the boundary case
    /// with the period the run did not finish in.
    ///
    /// - Parameters:
    ///   - periodKey: The period the ceiling belonged to, from
    ///     ``ReserveSpendLimits/periodKey`` and from nowhere else.
    ///   - checkedWholeUnits: What the run was measured as costing.
    ///   - date: When the measurement was taken.
    public mutating func recordCharge(periodKey: String, checkedWholeUnits: UInt64, at date: Date) {
        charges.append(
            ReserveEpochCharge(
                periodKey: periodKey,
                checkedWholeUnits: checkedWholeUnits,
                recordedAt: date
            )
        )
    }

    /// Claims one line's slots, to be called **before** the payment is attempted.
    ///
    /// **All three lists only ever grow at the end**, and that is a storage
    /// decision rather than a tidiness one. A runner saves the whole record
    /// once per line, so a backend that keeps the lists as rows can send only
    /// what is new when the rows it already wrote are a prefix of the list it
    /// is being handed. Sorting the holdings here, as this once did, put a new
    /// id in the middle about half the time, which made every save rewrite
    /// every row of the epoch: quadratic in the slots paid, and slow enough
    /// for an operator to kill a payout half way through, which is the
    /// half-finished payout the whole design exists to prevent. Nothing reads
    /// these in order, because every reader goes through the sets below.
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
        for holdingId in entry.claimedHoldingIds where claimed.insert(holdingId).inserted {
            claimedHoldingIds.append(holdingId)
        }
        let (sum, overflow) = paidBaseUnits.addingReportingOverflow(entry.baseUnitsAmount)
        paidBaseUnits = overflow ? UInt64.max : sum
    }

    /// The record this epoch would end with if every entry were paid.
    ///
    /// For a rehearsal, which needs the finished shape of the row without
    /// writing any of it. Folded in one pass because ``claim(entry:at:)``
    /// rebuilds the claimed set on every call, which is nothing for one payment
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
            for holdingId in entry.claimedHoldingIds where claimed.insert(holdingId).inserted {
                copy.claimedHoldingIds.append(holdingId)
            }
            let (sum, overflow) = copy.paidBaseUnits.addingReportingOverflow(entry.baseUnitsAmount)
            copy.paidBaseUnits = overflow ? UInt64.max : sum
        }
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
