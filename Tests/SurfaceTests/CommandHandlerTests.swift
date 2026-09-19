@preconcurrency import Foundation
import Gating
import Store
import Testing

@testable import Surface

/// The four commands this change ships.
@Suite("The four commands")
struct CommandHandlerTests {

    // MARK: - /ping

    @Test("Ping answers that the bot is awake and reads nothing at all (LEARN-3, RUN-11)")
    func pingReadsNothing() async throws {
        // No store, no chain reader and no portal are handed to this
        // command, and it still answers. That is the property: no one
        // member, however fast they type, can spend the day's budget for
        // reading the chain on their own.
        let arrived = Date(timeIntervalSince1970: 1_000)
        let command = PingCommand(now: { arrived.addingTimeInterval(0.25) })
        let reply = await command.handle(Fixture.command("ping", receivedAt: arrived))

        guard case .immediate(let message) = reply else {
            Issue.record("expected an immediate answer")
            return
        }
        #expect(message.isEphemeral)
        #expect(message.content == "Awake. Answered in 250ms.")
    }

    // MARK: - /help

    @Test("Help lists only what is switched on here (LEARN-8, LEARN-8.a)")
    func helpFollowsTheCatalogue() throws {
        let everything = HelpCommand.card(
            chrome: try Fixture.chrome(),
            features: SurfaceFeatures(enabled: Set(SurfaceFeature.allCases))
        )
        let commands = try #require(everything.fields.first { $0.name == "Commands" }).value
        #expect(commands.contains("/ping"))
        #expect(commands.contains("/verify"))
        #expect(commands.contains("/unlink"))

        let rolesOnly = HelpCommand.card(
            chrome: try Fixture.chrome(),
            features: SurfaceFeatures(enabled: [])
        )
        let fewer = try #require(rolesOnly.fields.first { $0.name == "Commands" }).value
        #expect(fewer.contains("/verify") == false)
        // Said plainly rather than left as an absence, so a member who has
        // heard of it elsewhere does not go looking for something that is
        // not there.
        #expect(rolesOnly.fields.contains { $0.name == "Proving an account" })
    }

    @Test("Help is ephemeral and needs no account (LEARN-4)")
    func helpNeedsNothing() async throws {
        let command = HelpCommand(chrome: try Fixture.chrome(), features: .rolesOnly)
        guard case .immediate(let message) = await command.handle(Fixture.command("help")) else {
            Issue.record("expected an immediate answer")
            return
        }
        #expect(message.isEphemeral)
        #expect(message.card != nil)
    }

    @Test("Help wears this operator's name, colour and picture, and nothing shipped (ADOPT-1.f)")
    func helpWearsTheOperatorsChrome() throws {
        let chrome = CardChrome(
            botName: "Doorkeeper",
            token: try Fixture.token(logoURL: "https://pictures.example.test/logo.png")
        )
        let card = HelpCommand.card(chrome: chrome, features: .rolesOnly)
        #expect(card.title == "Doorkeeper")
        #expect(card.thumbnailURL == "https://pictures.example.test/logo.png")

        // With no picture set there is no picture, not a shipped one.
        let bare = CardChrome(botName: "Doorkeeper", token: try Fixture.token(cardColor: nil))
        let plain = HelpCommand.card(chrome: bare, features: .rolesOnly)
        #expect(plain.thumbnailURL == nil)
        #expect(plain.color == nil)
    }

    @Test("Help fits inside Discord's bounds even with a long catalogue")
    func helpIsBounded() throws {
        let card = HelpCommand.card(
            chrome: try Fixture.chrome(),
            features: SurfaceFeatures(enabled: Set(SurfaceFeature.allCases))
        )
        guard case .within = ReplyBounds.enforce(VisibleMessage(card: card, isEphemeral: true)) else {
            Issue.record("the help card should fit as written")
            return
        }
    }

    // MARK: - /verify

    @Test("Verify never asks for a key, and says so before the button (VERIFY-1)")
    func verifyAsksForNoKey() throws {
        let card = VerifyCommand.disclosureCard(
            chrome: try Fixture.chrome(),
            disclosure: Fixture.disclosure,
            existingAccounts: [],
            url: "https://verify.example.test/s/abc"
        )
        #expect(card.description.contains("never sees a key or a seed phrase"))
        #expect(card.buttons.count == 1)
        #expect(card.buttons[0].style == .link)
        #expect(card.buttons[0].url == "https://verify.example.test/s/abc")
    }

