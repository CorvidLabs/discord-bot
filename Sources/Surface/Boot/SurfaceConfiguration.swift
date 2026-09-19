import Foundation

/// Everything this target reads from the environment.
///
/// Read in one place and refused in one place, so a boot failure is one
/// sentence naming one variable rather than a stack trace. Nothing here has a
/// default that belonged to another project, and the two ports have no default
/// at all: a port is somebody's firewall rule, and guessing one is how a
/// second instance binds a port the operator did not know was in use.
public struct SurfaceConfiguration: Sendable, Equatable {

    // MARK: - Properties

    /// The bot's token. A secret.
    public static let tokenKey = "DISCORD_BOT_TOKEN"

    /// The one server this process serves.
    public static let guildKey = "DISCORD_GUILD_ID"

    /// The application this bot is, for the invite URL.
    public static let applicationKey = "DISCORD_APPLICATION_ID"

    /// An extra role that may run operator commands.
    public static let adminRoleKey = "DISCORD_ADMIN_ROLE_ID"

    /// The port the health listener binds.
    public static let healthPortKey = "HEALTH_PORT"

    /// The port the verification callback listener binds.
    public static let callbackPortKey = "VERIFY_CALLBACK_PORT"

    /// What the listeners bind to.
    public static let listenAddressKey = "LISTEN_ADDRESS"

    /// Where the other half of verification lives.
    public static let portalURLKey = "VERIFY_PORTAL_URL"

    /// The one secret both halves hold.
    public static let sharedSecretKey = "VERIFY_SHARED_SECRET"

    /// What the operator calls this bot on its cards.
    public static let botNameKey = "BOT_NAME"

    /// Loopback. The default, because a process that may one day hold a
    /// signing key should not appear on every interface because nobody said
    /// otherwise.
    public static let defaultListenAddress = "127.0.0.1"

    /// The bot's token.
    public let botToken: String

    /// The one server this process serves.
    public let guildId: String

    /// The application id, when it is known, for the invite URL.
    public let applicationId: String?

    /// An extra operator role, or nil.
    public let adminRoleId: String?

    /// The health listener's port.
    public let healthPort: Int

    /// The callback listener's port.
    public let callbackPort: Int

    /// What both listeners bind to.
    public let listenAddress: String

    /// Where the other half lives, or nil when verification is off.
    public let portalURL: String?

    /// The one secret both halves hold, or nil when verification is off.
    public let sharedSecret: String?

    /// What the operator calls this bot.
    public let botName: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - botToken: The bot's token.
    ///   - guildId: The one server this process serves.
    ///   - applicationId: The application id, when known.
    ///   - adminRoleId: An extra operator role.
    ///   - healthPort: The health listener's port.
    ///   - callbackPort: The callback listener's port.
    ///   - listenAddress: What both listeners bind to.
    ///   - portalURL: Where the other half lives.
    ///   - sharedSecret: The one secret both halves hold.
    ///   - botName: What the operator calls this bot.
    public init(
        botToken: String,
        guildId: String,
        applicationId: String? = nil,
        adminRoleId: String? = nil,
        healthPort: Int,
        callbackPort: Int,
        listenAddress: String = SurfaceConfiguration.defaultListenAddress,
        portalURL: String? = nil,
        sharedSecret: String? = nil,
        botName: String = ""
    ) {
        self.botToken = botToken
        self.guildId = guildId
        self.applicationId = applicationId
        self.adminRoleId = adminRoleId
        self.healthPort = healthPort
        self.callbackPort = callbackPort
        self.listenAddress = listenAddress
        self.portalURL = portalURL
        self.sharedSecret = sharedSecret
        self.botName = botName
    }

    // MARK: - Public Methods

    /// Whether a member can prove an account at all.
    public var hasVerification: Bool {
        portalURL != nil && sharedSecret != nil
    }

    /// Which parts this instance is running.
    ///
    /// Spending and games are off in this build because neither has been
    /// brought across. They are named rather than omitted so that the day one
    /// arrives, it arrives switched off by default (`ADOPT-10.b`).
    public var features: SurfaceFeatures {
        var enabled: Set<SurfaceFeature> = []
        if hasVerification { enabled.insert(.verification) }
        return SurfaceFeatures(enabled: enabled)
    }

    /// Reads the environment, or refuses naming the variable.
    ///
    /// - Parameter environment: The environment.
    /// - Throws: ``SurfaceConfigurationError``.
    public static func load(from environment: [String: String]) throws -> SurfaceConfiguration {
        try load { environment[$0] }
    }

