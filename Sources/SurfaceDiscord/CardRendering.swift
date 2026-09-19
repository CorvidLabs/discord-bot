import DiscordBM
import Foundation
import Surface

/// Turns a card into the payload Discord draws.
///
/// **Every edit carries an `attachments` array, and it is never omitted.**
/// Editing a message *replaces* its attachment list with whatever is sent;
/// leave the key out and Discord keeps every file already on the message and
/// appends the new one. After a few edits the message holds several files of
/// the same name, `attachment://name` resolves to the oldest of them, and the
/// card appears to have frozen while the handler is working perfectly. An
/// empty array on a card with no file is what clears the last one, which is
/// why ``Surface/VisibleMessage/attachments`` is not optional and why this
/// file never writes `nil` there.
public enum CardRendering: Sendable {

    // MARK: - Public Methods

    /// A card as an embed.
    /// - Parameter card: The card.
    public static func embed(_ card: SurfaceCard) -> Embed {
        Embed(
            title: card.title.isEmpty ? nil : card.title,
            description: card.description.isEmpty ? nil : card.description,
            color: card.color.flatMap { DiscordColor(value: Int($0)) },
            footer: card.footer.map { Embed.Footer(text: $0) },
            image: card.imageURL.map { Embed.Media(url: .init(from: $0)) },
            thumbnail: card.thumbnailURL.map { Embed.Media(url: .init(from: $0)) },
            fields: card.fields.isEmpty
                ? nil
                : card.fields.map { Embed.Field(name: $0.name, value: $0.value, inline: $0.inline) }
        )
    }

    /// A card's buttons, in rows of five.
    ///
    /// Discord allows five buttons to a row and five rows to a message, and
    /// refuses the whole message for a sixth in a row rather than wrapping it.
    ///
    /// - Parameter card: The card.
    public static func components(_ card: SurfaceCard) -> [Interaction.ActionRow] {
        let usable = card.buttons.prefix(ReplyLimits.buttonsPerRow * ReplyLimits.rowsPerMessage)
        return stride(from: 0, to: usable.count, by: ReplyLimits.buttonsPerRow).map { start in
            let end = min(start + ReplyLimits.buttonsPerRow, usable.count)
            let row = usable[start..<end].map { Interaction.ActionRow.Component.button(button($0)) }
            return Interaction.ActionRow(components: Array(row))
        }
    }

    /// A message as an immediate interaction response.
    ///
    /// - Parameter message: What to send.
    public static func response(_ message: VisibleMessage) -> Payloads.InteractionResponse.Message {
        Payloads.InteractionResponse.Message(
            content: message.content,
            embeds: message.card.map { [embed($0)] },
            // Empty on purpose and not absent: no @everyone, no @here, no
            // role and no user mention is resolved, whatever the text holds.
            // The text is never rewritten, because rewriting somebody's words
            // mangles an announcement that quotes "@everyone" in prose.
            allowedMentions: silentMentions,
            flags: message.isEphemeral ? [.ephemeral] : nil,
            components: message.card.map(components) ?? [],
            attachments: message.attachments.map { .init(index: $0.index, filename: $0.filename) }
        )
    }

    /// A message as an edit of one already sent.
    ///
    /// - Parameter message: What the message should now be.
    public static func edit(_ message: VisibleMessage) -> Payloads.EditWebhookMessage {
        Payloads.EditWebhookMessage(
            content: message.content,
            embeds: message.card.map { [embed($0)] },
            allowed_mentions: silentMentions,
            components: message.card.map(components) ?? [],
            // Always present. See the type's documentation.
            attachments: message.attachments.map { .init(index: $0.index, filename: $0.filename) }
        )
    }

    /// A message as a replacement for the one a component sat on.
    ///
    /// - Parameter message: What the message should now be.
    public static func update(_ message: VisibleMessage) -> Payloads.InteractionResponse {
        .updateMessage(response(message))
    }

    /// Suggestions, as Discord's autocomplete payload.
    /// - Parameter choices: What to offer.
    public static func suggestions(_ choices: [AutocompleteChoice]) -> Payloads.InteractionResponse {
        // Discord refuses more than twenty-five and shows none of them, so a
        // long list is trimmed rather than lost.
        .autocompleteResult(.init(
            choices: choices.prefix(Self.maximumSuggestions).map {
                .init(name: $0.name, value: .string($0.value))
            }
        ))
    }

    /// Most suggestions Discord will show.
    public static let maximumSuggestions = 25

    // MARK: - Private Methods

    /// Mentions nobody, whatever the text says.
    private static let silentMentions = Payloads.AllowedMentions(parse: [], roles: [], users: [])

    /// One button.
    private static func button(_ spec: ButtonSpec) -> Interaction.ActionRow.Button {
        guard spec.style == .link, let url = spec.url else {
            return .init(
                style: nonLinkStyle(spec.style),
                label: spec.label,
                custom_id: spec.id,
                disabled: spec.disabled
            )
        }
        return .init(label: spec.label, url: url, disabled: spec.disabled)
    }

    /// Our style as Discord's, for a button that does work.
    private static func nonLinkStyle(_ style: ButtonStyle) -> Interaction.ActionRow.Button.NonLinkStyle {
        switch style {
        case .primary:
            return .primary
        case .success:
            return .success
        case .danger:
            return .danger
        case .secondary, .link:
            // `.link` cannot reach here: ``Surface/ButtonSpec`` refuses the
            // link style on a button with no url. Mapped rather than trapped,
            // because a card is not worth a crash.
            return .secondary
        }
    }
}
