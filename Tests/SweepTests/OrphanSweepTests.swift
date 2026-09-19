import Chain
import Foundation
import Gating
import Store
import Testing
@testable import Sweep

/// Taking managed roles back from members this bot has no record of, and
/// the guard in front of it.
///
/// The baseline is the whole point: it is recorded **only** when the guard
/// passes, so a refusal leaves the previous count in place and a mistyped
/// store path keeps being refused instead of lowering the bar to its own
/// tiny count.
@Suite("The orphan pass, and the baseline it may record")
struct OrphanSweepTests {

    private static func onRecord(_ count: Int) -> [SweptMember] {
        (1...count).map { Fixture.member(externalId: "member-\($0)", addresses: ["WALLET-\($0)"]) }
    }

    @Test("A member holding a managed role with nothing on record loses it")
    func orphanLosesManagedRoles() async throws {
        let members = Self.onRecord(1)
        let roster = SpyRoster([
            ServerMember(externalId: "member-1", roleIds: [Fixture.gold, Fixture.verified]),
            ServerMember(externalId: "ghost", roleIds: [Fixture.gold, Fixture.handGranted])
        ])
        let harness = try await Harness.build(
            members: members,
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)],
            roles: [
                "member-1": [Fixture.gold, Fixture.verified],
                "ghost": [Fixture.gold, Fixture.handGranted]
            ],
            roster: roster
        )

        let report = await harness.sweep.run()

        #expect(report.orphansCleared == 1)
        let held = await harness.gateway.rolesHeld(by: "ghost")
        #expect(held == [Fixture.handGranted])
        #expect(await harness.gateway.rolesHeld(by: "member-1").contains(Fixture.gold))
    }

    @Test("The baseline is recorded once the guard passes, and equals the members on record")
    func baselineRecordedOnRun() async throws {
        let members = Self.onRecord(3)
        let harness = try await Harness.build(
            members: members,
            roster: SpyRoster([])
        )

        _ = await harness.sweep.run()
        let baseline = try #require(try await harness.store.loadRoleBaseline())

        #expect(baseline.verifiedMemberCount == 3)
    }

    @Test("Nobody on record refuses the pass, records nothing and never lists the server")
    func noRecordsRefuses() async throws {
        let roster = SpyRoster([ServerMember(externalId: "ghost", roleIds: [Fixture.gold])])
        let harness = try await Harness.build(members: [], roster: roster)

        let report = await harness.sweep.run()

        #expect(report.orphansCleared == 0)
        #expect(await roster.listCount == 0)
        #expect(try await harness.store.loadRoleBaseline() == nil)
        #expect(report.problems.contains { $0.kind == .orphanSweepRefused })
    }

    @Test("More than half the members gone refuses, and the old baseline survives")
    func collapseRefusesAndKeepsBaseline() async throws {
        let store = InMemoryStore()
        let recorded = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.save(roleBaseline: RoleBaselineRecord(verifiedMemberCount: 40, recordedAt: recorded))
        let roster = SpyRoster([ServerMember(externalId: "ghost", roleIds: [Fixture.gold])])
        let harness = try await Harness.build(
            members: Self.onRecord(5),
            roster: roster,
            store: store
        )

        let report = await harness.sweep.run()
        let baseline = try #require(try await store.loadRoleBaseline())

        #expect(await roster.listCount == 0)
        // Recording 5 here is what would let the next pass pass the halving
        // check against itself and strip the server anyway.
        #expect(baseline.verifiedMemberCount == 40)
        #expect(report.problems.contains { $0.kind == .orphanSweepRefused })
    }

    @Test("A baseline that will not read refuses rather than reading as none")
    func unreadableBaselineRefuses() async throws {
        let store = InMemoryStore()
        await store.corruptBaseline(raw: "{ this is not a baseline")
        let roster = SpyRoster([ServerMember(externalId: "ghost", roleIds: [Fixture.gold])])
        let harness = try await Harness.build(
            members: Self.onRecord(20),
            roster: roster,
            store: store
        )

        let report = await harness.sweep.run()

        // A corrupt baseline read as nothing would fall back to the zero
        // floor alone, which twenty members pass.
        #expect(await roster.listCount == 0)
        #expect(report.orphansCleared == 0)
        #expect(report.problems.contains { $0.kind == .orphanSweepRefused })
    }

    @Test("A small server is allowed to shrink, because halving five is a Tuesday")
    func smallServerMayShrink() async throws {
        let store = InMemoryStore()
        try await store.save(
            roleBaseline: RoleBaselineRecord(
                verifiedMemberCount: 5,
                recordedAt: Date(timeIntervalSince1970: 1_600_000_000)
            )
        )
        let roster = SpyRoster([])
        let harness = try await Harness.build(members: Self.onRecord(1), roster: roster, store: store)

        _ = await harness.sweep.run()

        #expect(await roster.listCount == 1)
        #expect(try await store.loadRoleBaseline()?.verifiedMemberCount == 1)
    }

    @Test("A server that cannot be listed takes no role from anybody")
    func unlistableServerTakesNothing() async throws {
        let roster = SpyRoster([], fails: true)
        let harness = try await Harness.build(members: Self.onRecord(2), roster: roster)

        let report = await harness.sweep.run()

        #expect(report.orphansCleared == 0)
        #expect(report.problems.contains { $0.kind == .orphanSweepFailed })
    }

    @Test("No roster means no orphan pass at all, and no complaint about it")
    func noRosterNoPass() async throws {
        let harness = try await Harness.build(members: Self.onRecord(2), roster: nil)

        let report = await harness.sweep.run()

        #expect(report.orphansCleared == 0)
        #expect(report.problems.allSatisfy { $0.kind != .orphanSweepRefused })
        #expect(try await harness.store.loadRoleBaseline() == nil)
    }

    @Test("A member on record who proved nothing does not count toward the baseline")
    func memberWithoutAccountsDoesNotCount() async throws {
        var members = Self.onRecord(2)
        members.append(Fixture.member(externalId: "member-empty", addresses: []))
        let harness = try await Harness.build(members: members, roster: SpyRoster([]))

        _ = await harness.sweep.run()

        // Counting them would let a store that lost every account still
        // look populated to the guard.
        #expect(try await harness.store.loadRoleBaseline()?.verifiedMemberCount == 2)
    }

    @Test("A member who unlinked everything is held in the pass and cleared by the orphan one")
    func memberWhoProvedNothingLosesManagedRoles() async throws {
        var members = Self.onRecord(2)
        members.append(Fixture.member(externalId: "gave-up", addresses: []))
        let roster = SpyRoster([ServerMember(externalId: "gave-up", roleIds: [Fixture.gold, Fixture.verified])])
        let harness = try await Harness.build(
            members: members,
            roles: ["gave-up": [Fixture.gold, Fixture.verified]],
            roster: roster
        )

        let report = await harness.sweep.run()

        // The per-member pass has nothing to read and holds; the orphan
        // pass is what notices they proved nothing and takes the roles back.
        #expect(report.tally.heldReasons[SweepSkipReason.noAccounts.rawValue] == 1)
        #expect(report.orphansCleared == 1)
        #expect(await harness.gateway.rolesHeld(by: "gave-up").isEmpty)
    }

    @Test("An orphan whose write is refused is counted as not cleared")
    func refusedOrphanWriteIsReported() async throws {
        let roster = SpyRoster([ServerMember(externalId: "ghost", roleIds: [Fixture.gold])])
        let harness = try await Harness.build(
            members: Self.onRecord(1),
            roles: ["ghost": [Fixture.gold]],
            refusing: ["ghost"],
            roster: roster
        )

        let report = await harness.sweep.run()

        #expect(report.orphansCleared == 0)
        #expect(report.problems.contains { $0.kind == .orphanSweepFailed })
    }
}
