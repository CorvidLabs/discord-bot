@preconcurrency import Foundation

/// A link a member can follow to prove an account.
public struct VerificationSession: Sendable, Equatable {

    // MARK: - Properties

    /// The portal's own identifier for the session.
    ///
    /// Decoded and never used: never sent back, never stored, never shown. It
    /// is required because the decode is strict, and it is documented as
    /// required so a portal author does not leave it out.
    public let token: String

    /// Where the member goes. The only field that is read.
    public let url: String

    /// When the link stops working.
    public let expiresAt: Date

    // MARK: - Initializers

    /// - Parameters:
    ///   - token: The portal's identifier for the session.
    ///   - url: Where the member goes.
    ///   - expiresAt: When the link stops working.
    public init(token: String, url: String, expiresAt: Date) {
        self.token = token
        self.url = url
        self.expiresAt = expiresAt
    }
}

/// What the other half already has on record for a member.
public struct PortalAccount: Sendable, Equatable {

    // MARK: - Properties

    /// The account the member proved.
    public let address: String

    /// What the portal last saw it holding, in base units.
    ///
    /// A starting value only, replaced the moment a chain read succeeds. The
    /// portal's tier, if it sends one, is never read: this bot's ladder is
    /// this bot's.
    public let balanceBaseUnits: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - address: The account.
    ///   - balanceBaseUnits: What the portal last saw it holding.
    public init(address: String, balanceBaseUnits: UInt64) {
        self.address = address
        self.balanceBaseUnits = balanceBaseUnits
    }
}

/// What a keyed probe at boot found out.
public enum SharedSecretProbe: Sendable, Equatable {

    /// Both halves hold the same secret.
    case agreed

    /// They do not. Boot refuses (`VERIFY-5.b`).
    case disagreed

    /// This portal offers nothing to probe, so nothing is known either way.
    ///
    /// Not treated as agreement. A boot report says so, because an operator
    /// whose portal cannot answer this should know that the check they think
    /// they have is not running.
    case notOffered
}

/// What can go wrong talking to the other half.
public enum VerificationError: Error, Equatable, LocalizedError, Sendable {

    /// It could not be reached at all: refused, timed out, or TLS failed.
    case unreachable(String)

    /// It answered `401`. The two halves hold different secrets.
    case secretRejected

    /// It answered something this contract does not allow.
    ///
    /// `201` on create is load-bearing and compared exactly. A portal that
    /// answers `200` with a perfect body has created the session, issued the
    /// challenge, and told the member verification failed.
    case unexpectedStatus(expected: Int, received: Int)

    /// It answered the right status with a body that would not decode.
    case malformedResponse(String)

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case .unreachable(let detail):
            return "The verification portal could not be reached (\(detail)). Members cannot prove "
                + "an account until it is back."
        case .secretRejected:
            return "The verification portal refused this bot's shared secret. Both halves must hold "
                + "the same one, set in the same change."
        case .unexpectedStatus(let expected, let received):
            return "The verification portal answered \(received) where the contract says \(expected)."
        case .malformedResponse(let detail):
            return "The verification portal's answer could not be read (\(detail))."
        }
    }
}

/// The other half of verification, as a seam.
///
/// Whether the page a member signs on is served by this process or by a
/// separate service is undecided (`docs/decisions/0001-verification-portal.md`),
/// and this protocol is why that decision can wait: the shape of the four
/// calls is the same either way, and it is the shape `docs/VERIFICATION.md`
/// already describes, read out of a working implementation.
///
/// A test uses a fake. Nothing in the suite opens a socket (`BUILD-2`).
public protocol VerificationClient: Sendable {

    /// Whether it is up. Called once at boot, with no key.
    ///
    /// - Throws: ``VerificationError/unreachable(_:)``. A failure aborts the
    ///   boot rather than starting a bot whose `/verify` hands members a link
    ///   into nothing.
    func health() async throws

    /// Whether both halves hold the same secret.
    ///
    /// Called once at boot, **with** the key, because the health call carries
    /// none and so a portal reachable with the wrong secret passes that gate.
    /// `VERIFY-5.b` is that an operator learns this at startup rather than
    /// from the first member whose `/verify` came back `401`.
    func probeSharedSecret() async throws -> SharedSecretProbe

    /// The account the portal already has for this member, or nil.
    ///
    /// `404` is nil and is not an error: a member with no account is the
    /// ordinary case.
    ///
    /// - Parameters:
    ///   - externalId: The member's chat account id.
    ///   - guildId: The server.
    func account(externalId: String, guildId: String) async throws -> PortalAccount?

    /// A fresh link for this member.
    ///
    /// - Parameters:
    ///   - externalId: The member's chat account id.
    ///   - guildId: The server.
    func createSession(externalId: String, guildId: String) async throws -> VerificationSession

    /// Forgets this member on the other half too.
    ///
    /// Called on unlink. Deleting the link here and leaving a live session
    /// there is how an unlinked member keeps whatever the session opened.
    ///
    /// - Parameters:
    ///   - externalId: The member's chat account id.
    ///   - guildId: The server.
    func deleteSession(externalId: String, guildId: String) async throws
}
