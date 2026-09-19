@preconcurrency import Foundation

/// What kind of thing arrived.
public enum InteractionKind: String, Sendable, Equatable, CaseIterable, Codable {

    /// Somebody ran a slash command.
    case command

    /// Somebody is still typing one.
    case autocomplete

    /// Somebody pressed a button or picked from a menu.
    case component
}

/// A value an option arrived with.
public enum OptionValue: Sendable, Equatable, Codable {

    /// Text, or an id the chat client sent as text.
    case string(String)

    /// A whole number.
    case integer(Int)

    /// True or false.
    case boolean(Bool)

    /// A number with a fractional part.
    case number(Double)

    // MARK: - Public Methods

    /// The text, when it is text.
    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// The whole number, when it is one.
    public var integerValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    /// The flag, when it is one.
    public var booleanValue: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }
}

/// One inbound interaction, as a value with no chat-client type on it.
///
/// Everything the router and the handlers need, and nothing they do not: no
/// client to call, no gateway to reach, no token to spend. A handler takes one
/// of these and answers with a ``SurfaceReply``, which is why every handler in
/// this package is tested by constructing a struct.
public struct InteractionRequest: Sendable, Equatable {

    // MARK: - Properties

    /// What kind of thing arrived.
    public let kind: InteractionKind

    /// The command's name, for a command or an autocomplete.
    public let commandName: String?

    /// The subcommand group and subcommand, outermost first, when there is
    /// one.
    public let subcommandPath: [String]

    /// The options, by name, already flattened past any subcommand.
    public let options: [String: OptionValue]

    /// Which option the member is typing in, for an autocomplete.
    public let focusedOption: String?

    /// The component's id, for a component.
    public let customId: String?

    /// The server this arrived from, or nil when it arrived from a direct
    /// message.
    public let guildId: String?

    /// Who ran it, as a plain string.
    public let userExternalId: String

    /// Every role they hold, as plain strings.
    public let memberRoleIds: [String]

    /// The permissions Discord computed for them here, or nil.
    public let permissionBits: UInt64?

    /// Discord's id for this interaction.
    public let interactionId: String

    /// The token that answers it. Good for fifteen minutes.
    public let token: String

    /// When it arrived, which is when the fifteen minutes start.
    public let receivedAt: Date

    // MARK: - Initializers

    /// - Parameters:
    ///   - kind: What kind of thing arrived.
    ///   - commandName: The command's name.
    ///   - subcommandPath: The subcommand group and subcommand.
    ///   - options: The options, by name.
    ///   - focusedOption: Which option is being typed in.
    ///   - customId: The component's id.
    ///   - guildId: The server it arrived from.
    ///   - userExternalId: Who ran it.
    ///   - memberRoleIds: Every role they hold.
    ///   - permissionBits: The permissions Discord computed for them.
    ///   - interactionId: Discord's id for this interaction.
    ///   - token: The token that answers it.
    ///   - receivedAt: When it arrived.
    public init(
        kind: InteractionKind,
        commandName: String? = nil,
        subcommandPath: [String] = [],
        options: [String: OptionValue] = [:],
        focusedOption: String? = nil,
        customId: String? = nil,
        guildId: String?,
        userExternalId: String,
        memberRoleIds: [String] = [],
        permissionBits: UInt64? = nil,
        interactionId: String = "",
        token: String = "",
        receivedAt: Date = Date()
    ) {
        self.kind = kind
        self.commandName = commandName
        self.subcommandPath = subcommandPath
        self.options = options
        self.focusedOption = focusedOption
        self.customId = customId
        self.guildId = guildId
        self.userExternalId = userExternalId
        self.memberRoleIds = memberRoleIds
        self.permissionBits = permissionBits
        self.interactionId = interactionId
        self.token = token
        self.receivedAt = receivedAt
    }

    // MARK: - Public Methods

    /// The text an option arrived with, trimmed, or nil when it is absent or
    /// blank.
    ///
    /// Blank counts as absent for the same reason it does everywhere else in
    /// this package: somebody who submits an empty box meant to leave it out.
    ///
    /// - Parameter name: The option's name.
    public func string(_ name: String) -> String? {
        guard let text = options[name]?.stringValue else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether a flag option arrived true.
    /// - Parameter name: The option's name.
    public func flag(_ name: String) -> Bool {
        options[name]?.booleanValue ?? false
    }

    /// The invoker's id, checked.
    public var userId: DiscordUserId? {
        DiscordUserId(externalId: userExternalId)
    }
}
