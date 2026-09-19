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

    public func register(_ commands: [CommandDefinition], guildId: String) async throws {
        // Validated already, by `CommandValidator`, before this is reached.
        // Sending an invalid catalogue here is a 400 that fails the boot, and
        // under a supervisor that restarts the process it fails again for
        // ever. That is the failure the offline validator exists for.
        try await client.bulkSetGuildApplicationCommands(
            guildId: GuildSnowflake(guildId),
            payload: commands.map(CommandPayloadMapping.payload(for:))
        ).guardSuccess()
    }
}

/// Identifies to the gateway.
///
/// Wrapped in a type of its own so the boot sequence takes a protocol and a
/// test can count how many times identify was called. That count is the whole
/// point of the boot order: a second copy of this bot must reach zero.
public struct DiscordGatewayConnection: GatewayConnection {

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
}
