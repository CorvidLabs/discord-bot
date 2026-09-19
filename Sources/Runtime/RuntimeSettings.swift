import Chain
import Foundation
import Gating

/// The names of the variables this program reads for itself.
///
/// Held in one place, like ``Chain/ChainEnvironment``, so a refusal names the
/// exact variable and the catalogue takes the name from the constant rather
/// than retyping it.
public enum RuntimeEnvironment: Sendable {

    /// Where this instance keeps what it remembers. Required, and absolute.
    public static let storePath = "STORE_PATH"

    /// The port the health endpoint listens on. Required.
    public static let healthPort = "HEALTH_PORT"

    /// The address the health endpoint binds. Loopback unless set.
    public static let healthAddress = "HEALTH_ADDRESS"

    /// The address the endpoint binds when nothing says otherwise.
    public static let defaultHealthAddress = "127.0.0.1"
}

/// What this program needs that no other module reads.
///
/// Three values, and two of them are required with no default. Two more lines
/// in a first run, against the two defaults that bite hardest later: a shared
/// port that collides on the second community, and a relative path that
/// quietly becomes a second empty store.
public struct RuntimeSettings: Sendable, Equatable {

    // MARK: - Properties

    /// The store file. Absolute.
    public let storePath: String

    /// The port to bind. Zero is accepted, and means the operating system
    /// chooses, which is what lets a test bind without picking a number.
    public let healthPort: UInt16

    /// The address to bind.
    public let healthAddress: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - storePath: The store file. Absolute.
    ///   - healthPort: The port to bind.
    ///   - healthAddress: The address to bind.
    public init(storePath: String, healthPort: UInt16, healthAddress: String) {
        self.storePath = storePath
        self.healthPort = healthPort
        self.healthAddress = healthAddress
    }

    // MARK: - Public Methods

    /// Reads them, or refuses naming the variable.
    ///
    /// - Parameter lookup: Reads one variable.
    public static func load(_ lookup: (String) -> String?) throws -> RuntimeSettings {
        let path = try NumberedEnvironment.required(
            RuntimeEnvironment.storePath,
            purpose: "It is where this instance keeps what it remembers.",
            lookup
        )
        // Absolute, and this is not fussiness. A relative path is resolved
        // against the working directory, and a supervisor that starts the
        // process from a different directory after a reboot hands the same
        // command a different, empty store, which reads as a reserve that has
        // never paid anybody.
        guard path.hasPrefix("/") else {
            throw BootFailure(
                variable: RuntimeEnvironment.storePath,
                summary: "\(RuntimeEnvironment.storePath) is `\(path)`, which is relative to "
                    + "whatever directory this process happens to start in.",
                remedy: "Write it as an absolute path. A supervisor restarting from another "
                    + "directory would otherwise open a different and empty store, which looks "
                    + "exactly like a first boot.",
                code: .configuration
            )
        }

        let rawPort = try NumberedEnvironment.required(
            RuntimeEnvironment.healthPort,
            purpose: "It is the port the health endpoint listens on.",
            lookup
        )
        guard
            let number = UInt64(NumberedEnvironment.withoutDigitSeparators(rawPort)),
            number <= UInt64(UInt16.max)
        else {
            throw BootFailure(
                variable: RuntimeEnvironment.healthPort,
                summary: "\(RuntimeEnvironment.healthPort) is `\(rawPort)`, which is not a port.",
                remedy: "Write a number from 0 to 65535. Zero lets the operating system choose.",
                code: .configuration
            )
        }

        return RuntimeSettings(
            storePath: path,
            healthPort: UInt16(number),
            healthAddress: NumberedEnvironment.nonEmpty(RuntimeEnvironment.healthAddress, lookup)
                ?? RuntimeEnvironment.defaultHealthAddress
        )
    }
}

/// Everything the boot needs, loaded and checked, before anything is touched.
///
/// The one gate that reaches nothing, so a wrong variable costs no lock, no
/// socket and no request.
public struct LoadedConfiguration: Sendable {

    // MARK: - Properties

    /// What holding something earns somebody.
    public let gating: GatingConfiguration

    /// What this reads from the chain, and how hard.
    public let chain: ChainConfiguration

    /// What this program needs for itself.
    public let runtime: RuntimeSettings

    /// Every variable any loader asked for.
    public let keysRead: Set<String>

    // MARK: - Initializers

    /// - Parameters:
    ///   - gating: What holding something earns somebody.
    ///   - chain: What this reads from the chain.
    ///   - runtime: What this program needs for itself.
    ///   - keysRead: Every variable any loader asked for.
    public init(
        gating: GatingConfiguration,
        chain: ChainConfiguration,
        runtime: RuntimeSettings,
        keysRead: Set<String>
    ) {
        self.gating = gating
        self.chain = chain
        self.runtime = runtime
        self.keysRead = keysRead
    }

    // MARK: - Public Methods

    /// Loads everything, in the order the existing code requires.
    ///
    /// The token first, because the ladder's thresholds cannot be converted
    /// without its decimals and the pools cannot be given an asset id without
    /// its asset id (`GatingConfiguration.load`). That is why the first thing
    /// a clean machine is told to set is the asset id.
    ///
    /// - Parameters:
    ///   - settings: The one snapshot of the machine's variables.
    ///   - alsoRead: Variables something outside this module reads from the
    ///     same snapshot, recorded so the audit does not report them as set
    ///     and read by nobody. The one caller is a linked chat surface, which
    ///     reads its own variables because this module is not allowed to name
    ///     them (`BUILD-4`). The same compromise the chain loader already
    ///     makes, for the same reason: a read this reader cannot see.
    /// - Throws: ``BootFailure`` naming the variable to change.
    public static func load(
        _ settings: Settings,
        alsoRead: [String] = []
    ) throws -> LoadedConfiguration {
        do {
            let loaded = try settings.read { reader -> LoadedConfiguration in
                reader.note(alsoRead)
                let gating = try GatingConfiguration.load(reader.lookup)
                // The chain loader takes a dictionary rather than a lookup, so
                // its reads cannot record themselves. The names are noted from
                // the catalogue, which takes them from the constants that own
                // them.
                reader.note(SettingsCatalogue.chainNames)
                let chain = try ChainConfiguration.load(
                    token: gating.token,
                    environment: reader.settings.dictionary
                )
                return LoadedConfiguration(
                    gating: gating,
                    chain: chain,
                    runtime: try RuntimeSettings.load(reader.lookup),
                    keysRead: []
                )
            }
            return LoadedConfiguration(
                gating: loaded.value.gating,
                chain: loaded.value.chain,
                runtime: loaded.value.runtime,
                keysRead: loaded.keysRead
            )
        } catch {
            throw BootFailure.configuration(error)
        }
    }
}
