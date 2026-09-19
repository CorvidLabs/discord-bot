import Chain
import Foundation
import Gating
import Store
import Testing

@testable import Sweep

/// What happens to somebody who links or unlinks while a sweep is already
/// running.
///
/// A pass reads the records once and then spends minutes on the chain and on
/// the chat service. Everything it believes is that old by the time it
/// writes, and both directions of the mistake take roles off a real person:
/// a member who unlinked gets everything handed back, and a member who has
/// just verified gets everything taken away as an orphan.
@Suite("Records that change while a sweep is in flight")
struct MidSweepChangeTests {

    // MARK: - Doubles

    /// A gateway that runs one piece of work at the moment it is asked for a
    /// member's roles, which is the last moment before the sweep writes.
    private actor InterruptingGateway: RoleGateway {

        private var roles: [String: Set<String>]
        private let interrupt: @Sendable () async -> Void
        private(set) var applied: [String: RoleDecision] = [:]

        init(roles: [String: Set<String>], interrupt: @escaping @Sendable () async -> Void) {
            self.roles = roles
            self.interrupt = interrupt
        }

        func currentRoleIds(externalId: String) async throws -> Set<String> {
            await interrupt()
            return roles[externalId] ?? []
        }

        func apply(_ decision: RoleDecision, externalId: String) async throws {
            applied[externalId] = decision
            let current = roles[externalId] ?? []
            roles[externalId] = decision.target
                .intersection(decision.managed)
                .union(current.subtracting(decision.managed))
                .subtracting(decision.revoked)
        }

        func rolesHeld(by externalId: String) -> Set<String> {
            roles[externalId] ?? []
        }
    }

    /// A directory that gains a member after its first answer, which is what
    /// a store-backed one does the moment somebody finishes verifying.
    private actor GrowingDirectory: SweepDirectory {

        private let first: [SweptMember]
        private let afterwards: [SweptMember]
        private(set) var reads = 0

        init(first: [SweptMember], afterwards: [SweptMember]) {
            self.first = first
            self.afterwards = afterwards
        }

        func verifiedMembers() async throws -> [SweptMember] {
            reads += 1
            return reads == 1 ? first : afterwards
        }
    }

    /// A directory that answers once and refuses every time after that.
    private actor OnceThenRefusingDirectory: SweepDirectory {

        private let members: [SweptMember]
        private(set) var reads = 0

        init(members: [SweptMember]) {
            self.members = members
        }

        func verifiedMembers() async throws -> [SweptMember] {
            reads += 1
            guard reads == 1 else { throw SpyFailure.refused }
            return members
        }
    }

    // MARK: - Unlinking mid-sweep

