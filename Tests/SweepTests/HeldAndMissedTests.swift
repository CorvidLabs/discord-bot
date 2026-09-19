import Chain
import Foundation
import Gating
import Store
import Testing
@testable import Sweep

/// SEE-2.a: when somebody's roles did not change, an operator can tell
/// whether the bot held them on purpose or simply missed them, and each
/// case names a reason.
@Suite("Held on purpose and missed are told apart")
struct HeldAndMissedTests {

    @Test("A member whose roles could not be read is missed, and nothing is written")
    func unreadableRolesIsMissed() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)],
            roles: ["member-1": [Fixture.gold]],
            unreadable: ["member-1"]
        )

        let report = await harness.sweep.run()

        // A decision computed against an empty set would revoke every
        // managed role this member holds.
        #expect(await harness.gateway.applied.isEmpty)
        #expect(report.tally.missed == 1)
        #expect(report.tally.missedReasons[SweepSkipReason.rolesUnreadable.rawValue] == 1)
        #expect(SweepSkipReason.rolesUnreadable.isDeliberate == false)
    }

    @Test("A write the chat service refused is missed, not held")
    func refusedWriteIsMissed() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)],
            roles: ["member-1": []],
            refusing: ["member-1"]
        )

        let report = await harness.sweep.run()

        #expect(report.tally.missed == 1)
        #expect(report.tally.missedReasons[SweepSkipReason.applyFailed.rawValue] == 1)
        #expect(report.tally.changed == 0)
    }

    @Test("One sweep splits three members three ways, each with a reason")
    func threeWaySplit() async throws {
        let members = [
            Fixture.member(externalId: "held", addresses: ["WALLET-HELD"]),
            Fixture.member(externalId: "missed", addresses: ["WALLET-MISSED"]),
            Fixture.member(externalId: "correct", addresses: ["WALLET-CORRECT"])
        ]
        let harness = try await Harness.build(
            members: members,
            readings: [
                "WALLET-HELD": Fixture.unreadable("WALLET-HELD"),
                "WALLET-MISSED": Fixture.read("WALLET-MISSED", tokens: 20_000),
                "WALLET-CORRECT": Fixture.read("WALLET-CORRECT", tokens: 0)
            ],
            roles: [
                "held": [Fixture.gold, Fixture.verified],
                "missed": [Fixture.gold],
                "correct": []
            ],
            unreadable: ["missed"]
        )

        let report = await harness.sweep.run()

        #expect(report.tally.members == 3)
        #expect(report.tally.held == 1)
        #expect(report.tally.missed == 1)
        // Verified is granted from this bot's own record, so the member
        // with nothing still changes on their first sweep.
        #expect(report.tally.changed == 1)
        #expect(report.tally.heldReasons[SweepSkipReason.factsUnread.rawValue] == 1)
        #expect(report.tally.missedReasons[SweepSkipReason.rolesUnreadable.rawValue] == 1)
    }

    @Test("The journal gets one entry for the whole sweep, not one per member")
    func oneJournalEntryForSkips() async throws {
        let members = (1...5).map {
            Fixture.member(externalId: "member-\($0)", addresses: ["WALLET-\($0)"])
        }
        var readings: [String: WalletCheck] = [:]
        var roles: [String: Set<String>] = [:]
        for index in 1...5 {
            readings["WALLET-\(index)"] = Fixture.unreadable("WALLET-\(index)")
            // Already verified, because the verified badge is this bot's own
            // record and is decidable even when nothing else was read: a
            // member who has yet to receive it changes rather than holds.
            roles["member-\(index)"] = [Fixture.verified]
        }
        let harness = try await Harness.build(members: members, readings: readings, roles: roles)

        let report = await harness.sweep.run()
        let skipped = report.problems.filter { $0.kind == .membersSkipped }

        #expect(skipped.count == 1)
        let detail = try #require(skipped.first?.detail)
        #expect(detail.contains("Of 5 member(s)"))
        #expect(detail.contains("5 held on purpose"))
        #expect(detail.contains(SweepSkipReason.factsUnread.rawValue))
    }

    @Test("Every reason says something an operator could change")
    func everyReasonNamesSomethingChangeable() {
        for reason in SweepSkipReason.allCases {
            #expect(!reason.sentence.isEmpty)
            // SEE-11: a sentence naming the function that gave up is one
            // nobody running this can do anything with, so no sentence may
            // carry code in it.
            #expect(!reason.sentence.contains("("))
            #expect(!reason.sentence.contains(reason.rawValue))
            #expect(!reason.sentence.lowercased().contains("nil"))
            // Each is a clause, dropped into the middle of a line by
            // `RoleSweep.skipProblems` and by `MemberSweepOutcome.summary`,
            // so it must not start a sentence of its own.
            #expect(reason.sentence == reason.sentence.lowercased())
            #expect(!reason.sentence.hasSuffix("."))
        }
        // Named one by one rather than in a loop, so a case added later has
        // to be classified by hand: whether a skip is the bot's own decision
        // or the bot failing is the whole of SEE-2.a and is not derivable.
        #expect(SweepSkipReason.factsUnread.isDeliberate)
        #expect(SweepSkipReason.noAccounts.isDeliberate)
        #expect(SweepSkipReason.unlinkedMidSweep.isDeliberate)
        #expect(SweepSkipReason.rolesUnreadable.isDeliberate == false)
        #expect(SweepSkipReason.applyFailed.isDeliberate == false)
        #expect(SweepSkipReason.allCases.count == 5)
    }

    @Test("A badge whose collection nobody read is not granted to somebody who lacks it")
    func heldBadgesAreNotGranted() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        // No catalogue at all, which is the initializer's own default and
        // the module's stated safe direction: every collection badge is
        // held. Held means left exactly as it was, and this member does not
        // have it.
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)],
            registry: nil
        )

        let report = await harness.sweep.run()
        let decision = try #require(await harness.gateway.applied["member-1"])
        let after = await harness.gateway.rolesHeld(by: "member-1")

        #expect(decision.held.contains(Fixture.passBadge))
        #expect(!decision.granted.contains(Fixture.passBadge))
        // The one that actually mattered: what the member is left holding.
        // A decision can be right and still be applied wrongly, and the
        // adapter did exactly that by sending `held` as though it were
        // `granted`.
        #expect(!after.contains(Fixture.passBadge))
        #expect(after == [Fixture.bronze, Fixture.silver, Fixture.gold, Fixture.verified])
        #expect(report.tally.incomplete == 1)
    }

    @Test("A member decided partly is counted as incomplete even though roles changed")
    func partlyDecidedCountsAsIncomplete() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)],
            registry: FailingRegistry()
        )

        let report = await harness.sweep.run()

        #expect(report.tally.changed == 1)
        #expect(report.tally.incomplete == 1)
        #expect(report.tally.unreadFacts["collection:\(Fixture.passes)"] == 1)
    }
}
