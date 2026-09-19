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

    /// The **cadence** period this run claimed: the week or month that stops
    /// this schedule being paid twice.
    ///
    /// Named for its sense rather than called `periodKey`, because the other
    /// period in this module, the host's spending ceiling, now appears on the
    /// same value as ``charges``. Two senses of one word on one report is how
    /// somebody reconciles a payout against the wrong ceiling.
    public let cadencePeriodKey: String

    /// The ceilings this run was measured against, in the order they were
    /// charged, as the epoch's record now holds them.
    ///
    /// Carried here so a host can report which ceiling the run was counted
    /// against without reading the store a second time. Empty means the host
    /// stated no ceiling, never that the period is unknown.
    public let charges: [ReserveEpochCharge]

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
        cadencePeriodKey: String,
        charges: [ReserveEpochCharge],
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
        self.cadencePeriodKey = cadencePeriodKey
        self.charges = charges
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

    /// The spending periods this run was counted against, in the order they
    /// were charged.
    ///
    /// Empty means no ceiling was in force. A resumed epoch names both
    /// periods, which is the whole reason this is a list.
    public var chargedPeriodKeys: [String] { charges.map(\.periodKey) }
}
