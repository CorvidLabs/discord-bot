import Foundation

/// One rung of a collection's stacked count ladder: hold this many pieces,
/// get this role.
///
/// The original had four of these written into an enum for one collection,
/// with the thresholds in the source. They are a list here for the same
/// reason the holder rungs are (ADOPT-1.b): the numbers were never a fact
/// about the software.
public struct CollectionCountRung: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The fewest pieces that reach this rung. Always at least one.
    public let minimumCount: Int

    /// The Discord role it grants.
    public let roleId: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - minimumCount: The fewest pieces that reach this rung.
    ///   - roleId: The Discord role it grants.
    public init(minimumCount: Int, roleId: String) {
        self.minimumCount = minimumCount
        self.roleId = roleId
    }
}

/// One named collection, how a piece of it is recognised on chain, and what
/// holding pieces of it earns.
///
/// The original had exactly two of these, welded in: their ids, their
/// creators, their match rules and which of the two drove which role were all
/// decided in the source. Fifty-seven places asked "is this that one specific
/// collection?" to work out what somebody had earned. Here a server has as
/// many collections as it has, each saying for itself what holding one is
/// worth.
///
/// The original also carried a policy flag separating a "pass" collection,
/// which drove one globally named role, from a "collectible" one, which was
/// forbidden from granting it. That distinction survives without the flag:
/// every collection carries its own ``roleId`` and its own ``countRungs``, so
/// there is no shared role for one collection to grant by accident.
public struct CollectionProfile: Sendable, Equatable, Hashable, Identifiable {

    // MARK: - Properties

    /// Stable key. Persisted, and used to look a collection up.
    public let id: String

    /// What a member sees.
    public let displayName: String

    /// The account that minted the pieces.
    ///
    /// Required, per collection. There is no default creator: a default here
    /// would be one project's mint account, and a server that forgot to set
    /// it would grant roles for holding somebody else's art.
    public let creatorAddress: String

    /// Pieces whose name starts with this, ignoring case. Nil matches any
    /// name.
    public let namePrefix: String?

    /// Pieces whose unit name is exactly this, ignoring case. Nil matches any
    /// unit name.
    public let unitName: String?

    /// The largest supply an asset may have and still be a piece of this
    /// collection.
    ///
    /// One by default, because a collection is usually 1-of-1 pieces and a
    /// creator's fungible token must not be counted as one of them by whoever
    /// happens to hold a million of it. It is configuration and not a rule,
    /// because "a piece has a supply of one" is a fact about some projects and
    /// not about collections: a collection minted as editions of twenty-five
    /// says so, rather than matching nothing at all and quietly costing every
    /// holder their roles.
    public let maxSupply: UInt64

    /// The role for holding at least one piece, or nil when holding one earns
    /// no badge of its own.
    public let roleId: String?

    /// Stacked count rungs, ascending. Empty when a count earns nothing.
    public let countRungs: [CollectionCountRung]

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: Stable key.
    ///   - displayName: What a member sees; the id when omitted.
    ///   - creatorAddress: The minting account. Required.
    ///   - namePrefix: Match rule on the piece's name.
    ///   - unitName: Match rule on the piece's unit name.
    ///   - maxSupply: The largest supply a piece may have. One by default.
    ///   - roleId: The badge for holding one.
    ///   - countRungs: Stacked count rungs, in any order; sorted here.
    public init(
        id: String,
        displayName: String? = nil,
        creatorAddress: String,
        namePrefix: String? = nil,
        unitName: String? = nil,
        maxSupply: UInt64 = 1,
        roleId: String? = nil,
        countRungs: [CollectionCountRung] = []
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.creatorAddress = creatorAddress
        self.namePrefix = namePrefix
        self.unitName = unitName
        self.maxSupply = maxSupply
        self.roleId = roleId
        self.countRungs = countRungs.sorted { $0.minimumCount < $1.minimumCount }
    }

    // MARK: - Public Methods

    /// True when an asset belongs to this collection.
    ///
    /// A supply ceiling is part of the rule and not an oversight: it is what
    /// keeps a creator's fungible token from being counted as one of their
    /// pieces by whoever happens to hold a million of it. The ceiling is
    /// ``maxSupply``, which the operator sets and which is one unless they do.
    ///
    /// - Parameters:
    ///   - creator: The asset's creator account.
    ///   - name: The asset's name, when it has one.
    ///   - unitName: The asset's unit name, when it has one.
    ///   - total: The asset's total supply.
    public func matches(creator: String, name: String?, unitName: String?, total: UInt64) -> Bool {
        guard total >= 1, total <= maxSupply else { return false }
        guard creator == creatorAddress else { return false }
        if let namePrefix {
            guard let name, name.lowercased().hasPrefix(namePrefix.lowercased()) else {
                return false
            }
        }
        if let expectedUnit = self.unitName {
            guard let unitName, unitName.lowercased() == expectedUnit.lowercased() else {
                return false
            }
        }
        return true
    }

    /// Every count rung this many pieces reaches.
    ///
    /// Stacked: somebody on the third rung keeps the two under it, the same
    /// way the holder ladder stacks.
    public func rungsToAssign(count: Int) -> [CollectionCountRung] {
        countRungs.filter { count >= $0.minimumCount }
    }

    /// Every role this collection can grant.
    public var allRoleIds: Set<String> {
        var ids = Set(countRungs.map(\.roleId))
        if let roleId {
            ids.insert(roleId)
        }
        return ids
    }
}

/// Every collection a server gates on.
public struct CollectionCatalog: Sendable, Equatable {

    // MARK: - Properties

    /// The collections, in the order they were configured.
    public let collections: [CollectionProfile]

    // MARK: - Initializers

    /// - Parameter collections: Every collection the server gates on.
    public init(collections: [CollectionProfile] = []) {
        self.collections = collections
    }

    // MARK: - Public Methods

    /// True when the server gates on nothing held in a collection.
    public var isEmpty: Bool { collections.isEmpty }

    /// The collection with this id, or nil.
    public func collection(id: String) -> CollectionProfile? {
        collections.first { $0.id == id }
    }

    /// The collection an asset belongs to, or nil for none of them.
    ///
    /// First match wins, in configured order, so an operator who writes two
    /// overlapping match rules gets the one they wrote first rather than an
    /// answer that depends on dictionary ordering.
    public func match(creator: String, name: String?, unitName: String?, total: UInt64) -> CollectionProfile? {
        collections.first { $0.matches(creator: creator, name: name, unitName: unitName, total: total) }
    }

    /// Every role any collection can grant.
    public var allRoleIds: Set<String> {
        collections.reduce(into: Set<String>()) { $0.formUnion($1.allRoleIds) }
    }
}
