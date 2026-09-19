import Foundation

/// Something that happened to the request budget which somebody should read.
///
/// The bot this came from wrote these straight to a logger. This layer has no
/// logger and should not grow one: a library that logs decides for its host
/// where the words go, and the words here matter too much for that. They are
/// values instead, kept in a small buffer the host drains, which also means a
/// problem that started overnight is still there to read in the morning rather
/// than having scrolled past in a terminal nobody was watching.
public struct ChainNotice: Sendable, Equatable {

    // MARK: - Properties

    /// What happened.
    public let kind: Kind

    /// When it happened.
    public let at: Date

    /// One line, written for an operator mid incident.
    public let message: String

    // MARK: - Initializers

    /// A notice, with the line an operator will read already written.
    public init(kind: Kind, at: Date, message: String) {
        self.kind = kind
        self.at = at
        self.message = message
    }

    // MARK: - Kinds

    /// The kinds of notice this layer produces.
    public enum Kind: Sendable, Equatable {

        /// A percentage of the day's request budget has been reached for the
        /// first time today.
        case budgetThresholdCrossed(percent: Int, used: UInt64, limit: UInt64)

        /// The day's request budget is spent and work is paused.
        case budgetSpent(until: Date)

        /// The provider refused with its own quota error and work is paused.
        case providerRefusedQuota(until: Date)

        /// An operator lifted a pause by hand.
        case pauseLiftedByHand(wouldHaveEndedAt: Date)

        /// The day's count could not be written down.
        case budgetNotPersisted(reason: String)

        /// As many callers are being tracked for their share as this process
        /// will track, so a caller nobody is tracking yet is being refused.
        ///
        /// Recorded once a day rather than once per refusal, like the pause
        /// above and for the same reason: a refusal that repeats thousands of
        /// times would bury the announcement under copies of itself at exactly
        /// the moment somebody is reading it.
        case callerTrackingFull(tracked: Int)
    }
}
