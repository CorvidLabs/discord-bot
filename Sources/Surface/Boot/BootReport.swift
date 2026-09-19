import Foundation
import Gating

/// What this bot prints when it starts.
///
/// `ADOPT-9` is the want: when it starts, an operator can read what it made of
/// their settings, not only that it started. `ADOPT-11` adds the two things
/// they cannot work out for themselves: the exact Discord permissions this
/// process needs, in Discord's own words, and the invite that grants them.
///
/// Every line is built from loaded configuration. Nothing in here is a
/// constant from another project, which is checked by a test that greps the
/// report (`ADOPT-1.c`).
public enum BootReport: Sendable {

    // MARK: - Public Methods

    /// The invite that grants exactly the permissions this process needs.
    ///
    /// Nil when the application id is unknown, in which case ``lines(configuration:catalog:gating:)``
    /// names the variable to set rather than printing a URL with a hole in it.
    ///
    /// - Parameter applicationId: The application this bot is.
    public static func inviteURL(applicationId: String) -> String {
        "https://discord.com/oauth2/authorize?client_id=\(applicationId)"
            + "&permissions=\(DiscordPermission.required)"
            + "&scope=bot%20applications.commands"
    }

    /// Every managed role that sits above this bot's own, highest first.
    ///
    /// Discord will not let a bot grant or revoke a role above its own in the
    /// list, and it fails **quietly**: the API call succeeds for the roles it
    /// can do and the member is simply never promoted. `ADOPT-11.a` is that
    /// this is named at startup rather than after a member notices.
    ///
    /// - Parameters:
    ///   - managedRoleIds: Every role this bot is configured to manage.
    ///   - positions: Each role's position in the server's list, by id.
    ///   - botHighestPosition: The highest position this bot itself holds.
    ///   - names: Each role's name, by id, for the message.
    public static func rolesAboveBot(
        managedRoleIds: Set<String>,
        positions: [String: Int],
        botHighestPosition: Int,
        names: [String: String] = [:]
    ) -> [String] {
        managedRoleIds
            .compactMap { id -> (String, Int)? in
                guard let position = positions[id], position >= botHighestPosition else { return nil }
                return (names[id] ?? id, position)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// What to print when a configured role sits at or above this bot's own,
    /// or nil when none does.
    ///
    /// - Parameter roles: What ``rolesAboveBot(managedRoleIds:positions:botHighestPosition:names:)``
    ///   found, highest first.
    public static func rolesAboveBotLine(_ roles: [String]) -> String? {
        guard !roles.isEmpty else { return nil }
        return "\(roles.count) configured role(s) sit at or above this bot's own, so Discord will "
            + "refuse to grant them and will not say so: \(roles.joined(separator: ", ")). Move "
            + "this bot's own role above them in the server's role list."
    }

    /// Every role this configuration governs.
    ///
    /// The managed set of a decision where every fact is read, because that
    /// is exactly the set of roles this bot grants and revokes. Derived from
    /// ``Gating/RoleRules`` rather than listed again here, so a rung, a
    /// collection or a pool added later cannot be left out of the check.
    ///
    /// - Parameter gating: What the ladder, the collections and the pools
    ///   came out as.
    public static func managedRoleIds(_ gating: GatingConfiguration) -> Set<String> {
        RoleRules.decide(
            configuration: gating,
            holdings: MemberHoldings.unlinked(memberId: "", configuration: gating),
            currentRoleIds: []
        ).managed
    }

    /// The whole report, one line at a time.
    ///
    /// - Parameters:
    ///   - configuration: What this target loaded.
    ///   - catalog: What will be registered.
    ///   - gating: What the ladder, the collections and the pools came out as.
    public static func lines(
        configuration: SurfaceConfiguration,
        catalog: CommandCatalog,
        gating: GatingConfiguration
    ) -> [String] {
        var lines: [String] = []
        lines.append("Serving one server: \(configuration.guildId)")
        lines.append("Listening on \(configuration.listenAddress): health \(configuration.healthPort), "
            + "verification callback \(configuration.callbackPort)")
        lines.append("Token: \(gating.token.displayName) (\(gating.token.symbol)), asset "
            + "\(gating.token.assetId), \(gating.token.decimals) decimals")
        lines.append(rungLine(gating))
        lines.append(collectionLine(gating))
        lines.append(poolLine(gating))
        lines.append("Verified role: \(gating.verifiedRoleId ?? "none set, so nobody is given one")")
        lines.append("Commands to register: \(catalog.names.map { "/\($0)" }.joined(separator: " "))")
        lines.append(verificationLine(configuration))
        lines.append("Operator role beyond Administrator: "
            + (configuration.adminRoleId ?? "none set, so Administrator only"))
        lines.append("Permissions this bot needs, in Discord's words: "
            + DiscordPermission.requiredNames.joined(separator: ", "))
        if let applicationId = configuration.applicationId {
            lines.append("Invite that grants exactly those: \(inviteURL(applicationId: applicationId))")
        } else {
            lines.append("Invite URL not printed: set \(SurfaceConfiguration.applicationKey) to your "
                + "application id and it will be.")
        }
        return lines
    }

    // MARK: - Private Methods

    /// The ladder as it loaded, so a rung a typo dropped reads as missing
    /// before a sweep acts on it (`ADOPT-9.a`).
    private static func rungLine(_ gating: GatingConfiguration) -> String {
        guard !gating.ladder.rungs.isEmpty else {
            return "Ladder: no rungs configured, so no tier role is granted"
        }
        let rungs = gating.ladder.rungs.map { rung in
            let role = gating.roleId(for: rung) ?? "no role"
            let minimum = GatingFormatting.amount(rung.minimumBaseUnits, decimals: gating.token.decimals)
            return "\(rung.name) >= \(minimum) (\(role))"
        }
        return "Ladder, \(gating.ladder.rungs.count) rung(s): " + rungs.joined(separator: "; ")
    }

    /// The collections as they loaded.
    private static func collectionLine(_ gating: GatingConfiguration) -> String {
        guard !gating.collections.collections.isEmpty else {
            return "Collections: none configured"
        }
        return "Collections, \(gating.collections.collections.count): "
            + gating.collections.collections.map(\.id).joined(separator: ", ")
    }

    /// The pools as they loaded.
    private static func poolLine(_ gating: GatingConfiguration) -> String {
        guard !gating.pools.pools.isEmpty else {
            return "Pools: none counted toward a tier"
        }
        return "Pools, \(gating.pools.pools.count): " + gating.pools.pools.map(\.id).joined(separator: ", ")
    }

    /// What verification came out as.
    private static func verificationLine(_ configuration: SurfaceConfiguration) -> String {
        guard let portal = configuration.portalURL else {
            return "Verification: off, because \(SurfaceConfiguration.portalURLKey) is not set. "
                + "Nothing in your server offers to prove an account."
        }
        return "Verification: \(portal), one shared secret, probed at startup"
    }
}
