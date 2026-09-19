@preconcurrency import Foundation
import Chain
import Gating
import Store
import Testing

@testable import Surface

/// What happens between a member signing and the role beside their name.
@Suite("Verification callback")
struct VerificationCallbackTests {

    private let servedGuild = "100000000000000002"

    private func callback(
        externalId: String = "100000000000000001",
        guildId: String? = nil,
        address: String = "ACCOUNT-ONE",
        balance: UInt64 = 5_000
    ) -> VerificationCallback {
        VerificationCallback(
            externalId: externalId,
            guildId: guildId ?? servedGuild,
            address: address,
            balanceBaseUnits: balance
        )
    }

    private func handler(
        store: any BotStore,
        reader: FixtureAccountReader,
        roles: RecordingRoleApplier,
        configuration: GatingConfiguration? = nil
    ) throws -> VerificationCallbackHandler {
        VerificationCallbackHandler(
            servedGuildId: servedGuild,
            configuration: try configuration ?? Fixture.gating(),
            store: store,
            reader: reader,
            roles: roles,
            isValidAddress: { $0.hasPrefix("ACCOUNT") },
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }

    private func reading(_ address: String, holding: UInt64) throws -> WalletCheck {
        WalletCheck.read(
            address: address,
            holdings: [ChainHolding(assetId: 1, amount: holding)],
            token: try Fixture.token(),
            pools: [],
            reserves: [:]
        )
    }

    // MARK: - What is refused before anything is written

    @Test("A callback naming another community's server is refused and writes nothing (HOST-6)")
    func foreignGuildWritesNothing() async throws {
        let store = InMemoryStore()
        let subject = try handler(
            store: store,
            reader: FixtureAccountReader(),
            roles: RecordingRoleApplier()
        )
        await #expect(throws: VerificationCallbackError.refused(.foreignGuild)) {
            _ = try await subject.handle(callback(guildId: "999999999999999999"))
        }
        #expect(try await store.member(externalId: "100000000000000001") == nil)
    }

