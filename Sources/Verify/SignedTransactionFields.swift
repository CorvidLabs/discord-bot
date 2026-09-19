import Foundation

/// A field a proof must carry, named so a member is told which one is missing.
public enum RequiredTransactionField: String, Sendable, Equatable, CaseIterable {

    /// What kind of transaction this is.
    case type

    /// Who is paying.
    case sender

    /// Who is being paid.
    case receiver

    /// The bytes the challenge is carried in.
    case note

    /// The name this field goes by on the wire.
    public var wireName: String {
        switch self {
        case .type: return "type"
        case .sender: return "snd"
        case .receiver: return "rcv"
        case .note: return "note"
        }
    }
}

/// A field whose presence is a refusal, whether or not the signature is good.
///
/// The bot never submits what it is handed, so it cannot itself be the
/// attacker. Refusing is about what it would otherwise bless: a page that
/// builds the proof keeps the signed blob, and a blob this module has
/// certified as proof of ownership is a blob somebody can hold up as one.
/// None of these may be in something the bot calls a proof.
///
/// **The wire name for a rekey is `rekey`.** It is `rekeyTo` on the
/// dependency's transaction type and that is not the name the dependency's
/// canonical encoder puts on the wire. Written literally as `rekeyto`, the
/// refusal would match a key that never arrives, the reader would skip the
/// real one as an unknown field, and every rekeying proof would be accepted
/// with a perfectly valid signature. The fixtures in the suite take these
/// names from the encoder's own output rather than from a hand written
/// string, so the name in the test and the name on the wire cannot drift
/// apart.
public enum ForbiddenTransactionField: String, Sendable, Hashable, CaseIterable {

    /// Hands the account's spending authority to another key.
    case rekey

    /// Empties the account into somebody else on the way past.
    case close

    /// Empties an asset holding into somebody else on the way past.
    case assetClose

    /// Blocks the member's own transactions for the validity window.
    case lease

    /// Says the proof was one leg of an atomic group approved wholesale.
    case group

    /// The name this field goes by on the wire.
    public var wireName: String {
        switch self {
        case .rekey: return "rekey"
        case .close: return "close"
        case .assetClose: return "aclose"
        case .lease: return "lx"
        case .group: return "grp"
        }
    }

    /// The field a wire name belongs to, or nil for a name that is not one of
    /// these.
    ///
    /// - Parameter wireName: The key as it arrived.
    public init?(wireName: String) {
        guard let match = Self.allCases.first(where: { $0.wireName == wireName }) else { return nil }
        self = match
    }
}

/// What a submitted transaction turned out to say.
///
/// Everything is optional because absent is a real answer, and for two of them
/// the real answer is zero: Algorand's canonical encoding omits a field
/// holding its zero value, so a correctly formed zero amount, zero fee payment
/// carries neither `amt` nor `fee`. Requiring either key refuses every
/// correctly formed proof, which is the single easiest thing here to get
/// wrong.
public struct SignedTransactionFields: Sendable, Equatable {

    // MARK: - Properties

    /// The transaction type tag, such as `pay`.
    public let type: String?

    /// The sender's raw address bytes.
    public let sender: Data?

    /// The receiver's raw address bytes.
    public let receiver: Data?

    /// The amount, or nil when the key was absent.
    public let amount: UInt64?

    /// The fee, or nil when the key was absent.
    public let fee: UInt64?

    /// The note, which is where a challenge travels.
    public let note: Data?

    /// Which forbidden fields were present, in wire order.
    public let forbiddenFields: [ForbiddenTransactionField]

    /// The amount, reading an absent key as zero.
    public var amountOrZero: UInt64 { amount ?? 0 }

    /// The fee, reading an absent key as zero.
    ///
    /// **Zero, never unknown and never unbounded.** Under an equality with
    /// zero both readings of a missing key end in a refusal, so a reader that
    /// treats the key as unknown looks correct. Under a bound they part
    /// company: a missing key read as unknown is an accepted proof whose fee
    /// nobody checked.
    public var feeOrZero: UInt64 { fee ?? 0 }

    // MARK: - Initializers

    /// - Parameters:
    ///   - type: The transaction type tag.
    ///   - sender: The sender's raw address bytes.
    ///   - receiver: The receiver's raw address bytes.
    ///   - amount: The amount, or nil when the key was absent.
    ///   - fee: The fee, or nil when the key was absent.
    ///   - note: The note.
    ///   - forbiddenFields: Which forbidden fields were present.
    public init(
        type: String?,
        sender: Data?,
        receiver: Data?,
        amount: UInt64?,
        fee: UInt64?,
        note: Data?,
        forbiddenFields: [ForbiddenTransactionField]
    ) {
        self.type = type
        self.sender = sender
        self.receiver = receiver
        self.amount = amount
        self.fee = fee
        self.note = note
        self.forbiddenFields = forbiddenFields
    }
}
