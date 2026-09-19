import DiscordBM
@preconcurrency import Foundation
import Gating
import Store
import Surface

/// Claims the ports this process owns, and serves them.
///
/// The bind and the serving are the same act, deliberately. A binder that
/// only claimed a port and left the serving to a later call would make the
/// boot order look right while the health check answered nothing, which is
/// the failure `SEE-1.a` describes from the other side.
public actor ListenerBinder: PortBinder {

    // MARK: - Properties

    /// What answers on each port.
    private let responders: [Int: @Sendable (HTTPRequestHead, String) async -> HTTPListenerReply]

    /// What a message is reported through.
    private let log: @Sendable (String) -> Void

    /// The listeners, once started.
    private var listeners: [SocketHTTPListener] = []

    // MARK: - Initializers

    /// - Parameters:
    ///   - responders: What answers on each port.
    ///   - log: What a message is reported through. A listener that is
    ///     retrying or giving up says so through this and nothing else.
    public init(
        responders: [Int: @Sendable (HTTPRequestHead, String) async -> HTTPListenerReply],
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.responders = responders
        self.log = log
    }

    // MARK: - Public Methods

    public func bind(port: Int, address: String) async throws {
        guard let respond = responders[port] else {
            // A port nothing answers on is a wiring mistake, and binding it
            // anyway would claim a port for nothing.
            throw ListenerError.addressUnusable(address: "\(address):\(port)")
        }
        let listener = SocketHTTPListener(address: address, port: port, log: log, respond: respond)
        try await listener.start()
        listeners.append(listener)
    }

    /// Releases every port this has claimed.
    public func stop() async {
        for listener in listeners {
            await listener.stop()
        }
        listeners = []
    }
}

