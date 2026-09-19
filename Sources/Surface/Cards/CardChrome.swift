import Foundation
import Gating

/// The words and the colours on every card, as this operator set them.
///
/// **Nothing here has a default that came from somewhere else.** `ADOPT-1.f`
/// is that the name the bot goes by, the words on its cards and the picture
/// beside them are the operator's; `ADOPT-6.a` is that anything unset is empty
/// rather than somebody else's. So an unset picture is no picture, an unset
/// colour is no colour, and the only string with a fallback is the bot's name,
/// which falls back to a word that names nothing (`"this bot"`).
public struct CardChrome: Sendable, Equatable {

    // MARK: - Properties

    /// What the operator calls this bot.
    public let botName: String

    /// The token this server gates on.
    public let token: TokenProfile

    // MARK: - Initializers

    /// - Parameters:
    ///   - botName: What the operator calls this bot. Blank becomes
    ///     "this bot", which names no project.
    ///   - token: The token this server gates on.
    public init(botName: String, token: TokenProfile) {
        let trimmed = botName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.botName = trimmed.isEmpty ? "this bot" : trimmed
        self.token = token
    }

    // MARK: - Public Methods

    /// The colour a card is drawn in, or nil when the operator set none.
    public var color: UInt32? { token.cardColor }

    /// The picture beside a card's title, or nil.
    ///
    /// An unusable URL is dropped by ``SurfaceCard`` rather than here, so a
    /// mistyped logo costs the picture and not the card.
    public var thumbnailURL: String? { token.logoURL }
}

/// What a member is told before they sign anything.
///
/// `VERIFY-6` is the want: before signing, a member can read what this
/// server's bot will keep about them, who runs it, and which of it other
/// members will see. Two of those three are facts about this code and are
/// generated from it. The third is not knowable here at all, so it is
/// required configuration: a shipped sentence about who runs the server would
/// be a sentence about somebody else's server.
public struct DisclosureSettings: Sendable, Equatable {

    // MARK: - Properties

    /// The variable naming who runs this instance.
    public static let operatorNameKey = "VERIFY_OPERATOR_NAME"

    /// The variable saying which of it other members can see.
    public static let visibilityKey = "VERIFY_VISIBILITY_NOTE"

    /// The variable naming how to reach whoever runs it.
    public static let contactKey = "VERIFY_OPERATOR_CONTACT"

    /// Who runs this instance, in their own words.
    public let operatorName: String

    /// Which of it other members will see, in the operator's own words.
    public let visibilityNote: String

    /// How to reach them, or nil.
    public let contact: String?

    // MARK: - Initializers

    /// - Parameters:
    ///   - operatorName: Who runs this instance.
    ///   - visibilityNote: Which of it other members will see.
    ///   - contact: How to reach them.
    public init(operatorName: String, visibilityNote: String, contact: String? = nil) {
        self.operatorName = operatorName
        self.visibilityNote = visibilityNote
        self.contact = contact
    }

    /// Reads both required sentences, or refuses naming the variable.
    ///
    /// - Parameter lookup: Reads one variable.
    /// - Throws: ``SurfaceConfigurationError/missing(key:why:)`` when either
    ///   is unset. A member is about to sign something; being vague about who
    ///   is asking is not a thing to default.
    public static func load(_ lookup: (String) -> String?) throws -> DisclosureSettings {
        guard let name = Self.nonEmpty(operatorNameKey, lookup) else {
            throw SurfaceConfigurationError.missing(
                key: operatorNameKey,
                why: "a member is told who is asking before they sign, and this package cannot know "
                    + "who runs your server"
            )
        }
        guard let visibility = Self.nonEmpty(visibilityKey, lookup) else {
            throw SurfaceConfigurationError.missing(
                key: visibilityKey,
                why: "a member reads which of what is kept other members can see, and only you know "
                    + "what your server shows"
            )
        }
        return DisclosureSettings(
            operatorName: name,
            visibilityNote: visibility,
            contact: Self.nonEmpty(contactKey, lookup)
        )
    }

    // MARK: - Private Methods

    /// A variable's value with the whitespace off, or nil when blank.
    private static func nonEmpty(_ key: String, _ lookup: (String) -> String?) -> String? {
        guard let raw = lookup(key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
