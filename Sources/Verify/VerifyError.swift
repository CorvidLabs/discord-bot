import Foundation

/// What this module refuses before there is anything to check.
///
/// Every case here is a caller's mistake rather than a member's: a label the
/// operator configured badly, an address a page sent in a form no Algorand
/// tool would accept, a session id read back from somewhere it should never
/// have been written. A member's mistake is a ``ProofRefusal`` instead, which
/// carries a sentence written for them.
///
/// **Nothing here carries a value that could be replayed or that names a
/// person.** A case says which argument was wrong by the name of the argument,
/// not by its contents, because a thrown error is the thing a host writes into
/// a log and a log is read by whoever can read logs (VERIFY-7, HOST-2).
public enum VerifyError: Error, Sendable, Equatable, CustomStringConvertible {

    /// A value rendered into a challenge line carried a line break.
    ///
    /// A challenge is five lines and the subject is located by its line index
    /// when a submitted note is checked, so a value with a break in it does
    /// not merely look untidy: it moves every line below it and the subject
    /// check reads the wrong one.
    case challengeValueCarriesLineBreak(field: String)

    /// The operator's label was longer than a challenge line may be.
    case challengeLabelTooLong(byteCount: Int, limit: Int)

    /// A session id was not the width and alphabet a minted one has.
    case malformedSessionIdentifier(characterCount: Int)

    /// An address was not the canonical rendering every Algorand tool accepts.
    ///
    /// The address itself is deliberately not carried. The argument's name is
    /// enough for whoever is fixing it, and an address is a member's public
    /// identifier in this server rather than something to scatter through a
    /// host's error reporting.
    case addressNotCanonical(field: String)

    /// An authorising key was not thirty two bytes of Ed25519 public key.
    case authorizingKeyWrongLength(byteCount: Int)

    /// A configured interval was zero or negative, so nothing would ever be
    /// live for any length of time.
    case intervalNotPositive(field: String)

    // MARK: - Public Methods

    public var description: String {
        switch self {
        case .challengeValueCarriesLineBreak(let field):
            return "\(field) carries a line break, and a challenge line may not"
        case .challengeLabelTooLong(let byteCount, let limit):
            return "the challenge label is \(byteCount) UTF-8 bytes, and the limit is \(limit)"
        case .malformedSessionIdentifier(let characterCount):
            return "a session id is \(VerificationSessionIdentifier.characterCount) lowercase "
                + "hexadecimal characters, and this one has \(characterCount)"
        case .addressNotCanonical(let field):
            return "\(field) is not a canonical Algorand address"
        case .authorizingKeyWrongLength(let byteCount):
            return "an authorising key is 32 bytes, and this one has \(byteCount)"
        case .intervalNotPositive(let field):
            return "\(field) must be longer than nothing"
        }
    }
}
