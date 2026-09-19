import Foundation
import Gating

/// A variable that is set, belongs to this build, and nothing read.
public struct UnreadSetting: Sendable, Equatable {

    // MARK: - Properties

    /// The variable as the operator wrote it.
    public let name: String

    /// The catalogue entry it is within one edit of, when there is one.
    ///
    /// A suggestion rather than a correction: it is offered beside the name
    /// and the operator decides. Nothing is renamed, substituted or guessed
    /// at on their behalf.
    public let nearest: String?

    // MARK: - Initializers

    /// - Parameters:
    ///   - name: The variable as it was written.
    ///   - nearest: The entry it is nearly.
    public init(name: String, nearest: String?) {
        self.name = name
        self.nearest = nearest
    }
}

/// What the catalogue makes of the variables that are actually set.
///
/// Three answers, and the difference between them is the whole point. A
/// variable the build read is ordinary. A variable inside a prefix this build
/// owns that nothing read is a probable typo, reported and not refused,
/// because refusing an unknown name breaks both directions of an upgrade: a
/// variable set ahead of a deploy, and one left behind by a rollback
/// (ADOPT-9.a). A variable inside a prefix reserved for a part this build does
/// not have refuses the boot (RUN-9.a).
public struct SettingsAudit: Sendable, Equatable {

    // MARK: - Properties

    /// Set, owned by this build, and read by nothing.
    public let unread: [UnreadSetting]

    /// Set, and belonging to a part this build does not have.
    public let reserved: [BootFailure]

    /// Read by a loader and described by no catalogue entry.
    ///
    /// A mistake in this program rather than in the operator's file, which is
    /// why it carries the internal code: a variable added to a module without
    /// being described in the catalogue would otherwise ship undocumented
    /// (TRUST-1).
    public let undescribed: [String]

    // MARK: - Initializers

    /// - Parameters:
    ///   - unread: Set, owned, and read by nothing.
    ///   - reserved: Set, and belonging to a part this build does not have.
    ///   - undescribed: Read by a loader and in no catalogue entry.
    public init(unread: [UnreadSetting], reserved: [BootFailure], undescribed: [String]) {
        self.unread = unread
        self.reserved = reserved
        self.undescribed = undescribed
    }

    // MARK: - Public Methods

    /// The refusal this audit produces, or nil when it produces none.
    ///
    /// The undescribed keys come first because they are this program's fault
    /// and an operator can do nothing about them.
    public var refusal: BootFailure? {
        if let name = undescribed.sorted().first {
            return BootFailure(
                variable: name,
                summary: "A loader read \(name) and the settings catalogue does not describe it, "
                    + "so this build would ask for a variable it never documents.",
                remedy: "This is a fault in the program rather than in your settings. Add the "
                    + "variable to SettingsCatalogue.entries.",
                code: .internalError
            )
        }
        return reserved.first
    }

    /// Runs the audit.
    ///
    /// - Parameters:
    ///   - settings: The one snapshot of the machine's variables.
    ///   - keysRead: Every variable any loader asked for.
    public static func of(settings: Settings, keysRead: Set<String>) -> SettingsAudit {
        var unread: [UnreadSetting] = []
        var reserved: [BootFailure] = []

        for name in settings.names.sorted() {
            // Blank counts as unset, the same rule every loader in the
            // package already applies (`NumberedEnvironment.nonEmpty`). A
            // compose file writing `DISCORD_BOT_TOKEN: ${DISCORD_BOT_TOKEN}`
            // with nothing in the variable puts an empty one in the
            // environment, and refusing a boot over a variable the rest of
            // the program considers unset is one layer refusing what another
            // accepts, which is worse than either rule on its own.
            guard NumberedEnvironment.nonEmpty(name, settings.value) != nil else { continue }
            if let prefix = SettingsCatalogue.reservedPrefix(of: name) {
                reserved.append(
                    BootFailure(
                        variable: name,
                        summary: "\(name) is set, and this build has no \(SettingsCatalogue.reservedPart(prefix)).",
                        remedy: "Nothing here would read it, so the bot would start, answer "
                            + "healthy and never appear where you expected it. Remove the "
                            + "variable, or run a build that has that part.",
                        code: .configuration
                    )
                )
                continue
            }
            guard SettingsCatalogue.isOwned(name), !keysRead.contains(name) else { continue }
            unread.append(UnreadSetting(name: name, nearest: nearest(to: name)))
        }

        let undescribed = keysRead
            .filter { SettingsCatalogue.entry(for: $0) == nil }
            .sorted()

        return SettingsAudit(unread: unread, reserved: reserved, undescribed: undescribed)
    }

    // MARK: - Private Methods

    /// The catalogue pattern `name` is within one edit of, or nil.
    ///
    /// One edit, not a general nearest match. A cleverer distance produces a
    /// confident wrong suggestion, which is worse than none: the name is
    /// printed either way, and the operator's eye is the better matcher.
    private static func nearest(to name: String) -> String? {
        let candidates = SettingsCatalogue.entries.map(\.pattern)
        // A family pattern is compared with its numbers filled in from the
        // name being checked, so `TIER_2_MIM` is offered `TIER_2_MIN` rather
        // than `TIER_#_MIN`, which an operator would have to translate.
        for pattern in candidates {
            let target = pattern.contains("#") ? filled(pattern, like: name) : pattern
            if isWithinOneEdit(name, target) {
                return target
            }
        }
        return nil
    }

    /// The family pattern with each `#` replaced by the number in the same
    /// position of `name`, when there is one.
    private static func filled(_ pattern: String, like name: String) -> String {
        var numbers: [String] = []
        var current = ""
        for character in name {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                numbers.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            numbers.append(current)
        }
        var out = ""
        var index = 0
        for character in pattern {
            if character == "#" {
                out += index < numbers.count ? numbers[index] : "1"
                index += 1
            } else {
                out.append(character)
            }
        }
        return out
    }

    /// Whether `left` becomes `right` with at most one insertion, deletion or
    /// substitution.
    private static func isWithinOneEdit(_ left: String, _ right: String) -> Bool {
        if left == right { return false }
        let first = Array(left)
        let second = Array(right)
        if abs(first.count - second.count) > 1 { return false }
        if first.count == second.count {
            var differences = 0
            for index in first.indices where first[index] != second[index] {
                differences += 1
                if differences > 1 { return false }
            }
            return differences == 1
        }
        let shorter = first.count < second.count ? first : second
        let longer = first.count < second.count ? second : first
        var shortIndex = 0
        var longIndex = 0
        var skipped = false
        while shortIndex < shorter.count, longIndex < longer.count {
            if shorter[shortIndex] == longer[longIndex] {
                shortIndex += 1
                longIndex += 1
                continue
            }
            if skipped { return false }
            skipped = true
            longIndex += 1
        }
        return true
    }
}
