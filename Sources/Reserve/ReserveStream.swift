import Foundation

/// How a stream turns eligibility into slots.
///
/// The two rules exist because the two questions are genuinely different. "How
/// many people are here" is not "how many things are held", and a stream that
/// used the wrong one would either pay a collector once for a hundred items or
/// pay one person a hundred times for spreading their single membership across
/// a hundred accounts.
public enum ReservePayoutRule: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// One slot per recipient, however many units they hold and however many
    /// accounts they hold them across.
    ///
    /// The generosity is deliberate and so is the meanness: holding ten of a
    /// thing does not pay ten times, and neither does splitting one thing across
    /// ten accounts. There is nothing to game in either direction.
    case oncePerRecipient

    /// One slot for every unit held, across every account.
    case oncePerHeldUnit
}

/// One named part of the reserve.
///
/// A value, not a case in an enum. The original welded two streams and their
/// percentages into the type system, which meant a third stream was a code
/// change and a different split was a recompile. Here a stream is something a
/// host writes down: what it is called, what fraction of the reserve it gets,
/// what that fraction is divided by, and how slots are counted.
public struct ReserveStream: Sendable, Equatable, Hashable, Codable, Identifiable {

    // MARK: - Properties

    /// Keys this stream's ledger rows. Stable forever once anything has paid.
    public let id: String

    /// What a person reads on a card.
    public let name: String

    /// This stream's fraction of the whole reserve.
    public let share: ReserveShare

    /// What the share is divided by to get one slot's entitlement.
    ///
    /// **A constant, never the eligible count.** This is the single most
    /// important field in the package. Dividing by however many happen to be
    /// eligible today means every arrival shrinks everybody's payment and every
    /// departure grows it, so nobody can be told what they will receive. Fixing
    /// it means an unclaimed slot simply stays unclaimed.
    public let denominator: UInt64

    /// How slots are counted for this stream.
    public let rule: ReservePayoutRule

    /// What one payable slot is, singular: `member`, `pass`, `seat`.
    public let unitName: String

    /// Plural of ``unitName``.
    public let unitNamePlural: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: Stable ledger key.
    ///   - name: Display name; defaults to the id.
    ///   - share: Fraction of the reserve.
    ///   - denominator: Fixed slot count.
    ///   - rule: How slots are counted.
    ///   - unitName: What one slot is called; derived from `rule` when omitted.
    ///   - unitNamePlural: Plural; `unitName` plus `s` when omitted.
    public init(
        id: String,
        name: String? = nil,
        share: ReserveShare,
        denominator: UInt64,
        rule: ReservePayoutRule,
        unitName: String? = nil,
        unitNamePlural: String? = nil
    ) {
        let singular = unitName ?? (rule == .oncePerRecipient ? "recipient" : "unit")
        self.id = id
        self.name = name ?? id
        self.share = share
        self.denominator = denominator
        self.rule = rule
        self.unitName = singular
        self.unitNamePlural = unitNamePlural ?? "\(singular)s"
    }
}
