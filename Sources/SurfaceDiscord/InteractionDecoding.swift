import DiscordBM
@preconcurrency import Foundation
import Surface

/// Turns what the gateway delivered into a value the rest of this package can
/// take.
///
/// **This is where a snowflake stops.** Everything below reads a `String`,
/// which is what lets the router, the handlers and the store be exercised
/// with no gateway. `Store` does not even declare a chat client, so a
/// snowflake cannot reach it: the module is missing, not merely discouraged.
public enum InteractionDecoding: Sendable {

    // MARK: - Public Methods

    /// One interaction as a request, or nil when it carries nothing to route.
    ///
    /// - Parameters:
    ///   - interaction: What arrived.
    ///   - receivedAt: When it arrived, which is when the fifteen minutes
    ///     start.
    public static func request(
        from interaction: Interaction,
        receivedAt: Date = Date()
    ) -> InteractionRequest? {
        guard let externalId = (interaction.member?.user?.id ?? interaction.user?.id)?.rawValue else {
            return nil
        }
        let guildId = interaction.guild_id?.rawValue
        let roleIds = interaction.member?.roles.map(\.rawValue) ?? []
        // `StringBitField` is the permission set as one number, which is what
        // `CommandAuth` reads. Converted here so no bit field type appears in
        // a signature below this file.
        let permissions = interaction.member?.permissions.map { UInt64($0.rawValue) }

        switch interaction.data {
        case .applicationCommand(let command):
            let flattened = flatten(command.options ?? [])
            return InteractionRequest(
                kind: interaction.type == .applicationCommandAutocomplete ? .autocomplete : .command,
                commandName: command.name,
                subcommandPath: flattened.path,
                options: flattened.values,
                focusedOption: flattened.focused,
                guildId: guildId,
                userExternalId: externalId,
                memberRoleIds: roleIds,
                permissionBits: permissions,
                interactionId: interaction.id.rawValue,
                token: interaction.token,
                receivedAt: receivedAt
            )

        case .messageComponent(let component):
            return InteractionRequest(
                kind: .component,
                customId: component.custom_id,
                guildId: guildId,
                userExternalId: externalId,
                memberRoleIds: roleIds,
                permissionBits: permissions,
                interactionId: interaction.id.rawValue,
                token: interaction.token,
                receivedAt: receivedAt
            )

        default:
            // A modal submit or something Discord adds later. Not routed and
            // not pretended to be: the router answers everything it is given,
            // and giving it something it cannot name would make it lie.
            return nil
        }
    }

    // MARK: - Private Methods

    /// Options, with any subcommand path taken off the front.
    ///
    /// A subcommand arrives as an option containing the real options, one or
    /// two levels deep. Flattening here means a handler reads
    /// `request.string("account")` whether or not the command has
    /// subcommands, and the path it came down is kept separately.
    private static func flatten(
        _ options: [Interaction.ApplicationCommand.Option]
    ) -> (path: [String], values: [String: OptionValue], focused: String?) {
        var path: [String] = []
        var current = options

        while let first = current.first, first.type == .subCommand || first.type == .subCommandGroup {
            path.append(first.name)
            current = first.options ?? []
        }

        var values: [String: OptionValue] = [:]
        var focused: String?
        for option in current {
            if option.focused == true {
                focused = option.name
            }
            guard let value = option.value else { continue }
            values[option.name] = self.value(from: value)
        }
        return (path, values, focused)
    }

    /// One option value.
    private static func value(from value: StringIntDoubleBool) -> OptionValue {
        switch value {
        case .string(let text):
            return .string(text)
        case .int(let number):
            return .integer(number)
        case .double(let number):
            return .number(number)
        case .bool(let flag):
            return .boolean(flag)
        }
    }
}
