import Foundation

/// `/help`: what this bot can do **in this server**.
///
/// `LEARN-4` is that a member can find out what the bot does from inside
/// Discord without somebody telling them. `LEARN-8` is the harder half: what
/// they are shown is what it can do **here**. A page that answers from what
/// the software shipped with, rather than from what this server is running,
/// is worse than no page: it is confidently wrong, and the member reading it
/// is the one person with no way to tell.
///
/// So the page is generated from ``CommandCatalog``, which is the same list
/// the registration is built from. A command switched off is not registered,
/// so it is not in the catalogue, so it cannot be described here
/// (`LEARN-8.a`). An operator command is left out whatever the reader's
/// permissions, because this is what a member reads.
public struct HelpCommand: CommandHandler {

    // MARK: - Properties

    public let name = CommandCatalog.help

    /// The words and colours this operator set.
    private let chrome: CardChrome

    /// Which parts are switched on.
    private let features: SurfaceFeatures

    // MARK: - Initializers

    /// - Parameters:
    ///   - chrome: The words and colours this operator set.
    ///   - features: Which parts are switched on.
    public init(chrome: CardChrome, features: SurfaceFeatures) {
        self.chrome = chrome
        self.features = features
    }

    // MARK: - Public Methods

    public func handle(_ request: InteractionRequest) async -> SurfaceReply {
        .immediate(VisibleMessage(card: Self.card(chrome: chrome, features: features), isEphemeral: true))
    }

    /// The page itself, as a value a test can read.
    ///
    /// - Parameters:
    ///   - chrome: The words and colours this operator set.
    ///   - features: Which parts are switched on.
    public static func card(chrome: CardChrome, features: SurfaceFeatures) -> SurfaceCard {
        let entries = CommandCatalog.memberEntries(features: features)
        let lines = entries.map { "`/\($0.definition.name)` \u{2013} \($0.definition.description)" }
        let commands = ReplyLimits.joinWithinLimit(lines, limit: ReplyLimits.embedFieldValue)

        var fields: [SurfaceField] = [
            SurfaceField(name: "Commands", value: commands.isEmpty ? "None are switched on here." : commands)
        ]

        if !features.has(.verification) {
            // Said plainly rather than left as an absence, so a member who
            // has heard of /verify elsewhere does not go looking for it here.
            fields.append(SurfaceField(
                name: "Proving an account",
                value: "Switched off in this server, so no command offers it."
            ))
        }

        if !chrome.token.links.isEmpty {
            fields.append(SurfaceField(name: "\(chrome.token.symbol) links", value: chrome.token.linksMarkdown))
        }

        return SurfaceCard(
            title: chrome.botName,
            description: "What this bot can do in this server. Everything here is what is switched "
                + "on right now, not what the software can do elsewhere.",
            fields: fields,
            color: chrome.color,
            footer: "Roles follow what you hold. Nothing here asks for a key or a seed phrase.",
            thumbnailURL: chrome.thumbnailURL
        )
    }
}
