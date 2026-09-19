@preconcurrency import Foundation
import Gating
import Store

/// Something that claims a local port.
///
/// A seam because binding is the load-bearing step of the boot order and a
/// test has to be able to make it fail without holding a real socket.
public protocol PortBinder: Sendable {

    /// Claims one port, or throws.
    ///
    /// - Parameters:
    ///   - port: The port.
    ///   - address: What to bind it on.
    func bind(port: Int, address: String) async throws
}

/// Something that opens this instance's store and takes its lease.
public protocol StoreOpener: Sendable {

    /// Opens it, or throws when another process holds it.
    func open() async throws -> any BotStore
}

/// Something that registers the catalogue with the chat client over HTTP.
public protocol CommandRegistrar: Sendable {

    /// Replaces this server's commands with these.
    ///
    /// It takes ``ValidatedCatalog`` rather than an array of definitions, so
    /// a registration that has not been through the validator does not
    /// compile. An invalid catalogue is a `400` that fails the boot, and
    /// under a supervisor that restarts the process it fails again for ever
    /// (`ADOPT-2`).
    ///
    /// - Parameters:
    ///   - catalog: The catalogue, with proof that it passed the validator.
    ///   - guildId: The server. Guild commands, never global: a global
    ///     command appears in every server the bot is in, and this instance
    ///     serves one (`HOST-10`).
    func register(_ catalog: ValidatedCatalog, guildId: String) async throws
}

/// Something that identifies to the gateway.
public protocol GatewayConnection: Sendable {

    /// Identifies. Called once, and only once every bind has succeeded.
    func identify() async throws
}

/// One thing the boot did, in the order it did it.
public enum BootStep: Sendable, Equatable {

    /// The store opened and its lease was taken.
    case openedStore

    /// A port was claimed.
    case bound(port: Int)

    /// The other half answered its health check.
    case verificationReachable

    /// The keyed probe ran, and what it found.
    case probedSharedSecret(SharedSecretProbe)

    /// The catalogue passed the validator.
    case validatedCatalog(commandCount: Int)

    /// The catalogue was registered with the chat client.
    case registeredCommands(commandCount: Int)

    /// This process identified to the gateway.
    case identified

    /// Every step ran and the process is serving.
    ///
    /// Not the same as healthy: health answers `503 starting` until the
    /// gateway's own ready event arrives, which is after this.
    case ready
}

/// Why a boot stopped.
public enum BootError: Error, Equatable, LocalizedError, Sendable {

    /// A port was already in use. Almost always a second copy of this bot.
    case portInUse(port: Int, detail: String)

    /// Another process holds the store.
    case storeHeld(detail: String)

    /// The keyed probe found the two halves hold different secrets.
    case sharedSecretMismatch

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case .portInUse(let port, let detail):
            // The detail comes first and the guess second. A bind fails for
            // an unusable listen address and a socket the kernel would not
            // give as well as for a port already held, and an error that
            // names only the likeliest cause sends somebody looking for a
            // second copy that does not exist.
            return "Port \(port) could not be claimed: \(detail). The usual cause is a second copy "
                + "of this bot already running, and this one stopped before speaking to Discord so "
                + "that the copy already serving your server keeps serving it."
        case .storeHeld(let detail):
            return "Another process holds this instance's store (\(detail)). Two processes sharing "
                + "one store can each pay the same epoch."
        case .sharedSecretMismatch:
            return "This bot and the verification portal hold different shared secrets. Every "
                + "/verify would fail with a 401 nobody sees, so this stopped instead."
        }
    }
}

/// Starting up, in the order that matters.
///
/// **The order is the whole of it, and one step of it is not negotiable.**
/// The ports are bound before this process identifies to Discord.
///
/// Binding a port is how a process discovers that another copy of it is
/// already running. A second copy that identified first would take the live
/// copy's session away, because Discord answers a duplicate identify by
/// invalidating the session it collides with, and would then exit a moment
/// later on the bind it was always going to fail. Under any supervisor that
/// restarts it, that is a reconnect storm with no bottom: the healthy bot is
/// knocked offline every time the doomed one boots, and neither keeps a
/// session. Claiming the local ports first means the second copy dies without
/// the first ever noticing (`RUN-7`, `RUN-7.a`).
///
/// The store's lease comes before even that, because two processes sharing one
/// store can each run the same payout.
///
/// Registration is an HTTP call and is not identify, so it sits after the
/// binds and before the gateway. It is preceded by the validator, so a
/// catalogue Discord would refuse fails here rather than as a `400` that
/// crash-loops the boot (`ADOPT-2`).
public struct BootSequence: Sendable {

