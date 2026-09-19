import Foundation

/// Builds a ``CollectionCatalog`` from numbered variables.
///
/// ```
/// COLLECTION_1_ID=passes
/// COLLECTION_1_NAME=Passes
/// COLLECTION_1_CREATOR=...        # required: the minting account
/// COLLECTION_1_UNIT_NAME=pass     # optional match rule
/// COLLECTION_1_NAME_PREFIX=Pass   # optional match rule
/// COLLECTION_1_MAX_SUPPLY=1       # optional; editions of 25 set 25
/// COLLECTION_1_ROLE_ID=...        # holding one earns this
/// COLLECTION_1_COUNT_1_MIN=50     # and holding fifty also earns this
/// COLLECTION_1_COUNT_1_ROLE_ID=...
/// ```
///
/// Collections are read from `COLLECTION_1_` upward and the count rungs of
/// each from `_COUNT_1_` upward, both stopping at the first gap, for the same
/// reason the ladder does: a typo should drop an entry visibly rather than
/// renumber the ones above it silently.
///
/// A server with no collections sets none of this and gets an empty
/// catalogue. Unlike the ladder, that is not a refusal: gating on a balance
/// alone is an ordinary way to run a server.
public enum CollectionConfiguration: Sendable {

    // MARK: - Public Methods

    /// Reads the catalogue from a dictionary. The shape tests use.
    public static func load(from environment: [String: String]) throws -> CollectionCatalog {
        try load { environment[$0] }
    }

    /// Reads the catalogue, or says which variable is wrong.
    public static func load(_ lookup: (String) -> String?) throws -> CollectionCatalog {
        var collections: [CollectionProfile] = []
        var seenIds: [String: String] = [:]

        for index in 1...NumberedEnvironment.maxEntries {
            let prefix = "COLLECTION_\(index)_"
            let idKey = "\(prefix)ID"
            guard let rawId = NumberedEnvironment.nonEmpty(idKey, lookup) else { break }
            guard let id = NumberedEnvironment.slug(rawId) else {
                throw GatingConfigurationError.unusableName(key: idKey, value: rawId)
            }
            if let first = seenIds[id] {
                throw GatingConfigurationError.duplicateId(id: id, first: first, second: idKey)
            }
            seenIds[id] = idKey

            // Required, with no default, and this is the one that matters
            // most. A missing creator in the original fell back to a literal
            // mint account written into the source, so a server that never
            // set it granted roles for holding another project's pieces.
            let creator = try NumberedEnvironment.required(
                "\(prefix)CREATOR",
                purpose: "It is the account that minted collection \(index), and it is how a "
                    + "piece of it is told apart from every other asset on chain.",
                lookup
            )

            // How big a supply still counts as one piece. One unless the
            // operator says otherwise, because a collection minted as
            // editions is an ordinary collection and a rule written into the
            // source would match none of it while saying nothing.
            let supplyKey = "\(prefix)MAX_SUPPLY"
            var maxSupply: UInt64 = 1
            if NumberedEnvironment.nonEmpty(supplyKey, lookup) != nil {
                maxSupply = try NumberedEnvironment.requiredWholeNumber(
                    supplyKey,
                    purpose: "It is the largest supply an asset may have and still be a piece of "
                        + "collection \(index).",
                    lookup
                )
                guard maxSupply > 0 else {
                    throw GatingConfigurationError.zeroSupply(key: supplyKey)
                }
            }

            collections.append(
                CollectionProfile(
                    id: id,
                    displayName: NumberedEnvironment.nonEmpty("\(prefix)NAME", lookup),
                    creatorAddress: creator,
                    namePrefix: NumberedEnvironment.nonEmpty("\(prefix)NAME_PREFIX", lookup),
                    unitName: NumberedEnvironment.nonEmpty("\(prefix)UNIT_NAME", lookup),
                    maxSupply: maxSupply,
                    roleId: NumberedEnvironment.nonEmpty("\(prefix)ROLE_ID", lookup),
                    countRungs: try loadCountRungs(prefix: prefix, lookup)
                )
            )
        }

        if collections.count == NumberedEnvironment.maxEntries {
            try NumberedEnvironment.refuseOverflow(
                "COLLECTION_\(NumberedEnvironment.maxEntries + 1)_ID",
                lookup
            )
        }
        return CollectionCatalog(collections: collections)
    }

    // MARK: - Private Methods

    /// Reads one collection's stacked count rungs.
    ///
    /// A rung's role is required, unlike a holder rung's. A holder rung with
    /// no role still shows on a card and in a leaderboard, so it earns its
    /// place; a count rung with no role does nothing at all, and an operator
    /// who wrote one meant to give it a role and mistyped the variable
    /// (ADOPT-2).
    private static func loadCountRungs(
        prefix: String,
        _ lookup: (String) -> String?
    ) throws -> [CollectionCountRung] {
        var rungs: [CollectionCountRung] = []
        var seenMinimums: [UInt64: String] = [:]

        for index in 1...NumberedEnvironment.maxEntries {
            let rungPrefix = "\(prefix)COUNT_\(index)_"
            let minKey = "\(rungPrefix)MIN"
            guard NumberedEnvironment.nonEmpty(minKey, lookup) != nil else { break }
            let minimum = try NumberedEnvironment.requiredWholeNumber(
                minKey,
                purpose: "It is how many pieces reach this rung.",
                lookup
            )
            guard minimum > 0 else {
                throw GatingConfigurationError.zeroMinimum(key: minKey)
            }
            if let first = seenMinimums[minimum] {
                throw GatingConfigurationError.duplicateMinimum(
                    minimum: minimum,
                    first: first,
                    second: minKey
                )
            }
            seenMinimums[minimum] = minKey

            let roleKey = "\(rungPrefix)ROLE_ID"
            let roleId = try NumberedEnvironment.required(
                roleKey,
                purpose: "\(minKey) is set, so this rung needs a role to grant; a count rung "
                    + "without one does nothing at all.",
                lookup
            )
            // `Int` because a count of pieces is counted, not weighed, and
            // every caller holds it as one. A minimum past `Int.max` is a
            // rung nobody reaches either way.
            rungs.append(
                CollectionCountRung(
                    minimumCount: minimum > UInt64(Int.max) ? Int.max : Int(minimum),
                    roleId: roleId
                )
            )
        }

        if rungs.count == NumberedEnvironment.maxEntries {
            try NumberedEnvironment.refuseOverflow(
                "\(prefix)COUNT_\(NumberedEnvironment.maxEntries + 1)_MIN",
                lookup
            )
        }
        return rungs
    }
}
