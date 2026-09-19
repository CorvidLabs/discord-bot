import Foundation
import Testing
@testable import Gating

/// The decision: what a member should be holding, and what happens when
/// nobody could find out.
@Suite("Role rules")
struct RoleRulesTests {

    private static func decide(
        _ holdings: MemberHoldings,
        current: Set<String> = [],
        configuration: GatingConfiguration? = nil
    ) throws -> RoleDecision {
        RoleRules.decide(
            configuration: try configuration ?? Fixture.configuration(),
            holdings: holdings,
            currentRoleIds: current
        )
    }

    // MARK: - The ladder

    @Test("Holding enough earns the rung and everything under it")
    func rungsStack() throws {
        let decision = try Self.decide(Fixture.member(direct: 10_000))
        #expect(decision.granted == [Fixture.bronze, Fixture.silver, Fixture.gold, Fixture.verified])
        #expect(decision.revoked.isEmpty)
        #expect(decision.disposition == .changed)
        #expect(decision.standing.tier?.id == "gold")
    }

    @Test("Selling down to nothing takes the rungs back")
    func sellingDownRevokes() throws {
        let decision = try Self.decide(
            Fixture.member(direct: 0),
            current: [Fixture.bronze, Fixture.silver, Fixture.verified]
        )
        #expect(decision.revoked == [Fixture.bronze, Fixture.silver])
        #expect(decision.granted.isEmpty)
        #expect(decision.standing == .unranked)
    }

    @Test("A member already holding exactly the right roles is left alone")
    func nothingToDo() throws {
        let decision = try Self.decide(
            Fixture.member(direct: 1_000),
            current: [Fixture.bronze, Fixture.silver, Fixture.verified]
        )
        #expect(decision.disposition == .unchanged)
        #expect(decision.granted.isEmpty)
        #expect(decision.revoked.isEmpty)
        #expect(decision.target == [Fixture.bronze, Fixture.silver, Fixture.verified])
    }

    // MARK: - Pooled holdings count (ROLE-2)

    @Test("What I have parked in a pool counts toward my rung the same as what sits in my wallet")
    func liquidityCountsTowardTheLadder() throws {
        // Ninety in the wallet is below the bottom rung. The same member with
        // another twenty in a pool is a Bronze holder, because putting the
        // token in a pool is not selling it.
        let walletOnly = try Self.decide(Fixture.member(direct: 90))
        #expect(walletOnly.standing == .unranked)

        let pooled = try Self.decide(
            Fixture.member(direct: 90, positions: [Fixture.position(Fixture.usdPool, tokens: 20)])
        )
        #expect(pooled.standing.tier?.id == "bronze")
        #expect(pooled.combinedBalance == .known(Fixture.whole(110)))
        #expect(pooled.granted.contains(Fixture.bronze))
    }

    @Test("Pooled holdings add up across every pool")
    func liquiditySumsAcrossPools() throws {
        let decision = try Self.decide(
            Fixture.member(
                direct: 0,
                positions: [
                    Fixture.position(Fixture.usdPool, tokens: 600),
                    Fixture.position(Fixture.eurPool, tokens: 600)
                ]
            )
        )
        #expect(decision.combinedBalance == .known(Fixture.whole(1_200)))
        #expect(decision.standing.tier?.id == "silver")
    }

    @Test("Providing earns the provider badge, and the badge of the pool provided to")
    func liquidityBadges() throws {
        let decision = try Self.decide(
            Fixture.member(direct: 0, positions: [Fixture.position(Fixture.usdPool, lp: 5, tokens: 1)])
        )
        #expect(decision.granted.contains(Fixture.providerBadge))
        #expect(decision.granted.contains(Fixture.poolBadge))

        // The other pool has no badge of its own, so providing to it earns
        // the provider badge alone.
        let other = try Self.decide(
            Fixture.member(direct: 0, positions: [Fixture.position(Fixture.eurPool, lp: 5, tokens: 1)])
        )
        #expect(other.granted.contains(Fixture.providerBadge))
        #expect(other.granted.contains(Fixture.poolBadge) == false)
    }

