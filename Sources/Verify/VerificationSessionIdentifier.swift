import Foundation

/// The one thing that selects a session, and a bearer credential.
///
/// Worth saying out loud, because nothing said it in the implementation this
/// was ported from: whoever holds one of these can submit a proof against that
/// session, and an accepted proof binds whatever address the submitter
/// connected to whatever member the session names. The id is therefore the
/// whole credential, and a credential nobody has called one ends up in a query
/// string, a screenshot, an access log, a browser history or a referrer header
/// sent to a third party's asset.
///
/// A host carries it accordingly: only in the reply the member alone can see,
/// to the page in a fragment or a request body and never in a query string,
/// never into a log or an error report. This module holds up its own end by
/// never putting it in a ``ProofRefusal``, which is the value a host writes
/// down (see ``RefusalHandle``).
///
/// A hundred and twenty eight bits from the system's own generator, derived
/// from nothing: not the subject, not the address, not the clock. A counter or
/// a short token lets somebody walk the live sessions and submit against one
/// they did not open.
public struct VerificationSessionIdentifier: Sendable, Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// Characters in an id: a hundred and twenty eight bits as hexadecimal.
    public static let characterCount: Int = 32

    /// The characters an id may be made of.
    ///
    /// Written out rather than asked of `Character.isHexDigit`, which is
    /// true for the fullwidth compatibility forms as well: a string of
    /// thirty two fullwidth digits passes a count and a hex-digit test, is
    /// ninety six UTF-8 bytes, and is not an id this type ever minted.
    private static let alphabet: Set<Character> = Set("0123456789abcdef")

    /// The id itself, lowercase hexadecimal.
    public let value: String

    public var description: String { value }

    // MARK: - Initializers

    /// An id handed back from somewhere, or refused.
    ///
    /// - Parameter value: Thirty two lowercase hexadecimal characters.
    /// - Throws: ``VerifyError/malformedSessionIdentifier(characterCount:)``
    ///   when it is anything else.
    public init(_ value: String) throws {
        guard
            value.count == Self.characterCount,
            value.allSatisfy(Self.alphabet.contains)
        else {
            throw VerifyError.malformedSessionIdentifier(characterCount: value.count)
        }
        self.value = value
    }

    /// An id this type has just built, whose shape is this file's own doing.
    private init(unchecked value: String) {
        self.value = value
    }

    // MARK: - Public Methods

    /// A fresh id nothing can be worked back from.
    ///
    /// Deliberately takes no parameter. A mint with an argument is eventually
    /// handed something convenient by somebody making a test deterministic,
    /// and the whole property goes with nothing failing.
    public static func mint() -> VerificationSessionIdentifier {
        var generator = SystemRandomNumberGenerator()
        let high = UInt64.random(in: UInt64.min...UInt64.max, using: &generator)
        let low = UInt64.random(in: UInt64.min...UInt64.max, using: &generator)
        return VerificationSessionIdentifier(unchecked: hexadecimal(high) + hexadecimal(low))
    }

    // MARK: - Private Methods

    /// Sixty four bits as sixteen lowercase hexadecimal characters, padded.
    private static func hexadecimal(_ value: UInt64) -> String {
        let digits = String(value, radix: 16, uppercase: false)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
