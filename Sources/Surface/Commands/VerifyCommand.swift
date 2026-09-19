@preconcurrency import Foundation
import Gating
import Store

/// `/verify`: prove an account is yours.
///
/// `VERIFY-1` is the whole point and it is a promise about what this command
/// does **not** do: it never asks for a key, never asks for a seed phrase and
/// never asks anybody to paste a signature into Discord. It hands the member
/// a link, and the proving happens in a browser where a wallet can be reached.
/// This is also the one moment a stranger decides whether the whole thing is
/// trustworthy, so if it feels like a phishing flow it has already failed.
///
/// `VERIFY-6` is why there is a disclosure before the button rather than a
/// button alone: before signing anything a member can read what this server's
/// bot will keep about them, who runs it, and which of it other members will
/// see. Two of those three are facts about this code and are written here.
/// The third cannot be known here and is required configuration, because a
/// shipped sentence about who runs the server would be a sentence about
/// somebody else's server.
///
/// Ephemeral throughout. A verification link is a link to a session bound to
/// one member; posting it where the channel can see it is handing it to
/// whoever clicks first.
public struct VerifyCommand: CommandHandler {

    // MARK: - Properties

    public let name = CommandCatalog.verify

    /// The one server this process serves.
    private let guildId: String

    /// Where members and accounts are kept.
    private let store: any MemberDirectory & AccountStore

    /// The other half.
    private let verification: any VerificationClient

    /// The words and colours this operator set.
    private let chrome: CardChrome

    /// Who runs this, and what members see.
    private let disclosure: DisclosureSettings

    // MARK: - Initializers

    /// - Parameters:
    ///   - guildId: The one server this process serves.
    ///   - store: Where members and accounts are kept.
    ///   - verification: The other half.
    ///   - chrome: The words and colours this operator set.
    ///   - disclosure: Who runs this, and what members see.
    public init(
        guildId: String,
        store: any MemberDirectory & AccountStore,
        verification: any VerificationClient,
        chrome: CardChrome,
        disclosure: DisclosureSettings
    ) {
        self.guildId = guildId
        self.store = store
        self.verification = verification
        self.chrome = chrome
        self.disclosure = disclosure
    }

    // MARK: - Public Methods

    public func handle(_ request: InteractionRequest) async -> SurfaceReply {
        guard request.userId != nil else {
            return .refuse("Discord did not say who ran that, so nothing was done.")
        }

        var existing: [AccountRecord] = []
        if let member = try? await store.member(externalId: request.userExternalId) {
            existing = (try? await store.accounts(memberKey: member.key)) ?? []
        }

        let session: VerificationSession
        do {
            session = try await verification.createSession(
                externalId: request.userExternalId,
                guildId: guildId
            )
        } catch {
            return .refuse(
                "A verification link could not be created just now, so nothing about your account "
                    + "has changed. Try again in a minute, and tell an operator if it keeps happening."
            )
        }

        return .followUp(VisibleMessage(
            card: Self.disclosureCard(
                chrome: chrome,
                disclosure: disclosure,
                existingAccounts: existing.map(\.address),
                url: session.url,
                expiresAt: session.expiresAt
            ),
            isEphemeral: true
        ))
    }

    /// What a member reads before they sign.
    ///
    /// - Parameters:
    ///   - chrome: The words and colours this operator set.
    ///   - disclosure: Who runs this, and what members see.
    ///   - existingAccounts: Accounts they have already proved.
    ///   - url: Where they go to sign.
    ///   - expiresAt: When the link stops working, or nil when the other
    ///     half did not say.
    public static func disclosureCard(
        chrome: CardChrome,
        disclosure: DisclosureSettings,
        existingAccounts: [String],
        url: String,
        expiresAt: Date? = nil
    ) -> SurfaceCard {
        let adding = !existingAccounts.isEmpty

        var fields: [SurfaceField] = [
            SurfaceField(
                name: "Who is asking",
                value: disclosure.contact.map { "\(disclosure.operatorName) (\($0))" } ?? disclosure.operatorName
            ),
            SurfaceField(
                name: "What this server keeps",
                value: """
                    The account you prove, and what it was last read as holding in \
                    \(chrome.token.symbol). Nothing else about your wallet, and nothing at all \
                    about any other server.
                    """
            ),
            SurfaceField(name: "What other members see", value: disclosure.visibilityNote),
            SurfaceField(
                name: "Leaving",
                value: "`/unlink` removes an account. Removing your last one forgets you here."
            )
        ]

        if adding {
            let listed = ReplyLimits.joinWithinLimit(
                existingAccounts.map { "`\(shorten($0))`" },
                limit: ReplyLimits.embedFieldValue,
                separator: ", "
            )
            fields.insert(
                SurfaceField(name: "Already proved (\(existingAccounts.count))", value: listed),
                at: 0
            )
        }

        var description = """
            You will connect a wallet and sign a message. **Nothing is sent, nothing moves, and \
            this bot never sees a key or a seed phrase.** Walk away part way through and nothing \
            about you has changed.
            """
        // A member who comes back to a stale link gets an error from the
        // other half and no idea why, and the one thing that would have told
        // them was decoded and thrown away. As Discord's own markup rather
        // than a fixed number of minutes: the link's life is the portal's to
        // decide, and this renders in each reader's own clock.
        if let expiresAt {
            description += "\n\nThis link expires \(Self.relativeTime(expiresAt))."
        }

        return SurfaceCard(
            title: adding ? "Add another account" : "Prove an account is yours",
            description: description,
            fields: fields,
            color: chrome.color,
            footer: "Ownership is proved by a signature. The link is yours alone; do not share it.",
            thumbnailURL: chrome.thumbnailURL,
            buttons: [.link(label: adding ? "Add an account" : "Prove an account", url: url)]
        )
    }

    // MARK: - Private Methods

    /// A moment as Discord draws it, in the reader's own clock.
    private static func relativeTime(_ date: Date) -> String {
        "<t:\(Int(date.timeIntervalSince1970)):R>"
    }

    /// An account shortened enough to recognise and not to read out.
    private static func shorten(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))\u{2026}\(address.suffix(4))"
    }
}
