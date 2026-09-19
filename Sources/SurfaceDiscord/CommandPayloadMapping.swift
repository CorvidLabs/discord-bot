import DiscordBM
import Foundation
import Surface

/// Turns this package's command values into the payloads Discord accepts.
///
/// One direction, one place. The validator that decides whether a catalogue
/// is legal lives in `Surface` and imports nothing, so it runs in a unit test;
/// this file only translates, so a mistake here is a mapping bug rather than
/// a rule nobody can test.
public enum CommandPayloadMapping: Sendable {

    // MARK: - Public Methods

    /// One command, as Discord's create payload.
    /// - Parameter definition: The command.
    public static func payload(for definition: CommandDefinition) -> Payloads.ApplicationCommandCreate {
        Payloads.ApplicationCommandCreate(
            name: definition.name,
            description: definition.description,
            options: definition.options.isEmpty ? nil : definition.options.map(option(for:)),
            default_member_permissions: definition.defaultMemberPermissions.map(permissions(from:)),
            // This instance serves one server, so nothing it registers should
            // work in a direct message: a command answered outside the guild
            // has no member, no roles and no server to read (HOST-10).
            dm_permission: false
        )
    }

    /// The whole catalogue, as create payloads.
    /// - Parameter catalog: The validated catalogue.
    public static func payloads(for catalog: CommandCatalog) -> [Payloads.ApplicationCommandCreate] {
        catalog.commands.map(payload(for:))
    }

    // MARK: - Private Methods

    /// One option, and everything nested under it.
    private static func option(for option: CommandOption) -> ApplicationCommand.Option {
        ApplicationCommand.Option(
            type: kind(for: option.type),
            name: option.name,
            description: option.description,
            // A container is never `required`, and sending `false` on one is
            // accepted but meaningless. Nil keeps the payload the shape the
            // documentation describes.
            required: option.type.isContainer ? nil : option.required,
            choices: option.choices.isEmpty
                ? nil
                : option.choices.map { .init(name: $0.name, value: .string($0.value)) },
            options: option.options.isEmpty ? nil : option.options.map(self.option(for:)),
            autocomplete: option.autocomplete ? true : nil
        )
    }

    /// Our option kind as Discord's.
    private static func kind(for type: CommandOptionType) -> ApplicationCommand.Option.Kind {
        switch type {
        case .subcommand:
            return .subCommand
        case .subcommandGroup:
            return .subCommandGroup
        case .string:
            return .string
        case .integer:
            return .integer
        case .boolean:
            return .boolean
        case .user:
            return .user
        case .channel:
            return .channel
        case .role:
            return .role
        case .number:
            return .number
        }
    }

    /// A bit set as the permissions Discord's payload wants.
    ///
    /// Only the bits this package names are mapped. An unknown bit is dropped
    /// rather than guessed at, because `default_member_permissions` is a hint
    /// that hides a command and is never the authorisation: ``Surface/CommandAuth``
    /// is, and it reads the bits itself.
    private static func permissions(from bits: UInt64) -> [Permission] {
        var permissions: [Permission] = []
        if bits & DiscordPermission.administrator != 0 { permissions.append(.administrator) }
        if bits & DiscordPermission.manageRoles != 0 { permissions.append(.manageRoles) }
        if bits & DiscordPermission.sendMessages != 0 { permissions.append(.sendMessages) }
        if bits & DiscordPermission.embedLinks != 0 { permissions.append(.embedLinks) }
        if bits & DiscordPermission.attachFiles != 0 { permissions.append(.attachFiles) }
        return permissions
    }
}
