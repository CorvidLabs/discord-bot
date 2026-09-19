import Foundation

/// What this layer was told about one of the host's collections.
///
/// Three answers, because two are not enough. "Holds none of it" and "nobody
/// could read it" lead to opposite decisions and a `Bool` collapses them into
/// the first one, silently, at whatever moment the host's cache is having a bad
/// afternoon. The member is then treated as holding nothing, loses the perks
/// they paid for and is told nothing about why.
///
/// It is the same distinction the role rules keep, and it is written out again
/// here rather than shared, because this module depends on Foundation alone and
/// that independence is worth more than the dozen lines it costs (`PLAY-9`).
public enum GameHoldingReading: Sendable, Equatable {

    /// The player is known to hold at least one.
    case held

    /// The player is known to hold none.
    case notHeld

    /// Nobody could read it. Not zero, and not none.
    case unknown
}

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

    /// Collection ids somebody asked about for this player and could not answer.
    ///
    /// Empty is the ordinary case and means "everything asked about was read",
    /// **not** "nothing was unreadable because nobody checked". A host that
    /// cannot tell the difference should put the ids it asked about and failed
    /// on in here; one that never fails never touches it.
    ///
    /// An id in both sets is held: positive evidence beats a failed read, and
    /// that is the case where a second lookup succeeded after a first did not.
    public var unreadableCollectionIds: Set<String>

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
    ///   - unreadableCollectionIds: Ids that were asked about and could not be
    ///     read. Empty means everything asked about was answered.
    ///   - address: Account the ids were read from.
    ///   - pictureUrl: Picture for a card corner, if there is one.
    public init(
        collectionIds: Set<String> = [],
        unreadableCollectionIds: Set<String> = [],
        address: String = "",
        pictureUrl: String? = nil
    ) {
        self.collectionIds = collectionIds
        self.unreadableCollectionIds = unreadableCollectionIds
        self.address = address
        self.pictureUrl = pictureUrl
    }

    /// Decoded by hand for one reason: a table written down before this type
    /// could say "unreadable" has no such key, and it must read back as a
    /// player nothing failed for rather than refusing to load.
    ///
    /// The other keys stay required. A row missing its collections is a row
    /// that will not decode, which is what should happen: reading it as a
    /// player who holds nothing is the silent demotion this whole type is
    /// arranged against.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.collectionIds = try container.decode(Set<String>.self, forKey: .collectionIds)
        self.unreadableCollectionIds = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .unreadableCollectionIds
        ) ?? []
        self.address = try container.decode(String.self, forKey: .address)
        self.pictureUrl = try container.decodeIfPresent(String.self, forKey: .pictureUrl)
    }

    // MARK: - Public Methods

    /// No collections, no account, nothing that failed to be read. The ordinary
    /// case, not a degraded one: most players of most servers are here, and
    /// every game has to be worth playing from it (`ADOPT-3`, `PLAY-1`).
    public static let empty = GameHoldings()

    /// Whether the player is **known** to hold anything from `collectionId`.
    ///
    /// False for a collection nobody could read, which is why this is not the
    /// question a decision should be made on by itself. It is the right
    /// question for granting something and the wrong one for withholding it:
    /// ask ``reading(of:)`` when the difference matters.
    public func holds(_ collectionId: String) -> Bool {
        collectionIds.contains(collectionId)
    }

    /// What is known about one collection: held, not held, or unreadable.
    public func reading(of collectionId: String) -> GameHoldingReading {
        if collectionIds.contains(collectionId) { return .held }
        if unreadableCollectionIds.contains(collectionId) { return .unknown }
        return .notHeld
    }

    /// Whether anything about this player could not be read.
    public var hasUnreadableCollections: Bool {
        !unreadableCollectionIds.isEmpty
    }

    // MARK: - Private Methods

    private enum CodingKeys: String, CodingKey {
        case collectionIds
        case unreadableCollectionIds
        case address
        case pictureUrl
    }
}
