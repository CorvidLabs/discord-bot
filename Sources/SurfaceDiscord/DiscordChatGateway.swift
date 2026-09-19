import DiscordBM
import Foundation
import Gating
import Runtime
import Surface

/// The chat service, as the composition root asked for it.
///
/// This is the join. ``Runtime/ChatGateway`` is a protocol over Foundation
/// types declared by a target that links no chat library; this is the one
/// conformance to it, in the one target that may. The direction is the whole
/// safety argument: this target depends on the composition root, SwiftPM
/// refuses a cycle, so the composition root can never depend back and `Store`
/// stays two edges further away still (`BUILD-4`, `RT-002`).
///
/// **It cannot identify before a listener is bound.** The only entry point is
/// ``connect(afterBinding:)``, which takes a ``Runtime/ListenerBound``, and
/// the only initialiser of that value is internal to the composition root. So
/// the ordering that costs a live bot its session is not a comment somebody
/// moves, it is a program that does not compile (`RUN-7`, `RUN-7.a`).
///
/// Everything it touches is a seam, so the identify, the registration, the
/// ordering between them and the answering of an interaction are all
/// exercised with no token and no socket.
public actor DiscordChatGateway: ChatGateway {

    // MARK: - Properties

    /// Every variable this surface reads, for the report and the audit.
    public nonisolated let settingsEntries: [SettingsEntry]

    /// The one server this process serves.
    private let serverId: String

    /// The catalogue, with proof that it passed the validator.
    private let catalog: ValidatedCatalog

    /// What decides the answer to an interaction.
    private let router: SurfaceRouter

    /// The gateway connection.
    private let session: any ChatSession

    /// What registers the catalogue.
    private let registrar: any CommandRegistrar

    /// Reads and writes a member's roles.
    private let members: any GuildMemberRoles

    /// What carries an answer back.
    private let replies: any InteractionReplying

    /// What a message is reported through.
    private let log: @Sendable (String) -> Void

    /// The task reading the session, once connected.
    private var pump: Task<Void, Never>?

    /// How the composition root is told whether the session is open.
    ///
    /// Held from ``connect(afterBinding:reporting:)`` rather than from the
    /// initialiser, because there is nothing to report until something has
    /// been connected.
    private var reportSession: (@Sendable (ChatSessionState) async -> Void)?

    /// The answers still in flight, so a shutdown can wait for them.
    ///
    /// Keyed and removed on completion rather than appended to a list, or a
    /// long-running process accumulates one finished task per interaction it
    /// has ever answered.
    private var answering: [Int: Task<Void, Never>] = [:]

    /// The key the next answer is filed under.
    private var nextAnswer = 0

    // MARK: - Initializers

    /// - Parameters:
    ///   - serverId: The one server this process serves.
    ///   - catalog: The catalogue, with proof that it passed the validator.
    ///   - router: What decides the answer to an interaction.
    ///   - session: The gateway connection.
    ///   - registrar: What registers the catalogue.
    ///   - members: Reads and writes a member's roles.
    ///   - replies: What carries an answer back.
    ///   - settingsEntries: Every variable this surface reads.
    ///   - log: What a message is reported through.
    public init(
        serverId: String,
        catalog: ValidatedCatalog,
        router: SurfaceRouter,
        session: any ChatSession,
        registrar: any CommandRegistrar,
        members: any GuildMemberRoles,
        replies: any InteractionReplying,
        settingsEntries: [SettingsEntry] = ChatSurfaceSettings.settingsEntries,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.serverId = serverId
        self.catalog = catalog
        self.router = router
        self.session = session
        self.registrar = registrar
        self.members = members
        self.replies = replies
        self.settingsEntries = settingsEntries
        self.log = log
    }

    // MARK: - Public Methods

    /// Builds the live one, or nil when this operator wants no chat surface.
    ///
    /// It takes the settings as a dictionary rather than reading them,
    /// because there is exactly one place in `Sources/` that reads the
    /// process environment and it is the executable (`RT-003`,
    /// `BUILD-2.a`).
    ///
    /// Nothing here opens a socket. The gateway manager is built and told
    /// nothing; the first thing that reaches Discord is
    /// ``connect(afterBinding:)``.
    ///
    /// - Parameters:
    ///   - settings: The one snapshot of the machine's variables.
    ///   - log: What a message is reported through.
    /// - Throws: ``Runtime/BootFailure``. Only the chat variables refuse
    ///   here, because only this surface reads them; anything the
    ///   composition root's configuration gate also reads is left to that
    ///   gate rather than reported twice.
    public static func live(
        settings: [String: String],
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> DiscordChatGateway? {
        guard let chat = try ChatSurfaceSettings.load(settings) else { return nil }

        // The token this bot's cards are drawn with. A failure answers nil
        // rather than throwing, on purpose: the configuration gate reads the
        // same variables a moment later and refuses with the loader's own
        // sentence, naming the first thing to fix. Throwing here would say
        // it first, out of order, and in this target's words instead.
        guard let token = try? TokenProfile.load(from: settings) else { return nil }

        // What a member can reach in this build. Verification is off because
        // its other half is not assembled here: no callback listener is
        // bound and no portal is contacted, so offering `/verify` would be
        // offering something that cannot finish (`ADOPT-10.b`).
        let features = SurfaceFeatures(enabled: [])
        let catalog: ValidatedCatalog
        do {
            catalog = try CommandValidator.validated(CommandCatalog.build(features: features))
        } catch {
            // Nothing else in the program would report this, and it is not
            // the operator's to fix: the catalogue is a constant in this
            // package, so a refusal here means the package shipped one the
            // service would reject.
            throw BootFailure(
                summary: "The commands this build would register are not ones the chat service "
                    + "accepts: \(error)",
                remedy: "This is a fault in the program rather than in your settings.",
                code: .internalError
            )
        }

        let gateway = await BotGatewayManager(
            token: chat.botToken,
            // Passed rather than left to the client to dig out of the token.
            // The client's own extraction tries the raw segment and the
            // segment plus one padding pair, so an application id whose
            // base64 does not happen to land on those lengths leaves it nil,
            // and the registration then throws before it makes a request.
            // That differs by platform, and Linux is the deployment target.
            // ``Surface/SurfaceConfiguration/applicationId(fromToken:)`` maps
            // base64url and pads properly, and an operator who sets
            // `DISCORD_APPLICATION_ID` by hand expects it to be the answer.
            appId: chat.applicationId.map { ApplicationSnowflake($0) },
            presence: nil,
            // `guilds`, and nothing else. Not `guildMessages` and not message
            // content: reading every message in a server is a permission this
            // bot has no use for and no business holding.
            //
            // **And not `guildMembers` either.** It is privileged and off by
            // default on a new application, and Discord answers a request for
            // a disallowed intent by closing the websocket with 4014, which
            // the client will not retry: the process stays up, the REST
            // registration having already succeeded, and answers nothing for
            // ever. Nothing here reads a member event, so asking for it buys
            // a boot hazard and no feature. It comes back with the leave
            // event that forgets somebody, not before it (`VERIFY-7`).
            intents: [.guilds]
        )
        let client = gateway.client
        let chrome = CardChrome(botName: chat.botName, token: token)

        return DiscordChatGateway(
            serverId: chat.serverId,
            catalog: catalog,
            router: SurfaceRouter(
                servedGuildId: chat.serverId,
                catalog: catalog.catalog,
                adminRoleId: chat.operatorRoleId,
                commands: [
                    PingCommand(),
                    HelpCommand(chrome: chrome, features: features)
                ]
            ),
            session: DiscordGatewayConnection(gateway: gateway),
            registrar: DiscordCommandRegistrar(client: client),
            members: DiscordGuildMemberRoles(guildId: chat.serverId, client: client, log: log),
            replies: ReplySending(client: client, log: log),
            log: log
        )
    }

    public func connect(
        afterBinding listener: ListenerBound,
        reporting report: @escaping @Sendable (ChatSessionState) async -> Void
    ) async throws {
        reportSession = report

        // Registration first, because it is an HTTP round trip and is not an
        // identify. It is the step here that fails for ordinary reasons the
        // offline validator cannot catch: a 403 for a bot invited without the
        // commands scope, a 404 for a server it is not in, a 429, a 5xx. A
        // failure refuses the boot and the process exits, so under a
        // supervisor it happens again on every restart. Looping on an HTTP
        // call costs nothing; looping on an identify spends a session each
        // time, and a bot that identifies too often in a day has its token
        // revoked. It also cannot run before the definitions were checked:
        // the parameter is the validator's own answer and nothing outside
        // `Surface` can make one (`ADOPT-2`).
        try await registrar.register(catalog, guildId: serverId)
        log("chat: registered \(catalog.commands.count) command(s): "
            + catalog.names.map { "/\($0)" }.joined(separator: " "))

        // Then the reader, and this waits until it is genuinely subscribed
        // rather than merely started. Nothing is delivered before an
        // identify, so subscribing here misses nothing, and the session's
        // opening event a moment later has somebody reading for it. Starting
        // a task is not subscribing: the chat library hands out a fresh
        // continuation when the sequence is read and replays nothing, so an
        // event fanned out before that read is gone.
        let (subscribed, signal) = AsyncStream<Void>.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        pump = Task { [weak self, session] in
            await session.deliver(
                to: { [weak self] event in await self?.handle(event) },
                onceReading: { signal.yield() }
            )
            // Whether it ended or never started, nobody is waiting on a
            // signal that is not coming.
            signal.finish()
            await self?.sessionEnded()
        }
        for await _ in subscribed { break }

        try await session.identify()
        log("chat: identified, with \(listener.description) already bound")
    }

    public func roleIds(ofMember member: String) async throws -> Set<String> {
        try await members.roleIds(ofMember: member)
    }

    public func setRoles(ofMember member: String, to roleIds: Set<String>) async throws {
        try await members.setRoles(ofMember: member, to: roleIds)
    }

    public func disconnect() async {
        pump?.cancel()
        pump = nil

        // The answers already in flight, before the session goes and long
        // before the store above this closes. The composition root puts this
        // call first on the strength of a handler holding the store, and a
        // handler answering a member is exactly one of these tasks: without
        // the wait, that ordering buys nothing and a member's last command of
        // the day becomes a crash rather than an answer. Bounded by the chat
        // client's own request timeout rather than by a deadline here, so a
        // slow answer delays the exit and a hung one cannot outlive its
        // request (RT-028).
        let inFlight = answering.values
        answering = [:]
        for task in inFlight {
            await task.value
        }

        await session.stop()
    }

    // MARK: - Private Methods

    /// One event from the session.
    ///
    /// An interaction is answered in a task of its own, so a slow handler
    /// cannot hold up the next member's command: the three seconds the
    /// service allows are three seconds from delivery, not from the front of
    /// a queue.
    ///
    /// - Parameter event: What arrived.
    private func handle(_ event: ChatEvent) async {
        switch event {
        case .ready(let botExternalId):
            log("chat: the session is open, as \(botExternalId)")
            // The only place health is raised. Connecting returns before the
            // websocket is open, so a boot that raised it would answer 200 to
            // a deploy gate while no interaction could be delivered
            // (`SEE-1.a`).
            await reportSession?(.open)
        case .resumed:
            log("chat: the session was resumed with nothing missed")
            await reportSession?(.open)
        case .interaction(let request):
            // Kept, so a shutdown can wait for it. Nothing between making the
            // task and filing it suspends, so the task cannot ask to be
            // forgotten before it has been remembered.
            let key = nextAnswer
            nextAnswer += 1
            answering[key] = Task { [router, replies] in
                await replies.perform(await router.route(request), for: request)
                // No hop: a task started here inherits this actor, and every
                // step above it is an await, so a slow answer suspends rather
                // than holding the next member's command behind it.
                self.answered(key)
            }
        }
    }

    /// One answer is finished and no longer holds anything up.
    ///
    /// - Parameter key: Which answer.
    private func answered(_ key: Int) {
        answering[key] = nil
    }

    /// The session stopped delivering, for whatever reason.
    ///
    /// **This is what lowers health.** The chat library deliberately leaves
    /// its event stream open on a close it will not retry, so nothing else in
    /// the process would ever say that this bot has gone deaf, and a green
    /// check on a deaf process is worse than no check at all (`SEE-1.a`).
    private func sessionEnded() async {
        log("chat: the session ended, so nothing is being delivered")
        await reportSession?(.closed)
    }
}
