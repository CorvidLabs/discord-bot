import Chain
import Foundation
import Gating
import Store
import Testing
@testable import Sweep

/// Whose work a sweep is, and what it is allowed to write down afterwards.
@Suite("A sweep reads as the instance and writes back only whole readings")
struct CallerAndBalanceTests {

    @Test("Chain reads are the instance's own work and carry no member share")
    func readsAreSystemWork() async throws {
        let members = [
            Fixture.member(externalId: "member-1", addresses: ["WALLET-1"]),
            Fixture.member(externalId: "member-2", addresses: ["WALLET-2"])
        ]
        let harness = try await Harness.build(
            members: members,
            readings: [
                "WALLET-1": Fixture.read("WALLET-1", tokens: 1),
                "WALLET-2": Fixture.read("WALLET-2", tokens: 1)
            ]
        )

        _ = await harness.sweep.run()
        let callers = await harness.reader.callers

        #expect(callers == [.system(job: RoleSweep.jobName)])
        #expect(callers.allSatisfy { !$0.isRationed })
        #expect(callers.allSatisfy { $0.shareKey == nil })
    }

    @Test("Everybody's accounts are read in one batch, deduplicated, in order")
    func oneBatchForTheWholeSweep() async throws {
        let members = [
            Fixture.member(externalId: "member-1", addresses: ["WALLET-1", "WALLET-2"]),
            Fixture.member(externalId: "member-2", addresses: ["WALLET-3"])
        ]
        let harness = try await Harness.build(members: members)

        _ = await harness.sweep.run()
        let asked = await harness.reader.asked

        // One call, not one per member: a pool's reserves are then read once
        // for the whole pass rather than once per person.
        #expect(asked.count == 1)
        #expect(asked.first == ["WALLET-1", "WALLET-2", "WALLET-3"])
    }

    @Test("The same address twice is one question")
    func duplicateAddressesAreOneQuestion() {
        let key = MemberKey.mint()
        let shared = "WALLET-SHARED"
        let members = [
            SweptMember(
                member: MemberRecord(key: key, externalId: "member-1", firstSeenAt: .distantPast),
                accounts: [
                    AccountRecord(memberKey: key, address: shared, provenAt: .distantPast),
                    AccountRecord(memberKey: key, address: "WALLET-OTHER", provenAt: .distantPast),
                    AccountRecord(memberKey: key, address: shared, provenAt: .distantPast)
                ]
            )
        ]

        #expect(RoleSweep.addresses(of: members) == [shared, "WALLET-OTHER"])
    }

    @Test("The same address twice is one balance, not two")
    func duplicateAddressesAreCountedOnce() async throws {
        let key = MemberKey.mint()
        let shared = "WALLET-SHARED"
        // The input the dedup above exists for: a host's own query joining a
        // row twice. Asking the chain once and then summing the answer twice
        // saves the request and doubles the money, which is the worse half of
        // the bug rather than the cheaper one.
        let member = SweptMember(
            member: MemberRecord(key: key, externalId: "member-1", firstSeenAt: .distantPast),
            accounts: [
                AccountRecord(memberKey: key, address: shared, provenAt: .distantPast),
                AccountRecord(memberKey: key, address: shared, provenAt: .distantPast)
            ]
        )
        let harness = try await Harness.build(
            members: [member],
            readings: [shared: Fixture.read(shared, tokens: 6_000)]
        )

        _ = await harness.sweep.run()
        let decision = try #require(await harness.gateway.applied["member-1"])

        #expect(decision.combinedBalance == .known(Fixture.whole(6_000)))
        // 6,000 is the second rung. Counted twice it is 12,000, which is the
        // third, and the member is promoted on money they do not have.
        #expect(decision.granted.contains(Fixture.silver))
        #expect(!decision.granted.contains(Fixture.gold))
    }

    @Test("A whole reading is written back to the store")
    func wholeReadingIsWrittenBack() async throws {
        let store = InMemoryStore()
        let member = try await Fixture.admit(store, externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 250)],
            store: store
        )

        _ = await harness.sweep.run()
        let stored = try #require(try await harness.store.account(address: "WALLET-1"))

        #expect(stored.directBaseUnits == Fixture.whole(250))
        #expect(stored.liquidityBaseUnits == 0)
        #expect(stored.balancesReadAt != nil)
    }

    @Test("A chat service outage does not throw away a reading already paid for")
    func readingSurvivesAChatOutage() async throws {
        let store = InMemoryStore()
        let member = try await Fixture.admit(store, externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 42)],
            unreadable: ["member-1"],
            store: store
        )

        let report = await harness.sweep.run()
        let stored = try #require(try await store.account(address: "WALLET-1"))

        // The request came out of the day's budget before the chat service
        // was touched, so losing it to an outage there would be paying
        // twice for one answer.
        #expect(report.tally.missed == 1)
        #expect(stored.directBaseUnits == Fixture.whole(42))
    }

    @Test("A short reading is never written back as a smaller number")
    func shortReadingIsNotWrittenBack() async throws {
        let store = InMemoryStore()
        let member = try await Fixture.admit(store, externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.shortLiquidity("WALLET-1", tokens: 250)],
            store: store
        )

        _ = await harness.sweep.run()
        let stored = try #require(try await harness.store.account(address: "WALLET-1"))

        // Written back, it would become the figure the linking arithmetic
        // adds to next time, and one bad minute would outlive itself.
        #expect(stored.directBaseUnits == 0)
        #expect(stored.balancesReadAt == nil)
    }
}
