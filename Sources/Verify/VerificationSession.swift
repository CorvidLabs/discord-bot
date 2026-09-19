import Foundation

/// Where a session has got to.
///
/// Terminal is terminal. A session id that selects nothing live, because it
/// was never issued, or was consumed, or expired and was pruned, or was
/// displaced by a newer session for the same subject, refuses with one reason
/// that does not say which, so a refusal discloses nothing about what else
/// exists.
public enum VerificationSessionState: String, Sendable, Equatable, CaseIterable {

    /// Minted, and nothing has connected an address to it yet.
    case issued

    /// An address has been connected and is the one a proof is held to.
    case connected

    /// A proof was accepted. Nothing else will be.
    case consumed
}

/// One member's attempt to prove one wallet, for fifteen minutes.
///
/// Sessions live in memory in the conformer this module ships and do not
/// survive a restart. That is a real cost and a small one: a restart during a
/// verification means one member starts over, and they are told that rather
/// than shown a dead link. Making it durable would mean this module reaching
/// a database, or a database learning about verification, for the sake of
/// somebody who was mid-signature during a deploy.
///
/// The per-subject submission count goes with them, which is worth saying
/// rather than discovering: a restart hands every member a fresh allowance.
/// It is acceptable because a restart is the operator's action and not a
/// member's, and it is why the rate limit a host owns is the half of that
/// defence that does not evaporate on a deploy.
public struct VerificationSession: Sendable, Equatable {

    // MARK: - Properties

    /// The one thing that selects it, and a bearer credential.
    public let id: VerificationSessionIdentifier

    /// Who the proof will be adopted for, as an opaque string this module
    /// never interprets.
    public let subject: String

    /// What the member will be asked to sign.
    public let challenge: VerificationChallenge

    /// When it was minted.
    public let issuedAt: Date

    /// When it stops being usable. A proof presented at or after this is
    /// refused naming expiry, whatever else is wrong with it.
    public let expiresAt: Date

    /// The one address this session was pinned to when it was minted, if the
    /// member named a wallet before anything was signed.
    ///
    /// An address, never a name. Turning a name into an address is an
    /// outbound call, and this is the module that makes none.
    public let pinnedAddress: String?

    /// The address that was connected, recorded once.
    public private(set) var connectedAddress: String?

    /// Where it has got to.
    public private(set) var state: VerificationSessionState

    /// How many submissions have been made against it.
    public private(set) var submissionCount: Int

    /// Whether the one authorising key retry has already been offered.
    public private(set) var authorizingKeyRetryUsed: Bool

    // MARK: - Initializers

    /// A freshly minted session.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - subject: The opaque subject it is minted for.
    ///   - challenge: What the member will sign.
    ///   - issuedAt: When it was minted.
    ///   - expiresAt: When it stops being usable.
    ///   - pinnedAddress: The address the member named, if they named one.
    internal init(
        id: VerificationSessionIdentifier,
        subject: String,
        challenge: VerificationChallenge,
        issuedAt: Date,
        expiresAt: Date,
        pinnedAddress: String?
    ) {
        self.id = id
        self.subject = subject
        self.challenge = challenge
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.pinnedAddress = pinnedAddress
        self.connectedAddress = nil
        self.state = .issued
        self.submissionCount = 0
        self.authorizingKeyRetryUsed = false
    }

    // MARK: - Internal Methods

    /// Records the address a wallet connected, once.
    internal mutating func connect(_ address: String) {
        connectedAddress = address
        state = .connected
    }

    /// Counts one submission, whether it is accepted or refused.
    internal mutating func countSubmission() {
        submissionCount += 1
    }

    /// Marks the one authorising key retry as offered.
    internal mutating func markAuthorizingKeyRetryUsed() {
        authorizingKeyRetryUsed = true
    }

    /// Marks the session spent, before its outcome is adopted rather than
    /// after.
    ///
    /// A store that marks after the account is written leaves a live
    /// challenge sitting behind a proved account when a crash lands between
    /// the two.
    internal mutating func consume() {
        state = .consumed
    }
}
