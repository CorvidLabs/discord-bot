import Foundation

/// One rung of a server's holder ladder: what it is called and what it costs.
///
/// A value rather than a case in an enum, because the rungs belong to the
/// operator and not to us (ADOPT-1.a). A project with four tiers should have
/// four, and one whose top rung is called something else should see its own
/// word. The original's enum answered both questions on the operator's behalf
/// and could not be told otherwise without a recompile.
public struct Tier: Sendable, Equatable, Hashable, Codable, Comparable, Identifiable {

    // MARK: - Properties

    /// Stable key. Persisted, used to look up a role, never shown to a member.
    ///
    /// Kept apart from ``name`` so an operator can rename a rung without
    /// orphaning every row that already recorded somebody as being on it.
    public let id: String

    /// What a member sees.
    public let name: String

    /// Shown beside the name on a card. Empty is allowed and renders as
    /// nothing.
    public let emoji: String

    /// The smallest balance on this rung, in the token's smallest unit.
    ///
    /// Base units, never whole tokens, and converted from the operator's whole
    /// number through ``TokenProfile/baseUnits(whole:)`` and nowhere else.
    public let minimumBaseUnits: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: Stable key.
    ///   - name: What a member sees.
    ///   - emoji: Shown beside the name; may be empty.
    ///   - minimumBaseUnits: Smallest balance on this rung, in base units.
    public init(id: String, name: String, emoji: String = "", minimumBaseUnits: UInt64) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.minimumBaseUnits = minimumBaseUnits
    }

    // MARK: - Public Methods

    /// Ordered by what they cost, so a ladder sorts itself.
    public static func < (lhs: Tier, rhs: Tier) -> Bool {
        lhs.minimumBaseUnits < rhs.minimumBaseUnits
    }

    /// The name with the emoji in front, or just the name when there is none.
    public var display: String {
        emoji.isEmpty ? name : "\(emoji) \(name)"
    }
}

/// Where a member stands on the ladder, including the case where nobody knows.
///
/// Three cases rather than an optional, and that is the whole point of the
/// type. The original modelled "holds too little" as a `Tier` value with the
/// id `none`, which meant `tier == .none` compiled: Swift resolved it to
/// `Optional.none`, the comparison was always false, and four of them shipped.
/// The compiler warned about every one and nobody was reading warnings.
///
/// Here there is no `none` to compare against. The two things that are not a
/// rung are named separately, because they are not the same thing and they
/// lead to opposite decisions: ``unranked`` takes the tier roles away,
/// ``unread`` leaves every one of them alone (ROLE-1.a).
public enum TierStanding: Sendable, Equatable {

    /// The balance was read, and it reaches this rung.
    case on(Tier)

    /// The balance was read, and it reaches no rung.
    case unranked

    /// The balance was not read. This is not the bottom of the ladder.
    case unread

    // MARK: - Public Methods

    /// The rung, or nil when the member is on none.
    ///
    /// Safe to compare against nil: this really is an optional rung, so the
    /// mistake the type exists to prevent cannot be made here.
    public var tier: Tier? {
        switch self {
        case .on(let tier): return tier
        case .unranked, .unread: return nil
        }
    }

    /// True when somebody managed to read the balance, whatever it said.
    public var wasRead: Bool {
        switch self {
        case .on, .unranked: return true
        case .unread: return false
        }
    }
}

/// A server's holder ladder: the rungs, in order, and how a balance finds one.
///
/// The ladder is the only thing that turns a balance into a rung. Nothing else
/// in this module compares a balance against a threshold, so an operator who
/// changes the rungs changes every card, every role and every leaderboard at
/// once.
public struct TierLadder: Sendable, Equatable {

    // MARK: - Properties

    /// The earning rungs, ascending.
    ///
    /// May be empty. A server that gates on collections alone has no ladder,
    /// and that is a configuration, not an error.
    public let rungs: [Tier]

    /// What a member below the bottom rung is called on a card.
    ///
    /// A label, not a `Tier`. It has no threshold and no role, and giving it
    /// the shape of a rung is how the original ended up with a tier that
    /// resolved fine everywhere and then silently granted nothing.
    public let unrankedName: String

    /// The emoji beside ``unrankedName``.
    public let unrankedEmoji: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - rungs: Earning rungs in any order; sorted here, so a caller cannot
    ///     hand in a ladder that resolves out of sequence.
    ///   - unrankedName: What a member on no rung is called.
    ///   - unrankedEmoji: The emoji beside it.
    public init(rungs: [Tier], unrankedName: String = "None", unrankedEmoji: String = "") {
        self.rungs = rungs.sorted()
        self.unrankedName = unrankedName
        self.unrankedEmoji = unrankedEmoji
    }

    // MARK: - Public Methods

    /// The highest rung this balance reaches, or nil for none of them.
    public func tier(for baseUnits: UInt64) -> Tier? {
        var reached: Tier?
        for rung in rungs where baseUnits >= rung.minimumBaseUnits {
            reached = rung
        }
        return reached
    }

    /// Where a reading of a balance puts a member.
    ///
    /// The one place an unread balance becomes a standing rather than a zero.
    public func standing(for balance: Reading<UInt64>) -> TierStanding {
        switch balance {
        case .unknown:
            return .unread
        case .known(let baseUnits):
            guard let reached = tier(for: baseUnits) else { return .unranked }
            return .on(reached)
        }
    }

    /// Every rung at or below the one this balance reaches.
    ///
    /// Roles stack: somebody on the fourth rung keeps the three under it.
    public func rungsToAssign(for baseUnits: UInt64) -> [Tier] {
        rungs.filter { baseUnits >= $0.minimumBaseUnits }
    }

    /// Every rung at or below `tier`.
    public func rungsToAssign(upTo tier: Tier) -> [Tier] {
        rungs.filter { $0.minimumBaseUnits <= tier.minimumBaseUnits }
    }

    /// The rung with this id, or nil.
    public func rung(id: String) -> Tier? {
        rungs.first { $0.id == id }
    }

    /// The rung a stored row named, or nil when it names none of them.
    ///
    /// Deliberately lenient, in this order: the id exactly, the id ignoring
    /// case, then the display name ignoring case. A store that recorded the
    /// word a member was shown rather than the rung's id still resolves, so a
    /// change in how rows are written demotes nobody on the first sweep
    /// afterwards (ROLE-1.c). Matching on the id alone would read every one of
    /// those rows as no rung at once.
    ///
    /// The leniency is not free: one rung's display name competes with another
    /// rung's id. That is why the ids are tried first, and why a rung may not
    /// be named after the no-rung label. A stored row naming the label would
    /// otherwise resolve to the rung and grant its role to somebody on no rung
    /// at all.
    ///
    /// The cost of a name match is that **renaming a rung orphans every row
    /// that named it** until the next sweep rewrites them. An operator who
    /// renames a rung should run a resync afterwards.
    ///
    /// A row naming a rung the operator has since deleted reads as no rung:
    /// under-granting for one sweep is recoverable, granting a role that no
    /// longer exists is not.
    public func storedRung(_ stored: String) -> Tier? {
        if let exact = rung(id: stored) {
            return exact
        }
        let wanted = stored.lowercased()
        if let byId = rungs.first(where: { $0.id.lowercased() == wanted }) {
            return byId
        }
        return rungs.first { $0.name.lowercased() == wanted }
    }
}
