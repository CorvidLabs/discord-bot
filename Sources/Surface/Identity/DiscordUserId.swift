import Foundation

/// A chat account id, checked, on its way to becoming a plain string.
///
/// **This is the boundary, and it only goes one way.** Below it a member is a
/// `String` and nothing knows what a snowflake is: `Store` declares no chat
/// client, so `import DiscordBM` there is a missing module rather than a
/// review comment, and because the adapter depends on `Store` and SwiftPM
/// refuses a cycle, the direction cannot be reversed later by somebody in a
/// hurry.
///
/// What it buys is `VERIFY-4`: what a member proved in one community stays in
/// that community. A ``Store/MemberKey`` is minted rather than derived from
/// anything about the person, so two instances of this bot hold identifiers
/// with nothing in common, and the only row that ever connected a key to a
/// person is the directory row that forgetting them deletes.
public struct DiscordUserId: Sendable, Hashable, Codable, CustomStringConvertible {

    // MARK: - Properties

    /// The widest a Discord snowflake gets, written out in decimal.
    public static let maximumDigits = 20

    /// The id as digits.
    public let externalId: String

    // MARK: - Initializers

    /// An id, or nil when it is not one.
    ///
    /// Between one and twenty ASCII digits. Checked rather than trusted
    /// because this arrives from a webhook body as well as from the gateway,
    /// and an id from a webhook is a stranger's string until it has been
    /// looked at.
    ///
    /// - Parameter externalId: The candidate.
    public init?(externalId: String) {
        let bytes = externalId.utf8
        guard
            (1...Self.maximumDigits).contains(bytes.count),
            bytes.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") })
        else { return nil }
        self.externalId = externalId
    }

    // MARK: - Public Methods

    /// The markup that renders as a mention of this person.
    public var mention: String { "<@\(externalId)>" }

    public var description: String { externalId }
}