    @Test("A member who unlinks mid-sweep is not handed their roles back")
    func unlinkMidSweepHoldsTheWrite() async throws {
        let store = InMemoryStore()
        let member = try await Fixture.admit(store, externalId: "member-1", addresses: ["WALLET-1"])
        // The unlink command has already stripped every managed role by the
        // time the sweep reaches this member, which is why they hold none.
        let gateway = InterruptingGateway(roles: ["member-1": []]) {
            _ = try? await store.unlink(address: "WALLET-1")
        }
        let journal = RecordingJournal()
        let sweep = RoleSweep(
            configuration: try Fixture.configuration(),
            directory: StaticSweepDirectory(members: [member]),
            store: store,
            chain: RecordingChainReader(["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)]),
            registry: Fixture.catalogue,
            gateway: gateway,
            journal: journal,
            limits: .unthrottled,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let report = await sweep.run()

        // Nothing written, and nothing granted: the rungs and the verified
        // badge stay off somebody who has now proved nothing.
        #expect(await gateway.applied.isEmpty)
        #expect(await gateway.rolesHeld(by: "member-1").isEmpty)
        #expect(report.tally.held == 1)
        #expect(report.tally.heldReasons[SweepSkipReason.unlinkedMidSweep.rawValue] == 1)
    }

    @Test("A store that will not answer the re-check is not read as an unlink")
    func unreadableRecheckStillWrites() async throws {
        // An unread fact holds roles everywhere else in this module. Here the
        // decision has already been made from a complete chain reading, so
        // falling through to it is the conservative move: a store that will
        // not answer is not evidence that anybody unlinked, and refusing on
        // it would be the demotion this module exists to prevent.
        let store = InMemoryStore()
        let member = try await Fixture.admit(store, externalId: "member-1", addresses: ["WALLET-1"])
        await store.corruptAccount(address: "WALLET-1", raw: "{")
        let gateway = SpyGateway(roles: ["member-1": []])
        let sweep = RoleSweep(
            configuration: try Fixture.configuration(),
            directory: StaticSweepDirectory(members: [member]),
            store: store,
            chain: RecordingChainReader(["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)]),
            registry: Fixture.catalogue,
            gateway: gateway,
            journal: RecordingJournal(),
            limits: .unthrottled,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let report = await sweep.run()

        #expect(report.tally.changed == 1)
        #expect(await gateway.applied["member-1"] != nil)
    }

    // MARK: - Verifying mid-sweep

    @Test("A member who verifies mid-sweep is not stripped as an orphan")
    func latecomerIsNotAnOrphan() async throws {
        let store = InMemoryStore()
        var onRecord: [SweptMember] = []
        for index in 1...3 {
            onRecord.append(
                try await Fixture.admit(store, externalId: "member-\(index)", addresses: ["WALLET-\(index)"])
            )
        }
        let latecomer = try await Fixture.admit(store, externalId: "member-new", addresses: ["WALLET-NEW"])
        let directory = GrowingDirectory(first: onRecord, afterwards: onRecord + [latecomer])
        // The roster lists the server after the per-member pass, by which
        // time the latecomer is in it holding what verification granted them.
        let roster = SpyRoster(
            onRecord.map { ServerMember(externalId: $0.member.externalId, roleIds: [Fixture.gold]) }
                + [ServerMember(externalId: "member-new", roleIds: [Fixture.bronze, Fixture.verified])]
        )
        var roles: [String: Set<String>] = ["member-new": [Fixture.bronze, Fixture.verified]]
        var readings: [String: WalletCheck] = [:]
        for index in 1...3 {
            roles["member-\(index)"] = [Fixture.gold]
            readings["WALLET-\(index)"] = Fixture.read("WALLET-\(index)", tokens: 20_000)
        }
        let gateway = SpyGateway(roles: roles)
        let sweep = RoleSweep(
            configuration: try Fixture.configuration(),
            directory: directory,
            store: store,
            chain: RecordingChainReader(readings),
            registry: Fixture.catalogue,
            gateway: gateway,
            roster: roster,
            journal: RecordingJournal(),
            limits: .unthrottled,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let report = await sweep.run()

        // The pass never visited them, because they were not in the snapshot
        // it opened with. Taking their roles back as well would leave them
        // bare until the next interval, and the report would call it a
        // cleared orphan.
        #expect(report.orphansCleared == 0)
        #expect(await gateway.rolesHeld(by: "member-new") == [Fixture.bronze, Fixture.verified])
        #expect(await directory.reads == 2)
    }

    @Test("A second reading the records will not give refuses the orphan pass")
    func unreadableSecondReadingRefusesTheOrphanPass() async throws {
        let store = InMemoryStore()
        var onRecord: [SweptMember] = []
        for index in 1...3 {
            onRecord.append(
                try await Fixture.admit(store, externalId: "member-\(index)", addresses: ["WALLET-\(index)"])
            )
        }
        let directory = OnceThenRefusingDirectory(members: onRecord)
        let roster = SpyRoster([ServerMember(externalId: "ghost", roleIds: [Fixture.gold])])
        let gateway = SpyGateway(roles: ["ghost": [Fixture.gold]])
        var readings: [String: WalletCheck] = [:]
        for index in 1...3 {
            readings["WALLET-\(index)"] = Fixture.read("WALLET-\(index)", tokens: 20_000)
        }
        let sweep = RoleSweep(
            configuration: try Fixture.configuration(),
            directory: directory,
            store: store,
            chain: RecordingChainReader(readings),
            registry: Fixture.catalogue,
            gateway: gateway,
            roster: roster,
            journal: RecordingJournal(),
            limits: .unthrottled,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let report = await sweep.run()

        // The list this pass opened with is too old to strip anybody on, and
        // a refusal is the direction every other doubt here takes.
        #expect(report.orphansCleared == 0)
        #expect(await gateway.rolesHeld(by: "ghost") == [Fixture.gold])
        #expect(report.problems.contains { $0.kind == .orphanSweepRefused })
    }
}
