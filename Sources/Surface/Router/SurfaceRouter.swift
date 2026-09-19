import Foundation

/// One thing the adapter should do with the chat client.
///
/// The router answers in these rather than calling a client, so the whole of
/// the acknowledgement contract can be checked by comparing an array. "A
/// deferred command's first recorded action is a defer" is a test, not a
/// convention.
public enum RouterAction: Sendable, Equatable {

    /// Tell Discord the handler is working. Must be inside three seconds.
    case acknowledgeLater(isEphemeral: Bool)

    /// Answer now.
    case reply(VisibleMessage)

    /// Fill in an answer already deferred.
    case followUp(VisibleMessage)

    /// Replace the message a component sat on.
    case updateMessage(VisibleMessage)

    /// Offer these while the member types.
    case suggest([AutocompleteChoice])

    /// Remember a job whose report may outlive the interaction.
    case track(job: JobId, deadline: Date)
}

/// Something that answers one slash command.
public protocol CommandHandler: Sendable {

    /// The command's name, matching a ``CommandDefinition``.
    var name: String { get }

    /// Answers it.
    ///
    /// The router has already deferred when the command's policy says to, so
    /// a deferred command returns the body of the follow-up and not a defer.
    ///
    /// - Parameter request: What arrived.
    func handle(_ request: InteractionRequest) async -> SurfaceReply
}

/// Something that answers a button or a menu.
public protocol ComponentHandler: Sendable {

    /// The prefix this claims, including its separator.
    var namespace: String { get }

    /// Answers it.
    /// - Parameter request: What arrived.
    func handle(_ request: InteractionRequest) async -> SurfaceReply
}

/// Something that suggests as a member types.
public protocol AutocompleteHandler: Sendable {

    /// The command this suggests for.
    var commandName: String { get }

    /// Suggests. Must answer inside three seconds and cannot defer.
    /// - Parameter request: What arrived.
    func suggest(_ request: InteractionRequest) async -> [AutocompleteChoice]
}

/// Turns an interaction into the actions that answer it.
///
/// Three rules live here rather than in twenty-six handlers, because in the
/// original they lived in twenty-six handlers and one of them forgot.
///
/// **Everything is answered.** A command nobody claims, a button from an older
/// build, a malformed id: each gets an ephemeral sentence. The alternative is
/// Discord's own "This interaction failed", which tells a member nothing and
/// tells an operator less.
///
/// **The policy is enforced, not requested.** A command declared
/// ``AcknowledgePolicy/deferEphemeral`` is deferred by the router before its
/// handler is called, so a handler cannot forget and leave a member watching a
/// thinking indicator for three seconds and then nothing. An autocomplete is
/// never deferred, because Discord does not allow it.
///
/// **One guild.** An interaction from anywhere else is refused without reading
/// or writing anything (`HOST-10.a`). An instance added to a second server
/// says it does not serve there rather than answering with the first server's
/// data.
public struct SurfaceRouter: Sendable {

    // MARK: - Properties

    /// The one server this process serves.
    public let servedGuildId: String

    /// What can be run here.
    public let catalog: CommandCatalog

    /// The extra role that grants operator commands, or nil.
    public let adminRoleId: String?

    /// Handlers by command name.
    private let commandHandlers: [String: any CommandHandler]

    /// Component handlers, longest namespace first so a specific prefix is
    /// tried before a general one that also matches it.
    private let componentHandlers: [any ComponentHandler]

    /// Autocomplete handlers by command name.
    private let autocompleteHandlers: [String: any AutocompleteHandler]

    // MARK: - Initializers

    /// - Parameters:
    ///   - servedGuildId: The one server this process serves.
    ///   - catalog: What can be run here.
    ///   - adminRoleId: The extra operator role, or nil.
    ///   - commands: The command handlers.
    ///   - components: The component handlers.
    ///   - autocompletes: The autocomplete handlers.
    public init(
        servedGuildId: String,
        catalog: CommandCatalog,
        adminRoleId: String? = nil,
        commands: [any CommandHandler] = [],
        components: [any ComponentHandler] = [],
        autocompletes: [any AutocompleteHandler] = []
    ) {
        self.servedGuildId = servedGuildId
        self.catalog = catalog
        self.adminRoleId = adminRoleId
        self.commandHandlers = Dictionary(commands.map { ($0.name, $0) }) { first, _ in first }
        self.componentHandlers = components.sorted { $0.namespace.count > $1.namespace.count }
        self.autocompleteHandlers = Dictionary(autocompletes.map { ($0.commandName, $0) }) { first, _ in first }
    }

    // MARK: - Public Methods

