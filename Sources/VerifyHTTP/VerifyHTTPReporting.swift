@preconcurrency import Foundation
import Verify

/// What a call carries, in the one shape all three of them share.
///
/// Internal, because the only thing that builds one is this target's own
/// page. Nothing in the program constructs a request body.
internal struct VerifyCallBody: Decodable, Sendable {

    /// The session id, which arrives in a body and never in a query string.
    internal let session: String

    /// The address a wallet connected, on the connect call.
    internal let address: String?

    /// The signed blob, on the submit call.
    internal let blob: String?
}

/// One of the three calls that carry a session id.
internal enum VerifySessionCall: Sendable, Equatable {

    /// Who this session belongs to, its code and its expiry.
    case card

    /// The address a wallet connected.
    case connect

    /// The signed blob.
    case submit
}

/// What the page is told about a session before anybody signs anything.
internal struct VerifyCardReply: Encodable, Sendable {

    /// The chat account this session was minted for, as that member's own
    /// client would show it.
    internal let account: String

    /// The six characters the member compares against what their chat client
    /// just showed them.
    internal let code: String

    /// When the link stops working, in whole seconds since 1970.
    ///
    /// Read from the session's own `expiresAt` rather than written into a
    /// sentence, so what the member is shown and what the check enforces
    /// cannot drift. Rendered into the member's own clock by the page.
    internal let expiresAt: Int

    /// The exact five lines the member's wallet will ask them to sign.
    internal let challenge: String

    /// The address already connected to this session, if there is one.
    internal let connectedAddress: String?

    /// The address the member named when they ran the command, if they named
    /// one.
    internal let pinnedAddress: String?

    /// The largest fee a proof may carry.
    internal let maximumFeeMicroAlgos: UInt64
}

/// What the page is told once an address is bound to the session.
internal struct VerifyConnectReply: Encodable, Sendable {

    /// The address this session is held to from now on.
    internal let connectedAddress: String
}

/// What the page is told once a proof has been checked.
internal struct VerifyProvedReply: Encodable, Sendable {

    /// A word the page branches on.
    internal let status: String

    /// The sentence the member reads.
    internal let message: String
}

/// What every refusal from this surface looks like on the wire.
///
/// **A reason and a handle, and never the session id.** The id is a bearer
/// credential, and a refusal is the value that ends up pasted into a support
/// thread, screenshotted, and copied into a bug report (VERIFY-7,
/// REQ-verify-007).
internal struct VerifyRefusalReply: Encodable, Sendable {

    /// The sentence the member reads.
    internal let error: String

    /// Something an operator can correlate against, which nobody can replay.
    internal let handle: String?

    /// Whether trying again from this page could help, or whether the member
    /// has to run the command again.
    internal let retryable: Bool
}

/// How a refusal from the verification module is reported over HTTP.
///
/// The mapping is written down in one place rather than at each call site,
/// because a status code is a contract with the page and with anything an
/// operator points at this surface.
internal enum VerifyRefusalReporting: Sendable {

    // MARK: - Internal Methods

    /// The status code a refusal is answered with.
    ///
    /// - Parameter reason: Why the proof was not accepted.
    internal static func status(for reason: ProofRefusalReason) -> Int {
        switch reason {
        // The id selects nothing live, and the answer says no more than that.
        case .sessionUnavailable:
            return 404
        // Its own code, because a new link is what fixes it.
        case .sessionExpired:
            return 410
        // The session is already held to something else.
        case .addressAlreadyConnected, .pinnedAddressMismatch:
            return 409
        // An allowance ran out, which is what this code means.
        case .submissionsExhausted:
            return 429
        // The request was well formed and the proof was not.
        case .blobUnreadable, .transactionUnparsable, .missingField, .notAPayment,
             .senderMismatch, .receiverMismatch, .amountNotZero, .feeAboveBound,
             .forbiddenField, .subjectMismatch, .noteMismatch, .signatureInvalid:
            return 422
        }
    }

    /// Whether another try from the same page could come to anything.
    ///
    /// The page uses it to decide whether to leave the form up or to tell the
    /// member to start again, so a wrong answer here is a member retrying
    /// something that can never work.
    ///
    /// - Parameter reason: Why the proof was not accepted.
    internal static func isRetryable(_ reason: ProofRefusalReason) -> Bool {
        switch reason {
        case .sessionUnavailable, .sessionExpired, .submissionsExhausted,
             .addressAlreadyConnected, .subjectMismatch:
            return false
        case .blobUnreadable, .transactionUnparsable, .missingField, .notAPayment,
             .pinnedAddressMismatch, .senderMismatch, .receiverMismatch, .amountNotZero,
             .feeAboveBound, .forbiddenField, .noteMismatch, .signatureInvalid:
            return true
        }
    }
}
