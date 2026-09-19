import Foundation

/// How long a session lives and how long a subject's counts are kept.
///
/// The two maximums are **not** settings. They are fixed here, because a
/// number that decides how many times anybody may try is a number somebody
/// would eventually raise to make a support ticket go away, and the floor
/// below is the whole reason the smaller one is what it is.
public struct VerificationLimits: Sendable, Equatable {

    // MARK: - Properties

    /// How many submissions one session will take.
    ///
    /// **Three, and not fewer.** A ceiling with no floor is half a bound: a
    /// maximum of one or two passes every test written against the ceiling
    /// and locks out exactly the member the authorising key seam exists for.
    /// A member on a rekeyed account legitimately needs three: one with the
    /// wrong account selected in their wallet, one with the right account
    /// which fails the signature check because the account is rekeyed, and
    /// one more when the host calls back with the key it read.
    public static let maximumSubmissionsPerSession: Int = 3

    /// How many submissions one subject will get across every session in a
    /// window.
    ///
    /// Larger than the per-session maximum, so the ordinary case, a member
    /// who ran the command twice because the first attempt confused them, is
    /// not refused by the defence against a member who ran it two hundred
    /// times. Four sessions' worth.
    public static let maximumSubmissionsPerSubject: Int = 12

    /// How long a session is usable for.
    public let sessionLifetime: TimeInterval

    /// How long a subject's counts are kept before the window restarts.
    public let subjectWindow: TimeInterval

    /// Fifteen minutes to sign, an hour of counting.
    ///
    /// Fifteen is the number the contract this was ported from tells a member,
    /// and what the member is shown is read from the session's own
    /// `expiresAt` rather than written into a sentence, so the two cannot
    /// drift.
    public static let standard: VerificationLimits = VerificationLimits(
        uncheckedSessionLifetime: 15 * 60,
        subjectWindow: 60 * 60
    )

    // MARK: - Initializers

    /// - Parameters:
    ///   - sessionLifetime: How long a session is usable for.
    ///   - subjectWindow: How long a subject's counts are kept.
    /// - Throws: ``VerifyError/intervalNotPositive(field:)`` for an interval
    ///   that is zero or negative, which would make everything expire before
    ///   it existed.
    public init(sessionLifetime: TimeInterval, subjectWindow: TimeInterval) throws {
        guard sessionLifetime > 0 else {
            throw VerifyError.intervalNotPositive(field: "sessionLifetime")
        }
        guard subjectWindow > 0 else {
            throw VerifyError.intervalNotPositive(field: "subjectWindow")
        }
        self.sessionLifetime = sessionLifetime
        self.subjectWindow = subjectWindow
    }

    /// The pair this file chose itself, which has nothing to validate.
    private init(uncheckedSessionLifetime: TimeInterval, subjectWindow: TimeInterval) {
        self.sessionLifetime = uncheckedSessionLifetime
        self.subjectWindow = subjectWindow
    }
}
