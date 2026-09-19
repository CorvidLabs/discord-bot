import Foundation

/// Evidence that one line was paid.
public struct ReserveReceipt: Sendable, Equatable {

    // MARK: - Properties

    /// What was owed.
    public let entry: ReserveEpochEntry

    /// What the payer gave back as proof: a transaction id, a receipt number.
    public let reference: String

    // MARK: - Initializers

    public init(entry: ReserveEpochEntry, reference: String) {
        self.entry = entry
        self.reference = reference
    }
}

/// One line that did not get paid, and what happened to its claim.
public struct ReserveFailedPayment: Sendable, Equatable {

    // MARK: - Properties

    /// What was owed.
    public let entry: ReserveEpochEntry

    /// What went wrong, for the operator's report.
    public let reason: String

    /// Whether the claim was handed back.
    ///
    /// True only when the payer proved nothing moved. False means the slot stays
    /// claimed and unpaid for this epoch: the value stays in the reserve, and
    /// nobody is at risk of being paid twice for it.
    public let claimReleased: Bool

    // MARK: - Initializers

    public init(entry: ReserveEpochEntry, reason: String, claimReleased: Bool) {
        self.entry = entry
        self.reason = reason
        self.claimReleased = claimReleased
    }
}

/// What one run of one epoch actually did.
///
/// Note what is *not* here: a success flag. An epoch that paid nobody, an epoch
/// that paid everybody, and an epoch that paid most of them are all reported the
/// same way, as lists, because collapsing that into a boolean is how a partly
/// paid epoch gets announced as a success.
public struct ReserveEpochOutcome: Sendable, Equatable {

    // MARK: - Properties

    /// The stream paid.
    public let streamId: String

    /// The duration this epoch belongs to.
    public let schedule: ReserveSchedule

    /// Epoch number, from 1.
    public let epoch: UInt64

    /// The period this run claimed.
    public let periodKey: String

    /// Smallest units one slot was paid.
    public let perUnitBaseUnits: UInt64

    /// Lines that were paid, with their evidence.
    public let paid: [ReserveReceipt]

    /// Lines that were not.
    public let failed: [ReserveFailedPayment]

    /// Recipients the plan left out, with reasons.
    public let skipped: [ReserveSkippedRecipient]

    /// Smallest units that actually went out.
    public let paidBaseUnits: UInt64

    /// True when the run reached the end of the list and closed the epoch.
    public let isComplete: Bool

    // MARK: - Initializers

    public init(
        streamId: String,
        schedule: ReserveSchedule,
        epoch: UInt64,
        periodKey: String,
        perUnitBaseUnits: UInt64,
        paid: [ReserveReceipt],
        failed: [ReserveFailedPayment],
        skipped: [ReserveSkippedRecipient],
        paidBaseUnits: UInt64,
        isComplete: Bool
    ) {
        self.streamId = streamId
        self.schedule = schedule
        self.epoch = epoch
        self.periodKey = periodKey
        self.perUnitBaseUnits = perUnitBaseUnits
        self.paid = paid
        self.failed = failed
        self.skipped = skipped
        self.paidBaseUnits = paidBaseUnits
        self.isComplete = isComplete
    }

    // MARK: - Public Methods

    /// How many lines were paid.
    public var paidCount: Int { paid.count }

    /// Slots paid across every line.
    public var paidUnits: UInt64 {
        paid.reduce(UInt64(0)) { total, receipt in
            let (sum, overflow) = total.addingReportingOverflow(receipt.entry.units)
            return overflow ? UInt64.max : sum
        }
    }

    /// True when every planned line was paid.
    public var isClean: Bool { failed.isEmpty }
}
