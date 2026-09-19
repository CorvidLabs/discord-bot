@preconcurrency import Foundation
import Testing

@testable import Surface

/// Everything is answered, the policy is the router's, and one instance
/// serves one server.
@Suite("Router")
struct SurfaceRouterTests {

    // MARK: - Doubles

    struct EchoHandler: CommandHandler {
        let name: String
        var reply: SurfaceReply = .immediate(.ephemeral("ok"))
        func handle(_ request: InteractionRequest) async -> SurfaceReply { reply }
    }

    struct NamespacedComponent: ComponentHandler {
        let namespace: String
        func handle(_ request: InteractionRequest) async -> SurfaceReply {
            .updateMessage(VisibleMessage(content: "updated"))
        }
    }

    struct Suggester: AutocompleteHandler {
        let commandName: String
        func suggest(_ request: InteractionRequest) async -> [AutocompleteChoice] {
            [AutocompleteChoice(name: "one", value: "1")]
        }
    }

    private func router(
        commands: [any CommandHandler] = [],
        components: [any ComponentHandler] = [],
        autocompletes: [any AutocompleteHandler] = [],
        adminRoleId: String? = nil,
        catalog: CommandCatalog? = nil
    ) throws -> SurfaceRouter {
        SurfaceRouter(
            servedGuildId: "guild-1",
            catalog: try catalog ?? Fixture.catalog(),
            adminRoleId: adminRoleId,
            commands: commands,
            components: components,
            autocompletes: autocompletes
        )
    }

    // MARK: - One server

    @Test("An interaction from another server is refused and reads nothing (HOST-10.a)")
    func foreignGuildIsRefused() async throws {
        let handler = EchoHandler(name: "ping")
        let actions = try await router(commands: [handler])
            .route(Fixture.command("ping", guildId: "somebody-elses-server"))
        guard case .reply(let message) = actions.first else {
            Issue.record("expected a reply, got \(actions)")
            return
        }
        #expect(message.isEphemeral)
        #expect(message.content?.contains("serves one server") == true)
        #expect(actions.count == 1)
    }

    @Test("An interaction with no server at all is refused the same way")
    func directMessageIsRefused() async throws {
        let actions = try await router(commands: [EchoHandler(name: "ping")])
            .route(InteractionRequest(kind: .command, commandName: "ping", guildId: nil, userExternalId: "1"))
        #expect(actions.count == 1)
        if case .reply(let message) = actions[0] {
            #expect(message.isEphemeral)
        } else {
            Issue.record("expected a refusal")
        }
    }

    // MARK: - Nothing is dropped

    @Test("A command nobody claims is answered, not left as Discord's 'This interaction failed'")
    func unknownCommandIsAnswered() async throws {
        let actions = try await router().route(Fixture.command("nosuchcommand"))
        guard case .reply(let message) = actions.first else {
            Issue.record("expected a reply")
            return
        }
        #expect(message.isEphemeral)
    }

    @Test("A button from an older build is answered")
    func unroutedComponentIsAnswered() async throws {
        let request = InteractionRequest(
            kind: .component,
            customId: "gone:12345",
            guildId: "guild-1",
            userExternalId: "1"
        )
        let actions = try await router(components: [NamespacedComponent(namespace: "here:")]).route(request)
        guard case .reply(let message) = actions.first else {
            Issue.record("expected a reply")
            return
        }
        #expect(message.content?.contains("older version") == true)
    }

    @Test("A claimed button reaches its handler")
    func claimedComponentRuns() async throws {
        let request = InteractionRequest(
            kind: .component,
            customId: "here:go",
            guildId: "guild-1",
            userExternalId: "1"
        )
        let actions = try await router(components: [NamespacedComponent(namespace: "here:")]).route(request)
        guard case .updateMessage(let message) = actions.first else {
            Issue.record("expected an update, got \(actions)")
            return
        }
        #expect(message.content == "updated")
    }

    // MARK: - The three seconds

    @Test("A deferred command's first action is the defer, before the handler is called")
    func deferredCommandDefersFirst() async throws {
        let handler = EchoHandler(name: "verify", reply: .followUp(VisibleMessage(content: "done")))
        let actions = try await router(commands: [handler]).route(Fixture.command("verify"))
        guard case .acknowledgeLater(let isEphemeral) = actions.first else {
            Issue.record("expected a defer first, got \(actions)")
            return
        }
        #expect(isEphemeral)
        guard case .followUp = actions[1] else {
            Issue.record("expected a follow-up second")
            return
        }
    }

    @Test("An immediate command never defers")
    func immediateCommandDoesNotDefer() async throws {
        let actions = try await router(commands: [EchoHandler(name: "ping")]).route(Fixture.command("ping"))
        #expect(actions.count == 1)
        guard case .reply = actions[0] else {
            Issue.record("expected a plain reply")
            return
        }
    }

