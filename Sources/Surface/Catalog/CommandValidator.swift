import Foundation

/// A rule Discord enforces at registration, named so a failure says which one.
public enum CommandRule: String, Sendable, Equatable, CaseIterable, Codable {

    /// A required option came after an optional one in the same array.
    ///
    /// **The expensive one.** Discord answers `400` to the whole bulk
    /// registration, the boot that was waiting on it fails, and under a
    /// supervisor that restarts the process it fails again. The original paid
    /// for this with a rolled-back deployment, and the fixture that pins it
    /// here is a command shape that is not even shipped.
    case requiredAfterOptional

    /// A name or description was empty.
    case empty

    /// A name or description was longer than Discord allows, counted in
    /// UTF-16 code units.
    case tooLong

    /// A name used something outside Discord's allowed character set.
    case badCharacters

    /// Two options or subcommands in one array had the same name.
    case duplicateName

    /// More than twenty-five entries in one options array.
    case tooManyOptions

    /// A subcommand or a group sat beside a plain option in one array.
    case mixedContainers

    /// A subcommand group held something other than subcommands.
    case badNesting

    /// Two commands in the catalogue had the same name.
    case duplicateCommand
}

/// One thing wrong with a catalogue, and where.
public struct ValidationIssue: Sendable, Equatable, Codable, CustomStringConvertible {

    // MARK: - Properties

    /// Where it is, as a dotted path: `raffle.draw.confirm`.
    public let path: String

    /// Which rule it breaks.
    public let rule: CommandRule

    /// What to change.
    public let detail: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - path: Where it is, as a dotted path.
    ///   - rule: Which rule it breaks.
    ///   - detail: What to change.
    public init(path: String, rule: CommandRule, detail: String) {
        self.path = path
        self.rule = rule
        self.detail = detail
    }

    public var description: String { "\(path): \(rule.rawValue) (\(detail))" }
}

/// Everything wrong with a catalogue, as one error a boot can print.
public struct CommandCatalogInvalid: Error, Equatable, LocalizedError, Sendable {

    // MARK: - Properties

    /// Every issue found, in the order they were found.
    public let issues: [ValidationIssue]

    // MARK: - Initializers

    /// - Parameter issues: Every issue found.
    public init(issues: [ValidationIssue]) {
        self.issues = issues
    }

    // MARK: - Public Methods

    public var errorDescription: String? {
        "These commands would be refused by Discord, so none was registered:\n"
            + issues.map { "  - \($0.description)" }.joined(separator: "\n")
    }
}

/// Refuses, offline, a catalogue Discord would refuse.
///
/// **This runs before anything is sent and before the gateway is touched.**
/// The failure it exists for is not subtle and not rare: a registration
/// Discord rejects fails the boot, and under any supervisor that restarts the
/// process the boot fails again, for ever, over an options array somebody
/// reordered. Catching it in a unit test costs a millisecond. Catching it in
/// production costs a rollback.
///
/// Every rule below is one Discord actually enforces. Where a length is
/// involved it is counted in UTF-16 code units, through ``ReplyLimits``,
/// because that is the unit the other end counts in.
public enum CommandValidator: Sendable {

    // MARK: - Properties

    /// Longest a command or option name may be.
    public static let maximumNameLength = 32

    /// Longest a description may be.
    public static let maximumDescriptionLength = 100

    /// Most options, subcommands or groups in one array.
    public static let maximumOptionsPerArray = 25

    /// Most choices on one option.
    public static let maximumChoices = 25

    // MARK: - Public Methods

    /// Every issue in this catalogue, empty when there is none.
    ///
    /// - Parameter commands: The commands about to be registered.
    public static func issues(in commands: [CommandDefinition]) -> [ValidationIssue] {
        var found: [ValidationIssue] = []
        var seen: Set<String> = []

        for command in commands {
            found += nameIssues(command.name, path: command.name)
            found += descriptionIssues(command.description, path: command.name)
            if seen.contains(command.name.lowercased()) {
                found.append(ValidationIssue(
                    path: command.name,
                    rule: .duplicateCommand,
                    detail: "two commands are registered under this name"
                ))
            }
            seen.insert(command.name.lowercased())
            found += arrayIssues(command.options, path: command.name, depth: 0, parent: nil)
        }
        return found
    }

    /// Nothing, or a refusal naming every rule broken.
    ///
    /// - Parameter commands: The commands about to be registered.
    /// - Throws: ``CommandCatalogInvalid`` when anything is wrong.
    public static func validate(_ commands: [CommandDefinition]) throws {
        let found = issues(in: commands)
        guard found.isEmpty else { throw CommandCatalogInvalid(issues: found) }
    }

    // MARK: - Private Methods

