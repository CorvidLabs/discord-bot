import Foundation
import Gating

/// Why a sweep left one member's roles alone.
///
/// SEE-2.a: when somebody's roles did not change, an operator has to be able
/// to tell whether the bot held them on purpose or simply missed them. From
/// outside the two look identical, because the member has the same roles
/// either way, and they want opposite responses: a hold is the bot refusing
/// to act on something it could not read, a miss is the bot failing.
public enum SweepSkipReason: String, Sendable, Equatable, Hashable, CaseIterable, Codable {

    /// Something the rules needed was not read, so the roles it decides were
    /// left as they were. The most common reason, and the one the whole
    /// design is pointed at.
    case factsUnread = "facts-unread"

    /// The member is on record and has proved no account, so there is
    /// nothing to read and nothing to decide.
    case noAccounts = "no-accounts"

    /// The member's current roles could not be read. Nothing is written,
    /// because a decision built against an empty set revokes everything.
    case rolesUnreadable = "roles-unreadable"

    /// The write was refused by the chat service. The bot does not know what
    /// this member is holding now.
    case applyFailed = "apply-failed"

    /// The member's last account was unlinked between the batch read and the
    /// write, so the decision was computed for somebody who no longer exists
    /// as this sweep understood them and was thrown away rather than applied.
    case unlinkedMidSweep = "unlinked-mid-sweep"

    // MARK: - Public Methods

    /// Whether this is the bot's own decision rather than a failure.
    ///
    /// The whole of SEE-2.a in one property: deliberate reasons are counted
    /// as held, everything else as missed.
    public var isDeliberate: Bool {
        switch self {
        case .factsUnread, .noAccounts, .unlinkedMidSweep: return true
        case .rolesUnreadable, .applyFailed: return false
        }
    }

    /// One plain sentence an operator can act on.
    ///
    /// Each names something outside the code, because a sentence naming the
    /// function that gave up is a sentence nobody running this can do
    /// anything with (SEE-11).
    public var sentence: String {
        switch self {
        case .factsUnread:
            return "something the rules needed was not read, so the roles it decides were left alone"
        case .noAccounts:
            return "the member has proved no account, so there was nothing to read"
        case .rolesUnreadable:
            return "the member's current roles could not be read from the chat service, which is "
                + "usually a missing permission rather than a member who left"
        case .applyFailed:
            return "the chat service refused the role change, which is usually this bot's own role "
                + "sitting below the roles it was asked to grant"
        case .unlinkedMidSweep:
            return "the member unlinked their last account while this sweep was running, so what it "
                + "had decided for them was thrown away rather than written"
        }
    }
}

/// The four things a sweep can do to one member.
///
/// Four, not a `Bool`. A `Bool` collapses "compared and already correct",
/// "deliberately not compared" and "threw" into the same `false`, and that
/// is exactly the distinction an operator needs.
public enum SweepDisposition: String, Sendable, Equatable, Hashable, CaseIterable, Codable {

    /// Roles were written.
    case changed

    /// Compared against this sweep's readings and already correct.
    case unchanged

    /// Deliberately not written. The member keeps what they have.
    case held

    /// The sweep failed on this member and does not know what is correct.
    case missed
}

/// What one sweep did to one member, and why.
public struct MemberSweepOutcome: Sendable, Equatable {

    // MARK: - Properties

    /// Who this is about: this instance's own name for them, never the chat
    /// service's, so a log line and a journal row carry nothing belonging to
    /// a person.
    public let memberId: String

    /// What was done.
    public let disposition: SweepDisposition

    /// Why the member was held or missed. Nil when roles were compared.
    public let reason: SweepSkipReason?

    /// What the rules wanted and were not given, in the order they wanted it.
    ///
    /// Present on a changed outcome too: a member whose ladder moved while
    /// one collection went unread was partly decided and partly held, and a
    /// sweep where most members read that way is not the same sweep as one
    /// where none do.
    public let unknowns: [GatingUnknown]

    /// How many configured roles were deliberately left alone.
    public let heldRoleCount: Int

    // MARK: - Initializers

    /// - Parameters:
    ///   - memberId: This instance's own name for the member.
    ///   - disposition: What was done.
    ///   - reason: Why it was held or missed.
    ///   - unknowns: What the rules were not given.
    ///   - heldRoleCount: How many configured roles were left alone.
    public init(
        memberId: String,
        disposition: SweepDisposition,
        reason: SweepSkipReason?,
        unknowns: [GatingUnknown] = [],
        heldRoleCount: Int = 0
    ) {
        self.memberId = memberId
        self.disposition = disposition
        self.reason = reason
        self.unknowns = unknowns
        self.heldRoleCount = heldRoleCount
    }

    // MARK: - Public Methods

    /// Roles were written.
    public static func changed(
        memberId: String,
        unknowns: [GatingUnknown] = [],
        heldRoleCount: Int = 0
    ) -> MemberSweepOutcome {
        MemberSweepOutcome(
            memberId: memberId,
            disposition: .changed,
            reason: nil,
            unknowns: unknowns,
            heldRoleCount: heldRoleCount
        )
    }

    /// Roles were compared and already correct.
    public static func unchanged(memberId: String) -> MemberSweepOutcome {
        MemberSweepOutcome(memberId: memberId, disposition: .unchanged, reason: nil)
    }

    /// The bot chose not to touch this member.
    public static func held(
        memberId: String,
        _ reason: SweepSkipReason,
        unknowns: [GatingUnknown] = [],
        heldRoleCount: Int = 0
    ) -> MemberSweepOutcome {
        MemberSweepOutcome(
            memberId: memberId,
            disposition: .held,
            reason: reason,
            unknowns: unknowns,
            heldRoleCount: heldRoleCount
        )
    }

    /// The bot failed on this member.
    public static func missed(
        memberId: String,
        _ reason: SweepSkipReason,
        unknowns: [GatingUnknown] = []
    ) -> MemberSweepOutcome {
        MemberSweepOutcome(memberId: memberId, disposition: .missed, reason: reason, unknowns: unknowns)
    }

    /// Whether every fact the rules wanted was read.
    public var isComplete: Bool { unknowns.isEmpty }

    /// One line for a log, already naming the member and the reason.
    public var summary: String {
        var line = "\(memberId): \(disposition.rawValue)"
        if let reason {
            line += " (\(reason.sentence))"
        }
        if heldRoleCount > 0 {
            line += ", \(heldRoleCount) role(s) held"
        }
        return line
    }
}
