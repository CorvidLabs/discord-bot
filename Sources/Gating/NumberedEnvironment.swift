import Foundation

/// How every list in this module is written down, and the rules that make a
/// typo visible.
///
/// A tier ladder, a collection catalogue and a pool catalogue are all the same
/// shape: an operator numbers entries from 1 and the loader reads upward. That
/// shape is the template the whole module follows, and it is worth stating why
/// it is the one that survived.
///
/// **The first gap ends the list.** Skipping a missing number and carrying on
/// would renumber every entry above a typo without saying so, and an operator
/// who mistyped `TIER_4_NAME` would get a five-rung ladder whose rungs four and
/// five are their five and six. Stopping at the gap drops rungs instead, which
/// is visible in the server within a minute.
///
/// **Nothing falls back.** An entry that is half written is a refusal naming
/// the variable, not an entry with a sensible default filled in (ADOPT-2).
public enum NumberedEnvironment: Sendable {

    // MARK: - Properties

    /// Highest number any list is scanned to.
    ///
    /// Not a product limit anybody should reach. It stops a malformed
    /// environment from being scanned forever. Reaching it is not a reason to
    /// stop reading quietly: see ``refuseOverflow(_:_:)``.
    public static let maxEntries = 32

    // MARK: - Public Methods

    /// Refuses a list that carries on past the last number scanned.
    ///
    /// An operator who numbered a thirty-third entry wrote configuration this
    /// module would otherwise drop on the floor, which is the silent fallback
    /// the rule above forbids. Every loader calls this once it has read
    /// ``maxEntries`` entries without a gap, so a longer list is a refusal
    /// naming the variable rather than a list that is quietly shorter than the
    /// one that was written.
    ///
    /// - Parameters:
    ///   - key: The variable that would start the entry after the last one
    ///     read.
    ///   - lookup: Reads one variable.
    public static func refuseOverflow(_ key: String, _ lookup: (String) -> String?) throws {
        guard nonEmpty(key, lookup) != nil else { return }
        throw GatingConfigurationError.tooManyEntries(key: key, limit: maxEntries)
    }

    /// A variable's value with the whitespace taken off, or nil when it is
    /// unset or blank.
    ///
    /// Blank counts as unset on purpose: `TIER_3_NAME=` in an env file is
    /// somebody commenting a rung out, and reading it as a rung named ""
    /// helps nobody.
    public static func nonEmpty(_ key: String, _ lookup: (String) -> String?) -> String? {
        guard
            let value = lookup(key)?.trimmingCharacters(in: .whitespaces),
            !value.isEmpty
        else { return nil }
        return value
    }

    /// A variable that has to be a whole number and has to be set.
    ///
    /// Underscores are allowed as digit separators, because an operator
    /// typing a threshold with nine zeros in it will use them and should not
    /// be punished for it.
    public static func requiredWholeNumber(
        _ key: String,
        purpose: String,
        _ lookup: (String) -> String?
    ) throws -> UInt64 {
        guard let raw = nonEmpty(key, lookup) else {
            throw GatingConfigurationError.missing(key: key, purpose: purpose)
        }
        guard let value = UInt64(raw.replacingOccurrences(of: "_", with: "")) else {
            throw GatingConfigurationError.notANumber(key: key, value: raw)
        }
        return value
    }

    /// A variable that has to be set to something.
    public static func required(
        _ key: String,
        purpose: String,
        _ lookup: (String) -> String?
    ) throws -> String {
        guard let value = nonEmpty(key, lookup) else {
            throw GatingConfigurationError.missing(key: key, purpose: purpose)
        }
        return value
    }

    /// A slug fit for an id, from a display name an operator typed.
    ///
    /// Lowercased, runs of anything else collapsed to a single `_`, so
    /// "Diamond Hands" becomes `diamond_hands`. Nil for a name with nothing
    /// usable in it, which every loader reports rather than silently accepts.
    public static func slug(_ name: String) -> String? {
        var out = ""
        var lastWasSeparator = false
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                out.append(character)
                lastWasSeparator = false
            } else if !out.isEmpty, !lastWasSeparator {
                out.append("_")
                lastWasSeparator = true
            }
        }
        while out.hasSuffix("_") {
            out.removeLast()
        }
        return out.isEmpty ? nil : out
    }

    /// True when Discord will accept this as a link or a thumbnail.
    ///
    /// http or https, with a host, and short enough to send. Anything else is
    /// refused at load rather than producing a card with a broken thumbnail
    /// that nobody can explain.
    public static func isLinkableURL(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 2048 else { return false }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
            return false
        }
        guard scheme == "https" || scheme == "http" else { return false }
        return url.host?.isEmpty == false
    }

    /// Six hexadecimal digits as a colour, with or without `#` or `0x`.
    public static func color(_ key: String, _ lookup: (String) -> String?) throws -> UInt32? {
        guard let raw = nonEmpty(key, lookup) else { return nil }
        var digits = raw.lowercased()
        if digits.hasPrefix("#") {
            digits.removeFirst()
        } else if digits.hasPrefix("0x") {
            digits.removeFirst(2)
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            throw GatingConfigurationError.unusableColor(key: key, value: raw)
        }
        return value
    }
}
