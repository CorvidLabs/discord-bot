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

    // MARK: - Initializers

    /// Built by the governor. Public so a host can put one together from
    /// figures it stored earlier.
    public init(
        usedRequests: UInt64,
        limit: UInt64,
        remainingRequests: UInt64,
        pausedUntil: Date?,
        pauseReason: PauseReason?,
        dayStart: Date
    ) {
        self.usedRequests = usedRequests
        self.limit = limit
        self.remainingRequests = remainingRequests
        self.pausedUntil = pausedUntil
        self.pauseReason = pauseReason
        self.dayStart = dayStart
    }

    // MARK: - Public Methods

    /// Whether a budget is set at all.
    public var hasBudget: Bool { limit > 0 }

    /// Whether reads and signing are refused right now.
    public var isPaused: Bool { pausedUntil != nil }

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
