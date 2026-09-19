import Chain
import Foundation
import Gating
import Testing
@testable import Runtime

/// What changes, and what does not, when this build is given a chat surface.
///
/// The rule the reserved prefixes state was right and stays: a variable
/// belonging to a part that does not exist refuses the boot, because a
/// process that starts, answers healthy and never appears in the server is
/// the outage the SEE family opens with. What moves is the question it asks.
/// It no longer asks whether a prefix is on a list, it asks whether anything
/// linked into this build reads the variable, and a linked part answers by
/// describing its own (RUN-9.a, RT-014, BUILD-4).
@Suite("A linked chat surface, and the variables it owns")
internal struct ChatSurfaceGateTests {

    // MARK: - Fixtures

    /// What a chat surface says it reads. The real one takes these from its
    /// own configuration loader; this is the same shape with nothing behind
    /// it.
    private static let chatEntries: [SettingsEntry] = [
        SettingsEntry(
            "DISCORD_BOT_TOKEN",
            purpose: "This bot's own token.",
            secrecy: .secret,
            group: .chat
        ),
        SettingsEntry(
            "DISCORD_SERVER_ID",
            purpose: "The one server this process serves.",
            group: .chat
        )
    ]

    private static func surface() -> SpyChatGateway {
        SpyChatGateway(settingsEntries: chatEntries)
    }

    private static func configured() -> [String: String?] {
        ["DISCORD_BOT_TOKEN": "a-token", "DISCORD_SERVER_ID": "4242"]
    }

    // MARK: - Known rather than reserved

