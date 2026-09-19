import Foundation

/// Writing integer smallest units out for a person to read, and keeping a
/// payload inside the bounds Discord accepts.
///
/// Every amount somebody has to be able to check goes through ``grouped(_:)``
/// or ``amount(_:decimals:)``, and neither of those touches `Double`,
/// `NumberFormatter` or a locale. A grouping separator that moves between
/// macOS and Linux turns a reconciliation into an argument, and floating
/// point cannot represent these values exactly in the first place.
///
/// ``compact(_:decimals:)`` is the exception, and the only declaration in this
/// file that goes near `Double` or `pow`. It is for a card where the exact
/// figure is not the point, it throws digits away deliberately, and its own
/// documentation says so at length. Nothing anybody has to check may go
/// through it.
public enum GatingFormatting: Sendable {

    // MARK: - Numbers

    /// `1234567` as `1,234,567`.
    ///
    /// Hand-rolled because `NumberFormatter` is locale-sensitive and, on Linux,
    /// not identical to its Darwin counterpart.
    public static func grouped(_ value: UInt64) -> String {
        groupedDigits(String(value))
    }

    /// Smallest units written as a decimal amount, with no digit lost.
    ///
    /// The point is moved through the digits rather than by dividing, so the
    /// answer is exact at every precision an asset can have. Dividing needed
    /// ten to the power of `decimals` to fit in a `UInt64`, which capped this
    /// at nineteen places, and the guard that kept the multiply from trapping
    /// answered a twentieth with the smallest units themselves: one base unit
    /// of a twenty-decimal asset printed as `1`, a whole one, with nothing
    /// said.
    ///
    /// Trailing zeros of the fraction are trimmed, because `1,000.500000` and
    /// `1,000.5` are the same number and the shorter one is easier to check.
    /// Nothing else is rounded away.
    ///
    /// - Parameters:
    ///   - baseUnits: The amount, in the asset's smallest unit.
    ///   - decimals: How many decimal places that asset has. **Not six.** The
    ///     original assumed six in nine separate places, which is correct for
    ///     exactly one token and silently wrong by a factor of a million for
    ///     the next one. `UInt8` rather than `Int`, because a precision below
    ///     zero has no honest answer and the wider type invited one.
    /// - Returns: The amount as digits, grouped, with a fraction only when
    ///   there is one.
    public static func amount(_ baseUnits: UInt64, decimals: UInt8) -> String {
        let places = Int(decimals)
        guard places > 0 else { return grouped(baseUnits) }
        var digits = String(baseUnits)
        if digits.count <= places {
            // One digit more than the fraction takes, so there is always a
            // whole part to print even when it is a single zero.
            digits = String(repeating: "0", count: places - digits.count + 1) + digits
        }
        var fraction = String(digits.suffix(places))
        while fraction.hasSuffix("0") {
            fraction.removeLast()
        }
        let whole = groupedDigits(String(digits.dropLast(places)))
        return fraction.isEmpty ? whole : "\(whole).\(fraction)"
    }

    /// A balance shortened to `1.5M` or `250K`, for a card where the exact
    /// figure is not the point.
    ///
    /// **Never use this for money.** It goes through `Double`, and it throws
    /// digits away on purpose. A payout of `269,230.76923` prints as `269K`,
    /// and an operator reconciling that against an allocation has been handed
    /// nothing they can check. Amounts that somebody has to be able to verify
    /// go through ``amount(_:decimals:)``, which touches no `Double` at all.
    /// The original carried the same warning, and it is repeated here because
    /// the function keeps looking like the convenient one.
    ///
    /// Truncates rather than rounds, so it can never show more than is held.
    public static func compact(_ baseUnits: UInt64, decimals: UInt8) -> String {
        let divisor = pow(10.0, Double(decimals))
        let value = Double(baseUnits) / divisor
        let suffixes = ["", "K", "M", "B", "T"]
        var magnitude = 0
        var reduced = value

        while reduced >= 1000, magnitude < suffixes.count - 1 {
            reduced /= 1000
            magnitude += 1
        }

        let formatted: String
        if reduced < 10 {
            formatted = String(format: "%.2f%@", truncate(reduced, places: 2), suffixes[magnitude])
        } else if reduced < 100 {
            formatted = String(format: "%.1f%@", truncate(reduced, places: 1), suffixes[magnitude])
        } else {
            formatted = String(format: "%.0f%@", truncate(reduced, places: 0), suffixes[magnitude])
        }
        return trimTrailingZeros(formatted)
    }

