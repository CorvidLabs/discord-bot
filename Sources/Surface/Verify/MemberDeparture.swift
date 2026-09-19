@preconcurrency import Foundation
import Store

/// Somebody left the server.
///
/// `VERIFY-7` is that leaving takes everything with it: the accounts, what was
/// cached about what they hold, their record in the games, the timezone they
/// typed in once. Leaving is the loudest possible statement of "I want out",
/// and a member who has to also remember to run `/unlink` on the way out has
/// not been forgotten, they have been made to ask twice.
///
/// The forgetting itself is ``Store/MemberDirectory/forget(memberKey:)``, in
/// one transaction, because half a member is a member the next sweep still
/// acts on.
public struct MemberDeparture: Sendable {

    // MARK: - Properties

    /// The one server this process serves.
    public let servedGuildId: String

    /// Where members are kept.
    private let store: any MemberDirectory

    // MARK: - Initializers

    /// - Parameters:
    ///   - servedGuildId: The one server this process serves.
    ///   - store: Where members are kept.
    public init(servedGuildId: String, store: any MemberDirectory) {
        self.servedGuildId = servedGuildId
        self.store = store
    }

    // MARK: - Public Methods

    /// Forgets this member, if they are ours and are on record.
    ///
    /// - Parameters:
    ///   - externalId: Who left.
    ///   - guildId: Which server they left.
    /// - Returns: What was cleared, or nil when nothing was.
    @discardableResult
    public func handle(externalId: String, guildId: String) async throws -> ForgetOutcome? {
        // A leave event from another server is another community's business.
        guard guildId == servedGuildId else { return nil }
        guard DiscordUserId(externalId: externalId) != nil else { return nil }
        guard let member = try await store.member(externalId: externalId) else { return nil }
        return try await store.forget(memberKey: member.key)
    }
}
