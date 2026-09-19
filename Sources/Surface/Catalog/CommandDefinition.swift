import Foundation

/// The kind of thing a slash-command option holds.
///
/// Discord's own numbering, because the adapter maps straight onto it and a
/// second numbering would be a second thing to get wrong.
public enum CommandOptionType: Int, Sendable, Equatable, CaseIterable, Codable {

    /// A group of subcommands.
    case subcommandGroup = 2

    /// A subcommand.
    case subcommand = 1

    /// Text.
    case string = 3

    /// A whole number.
    case integer = 4

    /// True or false.
    case boolean = 5

    /// A member of the server.
    case user = 6

    /// A channel.
    case channel = 7

    /// A role.
    case role = 8

    /// A number with a fractional part.
    case number = 10

    // MARK: - Public Methods

    /// Whether this kind carries nested options rather than a value.
    public var isContainer: Bool {
        self == .subcommand || self == .subcommandGroup
    }
}

/// One fixed value an option offers.
public struct CommandChoice: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// What the member reads.
    public let name: String

    /// What the handler receives.
    public let value: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - name: What the member reads.
    ///   - value: What the handler receives.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// One option on a command, a subcommand, or a subcommand group.
public struct CommandOption: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// What kind of thing it holds.
    public let type: CommandOptionType

    /// Its name, lowercase.
    public let name: String

    /// What it is for, as the member reads it.
    public let description: String

    /// Whether the member must supply it.
    ///
    /// **A required option must come before every optional one in the same
    /// array.** Discord answers `400` to a registration that breaks this, and
    /// a registration that fails takes the boot with it, so this is the field
    /// that turns a typo into a crash loop. ``CommandValidator`` refuses it
    /// before anything is sent.
    public let required: Bool

    /// Nested options, for a subcommand or a group.
    public let options: [CommandOption]

    /// Fixed values, when the member picks rather than types.
    public let choices: [CommandChoice]

    /// Whether the handler is asked for suggestions as the member types.
    public let autocomplete: Bool

    // MARK: - Initializers

    /// - Parameters:
    ///   - type: What kind of thing it holds.
    ///   - name: Its name, lowercase.
    ///   - description: What it is for.
    ///   - required: Whether the member must supply it.
    ///   - options: Nested options, for a subcommand or a group.
    ///   - choices: Fixed values.
    ///   - autocomplete: Whether suggestions are offered as they type.
    public init(
        type: CommandOptionType,
        name: String,
        description: String,
        required: Bool = false,
        options: [CommandOption] = [],
        choices: [CommandChoice] = [],
        autocomplete: Bool = false
    ) {
        self.type = type
        self.name = name
        self.description = description
        self.required = required
        self.options = options
        self.choices = choices
        self.autocomplete = autocomplete
    }
}

/// One slash command, as a value this package owns.
///
/// Ours rather than the chat library's, so the catalogue can be asserted on,
/// validated and printed with nothing imported and no socket opened. The
/// adapter maps this into whatever the library wants at the one moment
/// registration happens.
public struct CommandDefinition: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// The name a member types after the slash.
    public let name: String

    /// What it does, as the member reads it in the picker.
    public let description: String

    /// Its options, subcommands or groups.
    public let options: [CommandOption]

    /// The permission bits Discord uses to hide it from ordinary members, or
    /// nil to show it to everybody.
    ///
    /// A hint, never the authorisation. See ``CommandAuth``.
    public let defaultMemberPermissions: UInt64?

    /// When the handler must have answered by.
    public let acknowledge: AcknowledgePolicy

    /// Whether this is an operator command, whatever Discord was told.
    public let isOperatorOnly: Bool

    // MARK: - Initializers

    /// - Parameters:
    ///   - name: The name a member types.
    ///   - description: What it does.
    ///   - options: Its options, subcommands or groups.
    ///   - defaultMemberPermissions: Bits Discord uses to hide it.
    ///   - acknowledge: When the handler must have answered by.
    ///   - isOperatorOnly: Whether the handler refuses everybody but an
    ///     operator.
    public init(
        name: String,
        description: String,
        options: [CommandOption] = [],
        defaultMemberPermissions: UInt64? = nil,
        acknowledge: AcknowledgePolicy = .immediate,
        isOperatorOnly: Bool = false
    ) {
        self.name = name
        self.description = description
        self.options = options
        self.defaultMemberPermissions = defaultMemberPermissions
        self.acknowledge = acknowledge
        self.isOperatorOnly = isOperatorOnly
    }
}
