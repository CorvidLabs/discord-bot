import Foundation

/// A ladder and the Discord role each rung grants.
public struct LoadedTiers: Sendable, Equatable {

    // MARK: - Properties

    /// The rungs, in order.
    public let ladder: TierLadder

    /// Discord role id per rung id. A rung with no role configured is simply
    /// absent, which is a ladder used for cards and leaderboards but not for
    /// roles. That is a legitimate configuration, not a mistake, and it is
    /// indistinguishable from a mistyped `TIER_n_ROLE_ID`, which is what
    /// ``rungsWithoutRoles`` is for.
    public let roleIds: [String: String]

    // MARK: - Initializers

    /// - Parameters:
    ///   - ladder: The rungs, in order.
    ///   - roleIds: Discord role id per rung id.
    public init(ladder: TierLadder, roleIds: [String: String]) {
        self.ladder = ladder
        self.roleIds = roleIds
    }

    // MARK: - Public Methods

    /// The rungs the operator gave no role, in ladder order.
    ///
    /// A rung with no role is legitimate, and empty here is the usual answer.
    /// But a mistyped `TIER_n_ROLE_ID` looks exactly the same from inside:
    /// the rung grants nothing, so it is in no decision's managed set and in
    /// no decision's held set either, and nothing an operator can look at
    /// would ever mention it. This is the one place it is visible, so a
    /// boundary reads it at boot and says it once.
    public var rungsWithoutRoles: [Tier] {
        ladder.rungs.filter { roleIds[$0.id] == nil }
    }
}

/// Builds a server's ``TierLadder`` from numbered variables.
///
/// ```
/// TIER_1_NAME=Holder
/// TIER_1_MIN=100          # whole tokens, not smallest units
/// TIER_1_EMOJI=(a)
/// TIER_1_ROLE_ID=...      # the Discord role
/// TIER_1_ID=holder        # optional; a slug of the name otherwise
/// ```
///
/// Rungs are read from `TIER_1_` upward and stop at the first gap, so a
/// mistyped `TIER_4_NAME` drops rung four and everything above it rather than
/// silently renumbering (ADOPT-1.a). A bad rung stops the load and names the
/// variable to fix (ADOPT-2).
///
/// **There is no default ladder.** The original shipped six rungs at one
/// project's thresholds and fell back to them whenever `TIER_1_NAME` was
/// unset, which was right for that project and is a trap for anybody else: a
/// server with no ladder configured would quietly grant roles at somebody
/// else's numbers. Set nothing here and the load refuses, naming
/// `TIER_1_NAME`.
public enum TierConfiguration: Sendable {

    // MARK: - Properties

    /// The variable that starts the ladder.
    public static let firstRungKey = "TIER_1_NAME"

    /// The variable naming what a member on no rung is called.
    public static let unrankedNameKey = "TIER_UNRANKED_NAME"

    /// The variable naming the emoji beside it.
    public static let unrankedEmojiKey = "TIER_UNRANKED_EMOJI"

    // MARK: - Public Methods

    /// Reads the ladder from a dictionary. The shape tests use.
    public static func load(from environment: [String: String], token: TokenProfile) throws -> LoadedTiers {
        try load({ environment[$0] }, token: token)
    }

