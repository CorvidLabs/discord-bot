import Foundation

/// Which of the host's collections a player holds, plus the account they were read
/// from.
///
/// Ids, not flags for two named collections. The original welded four booleans into
/// the type, which meant a host with three collections could not describe them and a
/// host with none was carrying somebody else's nouns around (`ADOPT-1.b`,
/// `ADOPT-1.c`). A collection id here is matched against ``GamePerks``, so a server
/// that owns nothing still plays: it simply matches no perk (`ADOPT-3`).
///
/// Membership only. The order perks apply in comes from the configuration, never
/// from this set, because a `Set`'s iteration order would make a seeded forage
/// unreplayable.
public struct GameHoldings: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// Collection ids the player holds at least one of.
    ///
    /// In the same normalised shape ``CollectionPerk/id`` is checked for:
    /// lowercase, and letters, digits and underscores. Not enforced here,
    /// because these arrive from whatever cache the host keeps and a reducer
    /// must not refuse a table over them, which is exactly why the perk side is
    /// the side that refuses.
    public var collectionIds: Set<String>

    /// The account the ids were read from. Empty when nothing is linked.
    ///
    /// A plain string. This layer never parses it, never validates it and never
    /// looks it up; it carries it so a card can name the account that earned a
    /// perk.
    public var address: String

    /// A picture this player holds, for the corner of a card.
    ///
    /// Read from whatever cache the host already keeps, never from a chain, so
    /// dealing a hand costs no request budget. Nil when there is none, or when the
    /// one they hold has no usable picture.
    public var pictureUrl: String?

    // MARK: - Initializers

    /// - Parameters:
    ///   - collectionIds: Ids the player holds at least one of.
    ///   - address: Account the ids were read from.
    ///   - pictureUrl: Picture for a card corner, if there is one.
    public init(
        collectionIds: Set<String> = [],
        address: String = "",
        pictureUrl: String? = nil
    ) {
        self.collectionIds = collectionIds
        self.address = address
        self.pictureUrl = pictureUrl
    }

    // MARK: - Public Methods

    /// No collections, no account. The ordinary case, not a degraded one: most
    /// players of most servers are here, and every game has to be worth playing
    /// from it (`ADOPT-3`, `PLAY-1`).
    public static let empty = GameHoldings()

    /// Whether the player holds anything from `collectionId`.
    public func holds(_ collectionId: String) -> Bool {
        collectionIds.contains(collectionId)
    }
}
