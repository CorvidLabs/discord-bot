import Foundation

/// The lengths Discord refuses a payload for, and the only place this package
/// is allowed to measure one.
///
/// **Everything here counts UTF-16 code units, because that is what Discord
/// counts.** `String.count` counts grapheme clusters and
/// ``Gating/GatingFormatting/clamp(_:to:)`` says so about itself: a thumbs-up
/// is one `Character` and two UTF-16 units, a flag is one `Character` and
/// four. A card built of emoji, combining marks or non-Latin script passes a
/// `count` check and is still refused by the API, and because the handler
/// deferred first, that refusal reaches the member as a thinking indicator
/// that never resolves. There is no error in the channel for them to read and
/// nothing in the log they can see.
///
/// So the rule is narrow and worth keeping narrow: a length compared against
/// one of these constants is measured with ``length(_:)`` and nothing else.
public enum ReplyLimits: Sendable {

    // MARK: - Properties

    /// A message body.
    public static let messageContent = 2_000

    /// An embed title.
    public static let embedTitle = 256

    /// An embed description.
    public static let embedDescription = 4_096

    /// An embed field's name.
    public static let embedFieldName = 256

    /// An embed field's value.
    public static let embedFieldValue = 1_024

    /// An embed footer.
    public static let embedFooter = 2_048

    /// Every embed on one message, added together.
    public static let embedTotal = 6_000

    /// Fields on one embed.
    public static let embedFieldCount = 25

    /// A button's label.
    public static let buttonLabel = 80

    /// A component's custom id. Short, which is why a button namespace is a
    /// few characters rather than a sentence.
    public static let customId = 100

    /// Buttons in one action row.
    public static let buttonsPerRow = 5

    /// Action rows on one message.
    public static let rowsPerMessage = 5

    /// What a clamped string ends with. One code unit, so the arithmetic below
    /// stays readable.
    public static let ellipsis = "\u{2026}"

    // MARK: - Public Methods

    /// How long Discord thinks this text is.
    public static func length(_ text: String) -> Int {
        text.utf16.count
    }

    /// Whether this text fits, in the unit that decides.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - limit: One of the constants above.
    public static func fits(_ text: String, within limit: Int) -> Bool {
        length(text) <= limit
    }

    /// The text, shortened to fit and marked as shortened.
    ///
    /// Characters are appended whole. Cutting at a UTF-16 index would split a
    /// surrogate pair and send Discord an unpaired half, which is not a
    /// shorter message but an invalid one, and it would split a family emoji
    /// into strangers. So the budget is counted in UTF-16 and spent a grapheme
    /// at a time: the result never exceeds `limit`, and it may fall a unit or
    /// three short of it when the last character would not fit whole.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - limit: One of the constants above.
    public static func clamp(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard length(text) > limit else { return text }
        let marker = ellipsis
        let budget = limit - length(marker)
        // A limit so small the marker alone does not fit. Nothing useful can
        // be said in it, and a partial marker is worse than an empty field.
        guard budget > 0 else { return length(marker) <= limit ? marker : "" }
        var kept = ""
        var used = 0
        for character in text {
            let width = length(String(character))
            if used + width > budget { break }
            kept.append(character)
            used += width
        }
        return kept + marker
    }

    /// Joins lines, dropping whole ones rather than cutting through one, and
    /// saying how many went.
    ///
    /// A line cut in half reads as a bug. "and 4 more" reads as a decision,
    /// which is what `RAIN-1.d` asks for: what is left out first is detail.
    ///
    /// A list whose first line does not fit on its own is dropped **whole**
    /// rather than sliced. That rule is here because of receipts: half of a
    /// transaction link is a link to nothing, and a member who taps it learns
    /// less than a member who is told the list did not fit.
    ///
    /// - Parameters:
    ///   - lines: The lines, in the order they matter.
    ///   - limit: One of the constants above.
    ///   - separator: What goes between them.
    ///   - sliceable: Whether a single over-long line may be clamped. False
    ///     for anything whose truncated form still looks complete.
    public static func joinWithinLimit(
        _ lines: [String],
        limit: Int,
        separator: String = "\n",
        sliceable: Bool = true
    ) -> String {
        guard !lines.isEmpty else { return "" }
        var kept: [String] = []
        var used = 0

        for line in lines {
            let addition = kept.isEmpty ? length(line) : length(line) + length(separator)
            let remaining = lines.count - kept.count - 1
            let note = remaining > 0 ? "\(separator)and \(remaining) more" : ""
            if used + addition + length(note) > limit { break }
            used += addition
            kept.append(line)
        }

        guard !kept.isEmpty else {
            return sliceable ? clamp(lines[0], to: limit) : "and \(lines.count) more"
        }
        let dropped = lines.count - kept.count
        if dropped > 0 {
            kept.append("and \(dropped) more")
        }
        return clamp(kept.joined(separator: separator), to: limit)
    }
}
