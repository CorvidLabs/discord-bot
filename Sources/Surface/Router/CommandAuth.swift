import Foundation

/// Discord's permission bits, as the few this package actually reads.
///
/// A `UInt64` rather than a library type, so the authorisation rule below is a
/// function from numbers and strings and can be tested without a gateway,
/// a guild or a token.
public enum DiscordPermission: Sendable {

    /// Administrator. Bit 3.
    public static let administrator: UInt64 = 1 << 3

    /// Manage Roles. Bit 28. The one that fails quietly when a managed role
    /// sits above the bot's own.
    public static let manageRoles: UInt64 = 1 << 28

    /// Send Messages. Bit 11.
    public static let sendMessages: UInt64 = 1 << 11

    /// Embed Links. Bit 14.
    public static let embedLinks: UInt64 = 1 << 14

    /// Attach Files. Bit 15.
    public static let attachFiles: UInt64 = 1 << 15

    /// Every permission this process needs, as one bit set, for the invite.
    public static let required: UInt64 = manageRoles | sendMessages | embedLinks | attachFiles

    /// The same permissions in the words Discord's own interface uses for
    /// them, in the order above, so an operator can find each one in the list
    /// rather than translate from a bit (`ADOPT-11.b`).
    public static let requiredNames: [String] = [
        "Manage Roles",
        "Send Messages",
        "Embed Links",
        "Attach Files"
    ]
}

/// Who may run an operator command.
///
/// **Registration metadata is not authorisation.** `default_member_permissions`
/// hides a command from ordinary members, and a guild administrator can later
/// grant that same command to `@everyone` in the Integrations screen without
/// anybody here hearing about it. So the handler checks again, every time,
/// which is `SPEND-6.a`: every surface that can spend refuses anybody the
/// operator has not made an operator, however they found it.
///
/// A pure function over a permission bit set and role id strings. No snowflake
/// type appears in the signature, so the whole rule is exercised by a test
/// that constructs two numbers and an array.
public enum CommandAuth: Sendable {

    // MARK: - Public Methods

    /// Whether this member may run an operator command.
    ///
    /// Granted when the interaction's computed permissions include
    /// Administrator, or when the member holds the one extra role the operator
    /// named. Nothing else grants it, and there is no built-in operator.
    ///
    /// - Parameters:
    ///   - permissionBits: The permissions Discord computed for this member in
    ///     this channel, or nil when the interaction carried none.
    ///   - memberRoleIds: Every role the member holds, as plain strings.
    ///   - adminRoleId: The extra operator role, or nil when the operator
    ///     named none.
    public static func isOperator(
        permissionBits: UInt64?,
        memberRoleIds: [String],
        adminRoleId: String?
    ) -> Bool {
        if let permissionBits, permissionBits & DiscordPermission.administrator != 0 {
            return true
        }
        // An empty string is what an unset environment variable reaches this
        // far as. Matching on it would make every member with no roles an
        // operator the moment somebody wrote `DISCORD_ADMIN_ROLE_ID=`.
        if let adminRoleId, !adminRoleId.isEmpty, memberRoleIds.contains(adminRoleId) {
            return true
        }
        return false
    }
}