    /// Every issue in one options array, and in everything nested under it.
    private static func arrayIssues(
        _ options: [CommandOption],
        path: String,
        depth: Int,
        parent: CommandOptionType?
    ) -> [ValidationIssue] {
        guard !options.isEmpty else { return [] }
        var found: [ValidationIssue] = []

        if options.count > maximumOptionsPerArray {
            found.append(ValidationIssue(
                path: path,
                rule: .tooManyOptions,
                detail: "\(options.count) entries, and Discord allows \(maximumOptionsPerArray)"
            ))
        }

        var seen: Set<String> = []
        var sawOptional = false
        let holdsContainers = options.contains { $0.type.isContainer }

        for option in options {
            let here = "\(path).\(option.name)"
            found += nameIssues(option.name, path: here)
            found += descriptionIssues(option.description, path: here)

            if seen.contains(option.name.lowercased()) {
                found.append(ValidationIssue(
                    path: here,
                    rule: .duplicateName,
                    detail: "two entries in this list share this name"
                ))
            }
            seen.insert(option.name.lowercased())

            if holdsContainers, !option.type.isContainer {
                found.append(ValidationIssue(
                    path: here,
                    rule: .mixedContainers,
                    detail: "a plain option cannot sit beside a subcommand; put it inside one"
                ))
            }

            // Two levels is all Discord has: a group holds subcommands and a
            // subcommand holds values. A subcommand inside a subcommand is
            // refused at registration, and depth alone cannot tell it apart
            // from the legal subcommand inside a group, so the parent is
            // carried down.
            if option.type == .subcommand, parent == .subcommand {
                found.append(ValidationIssue(
                    path: here,
                    rule: .badNesting,
                    detail: "a subcommand cannot be nested inside another subcommand"
                ))
            }

            if option.type == .subcommandGroup {
                if depth > 0 {
                    found.append(ValidationIssue(
                        path: here,
                        rule: .badNesting,
                        detail: "a subcommand group cannot be nested inside another"
                    ))
                }
                for nested in option.options where nested.type != .subcommand {
                    found.append(ValidationIssue(
                        path: "\(here).\(nested.name)",
                        rule: .badNesting,
                        detail: "a subcommand group holds subcommands and nothing else"
                    ))
                }
            }

            if option.choices.count > maximumChoices {
                found.append(ValidationIssue(
                    path: here,
                    rule: .tooManyOptions,
                    detail: "\(option.choices.count) choices, and Discord allows \(maximumChoices)"
                ))
            }

            // The rule that cost a deployment. A container is never required,
            // so it takes no part in the ordering; only value options do.
            if !option.type.isContainer {
                if option.required, sawOptional {
                    found.append(ValidationIssue(
                        path: here,
                        rule: .requiredAfterOptional,
                        detail: "a required option cannot follow an optional one; move it above them"
                    ))
                }
                if !option.required {
                    sawOptional = true
                }
            }

            found += arrayIssues(option.options, path: here, depth: depth + 1, parent: option.type)
        }
        return found
    }

    /// Every issue with one name.
    ///
    /// Discord's character set for a command or option name: lowercase
    /// letters, digits, `-` and `_`. It also accepts letters outside ASCII,
    /// which this refuses rather than tries to model, because a name this
    /// package generates is written in a source file by somebody who can
    /// choose an ASCII one, and an approximate charset check that passes
    /// something Discord then refuses is worse than none.
    private static func nameIssues(_ name: String, path: String) -> [ValidationIssue] {
        var found: [ValidationIssue] = []
        if name.isEmpty {
            found.append(ValidationIssue(path: path, rule: .empty, detail: "a name cannot be empty"))
            return found
        }
        if !ReplyLimits.fits(name, within: maximumNameLength) {
            found.append(ValidationIssue(
                path: path,
                rule: .tooLong,
                detail: "\(ReplyLimits.length(name)) characters, and Discord allows \(maximumNameLength)"
            ))
        }
        let allowed = name.allSatisfy { character in
            character.isASCII && (character.isLowercase || character.isNumber || character == "-" || character == "_")
        }
        if !allowed {
            found.append(ValidationIssue(
                path: path,
                rule: .badCharacters,
                detail: "use lowercase ASCII letters, digits, '-' and '_' only"
            ))
        }
        return found
    }

    /// Every issue with one description.
    private static func descriptionIssues(_ description: String, path: String) -> [ValidationIssue] {
        var found: [ValidationIssue] = []
        if description.isEmpty {
            found.append(ValidationIssue(
                path: path,
                rule: .empty,
                detail: "a description cannot be empty"
            ))
        }
        if !ReplyLimits.fits(description, within: maximumDescriptionLength) {
            found.append(ValidationIssue(
                path: path,
                rule: .tooLong,
                detail: "\(ReplyLimits.length(description)) characters, and Discord allows "
                    + "\(maximumDescriptionLength), counted in UTF-16 code units"
            ))
        }
        return found
    }
}
