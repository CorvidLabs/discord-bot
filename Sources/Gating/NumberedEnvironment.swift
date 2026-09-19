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

    /// Refuses an unbroken list that carries straight on past the last number
    /// scanned.
    ///
    /// An operator who numbered a thirty-third entry wrote configuration this
    /// module would otherwise drop on the floor, which is the silent fallback
    /// the rule above forbids. Every loader calls this once it has read
    /// ``maxEntries`` entries with no gap, so an unbroken list longer than
    /// this module reads is a refusal naming the variable rather than a list
    /// quietly shorter than the one that was written.
    ///
    /// **It probes one number, because one number is all it can probe.** A
    /// loader is handed a lookup, not an environment it can list, so it cannot
    /// ask what else an operator wrote: it can only name a variable and ask
    /// about that one. Any wider sweep would need a second arbitrary ceiling
    /// to stop at, and the entry above *that* would be dropped in the same
    /// silence, one number further along.
    ///
    /// So an operator who wrote 1 to 32 and then 34 has left a gap at 33, and
    /// the gap rule above governs from there: the list ends at the gap and the
    /// 34th is dropped, exactly as a gap at 4 drops a 5th. That is a dropped
    /// entry rather than a renumbered one, which is the trade this module
    /// makes at every size, and reading the loaded configuration back at boot
    /// is what makes a dropped entry visible (ADOPT-9.a). The refusal here is
    /// narrower than the gap rule on purpose: it is for the one case the gap
    /// rule cannot cover, where the list stopped for a reason that is nowhere
    /// in the operator's file.
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
    ///
    /// Newlines come off as well as spaces. Almost everything here arrives
    /// from a file, a file's last line ends in a newline, and `.whitespaces`
    /// does not include one: trimming spaces alone made `TIER_1_MIN=100\n`
    /// a value that is not a number, while another layer reading the same
    /// line got 100. One layer refusing what another accepts is worse than
    /// either rule on its own.
    public static func nonEmpty(_ key: String, _ lookup: (String) -> String?) -> String? {
        guard
            let value = lookup(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }

    /// A number with its digit separators taken out, ready to parse.
    ///
    /// Underscores are allowed wherever anything in this package reads a
    /// number, because an operator typing a threshold or a request budget
    /// with nine zeros in it will use them and should not be punished for it.
    /// The rule lives here on its own rather than inside one reader, so every
    /// layer gives the same answer: `100_000` was once a threshold in one
    /// place and not a number at all in another.
    ///
    /// - Parameter raw: The value as it was written down.
    /// - Returns: The same digits with every `_` removed.
    public static func withoutDigitSeparators(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "")
    }

    /// A variable that has to be a whole number and has to be set.
    ///
    /// Digit separators are taken out by ``withoutDigitSeparators(_:)``, which
    /// is the one place that rule lives.
    public static func requiredWholeNumber(
        _ key: String,
        purpose: String,
        _ lookup: (String) -> String?
    ) throws -> UInt64 {
        guard let raw = nonEmpty(key, lookup) else {
            throw GatingConfigurationError.missing(key: key, purpose: purpose)
        }
        guard let value = UInt64(withoutDigitSeparators(raw)) else {
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
