import Foundation

/// The button styles a chat client is expected to understand.
///
/// Plain cases, no client types. This layer says what a button means; whatever
/// drives it decides what that looks like.
public enum GameButtonStyle: String, Sendable, Equatable {
    /// The call to action.
    case primary
    /// A quieter alternative.
    case secondary
    /// A positive action.
    case success
    /// A destructive or losing action.
    case danger
    /// Navigation. Carries a url and sends no interaction back.
    case link
}

/// One button under a game card.
///
/// A `link` button carries a `url` and an empty `id`, because navigation never
/// comes back as an interaction.
public struct GameButton: Sendable, Equatable {

    // MARK: - Properties

    /// The action's id, or `""` for a link button.
    public let id: String

    /// Button face.
    public let label: String

    /// Style.
    public let style: GameButtonStyle

    /// Destination for a `link` button. Nil for every other style.
    public let url: String?

    /// Greyed out and unclickable.
    public let disabled: Bool

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: Action id, or `""` for a link button.
    ///   - label: Button face.
    ///   - style: Style.
    ///   - url: Destination for a link button.
    ///   - disabled: Greyed out and unclickable.
    public init(
        id: String,
        label: String,
        style: GameButtonStyle,
        url: String? = nil,
        disabled: Bool = false
    ) {
        self.id = id
        self.label = label
        self.style = style
        self.url = url
        self.disabled = disabled
    }
}

/// One field on a game card.
public struct GameField: Sendable, Equatable {

    // MARK: - Properties

    /// Field heading.
    public let name: String

    /// Field body.
    public let value: String

    /// Sit beside the previous field instead of below it.
    public let inline: Bool

    // MARK: - Initializers

    /// - Parameters:
    ///   - name: Field heading.
    ///   - value: Field body.
    ///   - inline: Sit beside the previous field.
    public init(name: String, value: String, inline: Bool = false) {
        self.name = name
        self.value = value
        self.inline = inline
    }
}

/// A rendered game card, in a chat client's shape but with none of its types.
///
/// Games build this and whatever is driving them maps it, so the same card can be
/// asserted in a test without a client, a token or a connection.
public struct GameMessage: Sendable, Equatable {

    // MARK: - Properties

    /// Card title.
    public let title: String

    /// Card body.
    public let description: String

    /// Extra fields under the body.
    public let fields: [GameField]

    /// Card colour as `0xRRGGBB`.
    public let color: Int

    /// Buttons under the card.
    public let buttons: [GameButton]

    /// Small print under the card.
    public let footer: String?

    /// Picture for the card's corner, as a plain url.
    ///
    /// A `String` rather than a media type, so this module still names no client
    /// types. Whatever renders the card is what decides whether the url is usable,
    /// and an unusable one drops the picture rather than the whole message.
    public let thumbnailUrl: String?

    /// The dealt cards to draw, top row first, as deck codes like `ks`, with
    /// ``Cards/faceDownCode`` for a hole card.
    ///
    /// Strings, not pictures. The reducer says which cards are on the table and a
    /// later layer draws them, which is why a game can be played and tested with
    /// no renderer in the package at all.
    public let hand: [[String]]

    // MARK: - Initializers

    /// - Parameters:
    ///   - title: Card title.
    ///   - description: Card body.
    ///   - fields: Extra fields.
    ///   - color: Card colour as `0xRRGGBB`.
    ///   - buttons: Buttons under the card.
    ///   - footer: Small print.
    ///   - thumbnailUrl: Picture for the corner.
    ///   - hand: Dealt cards as deck codes, top row first.
    public init(
        title: String,
        description: String,
        fields: [GameField] = [],
        color: Int,
        buttons: [GameButton] = [],
        footer: String? = nil,
        thumbnailUrl: String? = nil,
        hand: [[String]] = []
    ) {
        self.title = title
        self.description = description
        self.fields = fields
        self.color = color
        self.buttons = buttons
        self.footer = footer
        self.thumbnailUrl = thumbnailUrl
        self.hand = hand
    }
}
