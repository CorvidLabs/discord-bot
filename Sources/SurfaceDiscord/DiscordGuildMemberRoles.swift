import DiscordBM
import Foundation
import Surface

/// Reads and writes one member's roles over Discord.
///
/// **A snowflake is made here and nowhere else.** A member and a role are a
/// `String` on both sides of this type: the composition root's seam says so,
/// `Store` does not even declare a chat library, and this is the one place the
/// two vocabularies meet.
///
/// The write sends the **whole** list rather than one role at a time. A member
/// on the fourth rung with a badge and a verified role is six round trips the
/// other way, six chances to be rate limited half way through, and a member
/// left holding three of their six roles.
///
/// **A write that would change nothing is the caller's to skip.** This seam
/// is told exactly what the member should hold, and working that out is a
/// read the caller has already made through ``roleIds(ofMember:)``. Reading
/// again here to compare would spend a request per member per sweep to save
/// one, so the guard belongs where the answer is already in hand.
public struct DiscordGuildMemberRoles: GuildMemberRoles {

    // MARK: - Properties

    /// The one server this process serves.
    public let guildId: String

    /// The chat client.
    private let client: any DiscordClient

    /// What the write says it was for, in the server's audit log.
    private let reason: String

    /// What a write that did not land is reported through.
    private let log: @Sendable (String) -> Void

    // MARK: - Initializers

    /// - Parameters:
    ///   - guildId: The one server this process serves.
    ///   - client: The chat client.
    ///   - reason: What the write says it was for, in the server's audit log.
    ///   - log: What a write that did not land is reported through.
    public init(
        guildId: String,
        client: any DiscordClient,
        reason: String = "Roles follow holdings",
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.guildId = guildId
        self.client = client
        self.reason = reason
        self.log = log
    }

    // MARK: - Public Methods

    public func roleIds(ofMember member: String) async throws -> Set<String> {
        let found = try await client.getGuildMember(
            guildId: GuildSnowflake(guildId),
            userId: UserSnowflake(member)
        ).decode()
        return Set(found.roles.map(\.rawValue))
    }

    public func setRoles(ofMember member: String, to roleIds: Set<String>) async throws {
        try await client.updateGuildMember(
            guildId: GuildSnowflake(guildId),
            userId: UserSnowflake(member),
            reason: reason,
            payload: Payloads.ModifyGuildMember(roles: roleIds.sorted().map { RoleSnowflake($0) })
        ).guardSuccess()

        // Read back, because a `200` here does not mean the list landed:
        // Discord drops an id it does not recognise and says nothing, so one
        // wrong digit in a configured id costs every member that role for
        // ever, the same list is re-sent on every sweep because the member
        // still lacks it, and nothing anywhere says why (`SEE-4`).
        //
        // A read that itself fails is not an incident: it says nothing about
        // what the write did, and reporting every configured id as dropped
        // on a rate limit is the false alarm an operator learns to ignore.
        guard let observed = try? await self.roleIds(ofMember: member) else { return }
        if let line = RoleWriteCheck.incidentLine(
            externalId: member,
            ignored: RoleWriteCheck.silentlyIgnored(wanted: roleIds, observed: observed)
        ) {
            log(line)
        }
    }
}
