import Foundation
import Gating

/// Puts a decision into effect in the chat client.
///
/// Two calls rather than one, and the split matters. Reading a member's
/// current roles can fail, and a failed read is **unknown**, never an empty
/// set: applying a decision computed against no roles at all would revoke
/// every managed role the member has, for a member nobody could look at. That
/// is `ROLE-1.a` at the level of one person, and it is the reason the reader
/// throws rather than answering `[]`.
public protocol RoleApplier: Sendable {

    /// Every role this member holds now, including ones this bot manages
    /// nothing about.
    ///
    /// - Parameter externalId: The member's chat account id.
    /// - Throws: When the roles could not be read. The caller holds rather
    ///   than applying against an empty set.
    func currentRoleIds(externalId: String) async throws -> Set<String>

    /// Applies one decision.
    ///
    /// **Only ``Gating/RoleDecision/managed`` is touched, and in one call.**
    /// A round trip per role is how a sweep spends an afternoon and a rate
    /// limit; one payload is what the original settled on and what this
    /// carries across. A badge a moderator hands out by hand is outside the
    /// managed set and survives (`ROLE-5`).
    ///
    /// - Parameters:
    ///   - decision: What the rules decided.
    ///   - externalId: The member's chat account id.
    func apply(_ decision: RoleDecision, externalId: String) async throws
}

/// What the chat client actually did with a role list it accepted.
///
/// **Discord answers `200` to a member update and silently drops any role id
/// it does not recognise.** There is no error, no warning and nothing in the
/// response to say so: the call succeeded and the member simply never got the
/// role. One wrong digit in a configured id then costs every member that role
/// for ever, the bot re-sends the same list on every sweep because the member
/// still lacks it, and nothing anywhere says why.
///
/// So a write is read back and the difference is reported. The reporting is
/// separated from the reading because the reading needs a chat client and
/// this does not, which is what lets the sentence an operator has to find at
/// three in the morning be pinned by a test.
public enum RoleWriteCheck: Sendable {

    // MARK: - Public Methods

    /// Every role that was sent and is not on the member afterwards.
    ///
    /// - Parameters:
    ///   - wanted: The list that was sent.
    ///   - observed: The list the member came back holding.
    public static func silentlyIgnored(wanted: Set<String>, observed: Set<String>) -> Set<String> {
        wanted.subtracting(observed)
    }

    /// What to report, or nil when the write landed whole.
    ///
    /// - Parameters:
    ///   - externalId: The member's chat account id.
    ///   - ignored: What ``silentlyIgnored(wanted:observed:)`` found.
    public static func incidentLine(externalId: String, ignored: Set<String>) -> String? {
        guard !ignored.isEmpty else { return nil }
        let listed = ignored.sorted().joined(separator: ", ")
        return "Role write for \(externalId) did not land: Discord accepted the call and ignored "
            + "\(ignored.count) role(s) [\(listed)]. A role id that is not a role on this server, "
            + "or one above this bot's own, is dropped without an error."
    }
}
