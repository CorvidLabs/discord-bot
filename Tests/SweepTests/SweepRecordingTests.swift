import Chain
import Foundation
import Gating
import Store
import Testing
@testable import Sweep

/// What a sweep writes down, and when.
@Suite("A sweep writes itself down before and after the work")
struct SweepRecordingTests {

    @Test("The record is written before the work and again after it")
    func recordWrittenTwice() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)]
        )

        let report = await harness.sweep.run()
        let writes = await harness.journal.writes

        #expect(writes.count == 2)
        // Killed between these two, the newest thing on disk is an
        // unfinished sweep rather than the previous one's success.
        #expect(writes[0].finishedAt == nil)
        #expect(writes[1].finishedAt != nil)
        #expect(writes[0].runId == writes[1].runId)
        #expect(writes[1].runId == report.runId)
        #expect(writes[1].memberCount == 1)
        #expect(writes[1].accountCount == 1)
    }

    @Test("A record with only a start reads as unfinished, then as abandoned")
    func unfinishedRecordReadsAsAbandoned() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = SweepRecord(runId: "sweep-1", startedAt: startedAt)

        #expect(record.state(now: startedAt.addingTimeInterval(10), runningHorizon: 1800) == .running)
        #expect(record.state(now: startedAt.addingTimeInterval(3600), runningHorizon: 1800) == .abandoned)
        #expect(record.elapsed == nil)
    }

    @Test("A sweep that threw is finished with a reason, not abandoned")
    func failedSweepEndsItsRecord() async throws {
        let store = InMemoryStore()
        let journal = RecordingJournal()
        let sweep = RoleSweep(
            configuration: try Fixture.configuration(),
            directory: FailingDirectory(),
            store: store,
            chain: RecordingChainReader([:]),
            registry: Fixture.catalogue,
            gateway: SpyGateway(),
            journal: journal,
            limits: .unthrottled,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let report = await sweep.run()
        let writes = await journal.writes
        let last = try #require(writes.last)

        #expect(report.ran)
        #expect(report.failure != nil)
        #expect(writes.count == 2)
        #expect(last.finishedAt != nil)
        if case .failed = last.state(now: Date(), runningHorizon: 1800) {
            // The sweep reached an end and said why, which is not the same
            // thing as a process that vanished.
        } else {
            Issue.record("a sweep that threw should read as failed")
        }
        let problems = await journal.problems
        #expect(problems.contains { $0.kind == .sweepFailed })
    }

    @Test("Every line of one sweep carries the same run id")
    func everyLineCarriesTheRunId() async throws {
        let members = [
            Fixture.member(externalId: "member-1", addresses: ["WALLET-1"]),
            Fixture.member(externalId: "member-2", addresses: ["WALLET-2"])
        ]
        let harness = try await Harness.build(
            members: members,
            readings: [
                "WALLET-1": Fixture.read("WALLET-1", tokens: 20_000),
                "WALLET-2": Fixture.unreadable("WALLET-2")
            ]
        )

        let report = await harness.sweep.run()
        let lines = await harness.log.lines

        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.hasPrefix("[\(report.runId)] ") })
    }

    @Test("A run id sorts, names its UTC second, and two in one second differ")
    func runIdShape() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(SweepRecord.runId(startedAt: startedAt, suffix: "abcd") == "sweep-20231114T221320Z-abcd")
        let first = SweepRecord.newRunId(startedAt: startedAt)
        let second = SweepRecord.newRunId(startedAt: startedAt)
        #expect(first != second)
        #expect(first.hasPrefix("sweep-20231114T221320Z-"))
    }

    @Test("A clean sweep leaves nothing in the journal to read")
    func cleanSweepWritesNoProblem() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)]
        )

        let report = await harness.sweep.run()

        #expect(report.problems.isEmpty)
        #expect(await harness.journal.problems.isEmpty)
    }

    @Test("A second sweep started while one is running does nothing at all")
    func overlappingSweepIsSkipped() async throws {
        let gate = GateSignal()
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let journal = RecordingJournal()
        let sweep = RoleSweep(
            configuration: try Fixture.configuration(),
            directory: GatedDirectory(gate: gate, members: [member]),
            store: InMemoryStore(),
            chain: RecordingChainReader(["WALLET-1": Fixture.read("WALLET-1", tokens: 1)]),
            registry: Fixture.catalogue,
            gateway: SpyGateway(),
            journal: journal,
            limits: .unthrottled
        )

        let first = Task { await sweep.run() }
        while await gate.arrivals == 0 {
            await Task.yield()
        }
        let second = await sweep.run()
        await gate.release()
        let firstReport = await first.value

        #expect(second.ran == false)
        #expect(second.runId.isEmpty)
        #expect(firstReport.ran)
        // Two records, not four: the skipped pass wrote nothing.
        #expect(await journal.writes.count == 2)
    }
}
