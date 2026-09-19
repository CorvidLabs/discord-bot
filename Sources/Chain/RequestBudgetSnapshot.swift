import Foundation

/// What has been spent of today's request budget, and whether work is paused.
///
/// One value, so that every surface reporting it reports the same thing. An
/// operator can see how much of today's budget for reading the chain is gone
/// while there is still time to act on it, which is only useful if the health
/// page, the status command and the logs cannot disagree.
public struct RequestBudgetSnapshot: Sendable, Equatable {

    // MARK: - Properties

    /// Requests reserved so far today.
    public let usedRequests: UInt64

    /// Requests permitted per UTC day. Zero means no budget is set.
    public let limit: UInt64

    /// Requests left today. Zero when no budget is set, so read ``hasBudget``
    /// before drawing a conclusion from it.
    public let remainingRequests: UInt64

    /// When the current pause ends, or nil when nothing is paused.
    public let pausedUntil: Date?

    /// Why work is paused, or nil when nothing is paused.
    public let pauseReason: PauseReason?

    /// Midnight UTC at the start of the day these numbers belong to.
    public let dayStart: Date

    /// The most one member's caller may take before their allowance has to
    /// refill. Zero when shares are switched off, or when no budget is set and
    /// so there is no day to take a share of.
    public let callerShareBurst: UInt64

    /// How many callers are holding an allowance that has not refilled.
    ///
    /// A count, never a list of who: nothing that names a caller leaves this
    /// layer (HOST-2).
    ///
    /// **It does not mean anybody was refused.** A caller appears here for
    /// making a single request within one refill interval, which is ordinary
    /// use, and the figure that says somebody was turned away is
    /// ``callerRefusalsToday``. Reading this one as "throttling is happening"
    /// is the mistake it is easiest to make, so both are reported and the
    /// health body carries both (RUN-11, SEE-9).
    public let throttledCallers: Int

    /// Requests taken on behalf of members today, out of ``usedRequests``.
    ///
    /// How much of the day the shares have taken between them, so an operator
    /// can see whether members or the instance's own work is spending it.
    public let callerRequestsToday: UInt64

    /// How many reservations were refused at a share today.
    ///
    /// The one figure that says a member was actually turned away, since a
    /// share refusal deliberately writes no notice. Zero here with callers
    /// held above is a bot working normally (RUN-11, SEE-9).
    public let callerRefusalsToday: UInt64

    // MARK: - Initializers

    /// Built by the governor. Public so a host can put one together from
    /// figures it stored earlier.
    ///
    /// The four share figures default to nothing, because a host rebuilding a
    /// snapshot from what it wrote down has the day's count and not the
    /// governor's live tracking, and reporting zero callers held is the
    /// honest answer when nobody is holding any.
    public init(
        usedRequests: UInt64,
        limit: UInt64,
        remainingRequests: UInt64,
        pausedUntil: Date?,
        pauseReason: PauseReason?,
        dayStart: Date,
        callerShareBurst: UInt64 = 0,
        throttledCallers: Int = 0,
        callerRequestsToday: UInt64 = 0,
        callerRefusalsToday: UInt64 = 0
    ) {
        self.usedRequests = usedRequests
        self.limit = limit
        self.remainingRequests = remainingRequests
        self.pausedUntil = pausedUntil
        self.pauseReason = pauseReason
        self.dayStart = dayStart
        self.callerShareBurst = callerShareBurst
        self.throttledCallers = throttledCallers
        self.callerRequestsToday = callerRequestsToday
        self.callerRefusalsToday = callerRefusalsToday
    }

    // MARK: - Public Methods

    /// Whether a budget is set at all.
    public var hasBudget: Bool { limit > 0 }

    /// Whether reads and signing are refused right now.
    public var isPaused: Bool { pausedUntil != nil }

    /// Whether one member's caller is bounded at all.
    ///
    /// False when no budget is set, because there is no day's budget to take a
    /// part of, and false when the share is switched off.
    public var hasCallerShare: Bool { callerShareBurst > 0 }

    /// Percentage of the budget consumed, or nil when no budget is set.
    public var percentUsed: Int? {
        guard limit > 0 else { return nil }
        return Int((Double(usedRequests) / Double(limit)) * 100)
    }

    /// Why work is paused. Two different facts, deliberately not merged: one is
    /// this process deciding it has read enough, the other is the provider
    /// refusing.
    public enum PauseReason: Sendable, Equatable {
        /// This process spent the budget it was given.
        case budgetSpent
        /// The provider refused with its own quota error.
        case providerRefusedQuota
    }
}
