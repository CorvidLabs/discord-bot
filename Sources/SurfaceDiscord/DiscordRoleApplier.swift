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
/// The list sent is the managed half of ``Gating/RoleDecision/target`` plus
/// every role the member currently holds that the decision does **not**
/// manage. It is built from a fresh read rather than from the decision alone
/// because every role outside ``Gating/RoleDecision/managed`` has to survive
/// untouched: a badge a moderator handed out by hand is not this bot's to
/// remove (`ROLE-5`), and a rung whose balance nobody could read is not
/// either (`ROLE-1.a`).
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

    // MARK: - Internal Methods

    /// The exact role list one decision has to send, given what the member
    /// holds right now.
    ///
    /// Separated from the client for the same reason
    /// ``Surface/RoleWriteCheck`` is: this is arithmetic, it needs no token
    /// and no server, and the list that goes out is the one thing here worth
    /// pinning with a test.
    ///
    /// **``Gating/RoleDecision/held`` is not part of it.** `held` is every
    /// configured role the decision deliberately left alone because
    /// something needed to decide it was not read, and leaving a role alone
    /// means neither granting nor revoking it. Sending it would turn every
    /// unread fact into a grant: a member whose collection nobody could look
    /// up would receive that collection's badge, which is the exact opposite
    /// of ROLE-1.a. The roles to keep come from the fresh read instead.
    ///
    /// - Parameters:
    ///   - decision: What the rules decided.
    ///   - current: Every role the member holds now, just read.
    internal static func rolesToSend(decision: RoleDecision, current: Set<String>) -> Set<String> {
        // What the rules positively want, which is the managed half of the
        // target, plus everything outside the managed set the member already
        // has. The second half is what keeps a hand-granted badge (ROLE-5)
        // and what keeps a rung whose balance nobody could read (ROLE-1.a).
        decision.target
            .intersection(decision.managed)
            .union(current.subtracting(decision.managed))
            .subtracting(decision.revoked)
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
        // Read again rather than trusting the set the decision was computed
        // against: a moderator may have handed out a badge in between, and
        // that badge has to survive this write.
        let current = try await currentRoleIds(externalId: externalId)
        let wanted = Self.rolesToSend(decision: decision, current: current)

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
