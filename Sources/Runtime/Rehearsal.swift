import Chain
import Foundation
import Gating

/// The role rules run over members this invents, against the operator's own
/// configuration.
///
/// The point is what a contributor with no credentials can watch. It invents
/// **members and holdings only, never configuration**, so what they see work
/// is their own ladder, their own collections and their own pools rather than
/// somebody else's (BUILD-1.b, ADOPT-6.a). Nothing here opens a socket, a
/// store file or a connection.
public enum Rehearsal: Sendable {

    // MARK: - Public Methods

    /// The invented members, in the order they are printed.
    ///
    /// Chosen to cover the cases that are worth watching rather than to be
    /// realistic: somebody who has proved nothing, somebody on the bottom
    /// rung, somebody on the top one, somebody providing liquidity, and
    /// somebody whose balance nobody could read. The last one is the one that
    /// matters, because "unread" and "holds nothing" are the two cases that
    /// look alike and lead to opposite decisions (ROLE-1.a).
    ///
    /// - Parameter configuration: The operator's own.
    public static func members(configuration: GatingConfiguration) -> [(String, MemberHoldings)] {
        let token = configuration.token
        let ladder = configuration.ladder
        let lowest = ladder.rungs.first?.minimumBaseUnits ?? token.baseUnits(whole: 1)
        let highest = ladder.rungs.last?.minimumBaseUnits ?? token.baseUnits(whole: 1_000)
        let everyCollectionCounted = countsForEveryCollection(configuration, count: 1)

        var invented: [(String, MemberHoldings)] = []
        invented.append(
            (
                "has no proved account",
                MemberHoldings.unlinked(memberId: "member-unlinked", configuration: configuration)
            )
        )
        invented.append(
            (
                "proved an account and holds nothing",
                MemberHoldings(
                    memberId: "member-empty",
                    isVerified: true,
                    directBalance: .known(0),
                    liquidityPositions: .known([]),
                    collectionCounts: countsForEveryCollection(configuration, count: 0)
                )
            )
        )
        invented.append(
            (
                "holds just enough for the lowest rung",
                MemberHoldings(
                    memberId: "member-lowest",
                    isVerified: true,
                    directBalance: .known(lowest),
                    liquidityPositions: .known([]),
                    collectionCounts: countsForEveryCollection(configuration, count: 0)
                )
            )
        )
        invented.append(
            (
                "holds enough for the highest rung, and one piece of every collection",
                MemberHoldings(
                    memberId: "member-highest",
                    isVerified: true,
                    directBalance: .known(highest),
                    liquidityPositions: .known([]),
                    collectionCounts: everyCollectionCounted
                )
            )
        )
        if !configuration.pools.isEmpty {
            invented.append(
                (
                    "holds nothing directly and has a position in every pool",
                    MemberHoldings(
                        memberId: "member-provider",
                        isVerified: true,
                        directBalance: .known(0),
                        liquidityPositions: .known(
                            configuration.pools.pools.map { pool in
                                LiquidityPosition(
                                    poolId: pool.id,
                                    lpBaseUnits: 1,
                                    tokenBaseUnits: lowest
                                )
                            }
                        ),
                        collectionCounts: countsForEveryCollection(configuration, count: 0)
                    )
                )
            )
        }
        invented.append(
            (
                "had their balance go unread this time",
                MemberHoldings(
                    memberId: "member-unread",
                    isVerified: true,
                    directBalance: .unknown,
                    liquidityPositions: .known([]),
                    collectionCounts: countsForEveryCollection(configuration, count: 0)
                )
            )
        )
        return invented
    }

    /// The whole rehearsal as report sections.
    ///
    /// - Parameter configuration: The operator's own.
    public static func report(configuration: GatingConfiguration) -> [ReportSection] {
        var sections: [ReportSection] = [
            ReportSection(
                title: "Rehearsal",
                lines: [
                    "Your ladder, your collections and your pools, against members and holdings "
                        + "this invented. Nothing was read, nothing was written and nobody was "
                        + "granted anything.",
                    "A member starts with no roles, so `keeps` is empty for everybody here; in a "
                        + "real sweep it is what a hand-granted badge falls into."
                ]
            )
        ]
        for (description, holdings) in members(configuration: configuration) {
            let decision = RoleRules.decide(
                configuration: configuration,
                holdings: holdings,
                currentRoleIds: []
            )
            sections.append(
                ReportSection(title: "A member who \(description)", lines: lines(of: decision))
            )
        }
        return sections
    }

    // MARK: - Private Methods

    private static func lines(of decision: RoleDecision) -> [String] {
        var lines: [String] = []
        switch decision.standing {
        case .on(let tier):
            lines.append("Standing: \(tier.name)")
        case .unranked:
            lines.append("Standing: on no rung, and that was read rather than assumed")
        case .unread:
            lines.append("Standing: nobody read it, which is not the bottom of the ladder")
        }
        lines.append("Grants: \(list(decision.granted))")
        lines.append("Revokes: \(list(decision.revoked))")
        lines.append("Keeps, because this decision does not manage them: \(list(decision.held))")
        for unknown in decision.unknowns {
            lines.append("Not read: \(unknown.sentence)")
        }
        return lines
    }

    private static func list(_ roleIds: Set<String>) -> String {
        roleIds.isEmpty ? "nothing" : roleIds.sorted().joined(separator: ", ")
    }

    private static func countsForEveryCollection(
        _ configuration: GatingConfiguration,
        count: Int
    ) -> [String: Reading<Int>] {
        var counts: [String: Reading<Int>] = [:]
        for collection in configuration.collections.collections {
            counts[collection.id] = .known(count)
        }
        return counts
    }
}