    // MARK: - Payload bounds

    /// Clamps `text` to `limit` Swift characters, marking that it was cut.
    ///
    /// Discord rejects an over-long embed field, description or message
    /// outright, and because a handler defers first, the rejection surfaces to
    /// a member as a stuck "thinking" rather than as an error. Anything built
    /// from a collection or from off-chain metadata goes through here.
    ///
    /// **This makes a rejection unlikely, not impossible.** A Swift
    /// `Character` is a grapheme cluster: one flag, one skin-toned emoji, one
    /// accented letter written as two scalars. The receiving end counts
    /// something smaller, so a string of those can pass this and still be too
    /// long there. This layer has no Discord boundary to measure against, so
    /// it does not guess at the smaller unit; a boundary that does should
    /// check again in whatever the API it calls actually counts.
    public static func clamp(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        let ellipsis = "..."
        guard limit > ellipsis.count else { return String(text.prefix(limit)) }
        return String(text.prefix(limit - ellipsis.count)) + ellipsis
    }

    /// Joins `lines` while staying under `limit`, appending a count of what
    /// was dropped.
    ///
    /// Preferred over ``clamp(_:to:)`` for a list, because a line cut in half
    /// reads as a rendering bug while "and 4 more" reads as intent.
    public static func joinWithinLimit(
        _ lines: [String],
        limit: Int,
        separator: String = "\n"
    ) -> String {
        guard !lines.isEmpty else { return "" }
        var kept: [String] = []
        var length = 0

        for line in lines {
            let addition = kept.isEmpty ? line.count : line.count + separator.count
            // Leave room for the overflow note when this is not the last line.
            let remaining = lines.count - kept.count - 1
            let note = remaining > 0 ? "\(separator)and \(remaining) more" : ""
            if length + addition + note.count > limit { break }
            length += addition
            kept.append(line)
        }

        guard !kept.isEmpty else { return clamp(lines[0], to: limit) }
        let dropped = lines.count - kept.count
        if dropped > 0 {
            kept.append("and \(dropped) more")
        }
        return clamp(kept.joined(separator: separator), to: limit)
    }

    // MARK: - Private Methods

    /// Groups a string of digits in threes.
    ///
    /// Takes digits rather than a number because ``amount(_:decimals:)`` moves
    /// the point through the digits of a value whose whole part it never
    /// builds a `UInt64` out of.
    private static func groupedDigits(_ digits: String) -> String {
        let characters = Array(digits)
        var out: [Character] = []
        for (index, digit) in characters.enumerated() {
            if index > 0, (characters.count - index) % 3 == 0 {
                out.append(",")
            }
            out.append(digit)
        }
        return String(out)
    }

    /// Floors a double to `places`, never rounds up. Showing more than is held
    /// is the one direction that is not merely untidy.
    private static func truncate(_ value: Double, places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return floor(value * multiplier) / multiplier
    }

    /// Drops `1.50K` to `1.5K` and `2.00` to `2`, without a regular expression.
    private static func trimTrailingZeros(_ input: String) -> String {
        var result = input
        var suffix = ""
        if let last = result.last, "KMBT".contains(last) {
            suffix = String(last)
            result.removeLast()
        }
        if result.contains(".") {
            while result.hasSuffix("0") {
                result.removeLast()
            }
            if result.hasSuffix(".") {
                result.removeLast()
            }
        }
        return result + suffix
    }
}

/// The lengths Discord refuses a payload for.
///
/// Named constants rather than numbers typed at each call site: the original
/// had `256` and `4096` written out in dozens of places, and a card that grew
/// a field was one forgotten clamp away from a handler that never answered.
public enum DiscordPayloadLimit: Sendable {

    /// An embed title.
    public static let embedTitle = 256

    /// An embed description.
    public static let embedDescription = 4096

    /// One embed field's name.
    public static let embedFieldName = 256

    /// One embed field's value.
    public static let embedFieldValue = 1024

    /// An embed footer.
    public static let embedFooter = 2048

    /// An embed author's name.
    public static let embedAuthorName = 256

    /// Every field of every embed on one message, added together. A message
    /// can pass each of the limits above and still be refused on this one.
    public static let embedTotal = 6000

    /// Plain message content.
    public static let messageContent = 2000

    /// The label on a button or a select option.
    public static let componentLabel = 80
}