    /// How long an interaction token stays usable.
    public static let tokenLifetime: TimeInterval = 15 * 60

    /// What the adapter should do about this interaction.
    ///
    /// Never empty. Every path answers.
    ///
    /// - Parameter request: What arrived.
    public func route(_ request: InteractionRequest) async -> [RouterAction] {
        guard request.guildId == servedGuildId else {
            // Not "no permission" and not silence: an instance is set up for
            // one community and this is the sentence that says so.
            return [.reply(.ephemeral(
                "This bot serves one server and this is not it. Nothing here was read or changed."
            ))]
        }

        switch request.kind {
        case .autocomplete:
            return await suggest(request)
        case .component:
            return await component(request)
        case .command:
            return await command(request)
        }
    }

    // MARK: - Private Methods

    /// A slash command.
    private func command(_ request: InteractionRequest) async -> [RouterAction] {
        guard
            let name = request.commandName,
            let definition = catalog.command(named: name),
            let handler = commandHandlers[name]
        else {
            return [.reply(.ephemeral(
                "That command is not one this bot has. It may be left over from an older version; "
                    + "Discord will drop it shortly."
            ))]
        }

        if definition.isOperatorOnly {
            // Registration metadata hides a command. It does not refuse one.
            guard CommandAuth.isOperator(
                permissionBits: request.permissionBits,
                memberRoleIds: request.memberRoleIds,
                adminRoleId: adminRoleId
            ) else {
                return [.reply(.ephemeral("That command is for this server's operators."))]
            }
        }

        let policy = definition.acknowledge
        var actions: [RouterAction] = []
        if policy.defersFirst {
            actions.append(.acknowledgeLater(isEphemeral: policy.isEphemeral))
        }

        let reply = await handler.handle(request)
        actions += resolve(reply, policy: policy, request: request)
        return actions
    }

    /// A button or a menu.
    private func component(_ request: InteractionRequest) async -> [RouterAction] {
        guard let customId = request.customId else {
            return [.reply(.ephemeral("That control sent nothing this bot could read."))]
        }
        guard let handler = componentHandlers.first(where: { customId.hasPrefix($0.namespace) }) else {
            return [.reply(.ephemeral(
                "That button is from an older version of this bot. Run the command again."
            ))]
        }
        let reply = await handler.handle(request)
        return resolve(reply, policy: .immediate, request: request)
    }

    /// A member still typing.
    private func suggest(_ request: InteractionRequest) async -> [RouterAction] {
        guard
            let name = request.commandName,
            let handler = autocompleteHandlers[name]
        else {
            // An empty list is the answer. Discord shows "no options", which
            // is a complete answer, and there is deliberately no defer here:
            // Discord refuses one on an autocomplete.
            return [.suggest([])]
        }
        return [.suggest(await handler.suggest(request))]
    }

    /// The handler's answer, made to fit and made to match the policy.
    private func resolve(
        _ reply: SurfaceReply,
        policy: AcknowledgePolicy,
        request: InteractionRequest
    ) -> [RouterAction] {
        switch reply {
        case .immediate(let message), .followUp(let message):
            // The handler does not get to decide this. Whichever case it
            // returned, what goes out is what the policy already committed to.
            return [send(message, deferred: policy.defersFirst)]

        case .updateMessage(let message):
            return [bounded(message) { .updateMessage($0) }]

        case .autocomplete(let choices):
            return [.suggest(choices)]

        case .refuse(let reason):
            return [send(.ephemeral(reason), deferred: policy.defersFirst)]

        case .longRunning(let job, let started):
            let deadline = request.receivedAt.addingTimeInterval(Self.tokenLifetime)
            return [send(started, deferred: policy.defersFirst), .track(job: job, deadline: deadline)]
        }
    }

    /// A reply or a follow-up, whichever the policy already committed to.
    private func send(_ message: VisibleMessage, deferred: Bool) -> RouterAction {
        bounded(message) { deferred ? .followUp($0) : .reply($0) }
    }

    /// The message, within Discord's limits, or a refusal that is.
    ///
    /// The refusal is built ephemeral and plain, so it cannot itself be over
    /// long: a refusal that is refused is a member watching a thinking
    /// indicator for ever, which is the failure this whole layer exists for.
    private func bounded(
        _ message: VisibleMessage,
        _ wrap: (VisibleMessage) -> RouterAction
    ) -> RouterAction {
        switch ReplyBounds.enforce(message) {
        case .within(let bounded), .clamped(let bounded):
            return wrap(bounded)
        case .refused(let reason):
            return wrap(.ephemeral(ReplyLimits.clamp(reason, to: ReplyLimits.messageContent)))
        }
    }
}
