import Foundation
import Gating
import Testing
@testable import Sweep

/// The small values a sweep keeps and hands back.
@Suite("Tally, problems and report")
struct SweepValueTests {

    @Test("A tally counts each disposition and keeps its reasons")
    func tallyCounts() {
        var tally = SweepTally.empty
        tally.record(.changed(memberId: "a"))
        tally.record(.unchanged(memberId: "b"))
        tally.record(.held(memberId: "c", .factsUnread, unknowns: [.balance], heldRoleCount: 3))
        tally.record(.held(memberId: "d", .noAccounts))
        tally.record(.missed(memberId: "e", .applyFailed))

        #expect(tally.members == 5)
        #expect(tally.changed == 1)
        #expect(tally.unchanged == 1)
        #expect(tally.held == 2)
        #expect(tally.missed == 1)
        #expect(tally.incomplete == 1)
        #expect(tally.heldReasons["facts-unread"] == 1)
        #expect(tally.heldReasons["no-accounts"] == 1)
        #expect(tally.missedReasons["apply-failed"] == 1)
        #expect(tally.unreadFacts["balance"] == 1)
    }

    @Test("One member with the same fact twice is counted once")
    func duplicateFactsCountOnce() {
        var tally = SweepTally.empty
        tally.record(
            .held(memberId: "a", .factsUnread, unknowns: [.balance, .balance, .collection(id: "passes")])
        )

        #expect(tally.unreadFacts["balance"] == 1)
        #expect(tally.unreadFacts["collection:passes"] == 1)
        #expect(tally.incomplete == 1)
    }

    @Test("A fact's key is stable, because a sentence is written for a person")
    func factKeysAreStable() {
        #expect(SweepTally.key(for: .balance) == "balance")
        #expect(SweepTally.key(for: .liquidityPositions) == "liquidity-positions")
        #expect(SweepTally.key(for: .collection(id: "pals")) == "collection:pals")
    }

    @Test("A summary reads the same way every time it is printed")
    func summaryIsStable() {
        let counts = ["b": 2, "a": 2, "c": 5]
        // Two screenshots of one incident have to look like one incident.
        #expect(SweepTally.summary(counts) == "c x5, a x2, b x2")
        #expect(SweepTally.summary([:]).isEmpty)
    }

    @Test("A tally round-trips, because it is written to a journal")
    func tallyRoundTrips() throws {
        var tally = SweepTally.empty
        tally.record(.held(memberId: "a", .factsUnread, unknowns: [.balance]))
        let data = try JSONEncoder().encode(tally)
        let decoded = try JSONDecoder().decode(SweepTally.self, from: data)
        #expect(decoded == tally)
    }

    @Test("A record round-trips with its tally and its failure")
    func recordRoundTrips() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = SweepRecord(runId: "sweep-1", startedAt: startedAt)
            .ended(at: startedAt.addingTimeInterval(12), memberCount: 4, accountCount: 6, tally: .empty)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SweepRecord.self, from: data)

        #expect(decoded == record)
        #expect(decoded.elapsed == 12)
        #expect(decoded.state(now: Date(), runningHorizon: 1800) == .finished)
    }

    @Test("Problems are kept newest first and capped by count, never by age")
    func problemsAreTrimmedNewestFirst() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let problems = (0..<5).map { index in
            SweepProblem(
                at: base.addingTimeInterval(TimeInterval(index)),
                runId: "sweep-\(index)",
                kind: .membersSkipped,
                detail: "\(index)"
            )
        }
        let trimmed = SweepProblem.trimmed(problems, limit: 2)

        #expect(trimmed.map(\.detail) == ["4", "3"])
        #expect(SweepProblem.trimmed(problems, limit: 0).isEmpty)
    }

    @Test("A clean sweep writes no skip entry at all")
    func noSkipEntryForACleanSweep() {
        var tally = SweepTally.empty
        tally.record(.changed(memberId: "a"))
        let problems = RoleSweep.skipProblems(runId: "sweep-1", tally: tally, at: Date())
        #expect(problems.isEmpty)
    }

    @Test("Every problem kind has a heading somebody can scan")
    func everyKindHasALabel() {
        for kind in SweepProblem.Kind.allCases {
            #expect(!kind.label.isEmpty)
        }
    }

    @Test("A skipped pass says so rather than reporting a clean sweep")
    func skippedReportReadsAsSkipped() {
        #expect(SweepReport.skipped.ran == false)
        #expect(SweepReport.skipped.summary.contains("already running"))
    }

    @Test("A batch size under one is raised, so a sweep cannot loop for ever")
    func limitsAreClamped() {
        let limits = SweepLimits(memberBatchSize: 0, orphanBatchSize: -3, problemLimit: -1)
        #expect(limits.memberBatchSize == 1)
        #expect(limits.orphanBatchSize == 1)
        #expect(limits.problemLimit == 0)
        #expect(SweepLimits.unthrottled.pauseBetweenBatches == .zero)
    }

    @Test("The in-memory journal keeps the last sweep and caps its problems")
    func inMemoryJournalKeepsWhatItSays() async {
        let journal = InMemorySweepJournal(problemLimit: 2)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await journal.begin(SweepRecord(runId: "sweep-1", startedAt: base))
        await journal.record(
            (0..<4).map {
                SweepProblem(
                    at: base.addingTimeInterval(TimeInterval($0)),
                    runId: "sweep-1",
                    kind: .sweepFailed,
                    detail: "\($0)"
                )
            }
        )

        #expect(await journal.lastSweep()?.runId == "sweep-1")
        #expect(await journal.recentProblems().count == 2)
        #expect(await journal.recentProblems().map(\.detail) == ["3", "2"])
    }

    @Test("An outcome says in one line what happened and why")
    func outcomeSummaryReads() {
        let outcome = MemberSweepOutcome.held(
            memberId: "abc",
            .factsUnread,
            unknowns: [.balance],
            heldRoleCount: 2
        )
        #expect(outcome.summary.contains("abc"))
        #expect(outcome.summary.contains("held"))
        #expect(outcome.summary.contains("2 role(s) held"))
        #expect(outcome.isComplete == false)
        #expect(MemberSweepOutcome.unchanged(memberId: "abc").isComplete)
    }
}
