@preconcurrency import Foundation
import Store

/// How to corrupt a row of the store that keeps them in memory.
///
/// Offered here rather than left to a test target so the in-memory store is
/// held to the same rule the durable one is: a row that cannot be read throws.
/// A backend that cannot be made to fail is a backend whose failure handling is
/// never exercised.
public struct InMemoryCorruptionProbe: CorruptionProbe {

    // MARK: - Properties

    private let store: InMemoryStore

    // MARK: - Initializers

    /// - Parameter store: The store to write unreadable rows into.
    public init(store: InMemoryStore) {
        self.store = store
    }

    // MARK: - Public Methods

    public func corruptReserveEpoch(streamId: String, epoch: UInt64) async throws {
        await store.corruptEpoch(streamId: streamId, epoch: epoch, raw: Self.rubbish)
    }

    public func corruptBudgetUsage() async throws {
        await store.corruptBudget(raw: Self.rubbish)
    }

    public func corruptAccount(address: String) async throws {
        await store.corruptAccount(address: address, raw: Self.rubbish)
    }

    public func corruptReserveState() async throws {
        await store.corruptState(raw: Self.rubbish)
    }

    public func corruptRoleBaseline() async throws {
        await store.corruptBaseline(raw: Self.rubbish)
    }

    // MARK: - Private Methods

    /// Something that is present, non-empty, and not the value it should be.
    ///
    /// Not an empty string, because an empty row is the easy case. This one is
    /// well-formed text that is the wrong shape, which is what a half-written
    /// row or a schema from another version actually looks like.
    private static let rubbish = "{\"this\":\"is not a record\"}"
}

extension StoreConformance {

    // MARK: - Public Methods

    /// The suite, pointed at the store that keeps rows in memory.
    ///
    /// The lane a contributor hits first: no file, no driver, no socket and
    /// nothing installed (BUILD-2). It supplies no durability probe, so the
    /// behaviours that prove a claim reaches storage report as skipped with a
    /// reason, which makes "this store is not durable" something the suite says
    /// rather than something a reader has to know.
    public static func inMemory() -> StoreConformance {
        StoreConformance(backend: "in memory") {
            let store = InMemoryStore()
            return StoreUnderTest(
                store: store,
                corruption: InMemoryCorruptionProbe(store: store),
                durability: nil
            )
        }
    }
}