    @Test("The disclosure says who is asking, what is kept and what others see (VERIFY-6)")
    func disclosureIsComplete() throws {
        let card = VerifyCommand.disclosureCard(
            chrome: try Fixture.chrome(),
            disclosure: Fixture.disclosure,
            existingAccounts: [],
            url: "https://verify.example.test/s/abc"
        )
        let who = try #require(card.fields.first { $0.name == "Who is asking" }).value
        #expect(who.contains(Fixture.disclosure.operatorName))
        #expect(who.contains("#support"))

        let seen = try #require(card.fields.first { $0.name == "What other members see" }).value
        // The operator's own sentence, not a shipped one: nothing here can
        // know what another server shows.
        #expect(seen == Fixture.disclosure.visibilityNote)

        #expect(card.fields.contains { $0.name == "What this server keeps" })
        #expect(card.fields.contains { $0.name == "Leaving" })
    }

    @Test("A member who already proved something is offered another, not sent round again (VERIFY-2)")
    func addingAnotherAccountReadsDifferently() throws {
        let card = VerifyCommand.disclosureCard(
            chrome: try Fixture.chrome(),
            disclosure: Fixture.disclosure,
            existingAccounts: ["ACCOUNTAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"],
            url: "https://verify.example.test/s/abc"
        )
        #expect(card.title == "Add another account")
        #expect(card.fields.first?.name == "Already proved (1)")
        // Shortened: a full address is fifty-eight characters and a list of
        // them overran the field limit at fourteen.
        #expect(card.fields.first?.value.contains("\u{2026}") == true)
    }

    @Test("Verify is ephemeral, because the link belongs to one member")
    func verifyIsEphemeral() async throws {
        let command = VerifyCommand(
            guildId: "guild-1",
            store: InMemoryStore(),
            verification: FakeVerificationClient(),
            chrome: try Fixture.chrome(),
            disclosure: Fixture.disclosure
        )
        guard case .followUp(let message) = await command.handle(Fixture.command("verify")) else {
            Issue.record("expected a follow-up")
            return
        }
        #expect(message.isEphemeral)
        #expect(message.card?.buttons.first?.url == "https://verify.example.test/s/abc")
    }

    @Test("The card says when the link stops working, in the reader's own clock")
    func verifySaysWhenTheLinkExpires() async throws {
        // The portal tells this bot when the session dies and the original
        // told the member. Decoding it and saying nothing leaves somebody
        // clicking a dead link with an error they cannot explain.
        let command = VerifyCommand(
            guildId: "guild-1",
            store: InMemoryStore(),
            verification: FakeVerificationClient(),
            chrome: try Fixture.chrome(),
            disclosure: Fixture.disclosure
        )
        guard case .followUp(let message) = await command.handle(Fixture.command("verify")) else {
            Issue.record("expected a follow-up")
            return
        }
        let description = try #require(message.card?.description)
        #expect(description.contains("expires"))
        // Discord's own markup, so it reads correctly wherever the member is.
        #expect(description.contains("<t:2000:R>"))
    }

    @Test("A portal that will not answer leaves the member's account untouched and says so")
    func verifyRefusesCleanly() async throws {
        let portal = FakeVerificationClient()
        await portal.setCreateError(VerificationError.unreachable("refused"))
        let command = VerifyCommand(
            guildId: "guild-1",
            store: InMemoryStore(),
            verification: portal,
            chrome: try Fixture.chrome(),
            disclosure: Fixture.disclosure
        )
        guard case .refuse(let reason) = await command.handle(Fixture.command("verify")) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(reason.contains("nothing about your account has changed"))
    }

    // MARK: - /unlink

    private func storeWithAccounts(_ addresses: [String]) async throws -> (InMemoryStore, MemberKey) {
        let store = InMemoryStore()
        let member = try await store.admitMember(
            externalId: "100000000000000001",
            at: Date(timeIntervalSince1970: 0)
        )
        for address in addresses {
            try await store.prove(account: AccountRecord(
                memberKey: member.key,
                address: address,
                provenAt: Date(timeIntervalSince1970: 0),
                directBaseUnits: 5_000,
                // Read, and recorded as read. A stored figure with no
                // `balancesReadAt` is nobody's reading, which the test below
                // is about.
                balancesReadAt: Date(timeIntervalSince1970: 0)
            ))
        }
        return (store, member.key)
    }