    @Test("A malformed member id and a malformed account are each refused by name")
    func malformedIsRefused() async throws {
        let subject = try handler(
            store: InMemoryStore(),
            reader: FixtureAccountReader(),
            roles: RecordingRoleApplier()
        )
        await #expect(throws: VerificationCallbackError.refused(.malformedMemberId)) {
            _ = try await subject.handle(callback(externalId: "not-a-snowflake"))
        }
        await #expect(throws: VerificationCallbackError.refused(.malformedAddress)) {
            _ = try await subject.handle(callback(address: "nonsense"))
        }
        await #expect(throws: VerificationCallbackError.refused(.missingGuild)) {
            _ = try await subject.handle(callback(guildId: ""))
        }
    }

    @Test("An account another member already proved is refused, and is left where it is")
    func oneAccountOneMember() async throws {
        let store = InMemoryStore()
        let first = try await store.admitMember(externalId: "100000000000000009", at: Date())
        try await store.prove(account: AccountRecord(
            memberKey: first.key,
            address: "ACCOUNT-ONE",
            provenAt: Date()
        ))

        let subject = try handler(
            store: store,
            reader: FixtureAccountReader(),
            roles: RecordingRoleApplier()
        )
        await #expect(throws: VerificationCallbackError.self) {
            _ = try await subject.handle(callback())
        }
        let stillTheirs = try await store.account(address: "ACCOUNT-ONE")
        #expect(stillTheirs?.memberKey == first.key)
    }

    // MARK: - The whole path

    @Test("Admit, prove, read, decide, apply, once (ROLE-1, VERIFY-2)")
    func theWholePath() async throws {
        let store = InMemoryStore()
        let roles = RecordingRoleApplier(current: [])
        var reader = FixtureAccountReader()
        reader.checks["ACCOUNT-ONE"] = try reading("ACCOUNT-ONE", holding: 1_500)

        let outcome = try await handler(store: store, reader: reader, roles: roles).handle(callback())

        let member = try #require(try await store.member(externalId: "100000000000000001"))
        #expect(outcome.memberKey == member.key)
        #expect(try await store.accounts(memberKey: member.key).map(\.address) == ["ACCOUNT-ONE"])

        // One call, not one per role.
        #expect(await roles.applyCount == 1)
        let decision = try #require(await roles.lastDecision)
        #expect(decision.granted.contains("role-verified"))
        #expect(decision.granted.contains("role-one"))
        #expect(decision.granted.contains("role-two"))
        #expect(outcome.applied)
    }

    @Test("A second account is counted with the first, not instead of it (VERIFY-2.a)")
    func accountsAreCountedTogether() async throws {
        let store = InMemoryStore()
        let roles = RecordingRoleApplier()
        var reader = FixtureAccountReader()
        reader.checks["ACCOUNT-ONE"] = try reading("ACCOUNT-ONE", holding: 600)
        reader.checks["ACCOUNT-TWO"] = try reading("ACCOUNT-TWO", holding: 600)

        let subject = try handler(store: store, reader: reader, roles: roles)
        _ = try await subject.handle(callback(address: "ACCOUNT-ONE"))
        _ = try await subject.handle(callback(address: "ACCOUNT-TWO"))

        // Six hundred each is below the second rung; together they clear it.
        // Linking a second account must never demote somebody.
        let decision = try #require(await roles.lastDecision)
        #expect(decision.granted.contains("role-two"))
    }

    @Test("A balance nobody could read holds the roles it decides rather than taking them (ROLE-1.a)")
    func unreadableHoldsRoles() async throws {
        let store = InMemoryStore()
        // They are on the second rung now.
        let roles = RecordingRoleApplier(current: ["role-verified", "role-one", "role-two"])
        var reader = FixtureAccountReader()
        reader.unreadable = ["ACCOUNT-ONE"]

        let outcome = try await handler(store: store, reader: reader, roles: roles).handle(callback())

        let decision = try #require(await roles.lastDecision)
        // Silence from a node is not evidence that somebody sold up.
        #expect(decision.revoked.isEmpty)
        #expect(decision.held.contains("role-one"))
        #expect(decision.held.contains("role-two"))
        #expect(decision.unknowns.contains(.balance))
        #expect(outcome.notes.contains { $0.contains("were held") })
    }

    @Test("Roles that could not be read stop the apply, rather than applying against nothing")
    func unreadableCurrentRolesStopTheApply() async throws {
        let store = InMemoryStore()
        let roles = RecordingRoleApplier(readFails: true)
        var reader = FixtureAccountReader()
        reader.checks["ACCOUNT-ONE"] = try reading("ACCOUNT-ONE", holding: 1_500)

        let outcome = try await handler(store: store, reader: reader, roles: roles).handle(callback())
        #expect(outcome.applied == false)
        #expect(outcome.decision == nil)
        #expect(await roles.applyCount == 0)
        // The account is still proved: the member did the work, and a
        // Discord read failing is not their problem to redo.
        let member = try #require(try await store.member(externalId: "100000000000000001"))
        #expect(try await store.accounts(memberKey: member.key).count == 1)
    }

    @Test("A Discord call that fails keeps the record and says the next sweep will fix it")
    func applyFailureKeepsTheRecord() async throws {
        let store = InMemoryStore()
        let roles = RecordingRoleApplier(applyFails: true)
        var reader = FixtureAccountReader()
        reader.checks["ACCOUNT-ONE"] = try reading("ACCOUNT-ONE", holding: 1_500)

        let outcome = try await handler(store: store, reader: reader, roles: roles).handle(callback())
        #expect(outcome.applied == false)
        #expect(outcome.decision != nil)
        #expect(outcome.notes.contains { $0.contains("next sweep") })
    }

    @Test("What the chain said replaces what the portal said, and the portal's tier is never read")
    func chainBeatsThePortal() async throws {
        let store = InMemoryStore()
        var reader = FixtureAccountReader()
        reader.checks["ACCOUNT-ONE"] = try reading("ACCOUNT-ONE", holding: 42)

        _ = try await handler(
            store: store,
            reader: reader,
            roles: RecordingRoleApplier()
        ).handle(callback(balance: 999_999_999))

        let account = try #require(try await store.account(address: "ACCOUNT-ONE"))
        #expect(account.directBaseUnits == 42)
        #expect(account.balancesReadAt != nil)
    }

    @Test("Proving the same account twice is the same member, with the same key")
    func provingTwiceIsIdempotent() async throws {
        let store = InMemoryStore()
        var reader = FixtureAccountReader()
        reader.checks["ACCOUNT-ONE"] = try reading("ACCOUNT-ONE", holding: 100)
        let subject = try handler(store: store, reader: reader, roles: RecordingRoleApplier())

        let first = try await subject.handle(callback())
        let second = try await subject.handle(callback())
        #expect(first.memberKey == second.memberKey)
    }
}

/// Leaving the server takes everything with it (`VERIFY-7`).
@Suite("Member departure")
struct MemberDepartureTests {

    @Test("Somebody who leaves is forgotten without having to ask twice")
    func leavingForgets() async throws {
        let store = InMemoryStore()
        let member = try await store.admitMember(externalId: "100000000000000001", at: Date())
        try await store.prove(account: AccountRecord(
            memberKey: member.key,
            address: "ACCOUNT-ONE",
            provenAt: Date()
        ))

        let departures = MemberDeparture(servedGuildId: "guild-1", store: store)
        let outcome = try await departures.handle(
            externalId: "100000000000000001",
            guildId: "guild-1"
        )
        #expect(outcome != nil)
        #expect(try await store.member(externalId: "100000000000000001") == nil)
        #expect(try await store.account(address: "ACCOUNT-ONE") == nil)
    }

    @Test("Somebody leaving another server is another community's business")
    func foreignLeaveIsIgnored() async throws {
        let store = InMemoryStore()
        _ = try await store.admitMember(externalId: "100000000000000001", at: Date())
        let departures = MemberDeparture(servedGuildId: "guild-1", store: store)
        #expect(try await departures.handle(
            externalId: "100000000000000001",
            guildId: "another-guild"
        ) == nil)
        #expect(try await store.member(externalId: "100000000000000001") != nil)
    }

    @Test("Forgetting somebody who is not on record is not an error")
    func unknownMemberIsFine() async throws {
        let departures = MemberDeparture(servedGuildId: "guild-1", store: InMemoryStore())
        #expect(try await departures.handle(externalId: "100000000000000009", guildId: "guild-1") == nil)
    }
}
