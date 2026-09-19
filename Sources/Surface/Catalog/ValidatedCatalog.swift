import Foundation

/// Proof that a catalogue went through the validator, and the commands it
/// passed with.
///
/// The same trick ``CommandCatalog`` could not play on its own. A catalogue is
/// an ordinary value anybody can build, so a registrar that took one could be
/// called with definitions nothing had ever checked. Discord answers an
/// invalid bulk registration with a `400`, the boot waiting on it fails, and
/// under a supervisor that restarts the process it fails again for ever, which
/// is the crash loop the offline validator exists to prevent (`ADOPT-2`).
///
/// So this type's initialiser is internal to this module and
/// ``CommandValidator/validated(_:)`` is the only thing that calls it. A
/// registrar in another target can hold one and cannot make one, so
/// registering before validating does not compile.
///
/// **What it proves, exactly.** It proves the definitions inside it passed the
/// validator. It does not prove they are the definitions a particular boot
/// built, because nothing stops a caller holding one made earlier. What closes
/// that gap is that a boot makes exactly one, at the step before registration.
public struct ValidatedCatalog: Sendable, Equatable {

    // MARK: - Properties

    /// The catalogue that passed.
    public let catalog: CommandCatalog

    // MARK: - Initializers

    /// Made only by a completed validation, inside this module.
    internal init(catalog: CommandCatalog) {
        self.catalog = catalog
    }

    // MARK: - Public Methods

    /// The definitions to register, in the order they were built.
    public var commands: [CommandDefinition] {
        catalog.commands
    }

    /// The names, in order.
    public var names: [String] {
        catalog.names
    }
}
