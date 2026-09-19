import Foundation
import Testing

@testable import Surface

/// A catalogue Discord would refuse fails here, not at a boot (`ADOPT-2`).
@Suite("Command validator")
struct CommandValidatorTests {

    // MARK: - The one that cost a deployment

    @Test("A required option after an optional one is refused before anything is registered (ADOPT-2)")
    func requiredAfterOptionalIsRefused() {
        // The shape from the project this was ported from, kept as a fixture
        // although the command itself is not shipped. An optional selector
        // was added above two required options, Discord answered 400 to the
        // whole bulk registration, the boot that was waiting on it failed,
        // and the supervisor restarted it into the same failure. The release
        // was rolled back over these three lines.
        let draw = CommandDefinition(
            name: "raffle",
            description: "Draw a winner",
            options: [
                CommandOption(
                    type: .subcommand,
                    name: "draw",
                    description: "Pick a winner",
                    options: [
                        CommandOption(
                            type: .string,
                            name: "collection",
                            description: "Which collection",
                            required: false
                        ),
                        CommandOption(
                            type: .boolean,
                            name: "confirm",
                            description: "Really do it",
                            required: true
                        ),
                        CommandOption(
                            type: .integer,
                            name: "asa",
                            description: "Which asset",
                            required: true
                        )
                    ]
                )
            ]
        )

        let issues = CommandValidator.issues(in: [draw])
        let offending = issues.filter { $0.rule == .requiredAfterOptional }
        #expect(offending.count == 2)
        #expect(offending.map(\.path) == ["raffle.draw.confirm", "raffle.draw.asa"])
        #expect(throws: CommandCatalogInvalid.self) {
            try CommandValidator.validate([draw])
        }
    }

    @Test("The same options in a legal order pass")
    func legalOrderPasses() throws {
        let fixed = CommandDefinition(
            name: "raffle",
            description: "Draw a winner",
            options: [
                CommandOption(
                    type: .subcommand,
                    name: "draw",
                    description: "Pick a winner",
                    options: [
                        CommandOption(type: .boolean, name: "confirm", description: "Really", required: true),
                        CommandOption(type: .integer, name: "asa", description: "Asset", required: true),
                        CommandOption(type: .string, name: "collection", description: "Which", required: false)
                    ]
                )
            ]
        )
        try CommandValidator.validate([fixed])
    }

    // MARK: - Lengths, counted the way Discord counts

    @Test("A description is measured in UTF-16 code units, not characters")
    func descriptionLengthIsUTF16() {
        // Fifty-one thumbs-up is fifty-one `Character`s and a hundred and two
        // UTF-16 code units. A `String.count` check passes it; Discord does
        // not, and a registration it refuses fails the boot.
        let description = String(repeating: "\u{1F44D}", count: 51)
        #expect(description.count == 51)
        #expect(description.utf16.count == 102)

        let command = CommandDefinition(name: "ping", description: description)
        let issues = CommandValidator.issues(in: [command])
        #expect(issues.contains { $0.rule == .tooLong })
    }

    @Test("An empty name or description is refused")
    func emptyIsRefused() {
        let issues = CommandValidator.issues(in: [CommandDefinition(name: "", description: "")])
        #expect(issues.filter { $0.rule == .empty }.count == 2)
    }

    @Test("A name outside Discord's character set is refused")
    func charactersAreChecked() {
        let issues = CommandValidator.issues(in: [
            CommandDefinition(name: "Ping", description: "Upper case is refused"),
            CommandDefinition(name: "pi ng", description: "A space is refused")
        ])
        #expect(issues.filter { $0.rule == .badCharacters }.count == 2)
    }

    @Test("Two options of one name, and two commands of one name, are both refused")
    func duplicatesAreRefused() {
        let command = CommandDefinition(
            name: "dup",
            description: "Two of the same",
            options: [
                CommandOption(type: .string, name: "same", description: "One"),
                CommandOption(type: .string, name: "same", description: "Two")
            ]
        )
        let issues = CommandValidator.issues(in: [command, command])
        #expect(issues.contains { $0.rule == .duplicateName })
        #expect(issues.contains { $0.rule == .duplicateCommand })
    }

    @Test("More than twenty-five options in one list is refused")
    func optionCapIsEnforced() {
        let options = (1...26).map {
            CommandOption(type: .string, name: "opt\($0)", description: "Option \($0)")
        }
        let issues = CommandValidator.issues(in: [
            CommandDefinition(name: "many", description: "Too many", options: options)
        ])
        #expect(issues.contains { $0.rule == .tooManyOptions })
    }

    @Test("A plain option beside a subcommand is refused, and a group inside a group is too")
    func nestingIsChecked() {
        let mixed = CommandDefinition(
            name: "mixed",
            description: "A subcommand and a plain option",
            options: [
                CommandOption(type: .subcommand, name: "sub", description: "A subcommand"),
                CommandOption(type: .string, name: "loose", description: "A plain option")
            ]
        )
        let nested = CommandDefinition(
            name: "nested",
            description: "A group inside a group",
            options: [
                CommandOption(
                    type: .subcommandGroup,
                    name: "outer",
                    description: "Outer",
                    options: [
                        CommandOption(type: .subcommandGroup, name: "inner", description: "Inner")
                    ]
                )
            ]
        )
        let issues = CommandValidator.issues(in: [mixed, nested])
        #expect(issues.contains { $0.rule == .mixedContainers })
        #expect(issues.contains { $0.rule == .badNesting })
    }

    @Test("A subcommand inside a subcommand is refused here rather than by Discord")
    func subcommandsDoNotNest() {
        // Discord has two levels: a group holds subcommands and a subcommand
        // holds values. Both entries here are containers, so the mixed check
        // says nothing, and the depth check looks only at groups, so this
        // shape used to reach registration and fail the boot with a 400.
        let deep = CommandDefinition(
            name: "deep",
            description: "A subcommand inside a subcommand",
            options: [
                CommandOption(
                    type: .subcommand,
                    name: "outer",
                    description: "Outer",
                    options: [
                        CommandOption(type: .subcommand, name: "inner", description: "Inner")
                    ]
                )
            ]
        )
        let issues = CommandValidator.issues(in: [deep])
        #expect(issues.contains { $0.rule == .badNesting })

        // The legal shape it must not be confused with: a subcommand one
        // level down inside a group.
        let legal = CommandDefinition(
            name: "legal",
            description: "A group holding a subcommand",
            options: [
                CommandOption(
                    type: .subcommandGroup,
                    name: "outer",
                    description: "Outer",
                    options: [
                        CommandOption(type: .subcommand, name: "inner", description: "Inner")
                    ]
                )
            ]
        )
        #expect(CommandValidator.issues(in: [legal]).isEmpty)
    }

    @Test("The shipped catalogue passes its own validator")
    func shippedCatalogIsLegal() throws {
        try CommandValidator.validate(Fixture.catalog().commands)
    }
}
