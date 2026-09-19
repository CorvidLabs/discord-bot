import Chain
import Foundation
import Gating
import Store
import Testing
@testable import Sweep

/// The loop around the pass, and the one behaviour that is not a pure
/// function: it actually runs.
@Suite("The sweep loop")
struct SweepLoopTests {

    /// Waits for a condition, giving up rather than hanging the suite.
    ///
    /// A loop is the one thing here that cannot be tested without real
    /// time, so the waiting is bounded and the failure is a returned false
    /// rather than a test that never ends.
    private static func waitUntil(
        _ condition: @Sendable () async -> Bool,
        attempts: Int = 200
    ) async -> Bool {
        for _ in 0..<attempts {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    @Test("Starting the loop sweeps straight away when none is on record")
    func loopSweepsImmediately() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)]
        )

        await harness.sweep.start(interval: 3600)
        let ran = await Self.waitUntil { await harness.sweep.lastCompleted != nil }
        await harness.sweep.stop()

        #expect(ran)
        #expect(await harness.sweep.lastCompleted?.memberCount == 1)
        #expect(await harness.gateway.applied["member-1"] != nil)
    }

    @Test("A sweep recorded a moment ago delays the first pass rather than repeating it")
    func loopWaitsOutTheRemainder() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let journal = RecordingJournal()
        await journal.begin(SweepRecord(runId: "sweep-earlier", startedAt: now.addingTimeInterval(-5)))
        let sweep = RoleSweep(
            configuration: try Fixture.configuration(),
            directory: StaticSweepDirectory(members: []),
            store: InMemoryStore(),
            chain: RecordingChainReader([:]),
            gateway: SpyGateway(),
            journal: journal,
            limits: .unthrottled,
            now: { now }
        )

        await sweep.start(interval: 3600)
        // Long enough that an immediate pass would have happened by now.
        try? await Task.sleep(for: .milliseconds(50))
        let completed = await sweep.lastCompleted
        await sweep.stop()

        // Every boot used to sweep, so a restart loop multiplied the day's
        // chain spend by the restart count.
        #expect(completed == nil)
        #expect(await journal.writes.count == 1)
    }

    @Test("Starting a loop that is already running changes nothing")
    func startingTwiceIsHarmless() async throws {
        let harness = try await Harness.build(members: [])

        await harness.sweep.start(interval: 3600)
        await harness.sweep.start(interval: 3600)
        let ran = await Self.waitUntil { await harness.sweep.lastCompleted != nil }
        try? await Task.sleep(for: .milliseconds(20))
        await harness.sweep.stop()

        #expect(ran)
        // Two records, not four.
        #expect(await harness.journal.writes.count == 2)
    }

    @Test("Members are handled in batches, and every one of them is visited")
    func everyMemberIsVisitedInBatches() async throws {
        let members = (1...9).map {
            Fixture.member(externalId: "member-\($0)", addresses: ["WALLET-\($0)"])
        }
        var readings: [String: WalletCheck] = [:]
        for index in 1...9 {
            readings["WALLET-\(index)"] = Fixture.read("WALLET-\(index)", tokens: UInt64(index) * 1_000)
        }
        let harness = try await Harness.build(members: members, readings: readings)

        let report = await harness.sweep.run()
        let reads = await harness.gateway.reads

        #expect(report.tally.members == 9)
        #expect(Set(reads).count == 9)
        #expect(report.tally.changed == 9)
    }

    /// A chat service that gives up the moment the task asking it is
    /// cancelled, which is what every HTTP client does and what a spy that
    /// ignores cancellation hides.
    private actor CancellableGateway: RoleGateway {

        private(set) var applied: [String: RoleDecision] = [:]

        func currentRoleIds(externalId: String) async throws -> Set<String> {
            try Task.checkCancellation()
            return []
        }

        func apply(_ decision: RoleDecision, externalId: String) async throws {
            try Task.checkCancellation()
            applied[externalId] = decision
        }
    }

    @Test("Stopping the loop lets the pass in flight finish rather than blaming the chat service")
    func stoppingLetsThePassFinish() async throws {
        let gate = GateSignal()
        let store = InMemoryStore()
        var members: [SweptMember] = []
        var readings: [String: WalletCheck] = [:]
        for index in 1...4 {
            members.append(
                try await Fixture.admit(store, externalId: "member-\(index)", addresses: ["WALLET-\(index)"])
            )
            readings["WALLET-\(index)"] = Fixture.read("WALLET-\(index)", tokens: 20_000)
        }
        let gateway = CancellableGateway()
        let sweep = RoleSweep(
            configuration: try Fixture.configuration(),
            directory: GatedDirectory(gate: gate, members: members),
            store: store,
            chain: RecordingChainReader(readings),
            gateway: gateway,
            journal: RecordingJournal(),
            limits: .unthrottled,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        await sweep.start(interval: 3600)
        #expect(await Self.waitUntil { await gate.arrivals == 1 })
        // An ordinary shutdown or redeploy, with a pass already running.
        await sweep.stop()
        await gate.release()
        #expect(await Self.waitUntil { await sweep.lastCompleted != nil })

        let report = try #require(await sweep.lastCompleted)
        // A pass cancelled half way through records everybody it had not
        // reached as missed, and that reason's sentence blames a missing
        // permission at the chat service. Writing that into the journal on
        // every redeploy poisons the one record SEE-2 and SEE-5 exist to
        // make trustworthy.
        #expect(report.tally.missed == 0)
        #expect(report.tally.changed == 4)
        #expect(await gateway.applied.count == 4)
    }

    @Test("Having verified is this bot's own record, so it is granted even when nothing else reads")
    func verifiedBadgeIsAlwaysDecidable() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.unreadable("WALLET-1")],
            roles: ["member-1": [Fixture.gold]]
        )

        let report = await harness.sweep.run()
        let decision = try #require(await harness.gateway.applied["member-1"])

        // The badge is the bot's own record and cannot be unreadable, so it
        // is granted; every rung stays exactly where it was.
        #expect(decision.granted == [Fixture.verified])
        #expect(decision.revoked.isEmpty)
        #expect(report.tally.incomplete == 1)
    }
}
