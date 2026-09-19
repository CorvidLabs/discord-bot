import Foundation
import Crypto

/// Why a proof was not accepted, in the order the reasons are produced.
///
/// The order is the contract, not an implementation detail, and a later
/// reason is never returned while an earlier one holds. Two properties come
/// out of it. A member whose wallet had the wrong account selected is told the
/// sender did not match, which is something they can fix, rather than told
/// their signature was bad, which is not. And a caller that wants to know
/// whether a chain read for an authorising address is worth making can tell
/// the signature refusal apart from every other one.
///
/// Fifteen positions. ``step`` is what says which, so a suite can prove the
/// order rather than assert it.
public enum ProofRefusalReason: Sendable, Equatable {

    /// Which allowance a submission ran out of.
    ///
    /// The two are one step and one reason, and they are **not** one
    /// sentence, because the remedies are opposites: a session that has
    /// spent its three attempts is fixed by a new link, and a subject that
    /// has spent the window's twelve is fixed by nothing but waiting. Told
    /// to fetch a new link, that member fetches one, is refused on a link
    /// they have never tried, and reads a sentence that is not merely
    /// unhelpful but false. The non-disclosure argument that collapses four
    /// situations into ``sessionUnavailable`` does not reach here: the
    /// subject being told is the member themselves.
    public enum SubmissionBound: Sendable, Equatable {

        /// This link has been tried as often as one link may be.
        case session

        /// This member has tried as often as one member may in the window.
        case subject
    }

    /// The session id selects nothing live.
    ///
    /// **One reason for five situations**, deliberately: never issued,
    /// consumed, expired and pruned, displaced by a newer session for the
    /// same subject, or claimed by a call that is still being decided.
    /// Telling them apart tells whoever holds a stolen id whether it was ever
    /// real, and tells somebody walking ids when a member is part way
    /// through, which is exactly what the last of the five would otherwise
    /// announce. A session still held and past its expiry is a different case
    /// and reports ``sessionExpired``, because a member needs to know that a
    /// new link is what fixes it.
    ///
    /// It also covers a session nothing has connected an address to. A page
    /// connects before it asks anybody to sign, so this is the host's mistake
    /// rather than a member's, and saying more about a session to whoever
    /// holds its id is one more thing about somebody else's flow.
    case sessionUnavailable

    /// The session, or the subject, has made as many submissions as it may.
    ///
    /// A refused proof leaves the session usable, which is right for a member
    /// who mis-tapped and is also a loop: field correct proofs signed by a
    /// throwaway key, forever, each one costing the host a chain read for an
    /// authorising address. One member could exhaust the day's budget and
    /// pause everything the whole server depends on (RUN-11).
    ///
    /// - Parameter bound: Which allowance ran out, because a new link fixes
    ///   one of them and nothing but waiting fixes the other.
    case submissionsExhausted(SubmissionBound)

    /// The session is already connected to a different address.
    ///
    /// Answered without saying anything at all about the second address. The
    /// host's check for an address another member has already proved is the
    /// right behaviour and, asked freely, it answers "does this address
    /// belong to a member here?" for any address anybody cares to type. Bound
    /// to the session it is asked once, about the address the member actually
    /// connected.
    case addressAlreadyConnected

    /// The session had run out before the proof arrived.
    case sessionExpired

    /// The submission was not base64, was empty, or was over the ceiling.
    case blobUnreadable

    /// The bytes decoded and are not a signed transaction.
    case transactionUnparsable

    /// The transaction is missing something a proof has to carry.
    case missingField(RequiredTransactionField)

    /// The transaction is not a payment.
    case notAPayment

    /// The account that signed is not the account the member named when the
    /// session was minted.
    ///
    /// Its own reason, before ``senderMismatch``, because the two are
    /// different sentences to a member: this is not the account you named,
    /// and this is not the account you connected. Whenever both hold the
    /// first is the more useful, because the member chose it themselves and
    /// can hold it up against what their wallet is showing them.
    case pinnedAddressMismatch

    /// The account that signed is not the account that was connected.
    case senderMismatch

    /// The payment is not to the same account it came from.
    case receiverMismatch

    /// The payment moves something.
    case amountNotZero

    /// The fee is above what a proof may carry.
    case feeAboveBound

    /// The transaction carries a field a proof may never carry.
    case forbiddenField(ForbiddenTransactionField)

    /// The prompt that was signed was minted for a different member.
    ///
    /// Read out of the **submitted** note, at the line index the challenge
    /// shape fixes, and compared against the subject the session was minted
    /// for. Two things about that are load bearing. It is not rebuilt from
    /// the session's stored challenge, which would compare a value against
    /// itself and always pass. And it sits **before** the note comparison,
    /// which is byte exact: a proof naming another member differs in the note
    /// as well, so a subject reason placed after it could never be returned
    /// and the member would be told their wallet sent the wrong bytes rather
    /// than that this prompt was somebody else's.
    case subjectMismatch

    /// What was signed is not this session's challenge.
    case noteMismatch