    @Test("With no account named, unlink lists and changes nothing")
    func unlinkListsFirst() async throws {
        let (store, key) = try await storeWithAccounts(["ADDRESS-ONE", "ADDRESS-TWO"])
        let roles = RecordingRoleApplier()
        let command = UnlinkCommand(
            guildId: "guild-1",
            configuration: try Fixture.gating(),
            store: store,
            roles: roles,
            verification: FakeVerificationClient(),
            chrome: try Fixture.chrome()
        )

        guard case .followUp(let message) = await command.handle(Fixture.command("unlink")) else {
            Issue.record("expected a list")
            return
        }
        #expect(message.card?.title == "Your accounts")
        #expect(try await store.accounts(memberKey: key).count == 2)
        #expect(await roles.applyCount == 0)
    }

    @Test("Removing one of several leaves the member and their other accounts alone (VERIFY-3)")
    func unlinkOneOfSeveral() async throws {
        let (store, key) = try await storeWithAccounts(["ADDRESS-ONE", "ADDRESS-TWO"])
        let roles = RecordingRoleApplier(current: ["role-verified", "role-one"])
        let portal = FakeVerificationClient()
        let command = UnlinkCommand(
            guildId: "guild-1",
            configuration: try Fixture.gating(),
            store: store,
            roles: roles,
            verification: portal,
            chrome: try Fixture.chrome()
        )

        let reply = await command.handle(
            Fixture.command("unlink", options: ["account": .string("ADDRESS-ONE")])
        )
        guard case .followUp(let message) = reply else {
            Issue.record("expected a confirmation, got \(reply)")
            return
        }
        #expect(message.card?.title == "Account unlinked")
        #expect(try await store.accounts(memberKey: key).map(\.address) == ["ADDRESS-TWO"])
        // Still a member: they have not left.
        #expect(try await store.member(key: key) != nil)
        #expect(await portal.deletedFor == ["100000000000000001"])
        #expect(await roles.applyCount == 1)
    }

    @Test("Removing the last account forgets the member entirely (VERIFY-7)")
    func unlinkTheLastOneForgets() async throws {
        let (store, key) = try await storeWithAccounts(["ONLY-ADDRESS"])
        let command = UnlinkCommand(
            guildId: "guild-1",
            configuration: try Fixture.gating(),
            store: store,
            roles: RecordingRoleApplier(current: ["role-verified"]),
            verification: FakeVerificationClient(),
            chrome: try Fixture.chrome()
        )

        guard case .followUp(let message) = await command.handle(
            Fixture.command("unlink", options: ["account": .string("ONLY-ADDRESS")])
        ) else {
            Issue.record("expected a confirmation")
            return
        }
        #expect(message.card?.title == "Unlinked, and forgotten")
        #expect(try await store.member(key: key) == nil)
        #expect(try await store.member(externalId: "100000000000000001") == nil)
    }

    @Test("An account nobody has is refused, with the ones they do have listed")
    func unlinkRefusesAnUnknownAccount() async throws {
        let (store, _) = try await storeWithAccounts(["ADDRESS-ONE"])
        let command = UnlinkCommand(
            guildId: "guild-1",
            configuration: try Fixture.gating(),
            store: store,
            roles: RecordingRoleApplier(),
            verification: nil,
            chrome: try Fixture.chrome()
        )
        guard case .refuse(let reason) = await command.handle(
            Fixture.command("unlink", options: ["account": .string("SOMEBODY-ELSES")])
        ) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(reason.contains("No account of yours matches"))
    }

    @Test("A member with nothing proved is told so rather than shown an empty list")
    func unlinkWithNothingProved() async throws {
        let command = UnlinkCommand(
            guildId: "guild-1",
            configuration: try Fixture.gating(),
            store: InMemoryStore(),
            roles: RecordingRoleApplier(),
            verification: nil,
            chrome: try Fixture.chrome()
        )
        guard case .refuse = await command.handle(Fixture.command("unlink")) else {
            Issue.record("expected a refusal")
            return
        }
    }

