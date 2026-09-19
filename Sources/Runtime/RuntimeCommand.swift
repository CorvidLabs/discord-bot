import Foundation

/// What the binary was asked to do.
///
/// Four verbs, parsed by hand. An argument parsing package for four words
/// would be a new pin for a reader of TRUST-1 to weigh, and the usage text
/// below is the whole of the help this needs.
public enum RuntimeCommand: String, Sendable, Equatable, CaseIterable {

    /// Walk the gates, bind, and stay up. The default with no arguments.
    case run

    /// Load the settings, print the report the boot would, and touch
    /// nothing: no socket, no store file, no network.
    case check

    /// Load the operator's own configuration and run the role rules over
    /// members and holdings this invents, printing the decision for each.
    case rehearse

    /// Print the four verbs.
    case help

    // MARK: - Public Methods

    /// What each verb does, one line each.
    public static var usage: [String] {
        [
            "usage: bot [run|check|rehearse|help]",
            "",
            "  run       Walk the boot gates, bind the health endpoint and stay up.",
            "            The default when no argument is given.",
            "  check     Load the settings and print the report a start would, touching",
            "            nothing: no socket, no store file, no network.",
            "  rehearse  Run the role rules over members and holdings this invents, using",
            "            your own ladder, collections and pools. Touches nothing.",
            "  help      This.",
            "",
            "Exit codes: 0 stopped cleanly, 64 usage, 69 something is already here or",
            "cannot be used, 70 internal, 78 the configuration is wrong."
        ]
    }

    /// The verb in `arguments`, or the refusal to print.
    ///
    /// - Parameter arguments: The process arguments **without** the program
    ///   name, so a test does not have to invent one.
    public static func parse(_ arguments: [String]) -> Result<RuntimeCommand, BootFailure> {
        guard let first = arguments.first else { return .success(.run) }
        guard let command = RuntimeCommand(rawValue: first) else {
            return .failure(
                BootFailure(
                    summary: "`\(first)` is not something this takes.",
                    remedy: "It takes run, check, rehearse or help.",
                    code: .usage
                )
            )
        }
        guard arguments.count == 1 else {
            return .failure(
                BootFailure(
                    summary: "`\(command.rawValue)` takes no further arguments, and "
                        + "\(arguments.count - 1) were given.",
                    remedy: "It takes run, check, rehearse or help.",
                    code: .usage
                )
            )
        }
        return .success(command)
    }
}