/// One running bot.
///
/// The composition, and nothing else: every rule it applies belongs to a type
/// in `Surface` that a test can reach without a token. What is here is the
/// order things happen in and the wires between them.
public actor DiscordSurface {

    // MARK: - Properties

    /// What the operator configured for this target.
    public let configuration: SurfaceConfiguration

    /// What the operator configured for the ladder.
    public let gating: GatingConfiguration

    /// The validated catalogue.
    public let catalog: CommandCatalog

    /// What health reports.
    public let health: HealthState

    /// The gateway manager.
    private let gateway: BotGatewayManager

    /// The chat client.
    private let client: any DiscordClient

    /// Opens the store and takes its lease.
    private let storeOpener: any StoreOpener

    /// Reads an account.
    private let accountReader: any AccountHoldingsReader

    /// Whether an address parses on this chain.
    private let isValidAddress: @Sendable (String) -> Bool

    /// The other half, or nil when verification is off.
    private let verification: (any VerificationClient)?

    /// Who runs this, and what members see.
    private let disclosure: DisclosureSettings?

    /// What a message is reported through.
    private let log: @Sendable (String) -> Void

    /// How many callbacks one source may send.
    private let rateLimiter = CallbackRateLimiter()

    /// The store, once open.
    private var store: (any BotStore)?

    /// The ports, once claimed.
    private var binder: ListenerBinder?

    // MARK: - Initializers

    /// - Parameters:
    ///   - configuration: What the operator configured for this target.
    ///   - gating: What the operator configured for the ladder.
    ///   - catalog: The validated catalogue.
    ///   - storeOpener: Opens the store and takes its lease.
    ///   - accountReader: Reads an account.
    ///   - isValidAddress: Whether an address parses on this chain.
    ///   - verification: The other half, or nil.
    ///   - disclosure: Who runs this, and what members see.
    ///   - log: What a message is reported through.
    public init(
        configuration: SurfaceConfiguration,
        gating: GatingConfiguration,
        catalog: CommandCatalog,
        storeOpener: any StoreOpener,
        accountReader: any AccountHoldingsReader,
        isValidAddress: @escaping @Sendable (String) -> Bool,
        verification: (any VerificationClient)?,
        disclosure: DisclosureSettings?,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) async {
        self.configuration = configuration
        self.gating = gating
        self.catalog = catalog
        self.health = HealthState()
        self.storeOpener = storeOpener
        self.accountReader = accountReader
        self.isValidAddress = isValidAddress
        self.verification = verification
        self.disclosure = disclosure
        self.log = log
        self.gateway = await BotGatewayManager(
            token: configuration.botToken,
            presence: nil,
            // `guilds` for the server itself, `guildMembers` for the leave
            // event that forgets somebody. Not `guildMessages` and not
            // message content: reading every message in a server is a
            // permission this bot has no use for and no business holding.
            intents: [.guilds, .guildMembers]
        )
        self.client = gateway.client
    }

    // MARK: - Public Methods

    /// Boots, then serves until the process ends.
    ///
    /// - Throws: Whatever the boot refused on. Nothing here is caught and
    ///   carried on from: a bot that could not bind, could not register or
    ///   could not agree a secret should stop, not run half working.
    public func run() async throws {
        let binder = ListenerBinder(responders: responders(), log: log)
        self.binder = binder

        let boot = BootSequence(
            configuration: configuration,
            catalog: catalog,
            health: health,
            storeOpener: storeOpener,
            binder: binder,
            registrar: DiscordCommandRegistrar(client: client),
            gateway: DiscordGatewayConnection(gateway: gateway),
            verification: verification
        )
        let (openedStore, steps) = try await boot.run()
        store = openedStore
        for step in steps {
            log("boot: \(step)")
        }
        for line in BootReport.lines(configuration: configuration, catalog: catalog, gating: gating) {
            log(line)
        }

        let router = makeRouter(store: openedStore)
        let sender = ReplySending(client: client, log: log)
        let departures = MemberDeparture(servedGuildId: configuration.guildId, store: openedStore)

        for await event in await gateway.events {
            // One task per event, so a slow handler cannot hold up the next
            // member's command. The three seconds Discord allows are three
            // seconds from delivery, not from the front of a queue.
            Task { [router, sender, departures] in
                await self.handle(event, router: router, sender: sender, departures: departures)
            }
        }

        // The stream ends when the gateway stops, and a bot that receives
        // nothing is not healthy. Nothing else lowers this, and a green
        // check on a deaf process is worse than no check at all.
        await health.setDiscord(.down)
    }

    /// Stops accepting, releases the ports and closes the store.
    public func shutdown() async {
        await binder?.stop()
        await gateway.disconnect()
        await store?.close()
        store = nil
    }

    // MARK: - Private Methods

    /// One gateway event.
    private func handle(
        _ event: Gateway.Event,
        router: SurfaceRouter,
        sender: ReplySending,
        departures: MemberDeparture
    ) async {
        switch event.data {
        case .ready(let ready):
            // The only place health is raised. `connect()` returns before the
            // websocket is open, so a boot that raised it would answer `200`
            // to a deploy gate while no interaction could be delivered.
            await health.setDiscord(.up)
            await reportRolesAboveBot(botExternalId: ready.user.id.rawValue)

        case .resumed:
            await health.setDiscord(.up)

        case .interactionCreate(let interaction):
            guard let request = InteractionDecoding.request(from: interaction) else { return }
            await sender.perform(await router.route(request), for: request)

        case .guildMemberRemove(let removal):
            do {
                _ = try await departures.handle(
                    externalId: removal.user.id.rawValue,
                    guildId: removal.guild_id.rawValue
                )
            } catch {
                log("Could not forget a member who left: \(error)")
            }

        default:
            break
        }
    }

    /// The four commands, wired.
    private func makeRouter(store: any BotStore) -> SurfaceRouter {
        let chrome = CardChrome(botName: configuration.botName, token: gating.token)
        var commands: [any CommandHandler] = [
            PingCommand(),
            HelpCommand(chrome: chrome, features: configuration.features)
        ]
        let roles = DiscordRoleApplier(guildId: configuration.guildId, client: client, log: log)
        if let verification, let disclosure {
            commands.append(VerifyCommand(
                guildId: configuration.guildId,
                store: store,
                verification: verification,
                chrome: chrome,
                disclosure: disclosure
            ))
            commands.append(UnlinkCommand(
                guildId: configuration.guildId,
                configuration: gating,
                store: store,
                roles: roles,
                verification: verification,
                chrome: chrome
            ))
        }
        return SurfaceRouter(
            servedGuildId: configuration.guildId,
            catalog: catalog,
            adminRoleId: configuration.adminRoleId,
            commands: commands
        )
    }

    /// What answers on each port.
    private func responders() -> [Int: @Sendable (HTTPRequestHead, String) async -> HTTPListenerReply] {
        let health = self.health
        let healthResponder: @Sendable (HTTPRequestHead, String) async -> HTTPListenerReply = { request, _ in
            guard request.method == "GET", request.route == CallbackRouting.healthPath else {
                return HTTPListenerReply(status: 404, body: "{\"error\":\"Not Found\"}")
            }
            let snapshot = await health.snapshot()
            return HTTPListenerReply(status: snapshot.statusCode, body: snapshot.jsonBody)
        }
        let callback = CallbackResponder(
            health: health,
            limiter: rateLimiter,
            sharedSecret: configuration.sharedSecret,
            servedGuildId: configuration.guildId,
            isValidAddress: isValidAddress,
            handler: { [weak self] in await self?.callbackHandler() },
            log: log
        )
        return [
            configuration.healthPort: healthResponder,
            configuration.callbackPort: { request, source in
                await callback.respond(to: request, from: source)
            }
        ]
    }

    /// Names any configured role Discord will refuse to grant.
    ///
    /// A role above this bot's own in the server's list cannot be granted,
    /// and the attempt fails **quietly**: the call succeeds and the member is
    /// simply never promoted. Read when the gateway says ready, because the
    /// positions cannot be known before then, and an operator finding this
    /// out from a member instead is `ADOPT-11.a` failing.
    private func reportRolesAboveBot(botExternalId: String) async {
        let managed = BootReport.managedRoleIds(gating)
        guard !managed.isEmpty else { return }
        do {
            let roles = try await client.listGuildRoles(id: GuildSnowflake(configuration.guildId)).decode()
            let me = try await client.getGuildMember(
                guildId: GuildSnowflake(configuration.guildId),
                userId: UserSnowflake(botExternalId)
            ).decode()

            var positions: [String: Int] = [:]
            var names: [String: String] = [:]
            for role in roles {
                positions[role.id.rawValue] = role.position
                names[role.id.rawValue] = role.name
            }
            // No position for any role of this bot's own is not "position
            // zero": treating it as zero would name every configured role as
            // being above it, which is a false alarm an operator learns to
            // ignore.
            guard let highest = me.roles.compactMap({ positions[$0.rawValue] }).max() else {
                log("This bot's own roles could not be placed in the server's list, so no check "
                    + "was made of which configured roles sit above it.")
                return
            }
            let line = BootReport.rolesAboveBotLine(BootReport.rolesAboveBot(
                managedRoleIds: managed,
                positions: positions,
                botHighestPosition: highest,
                names: names
            ))
            if let line {
                log(line)
            }
        } catch {
            log("The server's role list could not be read, so no check was made of which "
                + "configured roles sit above this bot: \(error)")
        }
    }

    /// The callback handler, once the store is open.
    private func callbackHandler() -> VerificationCallbackHandler? {
        guard let store else { return nil }
        return VerificationCallbackHandler(
            servedGuildId: configuration.guildId,
            configuration: gating,
            store: store,
            reader: accountReader,
            roles: DiscordRoleApplier(guildId: configuration.guildId, client: client, log: log),
            isValidAddress: isValidAddress
        )
    }
}