    // MARK: - Properties

    /// What the operator configured.
    public let configuration: SurfaceConfiguration

    /// The catalogue to register.
    public let catalog: CommandCatalog

    /// Where health is recorded.
    private let health: HealthState

    /// Opens the store.
    private let storeOpener: any StoreOpener

    /// Claims ports.
    private let binder: any PortBinder

    /// Registers commands.
    private let registrar: any CommandRegistrar

    /// Identifies to the gateway.
    private let gateway: any GatewayConnection

    /// The other half, or nil when verification is off.
    private let verification: (any VerificationClient)?

    // MARK: - Initializers

    /// - Parameters:
    ///   - configuration: What the operator configured.
    ///   - catalog: The catalogue to register.
    ///   - health: Where health is recorded.
    ///   - storeOpener: Opens the store.
    ///   - binder: Claims ports.
    ///   - registrar: Registers commands.
    ///   - gateway: Identifies to the gateway.
    ///   - verification: The other half, or nil.
    public init(
        configuration: SurfaceConfiguration,
        catalog: CommandCatalog,
        health: HealthState,
        storeOpener: any StoreOpener,
        binder: any PortBinder,
        registrar: any CommandRegistrar,
        gateway: any GatewayConnection,
        verification: (any VerificationClient)? = nil
    ) {
        self.configuration = configuration
        self.catalog = catalog
        self.health = health
        self.storeOpener = storeOpener
        self.binder = binder
        self.registrar = registrar
        self.gateway = gateway
        self.verification = verification
    }

    // MARK: - Public Methods

    /// Runs the boot, or throws at the first step that will not work.
    ///
    /// - Returns: The store, open, and every step that ran.
    /// - Throws: ``BootError``, ``CommandCatalogInvalid``,
    ///   ``VerificationError``, or whatever the store threw.
    public func run() async throws -> (store: any BotStore, steps: [BootStep]) {
        var steps: [BootStep] = []

        let store: any BotStore
        do {
            store = try await storeOpener.open()
        } catch {
            await health.setStore(.down)
            throw BootError.storeHeld(detail: String(describing: error))
        }
        await health.setStore(.up)
        steps.append(.openedStore)

        for port in [configuration.healthPort, configuration.callbackPort] {
            do {
                try await binder.bind(port: port, address: configuration.listenAddress)
            } catch {
                await store.close()
                throw BootError.portInUse(port: port, detail: String(describing: error))
            }
            steps.append(.bound(port: port))
        }

        if let verification {
            do {
                try await verification.health()
            } catch {
                await store.close()
                await health.setVerification(.down)
                throw error
            }
            await health.setVerification(.up)
            steps.append(.verificationReachable)

            let probe = try await verification.probeSharedSecret()
            steps.append(.probedSharedSecret(probe))
            if probe == .disagreed {
                await store.close()
                throw BootError.sharedSecretMismatch
            }
        } else {
            await health.setVerification(.off)
        }

        // The validator's own answer is what the registrar takes, so these
        // two steps cannot be put in the other order by an edit.
        let validated = try CommandValidator.validated(catalog)
        steps.append(.validatedCatalog(commandCount: validated.commands.count))

        try await registrar.register(validated, guildId: configuration.guildId)
        steps.append(.registeredCommands(commandCount: validated.commands.count))

        try await gateway.identify()
        steps.append(.identified)

        // Health is **not** raised here. Identifying is asking for a
        // websocket, not having one: the call returns as soon as the attempt
        // is under way, so a `200` at this point tells a deploy gate the bot
        // is serving while the gateway may still be unreachable, and every
        // interaction after it is delivered to nobody. Only the gateway's own
        // ready event raises it (`SEE-1.a`).
        steps.append(.ready)
        return (store, steps)
    }
}
