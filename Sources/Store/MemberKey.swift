@preconcurrency import Foundation

/// How one instance names a member to itself.
///
/// **It is minted, not derived.** A hundred and twenty eight fresh random bits,
/// drawn when the member first proves anything, from nothing about them: not
/// their chat account id, not their address, not a hash of either. Every layer
/// below the chat boundary carries this and only this, so the ledger, the
/// caches and the games hold an identifier that came from a random number
/// generator rather than from a person.
///
/// That is what lets two promises hold at once. The payout ledger has to keep
/// who was already paid this epoch, or a resumed run pays them again. Somebody
/// who leaves has to be forgotten. With a derived pseudonym those fight, and
/// the usual answers are an HMAC with a key destroyed on a timer, or a
/// redaction that breaks the guard it was protecting. With a minted key there
/// is nothing to fight about: the directory row is the only thing that ever
/// connected the key to a person, deleting it is the forgetting, and every
/// surviving mention refers to nobody. No salt to seize, no hash to invert, no
/// key-destruction discipline for somebody to forget in a hurry.
///
/// A member who is forgotten and comes back is minted a **new** key, so the
/// ledger cannot be used to join their two lives together. Inside one open
/// epoch that in principle offers a second payment, and what stops it is not
/// the key. The line that paid them records, beside the key, the account it
/// paid and **every** holding that person had at the time, on every account of
/// theirs, so a returning member is skipped on the holding whichever wallet
/// they come back on. What is left over is honest rather than hidden: somebody
/// forgotten in the middle of an unfinished epoch who returns holding
/// something nobody was paid for is a new person to the ledger, because there
/// is deliberately nothing kept that could say otherwise.
public struct MemberKey: Sendable, Hashable, Codable, CustomStringConvertible {

    // MARK: - Properties

    /// Characters in a key: a hundred and twenty eight bits as hexadecimal.
    public static let characterCount = 32

    /// The key itself, lowercase hexadecimal.
    public let value: String

    // MARK: - Initializers

    /// A key read back from a store, or refused.
    ///
    /// - Parameter value: Thirty two lowercase hexadecimal characters.
    /// - Throws: ``StoreError/unreadableRow(row:reason:)`` when it is anything
    ///   else. A malformed key is a corrupt row, and a corrupt row throws.
    public init(_ value: String) throws {
        guard
            value.count == Self.characterCount,
            value.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        else {
            throw StoreError.unreadableRow(
                row: "member key",
                reason: "expected \(Self.characterCount) lowercase hexadecimal characters"
            )
        }
        self.value = value
    }

    /// A key this type has just built, whose shape is this file's own doing.
    ///
    /// Private, so the only way in from outside is the checked initialiser
    /// above. It exists so minting does not have to either re-check its own
    /// output or stop the process over a failure it cannot have.
    private init(unchecked value: String) {
        self.value = value
    }

    // MARK: - Public Methods

    /// A key nothing can be worked back from.
    ///
    /// Two draws of sixty four bits from the system generator. Deliberately not
    /// seedable and deliberately not derived from any argument: a mint that
    /// took a parameter would eventually be handed the member's chat id by
    /// somebody making a test deterministic, and the whole property would be
    /// gone with nothing failing.
    public static func mint() -> MemberKey {
        var generator = SystemRandomNumberGenerator()
        let high = UInt64.random(in: UInt64.min...UInt64.max, using: &generator)
        let low = UInt64.random(in: UInt64.min...UInt64.max, using: &generator)
        // The alphabet and the width are this file's own, so there is nothing
        // here to validate and nothing to refuse.
        return MemberKey(unchecked: Self.hexadecimal(high) + Self.hexadecimal(low))
    }

    public var description: String { value }

    /// One string, not an object wrapping one.
    ///
    /// Hand written rather than synthesised so the shape check runs on the way
    /// in. A synthesised decode would accept whatever the column happened to
    /// hold, and a malformed key that decodes is a key that reaches the ledger
    /// and matches nothing there.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    // MARK: - Private Methods

    /// Sixty four bits as sixteen lowercase hexadecimal characters, padded.
    ///
    /// Padded so every key is the same width, which is what lets a column be
    /// compared and ordered without a reader wondering whether a short one is a
    /// different kind of thing.
    private static func hexadecimal(_ value: UInt64) -> String {
        let digits = String(value, radix: 16, uppercase: false)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
