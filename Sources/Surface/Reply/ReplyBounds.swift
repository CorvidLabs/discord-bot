import Foundation

/// What enforcing the bounds did to a message.
public enum BoundedMessage: Sendable, Equatable {

    /// It fits, exactly as written.
    case within(VisibleMessage)

    /// It did not fit and was shortened. The message is the shortened one.
    case clamped(VisibleMessage)

    /// It did not fit and shortening it would have lied, so nothing is sent
    /// and this is what the person is told instead.
    case refused(String)

    // MARK: - Public Methods

    /// The message to send, or nil when it was refused.
    public var message: VisibleMessage? {
        switch self {
        case .within(let message), .clamped(let message):
            return message
        case .refused:
            return nil
        }
    }
}

/// The last thing between a handler and the chat client.
///
/// **An over-long payload fails here, never as an API refusal after a defer.**
/// That is the whole point of the layer. A handler that defers and then sends
/// 4,200 characters into a 4,096 character field gets a `400`, and the member
/// who ran the command gets a thinking indicator that never resolves, with
/// nothing anywhere they can read. Failing here means they get a sentence.
///
/// Every measurement is ``ReplyLimits/length(_:)``, in UTF-16 code units.
public enum ReplyBounds: Sendable {

    // MARK: - Public Methods

    /// The message, made to fit, or a refusal.
    ///
    /// Under ``TruncationPolicy/clamp`` every over-long part is shortened and
    /// marked. Under ``TruncationPolicy/refuse`` the first over-long part
    /// stops the send and names itself, because a truncated announcement or a
    /// truncated link still reads as a whole one.
    ///
    /// - Parameter message: What the handler wants to send.
    public static func enforce(_ message: VisibleMessage) -> BoundedMessage {
        var didClamp = false
        // Declared before the closure that writes it: the sentence a refusal
        // carries names the part that broke, and the caller below only knows
        // that something did.
        var refusal: String?

        func bound(_ text: String, _ limit: Int, _ what: String) -> String? {
            guard !ReplyLimits.fits(text, within: limit) else { return text }
            guard message.truncation == .clamp else {
                refusal = "That \(what) is \(ReplyLimits.length(text)) characters and Discord allows "
                    + "\(limit). Shortening it would change what it says, so nothing was sent."
                return nil
            }
            didClamp = true
            return ReplyLimits.clamp(text, to: limit)
        }

        let content: String?
        if let existing = message.content {
            guard let bounded = bound(existing, ReplyLimits.messageContent, "message") else {
                return .refused(refusal ?? Self.genericRefusal)
            }
            content = bounded
        } else {
            content = nil
        }

        var card: SurfaceCard?
        if let existing = message.card {
            guard let title = bound(existing.title, ReplyLimits.embedTitle, "card title") else {
                return .refused(refusal ?? Self.genericRefusal)
            }
            guard
                let description = bound(existing.description, ReplyLimits.embedDescription, "card body")
            else {
                return .refused(refusal ?? Self.genericRefusal)
            }

            var fields: [SurfaceField] = []
            // Under `clamp`, fields above the cap are dropped whole: the ones
            // kept are the ones the builder put first, and a builder puts a
            // warning before a detail (RAIN-1.d). Under `refuse` they are not
            // dropped at all, because a receipt missing its last recipients
            // is a receipt that reads as complete, which is the whole reason
            // that policy exists.
            if existing.fields.count > ReplyLimits.embedFieldCount {
                guard message.truncation == .clamp else {
                    return .refused(
                        "That card has \(existing.fields.count) sections and Discord allows "
                            + "\(ReplyLimits.embedFieldCount). The first \(ReplyLimits.embedFieldCount) "
                            + "would read as the whole of it, so nothing was sent."
                    )
                }
                didClamp = true
            }
            for field in existing.fields.prefix(ReplyLimits.embedFieldCount) {
                guard
                    let name = bound(field.name, ReplyLimits.embedFieldName, "field name"),
                    let value = bound(field.value, ReplyLimits.embedFieldValue, "field")
                else {
                    return .refused(refusal ?? Self.genericRefusal)
                }
                fields.append(SurfaceField(name: name, value: value, inline: field.inline))
            }

            var footer: String?
            if let existingFooter = existing.footer {
                guard let bounded = bound(existingFooter, ReplyLimits.embedFooter, "footer") else {
                    return .refused(refusal ?? Self.genericRefusal)
                }
                footer = bounded
            }

            var buttons: [ButtonSpec] = []
            let buttonCap = ReplyLimits.buttonsPerRow * ReplyLimits.rowsPerMessage
            if existing.buttons.count > buttonCap {
                guard message.truncation == .clamp else {
                    return .refused(
                        "That card has \(existing.buttons.count) buttons and Discord allows "
                            + "\(buttonCap). A card missing the rest of them would read as the whole "
                            + "of it, so nothing was sent."
                    )
                }
                didClamp = true
            }
            for button in existing.buttons.prefix(buttonCap) {
                // A custom id over the cap is a programming mistake rather
                // than something a member typed, and a clamped id routes to
                // nobody, so it is a refusal whatever the policy says.
                guard ReplyLimits.fits(button.id, within: ReplyLimits.customId) else {
                    return .refused(
                        "A button on that card has an id Discord will not accept, so nothing was sent."
                    )
                }
                guard let label = bound(button.label, ReplyLimits.buttonLabel, "button label") else {
                    return .refused(refusal ?? Self.genericRefusal)
                }
                buttons.append(Self.relabelled(button, label: label))
            }
            let rebuilt = SurfaceCard(
                title: title,
                description: description,
                fields: fields,
                color: existing.color,
                footer: footer,
                thumbnailURL: existing.thumbnailURL,
                imageURL: existing.imageURL,
                buttons: buttons,
                attachmentName: existing.attachmentName
            )

            // The per-part limits can all pass while the sum is still refused,
            // and the sum is the one nobody remembers. Dropping fields from
            // the end keeps the top of the card, which is where a builder put
            // the warning, and under `refuse` nothing is dropped at all.
            let trimmed = Self.withinTotal(rebuilt)
            if trimmed.dropped > 0 {
                guard message.truncation == .clamp else {
                    return .refused(
                        "That card is longer than the \(ReplyLimits.embedTotal) characters Discord "
                            + "counts across one embed. Leaving \(trimmed.dropped) section(s) off the "
                            + "end would read as the whole of it, so nothing was sent."
                    )
                }
                didClamp = true
            }
            card = trimmed.card
        }

        let bounded = VisibleMessage(
            content: content,
            card: card,
            isEphemeral: message.isEphemeral,
            attachments: message.attachments,
            truncation: message.truncation
        )
        return didClamp ? .clamped(bounded) : .within(bounded)
    }

