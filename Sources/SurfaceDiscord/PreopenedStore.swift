import Foundation
import Store
import Surface

/// Hands the boot a store that is already open.
///
/// The host opens the store first, because the chain layer's day counter is
/// written through it and the governor has to be built with somewhere to
/// write. That keeps the documented order intact rather than bending it: the
/// lease is still taken before any port is bound and long before this process
/// speaks to Discord, which is the part that matters (`RUN-7`).
public struct PreopenedStore: StoreOpener {

    // MARK: - Properties

    /// The store, already open and already holding its lease.
    private let store: any BotStore

    // MARK: - Initializers

    /// - Parameter store: The store, already open.
    public init(_ store: any BotStore) {
        self.store = store
    }

    // MARK: - Public Methods

    public func open() async throws -> any BotStore {
        store
    }
}
