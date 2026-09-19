import Foundation

/// A part of this bot an operator either switched on or did not.
public enum SurfaceFeature: String, Sendable, Equatable, CaseIterable, Codable {

    /// A member can prove an account. Needs somewhere to send them.
    case verification

    /// The bot holds a key and can move value.
    case spending

    /// The card table is open.
    case games
}

/// Which parts this instance is running.
///
/// **A part switched off costs nothing and offers nothing.** `ADOPT-10.b` is
/// the sharp end of that: an operator who never wants the bot to send anything
/// should find nothing in their server that offers to, rather than something
/// that offers and then fails. So the catalogue is built from this, and a
/// command that needs a part the operator left out is never registered, which
/// means Discord never shows it and `/help` never mentions it (`LEARN-8.a`).
public struct SurfaceFeatures: Sendable, Equatable {

    // MARK: - Properties

    /// The parts that are on.
    public let enabled: Set<SurfaceFeature>

    // MARK: - Initializers

    /// - Parameter enabled: The parts that are on.
    public init(enabled: Set<SurfaceFeature>) {
        self.enabled = enabled
    }

    /// A community that wants roles and nothing else (`SPEND-6.c`, `PLAY-9`).
    public static let rolesOnly = SurfaceFeatures(enabled: [.verification])

    // MARK: - Public Methods

    /// Whether this part is on.
    /// - Parameter feature: The part.
    public func has(_ feature: SurfaceFeature) -> Bool {
        enabled.contains(feature)
    }
}

/// One command, and what has to be switched on for it to exist.
public struct CatalogEntry: Sendable, Equatable {

    // MARK: - Properties

    /// The command.
    public let definition: CommandDefinition

    /// Every part that must be on. Empty means always.
    public let requires: Set<SurfaceFeature>

    /// Whether `/help` lists it to an ordinary member.
    public let isMemberFacing: Bool

    // MARK: - Initializers

    /// - Parameters:
    ///   - definition: The command.
    ///   - requires: Every part that must be on.
    ///   - isMemberFacing: Whether `/help` lists it.
    public init(
        definition: CommandDefinition,
        requires: Set<SurfaceFeature> = [],
        isMemberFacing: Bool = true
    ) {
        self.definition = definition
        self.requires = requires
        self.isMemberFacing = isMemberFacing
    }
}

/// Every slash command this process will register, as a value.
///
/// Registration maps this. Tests assert on this. Nothing anywhere else decides
/// that a command exists, which is the property that makes `/help` honest:
/// the page is generated from the same list the registration is, so a command
/// that is not registered here cannot be described there (`LEARN-8`).
///
/// **Four commands, and adding a fifth is a different change.** The ones that
/// are absent are absent on purpose and each waits for work of its own.
public struct CommandCatalog: Sendable, Equatable {

    // MARK: - Properties

    /// `/ping`.
    public static let ping = "ping"

    /// `/help`.
    public static let help = "help"

    /// `/verify`.
    public static let verify = "verify"

    /// `/unlink`.
    public static let unlink = "unlink"

    /// The option on `/unlink` naming which account to remove.
    public static let unlinkAccountOption = "account"

    /// The commands, in the order they were built.
    public let commands: [CommandDefinition]

    // MARK: - Initializers

    /// - Parameter commands: The commands.
    public init(commands: [CommandDefinition]) {
        self.commands = commands
    }

    // MARK: - Public Methods

    /// Every command this package knows how to build, with what each needs.
    ///
    /// The whole list, before anything is switched off. Exposed so a test can
    /// see what was filtered out rather than only what survived.
    public static func allEntries() -> [CatalogEntry] {
        [
            CatalogEntry(
                definition: CommandDefinition(
                    name: ping,
                    description: "Check whether the bot is awake",
                    acknowledge: .immediate
                )
            ),
            CatalogEntry(
                definition: CommandDefinition(
                    name: help,
                    description: "What this bot can do in this server",
                    acknowledge: .immediate
                )
            ),
            CatalogEntry(
                definition: CommandDefinition(
                    name: verify,
                    description: "Prove an account is yours and get the roles it earns",
                    acknowledge: .deferEphemeral
                ),
                requires: [.verification]
            ),
            CatalogEntry(
                definition: CommandDefinition(
                    name: unlink,
                    description: "Remove an account you proved, or list the ones you have",
                    options: [
                        CommandOption(
                            type: .string,
                            name: unlinkAccountOption,
                            description: "The account to remove. Leave it out to see the ones you have",
                            required: false
                        )
                    ],
                    acknowledge: .deferEphemeral
                ),
                requires: [.verification]
            )
        ]
    }

    /// The commands to register, given what is switched on.
    ///
    /// Validated on the way out, so a catalogue Discord would refuse is a
    /// thrown error at boot rather than a `400` from the registration call
    /// (`ADOPT-2`).
    ///
    /// - Parameter features: Which parts this instance is running.
    /// - Throws: ``CommandCatalogInvalid`` when a definition breaks a rule
    ///   Discord enforces.
    public static func build(features: SurfaceFeatures) throws -> CommandCatalog {
        let entries = allEntries().filter { entry in
            entry.requires.allSatisfy(features.has)
        }
        let commands = entries.map(\.definition)
        try CommandValidator.validate(commands)
        return CommandCatalog(commands: commands)
    }

    /// The entries `/help` lists, given what is switched on.
    ///
    /// Operator commands are left out whatever the reader's permissions,
    /// because `/help` is what a member reads and a member cannot run one.
    ///
    /// - Parameter features: Which parts this instance is running.
    public static func memberEntries(features: SurfaceFeatures) -> [CatalogEntry] {
        allEntries().filter { entry in
            entry.isMemberFacing
                && !entry.definition.isOperatorOnly
                && entry.requires.allSatisfy(features.has)
        }
    }

    /// The command of this name, or nil.
    /// - Parameter name: The name a member typed.
    public func command(named name: String) -> CommandDefinition? {
        commands.first { $0.name == name }
    }

    /// The names, in order.
    public var names: [String] { commands.map(\.name) }
}
