import Foundation
import Runtime
import Surface

/// What the chat surface reads from the operator's settings, and how it
/// describes itself to the composition root.
///
/// **The composition root does not name these variables.** It cannot: a
/// target that never links a chat library also never learns what a server or
/// a snowflake is, which is the rule a grep over `Sources/Runtime` enforces
/// (`BUILD-4`). So the part that reads them is the part that describes them,
/// and ``Runtime/ChatGateway/settingsEntries`` is how the description travels
/// back for the startup report and the audit.
///
/// The names come from ``Surface/SurfaceConfiguration``'s own constants
/// rather than being retyped, because a retyped name is how a rename becomes
/// a variable an operator sets and nothing reads.
public struct ChatSurfaceSettings: Sendable, Equatable {

    // MARK: - Properties

    /// The bot's token. A secret, and the switch: unset means this process
    /// has no chat surface and runs exactly as a build without one.
    public let botToken: String

    /// The one server this process serves.
    public let serverId: String

    /// The application this bot is, for anything that needs it.
    public let applicationId: String?

    /// An extra role that may run operator commands, or nil.
    public let operatorRoleId: String?

    /// What the operator calls this bot on its cards.
    public let botName: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - botToken: The bot's token.
    ///   - serverId: The one server this process serves.
    ///   - applicationId: The application this bot is.
    ///   - operatorRoleId: An extra operator role.
    ///   - botName: What the operator calls this bot.
    public init(
        botToken: String,
        serverId: String,
        applicationId: String? = nil,
        operatorRoleId: String? = nil,
        botName: String = ""
    ) {
        self.botToken = botToken
        self.serverId = serverId
        self.applicationId = applicationId
        self.operatorRoleId = operatorRoleId
        self.botName = botName
    }

    // MARK: - Public Methods

    /// Every variable this surface reads, described the way the composition
    /// root's catalogue describes its own.
    ///
    /// Handed back through the seam so the startup report lists them, the
    /// audit counts them as read, and a variable under the chat prefix stops
    /// being refused as belonging to a part that does not exist. A build
    /// without this target supplies none of these, and the refusal is exactly
    /// as it was.
    public static let settingsEntries: [SettingsEntry] = [
        SettingsEntry(
            SurfaceConfiguration.tokenKey,
            purpose: "This bot's own token. Unset means no chat surface: the process starts, "
                + "serves its health endpoint and identifies to nothing.",
            secrecy: .secret,
            group: .chat
        ),
        SettingsEntry(
            SurfaceConfiguration.guildKey,
            purpose: "The one server this process serves. Required once a token is set, because "
                + "commands are registered to one server rather than to every server this bot "
                + "is in.",
            group: .chat
        ),
        SettingsEntry(
            SurfaceConfiguration.applicationKey,
            purpose: "The application this bot is. Read out of the token when unset.",
            group: .chat
        ),
        SettingsEntry(
            SurfaceConfiguration.adminRoleKey,
            purpose: "An extra role allowed to run operator commands, beyond the server's own "
                + "administrators.",
            group: .chat
        ),
        SettingsEntry(
            SurfaceConfiguration.botNameKey,
            purpose: "What this bot calls itself on a card. A word that names nothing when "
                + "unset, never another project's name.",
            group: .chat
        )
    ]

    /// The variables that mean an operator wants a chat surface at all.
    ///
    /// ``Surface/SurfaceConfiguration/botNameKey`` is deliberately not one of
    /// them. It is what the bot calls itself on a card, it is worth setting
    /// on a build that has no chat surface, and refusing a boot because
    /// somebody named their bot would be this layer refusing something no
    /// other layer minds.
    public static let switchKeys: [String] = [
        SurfaceConfiguration.tokenKey,
        SurfaceConfiguration.guildKey,
        SurfaceConfiguration.applicationKey,
        SurfaceConfiguration.adminRoleKey
    ]

    /// Reads them, or nil when this operator wants no chat surface.
    ///
    /// Nil only when **nothing** under the chat prefix is set. A server id
    /// with no token is not "no chat surface", it is a half-finished one, and
    /// answering nil to it would start a process that never appears in the
    /// server and says nothing about why (`SEE-1.a`).
    ///
    /// A value still holding an example placeholder refuses here too, with
    /// the variable named and the value quoted. This loader is the one
    /// `swift run bot` uses, and the check it was missing is the one
    /// ``Surface/SurfaceConfiguration`` has always made: without it a copied
    /// example file builds a bot, identifies with junk and shows the operator
    /// a chat service's refusal instead of the one sentence naming the
    /// variable to change (`ADOPT-2`, `RUN-9.a`).
    ///
    /// - Parameter settings: The one snapshot of the machine's variables.
    /// - Throws: ``Runtime/BootFailure`` naming the variable to change.
    public static func load(_ settings: [String: String]) throws -> ChatSurfaceSettings? {
        let read: (String) throws -> String? = { key in
            guard let raw = settings[key] else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard !PlaceholderValues.looksUnfinished(trimmed) else {
                // Quoted on purpose, and safe to quote: the value is one of a
                // short list of example values, so nothing an operator would
                // mind seeing in a container log can reach this line.
                throw BootFailure(
                    variable: key,
                    summary: "\(key) still holds the example value '\(trimmed)'.",
                    remedy: "Replace it with yours. Starting on a placeholder points this bot "
                        + "at nothing at all.",
                    code: .configuration
                )
            }
            return trimmed
        }
        guard try switchKeys.contains(where: { try read($0) != nil }) else { return nil }

        guard let token = try read(SurfaceConfiguration.tokenKey) else {
            throw BootFailure(
                variable: SurfaceConfiguration.tokenKey,
                summary: "Something under the chat prefix is set and \(SurfaceConfiguration.tokenKey) "
                    + "is not, so this process would start and identify to nothing.",
                remedy: "Set it to this bot's own token, or take the other chat variables out.",
                code: .configuration
            )
        }
        guard let serverId = try read(SurfaceConfiguration.guildKey) else {
            throw BootFailure(
                variable: SurfaceConfiguration.guildKey,
                summary: "A token is set and \(SurfaceConfiguration.guildKey) is not.",
                remedy: "This bot serves one server and has to be told which. Copy its id from "
                    + "the server with developer mode on.",
                code: .configuration
            )
        }
        guard DiscordUserId(externalId: serverId) != nil else {
            throw BootFailure(
                variable: SurfaceConfiguration.guildKey,
                summary: "\(SurfaceConfiguration.guildKey) is not an id.",
                remedy: "An id is one to twenty digits, copied from the server with developer "
                    + "mode on.",
                code: .configuration
            )
        }

        return ChatSurfaceSettings(
            botToken: token,
            serverId: serverId,
            applicationId: try read(SurfaceConfiguration.applicationKey)
                ?? SurfaceConfiguration.applicationId(fromToken: token),
            operatorRoleId: try read(SurfaceConfiguration.adminRoleKey),
            botName: try read(SurfaceConfiguration.botNameKey) ?? ""
        )
    }
}