    @Test("Roles that could not be read are left alone rather than applied against nothing (ROLE-1.a)")
    func unlinkHoldsRolesWhenTheyCannotBeRead() async throws {
        let (store, _) = try await storeWithAccounts(["ADDRESS-ONE", "ADDRESS-TWO"])
        let roles = RecordingRoleApplier(readFails: true)
        let command = UnlinkCommand(
            guildId: "guild-1",
            configuration: try Fixture.gating(),
            store: store,
            roles: roles,
            verification: nil,
            chrome: try Fixture.chrome()
        )
        guard case .followUp(let message) = await command.handle(
            Fixture.command("unlink", options: ["account": .string("ADDRESS-ONE")])
        ) else {
            Issue.record("expected a confirmation")
            return
        }
        // Applying a decision computed against an empty set would strip every
        // managed role the member has, for a member nobody could look at.
        #expect(await roles.applyCount == 0)
        let note = try #require(message.card?.fields.first { $0.name == "Roles" }).value
        #expect(note.contains("Could not be read"))
    }

    @Test("An account nobody has read yet is not counted as a zero (ROLE-1.a)")
    func unlinkHoldsWhenARemainingAccountWasNeverRead() async throws {
        // The account that is left was proved a minute ago and never read.
        // Its stored zero is an absence of evidence, and counting it as a
        // reading takes every rung off somebody nobody has looked at.
        let store = InMemoryStore()
        let member = try await store.admitMember(
            externalId: "100000000000000001",
            at: Date(timeIntervalSince1970: 0)
        )
        try await store.prove(account: AccountRecord(
            memberKey: member.key,
            address: "ADDRESS-GOING",
            provenAt: Date(timeIntervalSince1970: 0),
            directBaseUnits: 5_000,
            balancesReadAt: Date(timeIntervalSince1970: 0)
        ))
        try await store.prove(account: AccountRecord(
            memberKey: member.key,
            address: "ADDRESS-NEVER-READ",
            provenAt: Date(timeIntervalSince1970: 0)
        ))
        let roles = RecordingRoleApplier(current: ["role-verified", "role-one", "role-two"])
        let command = UnlinkCommand(
            guildId: "guild-1",
            configuration: try Fixture.gating(),
            store: store,
            roles: roles,
            verification: nil,
            chrome: try Fixture.chrome()
        )

        _ = await command.handle(
            Fixture.command("unlink", options: ["account": .string("ADDRESS-GOING")])
        )
        let decision = try #require(await roles.lastDecision)
        #expect(decision.revoked.isEmpty)
        #expect(decision.held.contains("role-one"))
        #expect(decision.held.contains("role-two"))
    }

    @Test("Two very large accounts add up to the largest, not to a small number")
    func unlinkDoesNotWrapTheSum() async throws {
        // A wrapped sum puts the largest holder in the server on no rung at
        // all, which is the one demotion nobody would think to look for.
        let store = InMemoryStore()
        let member = try await store.admitMember(
            externalId: "100000000000000001",
            at: Date(timeIntervalSince1970: 0)
        )
        for (address, amount) in [("ADDRESS-GOING", UInt64(1)), ("ADDRESS-HUGE", UInt64.max), ("ADDRESS-TWO", 2)] {
            try await store.prove(account: AccountRecord(
                memberKey: member.key,
                address: address,
                provenAt: Date(timeIntervalSince1970: 0),
                directBaseUnits: amount,
                balancesReadAt: Date(timeIntervalSince1970: 0)
            ))
        }
        let roles = RecordingRoleApplier(current: ["role-verified"])
        let command = UnlinkCommand(
            guildId: "guild-1",
            configuration: try Fixture.gating(),
            store: store,
            roles: roles,
            verification: nil,
            chrome: try Fixture.chrome()
        )

        _ = await command.handle(
            Fixture.command("unlink", options: ["account": .string("ADDRESS-GOING")])
        )
        let decision = try #require(await roles.lastDecision)
        #expect(decision.granted.contains("role-two"))
        #expect(decision.revoked.isEmpty)
    }

    @Test("A shortened address a member copied off a card matches the account it came from")
    func unlinkMatchesAShortenedAddress() async throws {
        let (store, key) = try await storeWithAccounts(["PREFIXAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAASUFFIX"])
        let command = UnlinkCommand(
            guildId: "guild-1",
            configuration: try Fixture.gating(),
            store: store,
            roles: RecordingRoleApplier(current: []),
            verification: nil,
            chrome: try Fixture.chrome()
        )
        _ = await command.handle(Fixture.command("unlink", options: ["account": .string("PREFIX")]))
        #expect(try await store.accounts(memberKey: key).isEmpty)
    }
}
