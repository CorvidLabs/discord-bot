import Foundation
import Verify

extension VerificationOutcome {

    /// Why a submission was refused, or nil when it was not.
    ///
    /// A suite compares the reason rather than the whole outcome on
    /// purpose: a refusal's handle is minted inside the module and is not a
    /// value a test can construct, which is the same rule that keeps a
    /// proved account from being constructible outside it.
    var refusalReason: ProofRefusalReason? {
        switch self {
        case .refused(let refusal): return refusal.reason
        case .proved: return nil
        }
    }
}

extension ConnectionOutcome {

    /// Why a connection was refused, or nil when it was not.
    var refusalReason: ProofRefusalReason? {
        switch self {
        case .refused(let refusal): return refusal.reason
        case .connected: return nil
        }
    }

    /// The session, when the address was accepted.
    var session: VerificationSession? {
        switch self {
        case .connected(let session): return session
        case .refused: return nil
        }
    }
}
