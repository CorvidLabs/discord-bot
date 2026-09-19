import Foundation

/// Everything the operator wrote down, as one value read once.
///
/// A snapshot rather than a live lookup, and the reasons are worth keeping.
/// Every layer then sees the same values, so the startup report cannot
/// describe settings a loader read differently. A variable changed under a
/// running process cannot half take effect. And reading the environment while
/// another thread writes it is a data race on Linux, which one read at the top
/// of the executable avoids by construction.
///
/// **This type cannot reach the machine.** There is no initialiser that goes
/// to `ProcessInfo`, and nothing in this module has one: the single snapshot
/// is taken in the executable target and handed in (BUILD-2, BUILD-2.a). A
/// test builds one from a dictionary literal and needs nothing installed.
public struct Settings: Sendable, Equatable {

    // MARK: - Properties

    private let values: [String: String]

    // MARK: - Initializers

    /// - Parameter values: The variables, exactly as they were read.
    public init(_ values: [String: String]) {
        self.values = values
    }

    // MARK: - Public Methods

    /// One variable's value, unchanged, or nil when it is not set.
    ///
    /// Not trimmed here. Every loader in the package already decides what
    /// "set" means through ``Gating/NumberedEnvironment/nonEmpty(_:_:)``, and
    /// a second opinion at this level is how one layer came to accept what
    /// another refused.
    public func value(_ key: String) -> String? {
        values[key]
    }

    /// Every variable name that was set, in no particular order.
    public var names: Set<String> {
        Set(values.keys)
    }

    /// The variables as a dictionary, for the one loader that takes one.
    ///
    /// ``Chain/ChainConfiguration/load(token:environment:)`` takes a
    /// dictionary rather than a lookup, so a read through it cannot be
    /// recorded the way ``read(_:)`` records one. The caller notes those keys
    /// from the catalogue instead; see ``SettingsReader/note(_:)``.
    public var dictionary: [String: String] {
        values
    }

    /// Runs `body` against a reader that remembers every key it was asked
    /// for, and hands back both the result and that list.
    ///
    /// The recording is what pays for two checks that are otherwise
    /// impossible. A key read but not described in the catalogue fails the
    /// boot, so an undescribed variable cannot ship (RT-006). A key set,
    /// carrying a prefix this build owns, and read by nobody is a probable
    /// typo, and the report says so (ADOPT-9.a).
    ///
    /// The reader is deliberately not `Sendable` and deliberately scoped: the
    /// whole of configuration loading is synchronous and pure, so the
    /// recording never crosses a concurrency boundary and needs neither an
    /// actor nor a lock.
    ///
    /// - Parameter body: Reads what it needs through the reader.
    /// - Returns: What `body` produced, and every key it asked for.
    public func read<Value>(
        _ body: (SettingsReader) throws -> Value
    ) rethrows -> (value: Value, keysRead: Set<String>) {
        let reader = SettingsReader(self)
        let value = try body(reader)
        return (value, reader.keysRead)
    }
}

/// A view onto ``Settings`` that remembers what it was asked for.
///
/// Handed to the loaders as the `(String) -> String?` they already take, so
/// nothing in `Gating` or `Chain` changes to be audited.
public final class SettingsReader {

    // MARK: - Properties

    /// The settings this reads.
    public let settings: Settings

    /// Every key this reader was asked for, whether or not it was set.
    public private(set) var keysRead: Set<String> = []

    // MARK: - Initializers

    /// - Parameter settings: What to read.
    public init(_ settings: Settings) {
        self.settings = settings
    }

    // MARK: - Public Methods

    /// One variable, recorded as read.
    ///
    /// The shape every loader in the package takes. Pass it as
    /// `reader.lookup` and the loader is audited without knowing it is.
    public func lookup(_ key: String) -> String? {
        keysRead.insert(key)
        return settings.value(key)
    }

    /// Records keys read by something that could not be handed this reader.
    ///
    /// The one caller is the chain configuration, which takes a dictionary.
    /// The names come from the catalogue, which takes them from the constants
    /// that own them, so nothing here is a retyped variable name.
    ///
    /// - Parameter keys: The names to record as read.
    public func note(_ keys: some Sequence<String>) {
        keysRead.formUnion(keys)
    }
}