    @Test("A variable the linked surface describes is accepted, not refused")
    internal func aDescribedChatVariableIsAccepted() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output, chat: Self.surface()))
            .run(settings: Fixture.settings(extras: Self.configured()))

        #expect(outcome.failure == nil)
        #expect(outcome.gatesPassed == BootGate.allCases)
        if case .running(let instance) = outcome {
            await instance.shutDown()
        }
    }

    @Test("The same variable still refuses a build with no chat surface, so the rule survives")
    internal func theRuleIsNotDeleted() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings(extras: Self.configured()))

        let failure = try #require(outcome.failure)
        #expect(failure.variable == "DISCORD_BOT_TOKEN")
        #expect(failure.code == .configuration)
        #expect(failure.summary.contains("chat surface"))
        // Before the store is opened or a port is claimed, because an
        // operator who set a token believes their members are about to see a
        // bot and they are not (SEE-1.a).
        #expect(outcome.gatesPassed == [.banner])
    }

    @Test("A variable for a part that genuinely does not exist still refuses, surface or not")
    internal func verificationIsStillReserved() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output, chat: Self.surface()))
            .run(settings: Fixture.settings(extras: ["VERIFY_PORTAL_URL": "https://portal.example"]))

        let failure = try #require(outcome.failure)
        #expect(failure.variable == "VERIFY_PORTAL_URL")
        #expect(failure.summary.contains("wallet verification"))
    }

    @Test("A described variable is not reported as one nothing read")
    internal func aDescribedVariableIsNotATypo() async throws {
        let settings = Fixture.settings(extras: Self.configured())
        let names = Self.chatEntries.map(\.pattern)
        let loaded = try LoadedConfiguration.load(settings, alsoRead: names)
        let audit = SettingsAudit.of(
            settings: settings,
            keysRead: loaded.keysRead,
            catalogue: SettingsCatalogue.entries + Self.chatEntries
        )
        #expect(audit.refusal == nil)
        #expect(audit.unread.isEmpty)
        #expect(audit.undescribed.isEmpty)
    }

    @Test("A typo under the surface's own prefix is a typo, not a refusal (ADOPT-9.a)")
    internal func aNearMissIsStillOffered() throws {
        let settings = Fixture.settings(extras: ["DISCORD_BOT_TOKE": "a-token"])
        let names = Self.chatEntries.map(\.pattern)
        let loaded = try LoadedConfiguration.load(settings, alsoRead: names)
        let audit = SettingsAudit.of(
            settings: settings,
            keysRead: loaded.keysRead,
            catalogue: SettingsCatalogue.entries + Self.chatEntries
        )
        // Not refused. The prefix belongs to a part this build has, so an
        // unrecognised name inside it is a probable typo: refusing one
        // breaks both directions of an upgrade, a variable set ahead of a
        // deploy and one left behind by a rollback.
        #expect(audit.refusal == nil)
        let reported = try #require(audit.unread.first { $0.name == "DISCORD_BOT_TOKE" })
        #expect(reported.nearest == "DISCORD_BOT_TOKEN")
    }

    // MARK: - What the operator reads

    @Test("The surface's variables are listed under their own heading (ADOPT-9)")
    internal func theListingIncludesThem() {
        let text = StartupReportWriter.catalogue(
            settings: Fixture.settings(extras: Self.configured()),
            catalogue: SettingsCatalogue.entries + Self.chatEntries
        ).lines.joined(separator: "\n")
        #expect(text.contains(SettingsGroup.chat.rawValue))
        #expect(text.contains("DISCORD_BOT_TOKEN"))
        #expect(text.contains("DISCORD_SERVER_ID"))
    }

    @Test("A secret the surface declared is marked set and never printed (CATALOG-6.a)")
    internal func theSurfacesSecretIsNeverPrinted() async throws {
        let sentinel = "SENTINEL-CHAT-TOKEN-b7f3c1"
        let settings = Fixture.settings(extras: [
            "DISCORD_BOT_TOKEN": sentinel,
            "DISCORD_SERVER_ID": "4242"
        ])
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output, chat: Self.surface()))
            .run(settings: settings)

        let everything = await output.allText
        #expect(!everything.contains(sentinel))
        #expect(everything.contains("set (a secret, never printed)"))
        if case .running(let instance) = outcome {
            await instance.shutDown()
        }
    }

    @Test("The Parts section says the chat surface is on, and how it is ordered")
    internal func partsSaysTheSurfaceIsOn() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let on = StartupReportWriter.parts(
            configuration: configuration,
            capability: .cannotSpend,
            chainOutcome: .confirmed,
            hasChat: true
        ).lines.joined(separator: "\n")
        #expect(on.contains("on   chat surface"))
        #expect(on.contains("after the listener is bound"))

        let off = StartupReportWriter.parts(
            configuration: configuration,
            capability: .cannotSpend,
            chainOutcome: .confirmed
        ).lines.joined(separator: "\n")
        // Not "this build has none": an operator of the assembled program
        // who set no token would go looking for a different binary. Wallet
        // verification still says exactly that, on its own line, because
        // there it is true.
        let chatLine = off.components(separatedBy: "\n").first { $0.contains("chat surface") }
        #expect(chatLine == "off  chat surface, because none is configured: nothing identifies "
            + "and no command is registered")
    }

    @Test("A dry run describes the same build a start would (RT-026)")
    internal func theDryRunAgreesWithAStart() async throws {
        let output = RecordingOutput()
        let code = await Runtime(seams: Fixture.seams(output: output, chat: Self.surface()))
            .execute(.check, settings: Fixture.settings(extras: Self.configured()))
        #expect(code.exitCode == .ok)

        let text = await output.outText
        #expect(text.contains("DISCORD_BOT_TOKEN"))
        #expect(text.contains("on   chat surface"))
    }

    // MARK: - What the health endpoint says about it

    @Test("A linked chat surface contributes a component, and a build without one does not")
    internal func theChatSurfaceIsAComponent() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        #expect(
            BootSequence.componentNames(for: configuration, hasChat: true)
                .contains(HealthComponent.chat)
        )
        // A part that is off contributes none, or an instance with no chat
        // surface would sit at `starting` for ever waiting on one.
        #expect(
            !BootSequence.componentNames(for: configuration, hasChat: false)
                .contains(HealthComponent.chat)
        )
    }

    @Test("A bot that has not appeared in the server answers 503, however well the boot went")
    internal func healthWaitsForTheSession() async throws {
        let chat = Self.surface()
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output, chat: chat))
            .run(settings: Fixture.settings(extras: Self.configured()))

        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }

        // Every gate passed, and the endpoint still says starting. The gate
        // returning means the identify was asked for, and asking for a
        // websocket is not having one: 200 here is a deploy gate going green
        // on a process that is not in the server and answers no command
        // (SEE-1, SEE-1.a).
        #expect(instance.gatesPassed == BootGate.allCases)
        let starting = await instance.currentHealth()
        #expect(starting.statusCode == 503)
        #expect(starting.body.contains(HealthComponent.chat))

        await chat.openSession()
        #expect(await instance.currentHealth().statusCode == 200)

        // And it comes back down when the session ends. Nothing else in the
        // process would say this bot has gone deaf, and a green check on a
        // deaf process is worse than no check at all.
        await chat.closeSession()
        #expect(await instance.currentHealth().statusCode == 503)
        await instance.shutDown()
    }

    // MARK: - The order, with a surface attached

    @Test("The surface is still handed the bind, and still cannot be reached before it")
    internal func theOrderIsUnchanged() async throws {
        let chat = Self.surface()
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output, chat: chat))
            .run(settings: Fixture.settings(extras: Self.configured()))

        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        let bindIndex = try #require(instance.gatesPassed.firstIndex(of: .bind))
        let chatIndex = try #require(instance.gatesPassed.firstIndex(of: .chat))
        #expect(bindIndex < chatIndex)
        #expect(await chat.boundWhenConnected == instance.listener)
        await instance.shutDown()
    }

    @Test("Stopping leaves the chat session, and does it before the store closes")
    internal func shuttingDownLeavesTheSession() async throws {
        let chat = Self.surface()
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output, chat: chat))
            .run(settings: Fixture.settings(extras: Self.configured()))

        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        #expect(await chat.calls == ["connect"])
        await instance.shutDown()
        // A handler answering a member holds the store, and the session is
        // what delivers one, so the session goes first.
        #expect(await chat.calls == ["connect", "disconnect"])

        // And twice is the ordinary case, because a second signal arrives
        // while the first is still unwinding.
        await instance.shutDown()
        #expect(await chat.calls == ["connect", "disconnect"])
    }

    @Test("A surface that refuses the connection stops the boot and lets the port go")
    internal func aRefusedConnectionStopsTheBoot() async throws {
        let chat = SpyChatGateway(settingsEntries: Self.chatEntries, refusing: FixtureRefusal.no)
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output, chat: chat))
            .run(settings: Fixture.settings(extras: Self.configured()))

        let failure = try #require(outcome.failure)
        #expect(failure.summary.contains("refused the connection"))
        #expect(outcome.gatesPassed.contains(.bind))
        #expect(!outcome.gatesPassed.contains(.chat))

        // And the session it opened is left, before anything else unwinds.
        // The live surface registers, starts reading and identifies inside
        // this one call, so a refusal that walked away would leave an
        // identified session and a reconnecting client behind while the
        // process exits and a supervisor starts another one (RUN-7.a).
        #expect(await chat.calls == ["connect", "disconnect"])

        // The port went back, which is the whole reason the refusal unwinds
        // rather than exiting where it stands: the next start has to be able
        // to claim it.
        let again = HealthListener(state: HealthState(componentNames: []))
        let rebound = try await again.bind(address: "127.0.0.1", port: 0)
        #expect(rebound.port != 0)
        await again.stop()
    }
}

/// Something for a double to refuse with.
internal enum FixtureRefusal: Error, Sendable {

    /// No reason worth naming; the boot's own sentence is what is being
    /// checked.
    case no
}
