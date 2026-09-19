@preconcurrency import Foundation

/// One member of the served community, as this instance knows them.
///
/// The directory row, and the only place a key and a chat account id appear
/// together. Delete it and every other mention of the key refers to nobody.
public struct MemberRecord: Sendable, Equatable, Codable, Identifiable {

    // MARK: - Properties

    /// How this instance names them. See ``MemberKey``.
    public let key: MemberKey

    /// Who they are to the chat client, as a plain string.
    ///
    /// A string rather than a snowflake because this target declares no chat
    /// client and must not acquire one. The adapter that knows what a snowflake
    /// is depends on this target, and a dependency cycle is a build failure, so
    /// the direction cannot be reversed later by somebody in a hurry.
    public let externalId: String

    /// When the member first proved anything.
    public let firstSeenAt: Date

    /// The key, so a member can be put in a keyed collection by identity.
    public var id: MemberKey { key }

    // MARK: - Initializers

    /// - Parameters:
    ///   - key: How this instance names them.
    ///   - externalId: Who they are to the chat client.
    ///   - firstSeenAt: When they first proved anything, recorded to the
    ///     second.
    public init(key: MemberKey, externalId: String, firstSeenAt: Date) {
        self.key = key
        self.externalId = externalId
        self.firstSeenAt = StoreDate.whole(firstSeenAt)
    }
}