    @Test("Withdrawing from a pool takes the pool badges back")
    func withdrawingRevokesBadges() throws {
        let decision = try Self.decide(
            Fixture.member(direct: 0, positions: []),
            current: [Fixture.providerBadge, Fixture.poolBadge, Fixture.verified]
        )
        #expect(decision.revoked == [Fixture.providerBadge, Fixture.poolBadge])
    }

    // MARK: - Collections

    @Test("Holding one piece earns that collection's badge")
    func collectionBadge() throws {
        let decision = try Self.decide(Fixture.member(direct: 0, passes: 1))
        #expect(decision.granted.contains(Fixture.passBadge))

        let without = try Self.decide(
            Fixture.member(direct: 0, passes: 0),
            current: [Fixture.passBadge]
        )
        #expect(without.revoked == [Fixture.passBadge])
    }

    @Test("Holding more pieces of a collection earns more of its roles, and keeps the earlier ones")
    func collectionCountRungs() throws {
        let decision = try Self.decide(Fixture.member(direct: 0, pals: 12))
        #expect(decision.granted.contains(Fixture.palOne))
        #expect(decision.granted.contains(Fixture.palTen))
        #expect(decision.granted.contains(Fixture.palFifty) == false)
    }

    @Test("One collection's roles do not follow from another's")
    func collectionsAreSeparate() throws {
        let decision = try Self.decide(Fixture.member(direct: 0, passes: 3, pals: 0))
        #expect(decision.granted.contains(Fixture.passBadge))
        #expect(decision.granted.contains(Fixture.palOne) == false)
    }

    // MARK: - An unread fact is not a zero (ROLE-1.a)

    @Test("A member whose balance nobody could read keeps the rung they had")
    func unreadBalanceKeepsTheRung() throws {
        // The failure that actually matters: silence from a data provider is
        // not evidence that somebody sold up. Reading it as zero is what
        // dropped a member several rungs for an outage that lasted a minute.
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .unknown,
            liquidityPositions: .known([]),
            collectionCounts: [Fixture.passes: .known(0), Fixture.pals: .known(0)]
        )
        let decision = try Self.decide(holdings, current: [Fixture.bronze, Fixture.silver, Fixture.verified])

