import DiscordBM
import Foundation
import Surface

/// Registers the catalogue with Discord over HTTP.
///
/// Guild commands, never global. A global command appears in every server the
/// bot is in and takes an hour to propagate; this instance serves one server
/// (`HOST-10`), and a guild registration is immediate, which is also what
/// makes a wrong catalogue visible in a minute rather than tomorrow.
public struct DiscordCommandRegistrar: CommandRegistrar {

    // MARK: - Properties

    /// The chat client.
    private let client: any DiscordClient

    // MARK: - Initializers

    /// - Parameter client: The chat client.
    public init(client: any DiscordClient) {
        self.client = client
    }

    // MARK: - Public Methods

    public func register(_ catalog: ValidatedCatalog, guildId: String) async throws {
        // Validated already: the parameter is the validator's own answer and
        // nothing outside `Surface` can make one. Sending an invalid
        // catalogue here is a 400 that fails the boot, and under a
        // supervisor that restarts the process it fails again for ever. That
        // is the failure the offline validator exists for.
        try await client.bulkSetGuildApplicationCommands(
            guildId: GuildSnowflake(guildId),
            payload: catalog.commands.map(CommandPayloadMapping.payload(for:))
        ).guardSuccess()
    }
}

/// Identifies to the gateway, delivers what arrives, and closes it again.
///
/// Wrapped in a type of its own so the boot sequence takes a protocol and a
/// test can count how many times identify was called. That count is the whole
/// point of the boot order: a second copy of this bot must reach zero.
///
/// It is one type answering to two protocols rather than two types wrapping
/// the same manager, because there is exactly one gateway in a process and a
/// second wrapper is a second thing that could be told to connect.
public struct DiscordGatewayConnection: GatewayConnection, ChatSession {

    // MARK: - Properties

    /// The gateway manager.
    private let gateway: BotGatewayManager

    // MARK: - Initializers

    /// - Parameter gateway: The gateway manager.
    public init(gateway: BotGatewayManager) {
        self.gateway = gateway
    }

    // MARK: - Public Methods

    public func identify() async throws {
        await gateway.connect()
    }

    public func deliver(
        to handler: @escaping @Sendable (ChatEvent) async -> Void,
        onceReading reading: @escaping @Sendable () -> Void
    ) async {
        // Subscribed here, and the signal goes out here. `events` hands out a
        // fresh continuation at the moment it is read and replays nothing, so
        // anything the manager fans out before this line is lost. That is why
        // the caller waits for the signal before identifying rather than
        // trusting that a task it started has run.
        let events = await gateway.events
        reading()
        for await event in events {
            guard let translated = Self.event(from: event) else { continue }
            await handler(translated)
        }
    }

    public func stop() async {
        await gateway.disconnect()
        // A short wait for the socket's own pending work, which the manager
        // does not offer a way to await. Closing the process out from under
        // an SSL write in flight is a "bad file descriptor" crash on the way
        // out rather than a clean exit, and a crash here is what a supervisor
        // reads as a failure worth restarting (RT-028).
        try? await Task.sleep(for: .milliseconds(500))
    }

    // MARK: - Internal Methods

    /// One delivered event with the snowflakes taken out, or nil when it
    /// carries nothing this bot acts on.
    ///
    /// Everything else is dropped here rather than higher up. This process
    /// asks for `guilds` and `guildMembers` and nothing else, so what arrives
    /// is already narrow.
    ///
    /// The `default` is not laziness and the compiler will not replace it:
    /// the enum being switched over belongs to the chat library and carries
    /// every event it knows how to deliver, so an exhaustive switch here
    /// would stop building the next time that library learns a new one. What
    /// keeps this honest instead is ``ChatEvent`` being small and this being
    /// the only place it is made, so a case added there with nothing here to
    /// produce it is a case nothing ever sends, which a test catches.
    ///
    /// - Parameter event: What the gateway delivered.
    internal static func event(from event: Gateway.Event) -> ChatEvent? {
        switch event.data {
        case .ready(let ready):
            return .ready(botExternalId: ready.user.id.rawValue)
        case .resumed:
            return .resumed
        case .interactionCreate(let interaction):
            guard let request = InteractionDecoding.request(from: interaction) else { return nil }
            return .interaction(request)
        default:
            return nil
        }
    }
}