    /// The signature does not check out.
    ///
    /// - Parameter authorizingKeyRetryAvailable: Whether the caller may read
    ///   the account's authorising address once and ask again, which is what
    ///   lets a rekeyed account still prove ownership. At most once per
    ///   session: a bound that lives in a sentence is a habit, and a habit is
    ///   not a bound.
    case signatureInvalid(authorizingKeyRetryAvailable: Bool)

    // MARK: - Public Methods

    /// Which of the fifteen positions this reason is produced at.
    ///
    /// Three reasons share position one, because session state is one step
    /// with more than one thing that can be wrong with it, and each of those
    /// is a different sentence to a member.
    public var step: Int {
        switch self {
        case .sessionUnavailable, .submissionsExhausted, .addressAlreadyConnected: return 1
        case .sessionExpired: return 2
        case .blobUnreadable: return 3
        case .transactionUnparsable: return 4
        case .missingField: return 5
        case .notAPayment: return 6
        case .pinnedAddressMismatch: return 7
        case .senderMismatch: return 8
        case .receiverMismatch: return 9
        case .amountNotZero: return 10
        case .feeAboveBound: return 11
        case .forbiddenField: return 12
        case .subjectMismatch: return 13
        case .noteMismatch: return 14
        case .signatureInvalid: return 15
        }
    }

    /// A sentence a member can act on.
    ///
    /// Written here rather than configured, because this module reads nothing
    /// from outside the process. A host that wants its own words switches on
    /// the case and writes them, which is also how it translates them.
    public var message: String {
        switch self {
        case .sessionUnavailable:
            return "That link is no longer usable. Run the command again for a new one."
        case .addressAlreadyConnected:
            return "That link is already connected to a different wallet. "
                + "Run the command again if you meant to use another one."
        case .submissionsExhausted(.session):
            return "That link has been tried too many times. Run the command again for a new one."
        case .submissionsExhausted(.subject):
            return "You have tried to verify too many times in a short while. "
                + "Wait a while and run the command again; a new link will not help."
        case .sessionExpired:
            return "That link has expired. Run the command again for a new one."
        case .blobUnreadable:
            return "Your wallet's reply did not arrive in a form this could read. Try again."
        case .transactionUnparsable:
            return "Your wallet's reply was not a signed transaction. Try again."
        case .missingField(let field):
            return "The signed transaction has no \(field.rawValue). Try again."
        case .notAPayment:
            return "What was signed is not a payment. Start again from the link."
        case .pinnedAddressMismatch:
            return "That is not the account you named when you ran the command. "
                + "Select that account in your wallet, or run the command again for the one you meant."
        case .senderMismatch:
            return "That is not the account you connected. Select that account in your wallet and try again."
        case .receiverMismatch:
            return "What was signed is a payment to somebody else rather than a proof. Start again from the link."
        case .amountNotZero:
            return "What was signed moves funds. A proof moves nothing. Start again from the link."
        case .feeAboveBound:
            return "What was signed carries a fee above what a proof may carry. Start again from the link."
        case .forbiddenField(let field):
            return "What was signed carries \(field.wireName), which a proof may never carry. "
                + "Do not sign it again, and start again from the link."
        case .subjectMismatch:
            return "That prompt was started for somebody else. If you did not just run the command yourself, "
                + "somebody is trying to take your wallet."
        case .noteMismatch:
            return "What was signed is not this request. Run the command again for a new link."
        case .signatureInvalid:
            return "The signature does not match that account. Select the account you connected and try again."
        }
    }
}

/// Something a host can correlate a refusal against, and nobody can replay.
///
/// A refusal is the value that ends up in a log, and the session id may never
/// reach one: it is a bearer credential, and whoever reads the log could then
/// submit against the session. So the refusal carries this instead. It is
/// stable, so an operator can match a member's report to a line, and it is a
/// truncated digest of a hundred and twenty eight bit random value, so it is
/// not an abbreviation of the id with fewer characters to guess.
public struct RefusalHandle: Sendable, Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// Characters in a handle.
    public static let characterCount: Int = 12

    /// The handle itself, lowercase hexadecimal.
    public let value: String

    public var description: String { value }

    // MARK: - Initializers

    /// - Parameter sessionIdentifier: The session the refusal belongs to.
    internal init(sessionIdentifier: VerificationSessionIdentifier) {
        let digest = SHA256.hash(data: Data(sessionIdentifier.value.utf8))
        self.value = digest
            .prefix(RefusalHandle.characterCount / 2)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// A refusal, as a host receives it.
///
/// Exhaustively: a reason and a handle. Not the submitted blob, not the
/// signature, not the challenge, and **not the session id**. A signature in a
/// log is a signature somebody else can replay against any checker that does
/// not bind to a session; a session id in a log is worse, because it binds.
public struct ProofRefusal: Sendable, Equatable {

    // MARK: - Properties

    /// Why the proof was not accepted.
    public let reason: ProofRefusalReason

    /// Something to correlate this against, which nobody can replay.
    public let handle: RefusalHandle

    /// The sentence a member reads.
    public var message: String { reason.message }

    // MARK: - Initializers

    /// - Parameters:
    ///   - reason: Why the proof was not accepted.
    ///   - handle: The handle for the session it was submitted to.
    internal init(reason: ProofRefusalReason, handle: RefusalHandle) {
        self.reason = reason
        self.handle = handle
    }
}