    @Test("A handler that answers the wrong way is corrected rather than obeyed")
    func policyBeatsTheHandler() async throws {
        // The handler returned `.immediate` for a command the router has
        // already deferred. Sending a fresh reply there is a Discord error
        // and the member is left watching a spinner, so the router sends the
        // follow-up the policy committed to.
        let handler = EchoHandler(name: "verify", reply: .immediate(VisibleMessage(content: "late")))
        let actions = try await router(commands: [handler]).route(Fixture.command("verify"))
        guard case .followUp = actions[1] else {
            Issue.record("expected a follow-up, got \(actions)")
            return
        }
    }

    @Test("Autocomplete is never deferred, because Discord does not allow it")
    func autocompleteNeverDefers() async throws {
        let request = InteractionRequest(
            kind: .autocomplete,
            commandName: "unlink",
            guildId: "guild-1",
            userExternalId: "1"
        )
        let actions = try await router(autocompletes: [Suggester(commandName: "unlink")]).route(request)
        #expect(actions.count == 1)
        guard case .suggest(let choices) = actions[0] else {
            Issue.record("expected suggestions")
            return
        }
        #expect(choices.count == 1)
    }

    @Test("Autocomplete for a command with no suggester still answers, with nothing")
    func unknownAutocompleteAnswersEmpty() async throws {
        let request = InteractionRequest(
            kind: .autocomplete,
            commandName: "ping",
            guildId: "guild-1",
            userExternalId: "1"
        )
        let actions = try await router().route(request)
        #expect(actions == [.suggest([])])
    }

    // MARK: - Operators

    @Test("An operator command refuses a member, whatever registration was told (SPEND-6.a)")
    func operatorCommandRefusesMembers() async throws {
        let operatorCommand = CommandDefinition(
            name: "sweep",
            description: "An operator command",
            defaultMemberPermissions: DiscordPermission.administrator,
            isOperatorOnly: true
        )
        let catalog = CommandCatalog(commands: [operatorCommand])
        let subject = try router(
            commands: [EchoHandler(name: "sweep")],
            adminRoleId: "role-ops",
            catalog: catalog
        )

        let member = await subject.route(Fixture.command("sweep", permissionBits: 0))
        guard case .reply(let refusal) = member.first else {
            Issue.record("expected a refusal")
            return
        }
        #expect(refusal.content?.contains("operators") == true)

        let administrator = await subject.route(
            Fixture.command("sweep", permissionBits: DiscordPermission.administrator)
        )
        guard case .reply(let allowed) = administrator.first else {
            Issue.record("expected the handler to run")
            return
        }
        #expect(allowed.content == "ok")

        let namedRole = await subject.route(Fixture.command("sweep", roleIds: ["role-ops"]))
        guard case .reply(let byRole) = namedRole.first else {
            Issue.record("expected the handler to run")
            return
        }
        #expect(byRole.content == "ok")
    }

    // MARK: - Bounds

    @Test("An over-long answer becomes a refusal a member can read, never a silent failure")
    func overLongAnswerIsBounded() async throws {
        let handler = EchoHandler(
            name: "ping",
            reply: .immediate(VisibleMessage(
                content: String(repeating: "x", count: 3_000),
                truncation: .refuse
            ))
        )
        let actions = try await router(commands: [handler]).route(Fixture.command("ping"))
        guard case .reply(let message) = actions.first, let content = message.content else {
            Issue.record("expected a reply")
            return
        }
        #expect(ReplyLimits.fits(content, within: ReplyLimits.messageContent))
        #expect(message.isEphemeral)
    }

    // MARK: - Long running

    @Test("A long-running command is tracked with the fifteen minutes it has (RAIN-13)")
    func longRunningIsTracked() async throws {
        let started = Date(timeIntervalSince1970: 1_000)
        let definition = CommandDefinition(
            name: "sweep",
            description: "Takes a while",
            acknowledge: .longRunning
        )
        let handler = EchoHandler(
            name: "sweep",
            reply: .longRunning(job: JobId("j-1"), started: VisibleMessage(content: "working"))
        )
        let actions = try await router(
            commands: [handler],
            catalog: CommandCatalog(commands: [definition])
        ).route(Fixture.command("sweep", receivedAt: started))

        #expect(actions.count == 3)
        guard case .track(let job, let deadline) = actions[2] else {
            Issue.record("expected the job to be tracked, got \(actions)")
            return
        }
        #expect(job == JobId("j-1"))
        #expect(deadline == started.addingTimeInterval(SurfaceRouter.tokenLifetime))
    }
}