        #expect(decision.revoked.isEmpty)
        #expect(decision.target.contains(Fixture.bronze))
        #expect(decision.target.contains(Fixture.silver))
        #expect(decision.standing == .unread)
        #expect(decision.unknowns == [.balance])
        #expect(decision.held == [Fixture.bronze, Fixture.silver, Fixture.gold])
        #expect(decision.isComplete == false)
    }

    @Test("A member who was read and holds nothing does lose the rung")
    func readZeroDoesRevoke() throws {
        // The other half of the previous test. If an unknown and a zero both
        // preserved the roles, nobody would ever be demoted; if both revoked
        // them, an outage would demote the server. They have to differ.
        let decision = try Self.decide(
            Fixture.member(direct: 0),
            current: [Fixture.bronze, Fixture.silver, Fixture.verified]
        )
        #expect(decision.revoked == [Fixture.bronze, Fixture.silver])
        #expect(decision.standing == .unranked)
        #expect(decision.isComplete)
        #expect(decision.held.isEmpty)
    }

    @Test("A pooled position nobody could read holds the ladder rather than shortening the total")
    func unreadLiquidityHoldsTheLadder() throws {
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(Fixture.whole(90)),
            liquidityPositions: .unknown,
            collectionCounts: [Fixture.passes: .known(0), Fixture.pals: .known(0)]
        )
        let decision = try Self.decide(holdings, current: [Fixture.bronze, Fixture.providerBadge])

        // Ninety alone is below the bottom rung, and that is exactly the
        // trap: the missing figure is the one that would have kept them on it.
        #expect(decision.revoked.isEmpty)
        #expect(decision.combinedBalance == .unknown)
        #expect(decision.unknowns == [.liquidityPositions])
        #expect(decision.target.contains(Fixture.bronze))
        #expect(decision.target.contains(Fixture.providerBadge))
    }

    @Test("A collection nobody could count holds its own roles and lets the rest be decided")
    func unreadCollectionHoldsOnlyItself() throws {
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(Fixture.whole(1_000)),
            liquidityPositions: .known([]),
            collectionCounts: [Fixture.passes: .known(0), Fixture.pals: .unknown]
        )
        let decision = try Self.decide(holdings, current: [Fixture.palOne, Fixture.passBadge])

        #expect(decision.unknowns == [.collection(id: Fixture.pals)])
        #expect(decision.held == [Fixture.palOne, Fixture.palTen, Fixture.palFifty])
        // The unread collection keeps its role.
        #expect(decision.target.contains(Fixture.palOne))
        // Everything that was read is still decided: the pass badge goes,
        // the rungs arrive.
        #expect(decision.revoked == [Fixture.passBadge])
        #expect(decision.granted.contains(Fixture.silver))
    }

    @Test("A collection nobody asked about is unknown, never nought")
    func absentCountIsUnknown() throws {
        // A caller that simply forgot a collection must not strip its roles.
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(0),
            liquidityPositions: .known([]),
            collectionCounts: [:]
        )
        #expect(holdings.count(ofCollection: Fixture.passes) == .unknown)

        let decision = try Self.decide(holdings, current: [Fixture.passBadge, Fixture.palOne])
        #expect(decision.revoked.isEmpty)
        #expect(decision.unknowns.count == 2)
    }

    @Test("A sweep that read nothing about somebody takes nothing away from them")
    func everythingUnknown() throws {
        // Everything on chain is unread, so every role those facts decide is
        // held. The verified badge is decided by this bot's own record rather
        // than by a read, so it is still granted, and the caller had to say
        // so: `isVerified` is the one field of `MemberHoldings` with no
        // default, because a caller who said nothing used to be taken to mean
        // yes and the badge went out on a sweep that read nothing.
        let holdings = MemberHoldings(memberId: "member-1", isVerified: true)
        let current: Set<String> = [Fixture.gold, Fixture.passBadge, Fixture.providerBadge]
        let decision = try Self.decide(holdings, current: current)

        #expect(decision.target == current.union([Fixture.verified]))
        #expect(decision.revoked.isEmpty)
        #expect(decision.granted == [Fixture.verified])
        #expect(decision.disposition == .changed)
        #expect(decision.unknowns.count == 4)
    }

    @Test("The verified badge follows what the caller said, and there is nothing else it could follow")
    func verificationIsAlwaysStated() throws {
        // Two members, identical but for the one field, and the field decides
        // the badge both ways. Neither answer is safe as a default: yes grants
        // a badge on a sweep that read nothing, no takes it off everybody who
        // has one, so `MemberHoldings` makes the caller say which.
        let said = try Self.decide(
            MemberHoldings(memberId: "member-1", isVerified: true),
            current: []
        )
        let saidNot = try Self.decide(
            MemberHoldings(memberId: "member-1", isVerified: false),
            current: [Fixture.verified]
        )
        #expect(said.granted == [Fixture.verified])
        #expect(saidNot.revoked == [Fixture.verified])
        #expect(saidNot.granted.isEmpty)
    }

    @Test("An unread fact is reported once, however many roles it was holding")
    func unknownsAreNotRepeated() throws {
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(0),
            liquidityPositions: .unknown,
            collectionCounts: [Fixture.passes: .known(0), Fixture.pals: .known(0)]
        )
        let decision = try Self.decide(holdings)
        // The positions decide both the ladder and the pool badges; an
        // operator reading the sweep should be told once.
        #expect(decision.unknowns == [.liquidityPositions])
    }

    @Test("A badge two collections grant is not taken away because only one of them was counted")
    func sharedBadgeSurvivesAnUnreadCollection() throws {
        // Two collections sharing one badge is an ordinary configuration, and
        // nothing at load forbids it. The collection that WAS counted must not
        // put the shared badge into the managed set on its own, or an outage
        // over the other one takes the badge off somebody who still holds
        // three of it.
        let configuration = try Fixture.configuration(overriding: [
            "COLLECTION_2_ROLE_ID": Fixture.passBadge
        ])
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(0),
            liquidityPositions: .known([]),
            collectionCounts: [Fixture.passes: .known(0), Fixture.pals: .unknown]
        )
        let decision = try Self.decide(
            holdings,
            current: [Fixture.passBadge, Fixture.verified],
            configuration: configuration
        )

        #expect(decision.revoked.isEmpty)
        #expect(decision.target.contains(Fixture.passBadge))
        #expect(decision.held.contains(Fixture.passBadge))
        #expect(decision.unknowns == [.collection(id: Fixture.pals)])
    }

    @Test("A badge the ladder and the pools both grant survives a balance nobody could read")
    func sharedBadgeSurvivesAnUnreadBalance() throws {
        // The same overlap the other way round: an operator who points
        // LP_PROVIDER_ROLE_ID at a rung's role. The positions were read and
        // say the member provides nothing, but the balance that also decides
        // that role was not read, so the role is nobody's to take away.
        let configuration = try Fixture.configuration(overriding: [
            "LP_PROVIDER_ROLE_ID": Fixture.bronze
        ])
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .unknown,
            liquidityPositions: .known([]),
            collectionCounts: [Fixture.passes: .known(0), Fixture.pals: .known(0)]
        )
        let decision = try Self.decide(
            holdings,
            current: [Fixture.bronze, Fixture.poolBadge],
            configuration: configuration
        )

        #expect(decision.revoked == [Fixture.poolBadge])
        #expect(decision.target.contains(Fixture.bronze))
        #expect(decision.held.contains(Fixture.bronze))
    }

    @Test("A read fact still grants a badge it shares with one nobody could read")
    func sharedBadgeIsStillGranted() throws {
        let configuration = try Fixture.configuration(overriding: [
            "COLLECTION_2_ROLE_ID": Fixture.passBadge
        ])
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(0),
            liquidityPositions: .known([]),
            collectionCounts: [Fixture.passes: .known(2), Fixture.pals: .unknown]
        )
        let decision = try Self.decide(holdings, configuration: configuration)
        #expect(decision.granted.contains(Fixture.passBadge))
        #expect(decision.revoked.isEmpty)
        // Holding a role back from the managed set must not smuggle a grant
        // past it: what this decision adds, it is entitled to add.
        #expect(decision.granted.isSubset(of: decision.managed))
    }

    // MARK: - A server with no pools

    @Test("A server that counts no pools decides the ladder from the balance alone")
    func noPoolsMeansNoPooledHalfToWaitFor() throws {
        // Nothing reads positions in a server with no pools, so the natural
        // caller leaves them unread. Insisting on both halves there freezes
        // every ladder in the server for ever.
        let configuration = try GatingConfiguration.load(from: [
            "TOKEN_ASSET_ID": "7001",
            "TOKEN_SYMBOL": "TOKEN",
            "TOKEN_DECIMALS": "0",
            "TIER_1_NAME": "Member",
            "TIER_1_MIN": "1",
            "TIER_1_ROLE_ID": "role-member"
        ])
        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: MemberHoldings(memberId: "member-1", isVerified: true, directBalance: .known(5)),
            currentRoleIds: []
        )

        #expect(decision.granted == ["role-member"])
        #expect(decision.combinedBalance == .known(5))
        #expect(decision.standing.tier?.id == "member")
        #expect(decision.unknowns.isEmpty)
    }

    @Test("A server that does count pools still waits for them")
    func configuredPoolsAreStillWaitedFor() throws {
        let decision = try Self.decide(
            MemberHoldings(
                memberId: "member-1",
                isVerified: true,
                directBalance: .known(Fixture.whole(10_000)),
                liquidityPositions: .unknown,
                collectionCounts: [Fixture.passes: .known(0), Fixture.pals: .known(0)]
            )
        )
        #expect(decision.combinedBalance == .unknown)
        #expect(decision.unknowns == [.liquidityPositions])
    }

    // MARK: - Roles this bot does not own

    @Test("A badge a moderator handed out by hand survives every sweep")
    func unmanagedRolesAreUntouched() throws {
        let decision = try Self.decide(
            Fixture.member(direct: 0),
            current: ["role-moderator", "role-birthday", Fixture.bronze]
        )
        #expect(decision.target.contains("role-moderator"))
        #expect(decision.target.contains("role-birthday"))
        #expect(decision.revoked == [Fixture.bronze])
        #expect(decision.managed.contains("role-moderator") == false)
    }

    @Test("Only roles the operator configured are ever taken away")
    func revokedIsAlwaysManaged() throws {
        let configured = try Fixture.configuration().allRoleIds
        let decision = try Self.decide(
            Fixture.member(direct: 0),
            current: [Fixture.gold, "role-moderator"]
        )
        #expect(decision.revoked.isSubset(of: decision.managed))
        #expect(decision.managed.isSubset(of: configured))
    }

    // MARK: - Verification

    @Test("Verifying an account earns the verified role on its own")
    func verifiedRole() throws {
        let decision = try Self.decide(Fixture.member(direct: 0))
        #expect(decision.granted == [Fixture.verified])
    }

    @Test("A member with no verified account keeps nothing the bot granted, and everything it did not")
    func unlinkedMemberIsStripped() throws {
        let configuration = try Fixture.configuration()
        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: MemberHoldings.unlinked(memberId: "member-1", configuration: configuration),
            currentRoleIds: [Fixture.gold, Fixture.passBadge, Fixture.verified, "role-moderator"]
        )
        #expect(decision.revoked == [Fixture.gold, Fixture.passBadge, Fixture.verified])
        #expect(decision.target == ["role-moderator"])
        #expect(decision.isComplete)
    }

    // MARK: - The sweep that strips orphans

    @Test("A sweep against a database that lost its members refuses rather than stripping the server")
    func orphanSweepGuard() {
        // With no verified members, every member holding a managed role
        // looks like an orphan and the whole server is stripped in one pass.
        // A wrong database path produces exactly that, and a wrong database
        // path is a typo.
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 0, lastRecordedCount: nil).mayRun == false)
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 0, lastRecordedCount: 400).mayRun == false)

        // One leftover row passes a zero floor, which is why the zero floor
        // is not the whole guard.
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 1, lastRecordedCount: 400).mayRun == false)
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 199, lastRecordedCount: 400).mayRun == false)
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 200, lastRecordedCount: 400) == .run(recordBaseline: 200))

        // A first run has no baseline, and a small server is allowed to
        // shrink: five members becoming three is a Tuesday.
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 3, lastRecordedCount: nil) == .run(recordBaseline: 3))
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 3, lastRecordedCount: 5) == .run(recordBaseline: 3))
    }

    @Test("A refused sweep hands back no baseline, so the guard cannot be lowered to the wrong count")
    func refusedSweepRecordsNothing() {
        // The refusal is only worth an interval if the caller then records
        // what it just saw: sweep N+1 refuses against a baseline of 400,
        // writes 1, and sweep N+2 passes the halving check against its own 1
        // and strips the server. There is nothing here to write.
        let refused = RoleRules.orphanSweep(verifiedMemberCount: 1, lastRecordedCount: 400)
        #expect(refused.mayRun == false)
        guard case .refuse(let reason) = refused else {
            Issue.record("a refusal that carried a baseline")
            return
        }
        #expect(reason.contains("400"))
        #expect(refused.refusal != nil)

        // And the count to record is only ever the one a run was allowed on.
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 400, lastRecordedCount: 400)
            == .run(recordBaseline: 400))
    }

    @Test("An odd baseline is halved the way the rule reads, not the way integers divide")
    func orphanSweepHalvesAnOddBaseline() {
        // 401 members becoming 200 is a drop of more than half, and integer
        // division rounds the bar down to 200 and lets it through.
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 200, lastRecordedCount: 401).mayRun == false)
        #expect(RoleRules.orphanSweep(verifiedMemberCount: 201, lastRecordedCount: 401).mayRun)
    }

    // MARK: - Reporting

    @Test("A decision says in one line what it did and what it could not")
    func summary() throws {
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .unknown,
            liquidityPositions: .known([]),
            collectionCounts: [Fixture.passes: .known(1), Fixture.pals: .known(0)]
        )
        let decision = try Self.decide(holdings)
        #expect(decision.summary.contains("member-1"))
        #expect(decision.summary.contains("held"))
        #expect(decision.summary.contains("balance could not be read"))
    }
}
