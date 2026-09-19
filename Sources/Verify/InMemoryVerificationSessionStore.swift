import Foundation

/// Sessions kept in memory, which is where this module expects them.
///
/// A session is fifteen minutes of state holding a challenge and a subject.
/// Rows do not survive the process, and that is the decision rather than a
/// gap waiting to be filled: a durable one would mean this module reaching a
/// database, or a database learning about verification, to save one member
/// from running the command again after a deploy.
///
/// A host that wants durability writes its own conformer to
/// ``VerificationSessionStore``, which is where the per-subject bound stops
/// evaporating on a restart, and it should.
public actor InMemoryVerificationSessionStore: VerificationSessionStore {

    // MARK: - Properties

    private var sessions: [String: VerificationSession] = [:]
    private var sessionIdBySubject: [String: String] = [:]
    private var tallies: [String: SubjectTally] = [:]

    // MARK: - Initializers

    /// An empty store.
    public init() {}

    // MARK: - Public Methods

    public func store(_ session: VerificationSession) {
        if let displaced = sessionIdBySubject[session.subject] {
            // Gone at once, with its challenge, rather than left to expire.
            sessions.removeValue(forKey: displaced)
        }
        sessions[session.id.value] = session
        sessionIdBySubject[session.subject] = session.id.value
    }

    public func session(id: VerificationSessionIdentifier) -> VerificationSession? {
        sessions[id.value]
    }

    public func update(_ session: VerificationSession) {
        // Only a session this store still holds. A displaced session that a
        // caller is still carrying must not be written back into life.
        guard sessions[session.id.value] != nil else { return }
        sessions[session.id.value] = session
    }

    public func prune(now: Date, subjectWindow: TimeInterval) {
        for (key, session) in sessions
        where session.state == .consumed || session.expiresAt <= now {
            sessions.removeValue(forKey: key)
            if sessionIdBySubject[session.subject] == key {
                sessionIdBySubject.removeValue(forKey: session.subject)
            }
        }
        for (subject, tally) in tallies
        where now.timeIntervalSince(tally.windowStartedAt) >= subjectWindow {
            tallies.removeValue(forKey: subject)
        }
    }

    public func tally(forSubject subject: String, now: Date, subjectWindow: TimeInterval) -> SubjectTally {
        current(forSubject: subject, now: now, subjectWindow: subjectWindow)
    }

    public func countSubmission(forSubject subject: String, now: Date, subjectWindow: TimeInterval) {
        let tally = current(forSubject: subject, now: now, subjectWindow: subjectWindow)
        tallies[subject] = SubjectTally(
            submissions: tally.submissions + 1,
            retriesOffered: tally.retriesOffered,
            windowStartedAt: tally.windowStartedAt
        )
    }

    public func countRetryOffered(forSubject subject: String, now: Date, subjectWindow: TimeInterval) {
        let tally = current(forSubject: subject, now: now, subjectWindow: subjectWindow)
        tallies[subject] = SubjectTally(
            submissions: tally.submissions,
            retriesOffered: tally.retriesOffered + 1,
            windowStartedAt: tally.windowStartedAt
        )
    }

    /// How many sessions are held, for a suite that wants to prove a prune
    /// left nothing behind.
    public var heldSessionCount: Int { sessions.count }

    // MARK: - Private Methods

    /// The subject's counts, starting a new window when the last has passed.
    private func current(forSubject subject: String, now: Date, subjectWindow: TimeInterval) -> SubjectTally {
        guard
            let tally = tallies[subject],
            now.timeIntervalSince(tally.windowStartedAt) < subjectWindow
        else {
            return SubjectTally(submissions: 0, retriesOffered: 0, windowStartedAt: now)
        }
        return tally
    }
}