    // MARK: - Private Methods

    /// Said when a bound was broken and no more specific sentence was built.
    private static let genericRefusal =
        "That reply is longer than Discord accepts, so nothing was sent rather than something misleading."

    /// The same button with a different label.
    private static func relabelled(_ button: ButtonSpec, label: String) -> ButtonSpec {
        guard button.style != .link else {
            return .link(label: label, url: button.url ?? "")
        }
        return ButtonSpec(id: button.id, label: label, style: button.style, disabled: button.disabled)
    }

    /// The card with fields dropped from the end until the whole embed fits,
    /// and how many that took.
    private static func withinTotal(_ card: SurfaceCard) -> (card: SurfaceCard, dropped: Int) {
        var fields = card.fields
        while total(of: card, fields: fields) > ReplyLimits.embedTotal, !fields.isEmpty {
            fields.removeLast()
        }
        let dropped = card.fields.count - fields.count
        guard dropped > 0 else { return (card, 0) }
        return (SurfaceCard(
            title: card.title,
            description: card.description,
            fields: fields,
            color: card.color,
            footer: card.footer,
            thumbnailURL: card.thumbnailURL,
            imageURL: card.imageURL,
            buttons: card.buttons,
            attachmentName: card.attachmentName
        ), dropped)
    }

    /// Every piece of text on one embed, added the way Discord adds it.
    private static func total(of card: SurfaceCard, fields: [SurfaceField]) -> Int {
        var sum = ReplyLimits.length(card.title)
            + ReplyLimits.length(card.description)
            + ReplyLimits.length(card.footer ?? "")
        for field in fields {
            sum += ReplyLimits.length(field.name) + ReplyLimits.length(field.value)
        }
        return sum
    }
}