    /// Reads one variable at a time, or refuses naming it.
    ///
    /// - Parameter lookup: Reads one variable.
    /// - Throws: ``SurfaceConfigurationError``.
    public static func load(_ lookup: (String) -> String?) throws -> SurfaceConfiguration {
        let token = try required(tokenKey, lookup, why: "this bot cannot connect to Discord without it")
        let guildId = try required(
            guildKey,
            lookup,
            why: "this bot serves one server and has to be told which"
        )
        guard DiscordUserId(externalId: guildId) != nil else {
            throw SurfaceConfigurationError.invalid(
                key: guildKey,
                value: guildId,
                why: "a server id is one to twenty digits, copied from Discord with developer mode on"
            )
        }

        let healthPort = try port(healthPortKey, lookup, why: "the health check binds it before this "
            + "bot identifies to Discord, and a bind is how a second copy discovers the first")
        let callbackPort = try port(callbackPortKey, lookup, why: "the portal's callback arrives on it")
        guard healthPort != callbackPort else {
            throw SurfaceConfigurationError.invalid(
                key: callbackPortKey,
                value: String(callbackPort),
                why: "it is the same as \(healthPortKey), and one process cannot bind a port twice"
            )
        }

        let portalURL = optional(portalURLKey, lookup)
        let secret = optional(sharedSecretKey, lookup)
        if portalURL != nil, secret == nil {
            throw SurfaceConfigurationError.missing(
                key: sharedSecretKey,
                why: "a portal is configured and both halves hold the same one secret"
            )
        }
        if let portalURL {
            guard
                let url = URL(string: portalURL),
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                url.host?.isEmpty == false
            else {
                throw SurfaceConfigurationError.invalid(
                    key: portalURLKey,
                    value: portalURL,
                    why: "it must be an absolute http or https URL with a host, and no trailing slash"
                )
            }
        }

        return SurfaceConfiguration(
            botToken: token,
            guildId: guildId,
            applicationId: optional(applicationKey, lookup) ?? applicationId(fromToken: token),
            adminRoleId: optional(adminRoleKey, lookup),
            healthPort: healthPort,
            callbackPort: callbackPort,
            listenAddress: optional(listenAddressKey, lookup) ?? defaultListenAddress,
            portalURL: portalURL.map(Self.withoutTrailingSlash),
            sharedSecret: secret,
            botName: optional(botNameKey, lookup) ?? ""
        )
    }

    /// The application id a bot token carries, or nil.
    ///
    /// A Discord bot token's first dot-separated segment is the application
    /// id in base64url. Reading it means the boot report can print an invite
    /// URL without asking for a variable the operator would have to look up.
    /// Anything unexpected answers nil rather than guessing, and the report
    /// then names ``applicationKey`` as the thing to set.
    ///
    /// - Parameter token: The bot token.
    public static func applicationId(fromToken token: String) -> String? {
        guard let segment = token.split(separator: ".").first else { return nil }
        var padded = String(segment).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 {
            padded.append("=")
        }
        guard
            let data = Data(base64Encoded: padded),
            let decoded = String(data: data, encoding: .utf8),
            DiscordUserId(externalId: decoded) != nil
        else { return nil }
        return decoded
    }

    // MARK: - Private Methods

    /// A required variable, checked for a placeholder.
    private static func required(
        _ key: String,
        _ lookup: (String) -> String?,
        why: String
    ) throws -> String {
        guard let value = optional(key, lookup) else {
            throw SurfaceConfigurationError.missing(key: key, why: why)
        }
        guard !PlaceholderValues.looksUnfinished(value) else {
            throw SurfaceConfigurationError.placeholder(key: key, value: value)
        }
        return value
    }

    /// A variable's value with the whitespace off, or nil when blank.
    private static func optional(_ key: String, _ lookup: (String) -> String?) -> String? {
        guard let raw = lookup(key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A required port number.
    private static func port(_ key: String, _ lookup: (String) -> String?, why: String) throws -> Int {
        let raw = try required(key, lookup, why: why)
        guard let value = Int(raw.replacingOccurrences(of: "_", with: "")), (1...65_535).contains(value) else {
            throw SurfaceConfigurationError.invalid(
                key: key,
                value: raw,
                why: "a port is a number from 1 to 65535"
            )
        }
        return value
    }

    /// The URL without the trailing slash the contract says it has none of.
    private static func withoutTrailingSlash(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}
