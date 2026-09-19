import DiscordBM
import Foundation
import Gating
import Surface

/// Applies a decision to a member in one Discord call.
///
/// **One call, not one per role.** A member on the fourth rung with a badge
/// and a verified role is six round trips the other way, six chances to be
/// rate limited half way through, and a member left holding three of their
/// six roles. Discord's modify-guild-member endpoint takes the whole role
/// list, so the decision goes out as one list and either lands or does not.
///
/// The list sent is the member's **current** roles, minus everything the
/// decision revoked, plus everything it granted. It is built that way rather
/// than from the decision alone because every role outside
/// ``Gating/RoleDecision/managed`` has to survive untouched: a badge a
/// moderator handed out by hand is not this bot's to remove (`ROLE-5`).
public struct DiscordRoleApplier: RoleApplier {

    // MARK: - Properties

    /// The one server this process serves.
    public let guildId: String

    /// The chat client.
    private let client: any DiscordClient

    /// What a message is reported through.
    private let log: @Sendable (String) -> Void

    // MARK: - Initializers

    /// - Parameters:
    ///   - guildId: The one server this process serves.
    ///   - client: The chat client.
    ///   - log: What a message is reported through.
    public init(
        guildId: String,
        client: any DiscordClient,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.guildId = guildId
        self.client = client
        self.log = log
    }

    // MARK: - Public Methods

    public func currentRoleIds(externalId: String) async throws -> Set<String> {
        let member = try await client.getGuildMember(
            guildId: GuildSnowflake(guildId),
            userId: UserSnowflake(externalId)
        ).decode()
        return Set(member.roles.map(\.rawValue))
    }

    public func apply(_ decision: RoleDecision, externalId: String) async throws {
        var wanted = decision.held.union(decision.granted)
        // Everything outside the managed set the member already has. The
        // decision does not carry it, because the rules deliberately know
        // nothing about roles nobody configured.
        let current = try await currentRoleIds(externalId: externalId)
        wanted.formUnion(current.subtracting(decision.managed))
        wanted.subtract(decision.revoked)

        guard wanted != current else { return }

        try await client.updateGuildMember(
            guildId: GuildSnowflake(guildId),
            userId: UserSnowflake(externalId),
            reason: "Roles follow holdings",
            payload: Payloads.ModifyGuildMember(roles: wanted.sorted().map { RoleSnowflake($0) })
        ).guardSuccess()

        // Read back, because a `200` here does not mean the list landed:
        // Discord drops an id it does not recognise and says nothing. The
        // read is one more request per member whose roles actually changed,
        // which is the price of ever finding out about a mistyped role id.
        let observed = (try? await currentRoleIds(externalId: externalId)) ?? wanted
        if let line = RoleWriteCheck.incidentLine(
            externalId: externalId,
            ignored: RoleWriteCheck.silentlyIgnored(wanted: wanted, observed: observed)
        ) {
            log(line)
        }
    }
}
