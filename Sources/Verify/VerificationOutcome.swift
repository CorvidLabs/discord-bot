import Foundation

/// What a submission came to.
public enum VerificationOutcome: Sendable, Equatable {

    /// A signature was checked and the session was spent.
    case proved(ProvedAccount)

    /// It was not, and this is the first reason in the order that held.
    case refused(ProofRefusal)
}

/// What connecting an address to a session came to.
///
/// Its own type because connecting is a different moment from submitting: it
/// happens before the member's wallet asks them to sign, which is the whole
/// value of naming a wallet up front. A mismatch found here costs the member
/// a retyped command; the same mismatch found after a signature costs them a
/// signature.
public enum ConnectionOutcome: Sendable, Equatable {

    /// The address is the one this session is held to from now on.
    case connected(VerificationSession)

    /// It is not, and this is why.
    case refused(ProofRefusal)
}
