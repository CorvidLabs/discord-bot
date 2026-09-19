import Foundation

/// Something the rules needed and were not given.
///
/// Each one names a fact, not a role, because one unread fact usually holds
/// several roles still. An operator reading a sweep wants to know which
/// question went unanswered, so they know what to go and fix.
public enum GatingUnknown: Sendable, Equatable, Hashable {

    /// The member's direct balance was not read.
    case balance

    /// The member's liquidity positions were not read.
    case liquidityPositions

    /// How many pieces of this collection the member holds was not read.
    case collection(id: String)

    // MARK: - Public Methods

    /// One plain sentence an operator can act on.
    public var sentence: String {
        switch self {
        case .balance:
            return "the member's balance could not be read, so their rung was left as it was"
        case .liquidityPositions:
            return "the member's liquidity positions could not be read, so nothing that counts "
                + "them was decided"
        case .collection(let id):
            return "how many pieces of \(id) the member holds could not be read, so that "
                + "collection's roles were left as they were"
        }
    }
}

/// What a sweep did to one member.
///
/// Two cases, not a `Bool`, because a decision also carries why it did
/// nothing: roles unchanged because the member is already correct and roles
/// unchanged because nobody could read anything are the same `false` and
/// want opposite responses (SEE-2.a). The reasons live in
/// ``RoleDecision/unknowns``.
public enum MemberDisposition: String, Sendable, Equatable, CaseIterable, Codable {

    /// The member should end the sweep holding a different set of roles.
    case changed

    /// The member already holds exactly what they should.
    case unchanged
}

/// Which roles a member should hold, which they should not, and what was not
/// read.
///
/// The decision is a value. It grants nothing and takes nothing away: a
/// caller at the Discord boundary applies it, which is what lets every rule
/// in this module be pinned by a test without a guild, a database or a chain.
public struct RoleDecision: Sendable, Equatable {

    // MARK: - Properties

    /// Who this is about.
    public let memberId: String

    /// Where the member stands on the ladder, including "nobody read it".
    public let standing: TierStanding

    /// Direct plus pooled, in base units, or unknown.
    public let combinedBalance: Reading<UInt64>

    /// Every role this decision is entitled to add or remove.
    ///
    /// A configured role is only managed when the fact that decides it was
    /// read. That is the whole of ROLE-1.a in one set: a role outside it is
    /// not touched, so a member whose balance nobody could read keeps the
    /// rung they had.
    public let managed: Set<String>

    /// Exactly the roles the member should hold when the decision is applied,
    /// including the ones this decision does not manage and must preserve.
    public let target: Set<String>

    /// Roles to add.
    public let granted: Set<String>

    /// Roles to take away. Always a subset of ``managed``.
    public let revoked: Set<String>

    /// Configured roles this decision deliberately left alone, because
    /// something needed to decide them was not read.
    public let held: Set<String>

    /// What was not read, in the order the rules wanted it.
    public let unknowns: [GatingUnknown]

    // MARK: - Initializers

    /// - Parameters:
    ///   - memberId: Who this is about.
    ///   - standing: Where they stand on the ladder.
    ///   - combinedBalance: Direct plus pooled, or unknown.
    ///   - managed: Roles this decision may add or remove.
    ///   - target: Roles the member should hold afterwards.
    ///   - granted: Roles to add.
    ///   - revoked: Roles to take away.
    ///   - held: Configured roles deliberately left alone.
    ///   - unknowns: What could not be read.
    public init(
        memberId: String,
        standing: TierStanding,
        combinedBalance: Reading<UInt64>,
        managed: Set<String>,
        target: Set<String>,
        granted: Set<String>,
        revoked: Set<String>,
        held: Set<String>,
        unknowns: [GatingUnknown]
    ) {
        self.memberId = memberId
        self.standing = standing
        self.combinedBalance = combinedBalance
        self.managed = managed
        self.target = target
        self.granted = granted
        self.revoked = revoked
        self.held = held
        self.unknowns = unknowns
    }

    // MARK: - Public Methods

    /// Whether applying this would change anything.
    public var disposition: MemberDisposition {
        granted.isEmpty && revoked.isEmpty ? .unchanged : .changed
    }

    /// True when every fact the rules wanted was read.
    public var isComplete: Bool { unknowns.isEmpty }

    /// One line for a log or an operator's card.
    public var summary: String {
        var parts: [String] = []
        parts.append("+\(granted.count)")
        parts.append("-\(revoked.count)")
        if !held.isEmpty {
            parts.append("\(held.count) held")
        }
        let reasons = unknowns.map(\.sentence).joined(separator: "; ")
        let tail = reasons.isEmpty ? "" : " (\(reasons))"
        return "\(memberId): \(parts.joined(separator: " "))\(tail)"
    }
}
