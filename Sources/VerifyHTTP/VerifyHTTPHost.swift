@preconcurrency import Foundation
import Verify

/// What happened to a proof this surface handed back to the program.
public enum ProofHandoff: Sendable, Equatable {

    /// It is held, and the member finishes by confirming where they started.
    ///
    /// The confirmation is not optional and it is not this target's. A
    /// checked proof binds nothing until the member says so in the chat
    /// account the session was minted for, which is what stops somebody who
    /// relayed a link from having a wallet adopted for a member who never
    /// asked (REQ-verify-009).
    case awaitingConfirmation

    /// The program could not hold it, so nothing was recorded anywhere.
    ///
    /// Told to the member as "try again", because the alternative is a
    /// member who saw a success page and has no role.
    case unavailable
}

/// The four things this surface cannot do for itself.
///
/// Every one of them is a read of something this target deliberately cannot
/// reach. It links the verification module and nothing else: no store, no
/// chain reader, no chat client. That is what lets the whole surface be
/// exercised with no token, no node and no database, and it is why these
/// arrive as closures the program fills in.
public struct VerifyHTTPHost: Sendable {

    // MARK: - Properties

    /// The display name the member's own chat client would show, from the
    /// program's own record, given the opaque subject.
    ///
    /// **Answering nil stops the flow rather than dropping the name.** The
    /// named account is the whole mitigation for a relayed prompt: somebody
    /// runs the command, sends the link to a member, and the member is
    /// standing on the operator's real page, which cannot be made to lie
    /// about whose session it is. A page that quietly renders without the
    /// name is a page with that mitigation switched off and nothing saying
    /// so, so this surface refuses instead (REQ-verify-010).
    public let chatAccountName: @Sendable (_ subject: String) async -> String?

    /// Whether an address is already bound to somebody who is not this
    /// subject, or nil when the program could not tell.
    ///
    /// Asked after the coordinator has bound the address to the session, and
    /// never before. Asked freely it answers "does this address belong to a
    /// member here?" for any address anybody cares to type, which is an
    /// afternoon's walk from a public holder list to a list of this
    /// community's members. Asked after the bind, it is only ever asked
    /// about an address the member actually connected: once at the connect,
    /// and once more before a checked proof is handed over, because those
    /// are two separate requests and a caller that ignores the first
    /// refusal can simply send the second.
    ///
    /// **Answering nil stops the flow rather than meaning "not claimed".**
    /// A read that threw is a fact this process does not have, and a lock
    /// that reports itself open because the key could not be found is a lock
    /// that is open. The surface refuses with a `503` instead, the same way
    /// it does for a name it could not read.
    public let addressAlreadyClaimed: @Sendable (_ address: String, _ bySubjectOtherThan: String) async -> Bool?

    /// The key at that exact account's authorising address field, read by
    /// the program from a chain, or nil when there is no chain reader.
    ///
    /// Asked at most once per session and only on the signature refusal that
    /// reports the retry as available, which is the only refusal it could
    /// explain. Left nil, a rekeyed account cannot verify, and that is a
    /// smaller failure than a key from anywhere else: a key that did not
    /// come from the account's own authorising address field turns the
    /// checker into "accept a signature by whatever key the caller handed
    /// us" (REQ-verify-008, REQ-verify-009).
    public let authorizingKey: (@Sendable (_ address: String) async -> Data?)?

    /// Holds a checked proof until the member confirms it where they started.
    public let recordPendingProof: @Sendable (ProvedAccount) async -> ProofHandoff

    // MARK: - Initializers

    /// - Parameters:
    ///   - chatAccountName: The display name for an opaque subject.
    ///   - addressAlreadyClaimed: Whether an address is bound to somebody
    ///     else, or nil when that could not be read. There is no default,
    ///     because a default of false is a lock that is open and looks shut,
    ///     and nil is how a program says so rather than having to guess.
    ///   - authorizingKey: The key at an account's authorising address
    ///     field, or nil when nothing here can read a chain.
    ///   - recordPendingProof: Holds a checked proof for confirmation.
    public init(
        chatAccountName: @escaping @Sendable (_ subject: String) async -> String?,
        addressAlreadyClaimed: @escaping @Sendable (_ address: String, _ bySubjectOtherThan: String) async -> Bool?,
        authorizingKey: (@Sendable (_ address: String) async -> Data?)? = nil,
        recordPendingProof: @escaping @Sendable (ProvedAccount) async -> ProofHandoff
    ) {
        self.chatAccountName = chatAccountName
        self.addressAlreadyClaimed = addressAlreadyClaimed
        self.authorizingKey = authorizingKey
        self.recordPendingProof = recordPendingProof
    }
}