    /// Reads the ladder, or says what is wrong with it.
    ///
    /// - Parameters:
    ///   - lookup: Reads one variable. A lookup rather than a dictionary so a
    ///     caller can pass its own environment through without copying it.
    ///   - token: Turns each rung's whole-token minimum into base units. Every
    ///     threshold in the module is converted here and nowhere else, which
    ///     is what makes a two-decimal asset behave like a two-decimal asset.
    public static func load(_ lookup: (String) -> String?, token: TokenProfile) throws -> LoadedTiers {
        guard NumberedEnvironment.nonEmpty(firstRungKey, lookup) != nil else {
            throw GatingConfigurationError.missing(
                key: firstRungKey,
                purpose: "It is the first rung of your holder ladder, and the ladder is yours: "
                    + "your names, your thresholds, as many rungs as you want."
            )
        }

        var rungs: [Tier] = []
        var roleIds: [String: String] = [:]
        var seenIds: [String: String] = [:]
        var seenNames: [String: String] = [:]
        var seenMinimums: [UInt64: String] = [:]

        for index in 1...NumberedEnvironment.maxEntries {
            let prefix = "TIER_\(index)_"
            let nameKey = "\(prefix)NAME"
            // The first gap ends the ladder. Skipping it and carrying on would
            // renumber every rung above a typo without saying so.
            guard let name = NumberedEnvironment.nonEmpty(nameKey, lookup) else { break }

            let minKey = "\(prefix)MIN"
            let whole = try NumberedEnvironment.requiredWholeNumber(
                minKey,
                purpose: "It is the smallest holding on rung \(index), in whole tokens.",
                lookup
            )
            guard whole > 0 else {
                throw GatingConfigurationError.zeroMinimum(key: minKey)
            }
            // Compared as what the rung is actually decided by, not as what
            // was typed. Two different whole numbers that are both past what
            // this token's precision can express land on the same ceiling, and
            // comparing the typed numbers would let that ladder load: two
            // rungs at one threshold, one of them unreachable, nothing said.
            let minimumBaseUnits = token.baseUnits(whole: whole)
            if let first = seenMinimums[minimumBaseUnits] {
                throw GatingConfigurationError.duplicateMinimum(minimum: whole, first: first, second: minKey)
            }
            seenMinimums[minimumBaseUnits] = minKey

            // Two rungs sharing a display name would be merged by everything
            // that counts them, because a stored row records the name.
            let foldedName = name.lowercased()
            if let first = seenNames[foldedName] {
                throw GatingConfigurationError.duplicateName(name: name, first: first, second: nameKey)
            }
            seenNames[foldedName] = nameKey

            // The key the operator actually set, so an error sends them to a
            // variable they have heard of rather than one they never wrote.
            let idKey = "\(prefix)ID"
            let id: String
            let idSource: String
            if let explicit = NumberedEnvironment.nonEmpty(idKey, lookup) {
                guard let slug = NumberedEnvironment.slug(explicit) else {
                    throw GatingConfigurationError.unusableName(key: idKey, value: explicit)
                }
                id = slug
                idSource = idKey
            } else {
                guard let slug = NumberedEnvironment.slug(name) else {
                    throw GatingConfigurationError.unusableName(key: nameKey, value: name)
                }
                id = slug
                idSource = nameKey
            }
            if let first = seenIds[id] {
                throw GatingConfigurationError.duplicateId(id: id, first: first, second: idSource)
            }
            seenIds[id] = idSource

            rungs.append(
                Tier(
                    id: id,
                    name: name,
                    emoji: NumberedEnvironment.nonEmpty("\(prefix)EMOJI", lookup) ?? "",
                    minimumBaseUnits: minimumBaseUnits
                )
            )
            if let roleId = NumberedEnvironment.nonEmpty("\(prefix)ROLE_ID", lookup) {
                roleIds[id] = roleId
            }
        }

        if rungs.count == NumberedEnvironment.maxEntries {
            try NumberedEnvironment.refuseOverflow("TIER_\(NumberedEnvironment.maxEntries + 1)_NAME", lookup)
        }

        // The word for holding too little is a label, not a rung: it has no
        // threshold and no role. A rung that shares it is the shape the
        // original refused by reserving an id, and it is worth refusing for
        // the same reason: a stored row naming it resolves to the rung, and
        // somebody on no rung at all is granted that rung's role.
        let unrankedName = NumberedEnvironment.nonEmpty(unrankedNameKey, lookup) ?? "None"
        let foldedUnranked = unrankedName.lowercased()
        let unrankedSlug = NumberedEnvironment.slug(unrankedName)
        if let clash = rungs.first(where: { $0.name.lowercased() == foldedUnranked || $0.id == unrankedSlug }) {
            throw GatingConfigurationError.duplicateName(
                name: unrankedName,
                first: unrankedNameKey,
                second: seenNames[clash.name.lowercased()] ?? seenIds[clash.id] ?? unrankedNameKey
            )
        }

        return LoadedTiers(
            ladder: TierLadder(
                rungs: rungs,
                unrankedName: unrankedName,
                unrankedEmoji: NumberedEnvironment.nonEmpty(unrankedEmojiKey, lookup) ?? ""
            ),
            roleIds: roleIds
        )
    }
}
