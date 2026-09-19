import Foundation

/// What one subject has spent, across every session they have had.
///
/// Kept per subject rather than only per session because a new session
/// displaces the old one: a bound a member can refresh by running the command
/// again is a formality, and the chain reads the bound exists to limit go on
/// being spent. It survives displacement, consumption, expiry and pruning,
/// and is dropped only when the window it is counted over has passed.
///
/// It holds no challenge, no address and no session id, so keeping it past
/// the sessions it counted is not keeping anything about the member beyond a
/// number and a moment.
public struct SubjectTally: Sendable, Equatable {

    // MARK: - Properties

    /// Submissions made in this window.
    public let submissions: Int

    /// Authorising key retries offered in this window.
    public let retriesOffered: Int

    /// When the window started.
    public let windowStartedAt: Date

    // MARK: - Initializers

    /// - Parameters:
    ///   - submissions: Submissions made in this window.
    ///   - retriesOffered: Authorising key retries offered in this window.
    ///   - windowStartedAt: When the window started.
    public init(submissions: Int, retriesOffered: Int, windowStartedAt: Date) {
        self.submissions = submissions
        self.retriesOffered = retriesOffered
        self.windowStartedAt = windowStartedAt
    }
}

/// Where sessions and the counts that bound them are kept.
///
/// A host backs this with whatever it already has. Three obligations, and
/// none of them is a suggestion:
///
/// 1. **One live session per subject.** ``store(_:)`` displaces whatever the
///    subject had, and the displaced session and its challenge are gone at
///    once rather than left to expire. Two live challenges for one member is
///    two links either of which proves a wallet.
/// 2. **A subject's counts are not a session's counts.** They survive
///    displacement, consumption, expiry and pruning, because a count a new
///    session resets is not a bound.
/// 3. **A pruned session leaves nothing.** Not the challenge, not the
///    subject, not the address.
///
/// A fourth, for a conformer that is shared rather than one process's own:
/// ``update(_:)`` here writes a whole session back, so two writers with
/// copies read at the same moment lose one of the two. The coordinator
/// claims a session for the length of a call, which covers every host that
/// runs one instance. A host that backs this with a database several
/// instances share owes the same claim at that level, or a consumed session
/// can be written back live by a call that read it before it was spent.
///
/// Every method takes the instant it needs. Nothing here reads a clock.
public protocol VerificationSessionStore: Sendable {

    /// Stores a newly minted session, displacing and discarding whatever the
    /// subject already had.
    ///
    /// - Parameter session: The session.
    func store(_ session: VerificationSession) async

    /// The session that id selects, or nil when it selects nothing.
    ///
    /// - Parameter id: The session id, compared whole.
    func session(id: VerificationSessionIdentifier) async -> VerificationSession?

    /// Writes back a session whose state or counts have moved on.
    ///
    /// - Parameter session: The session, as it now stands.
    func update(_ session: VerificationSession) async

    /// Drops consumed and expired sessions with their challenges, and subject
    /// counts whose window has passed.
    ///
    /// - Parameters:
    ///   - now: The instant to measure against.
    ///   - subjectWindow: How long a subject's counts are kept.
    func prune(now: Date, subjectWindow: TimeInterval) async

    /// What a subject has spent in the current window, starting a new window
    /// when the last one has passed.
    ///
    /// - Parameters:
    ///   - subject: The opaque subject.
    ///   - now: The instant to measure the window against.
    ///   - subjectWindow: How long a window lasts.
    func tally(forSubject subject: String, now: Date, subjectWindow: TimeInterval) async -> SubjectTally

    /// Counts one submission against a subject.
    ///
    /// - Parameters:
    ///   - subject: The opaque subject.
    ///   - now: The instant to measure the window against.
    ///   - subjectWindow: How long a window lasts.
    func countSubmission(forSubject subject: String, now: Date, subjectWindow: TimeInterval) async

    /// Counts one authorising key retry offered to a subject.
    ///
    /// Recorded rather than used as a bound of its own: the submission count
    /// already caps how many times a subject can be told anything at all, and
    /// a retry is offered at most once per session. A host that wants to see
    /// how often rekeyed accounts are turning up has the number.
    ///
    /// - Parameters:
    ///   - subject: The opaque subject.
    ///   - now: The instant to measure the window against.
    ///   - subjectWindow: How long a window lasts.
    func countRetryOffered(forSubject subject: String, now: Date, subjectWindow: TimeInterval) async
}
