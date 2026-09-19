@preconcurrency import Foundation
import Store

/// One freshly made store, with whatever a backend can offer to prove things
/// about itself.
///
/// The probes arrive with the store rather than with the suite because they are
/// properties of a particular file or a particular process, not of a backend in
/// the abstract. A backend that cannot supply one says so by leaving it nil, and
/// the behaviours that need it are reported as skipped rather than passing on
/// nothing.
public struct StoreUnderTest: Sendable {

    // MARK: - Properties

    /// The store the behaviours run against.
    public let store: any BotStore

    /// How to write a row no reader can parse, or nil when a backend cannot.
    public let corruption: (any CorruptionProbe)?

    /// How to look at the same storage from somewhere else, or nil.
    public let durability: (any DurabilityProbe)?

    // MARK: - Initializers

    /// - Parameters:
    ///   - store: The store, with nothing in it.
    ///   - corruption: How to write an unreadable row.
    ///   - durability: How to look at the same storage from elsewhere.
    public init(
        store: any BotStore,
        corruption: (any CorruptionProbe)? = nil,
        durability: (any DurabilityProbe)? = nil
    ) {
        self.store = store
        self.corruption = corruption
        self.durability = durability
    }
}

/// Writing a row the store's own reader cannot parse.
///
/// Without this, the most important rule in the package is asserted in a
/// comment. A ledger row that reads as blank looks like an epoch nobody was paid
/// for, and the next run pays every one of them again, so "an unreadable row
/// throws" has to be something a test can produce rather than something a
/// reviewer can only hope for.
public protocol CorruptionProbe: Sendable {

    /// Leaves one epoch's row present and unparseable.
    func corruptReserveEpoch(streamId: String, epoch: UInt64) async throws

    /// Leaves the day's request count present and unparseable.
    func corruptBudgetUsage() async throws

    /// Leaves one account's row present and unparseable.
    func corruptAccount(address: String) async throws

    /// Leaves the reserve's own state present and unparseable.
    ///
    /// The row that decides which epoch is next and which period has already
    /// been claimed. Read as a fresh reserve it disarms the cadence guard and
    /// the spend ceiling together, which is why it is not enough for the
    /// unreadable-row rule to be proved on the epoch row alone.
    func corruptReserveState() async throws

    /// Leaves the sweep baseline present and unparseable.
    ///
    /// The one with no second guard behind it. A baseline read as nothing is a
    /// first run, a first run is allowed to sweep, and a sweep with nobody
    /// verified takes every managed role off every member in the server.
    func corruptRoleBaseline() async throws
}

/// Looking at the same storage from somewhere other than the handle that wrote
/// to it.
///
/// This is the only way a store can be asked whether a save that returned is
/// really there, rather than sitting in a buffer or behind a task nobody
/// awaited. A backend whose rows die with the process supplies nothing here, and
/// the suite then states that it is not durable rather than quietly passing.
public protocol DurabilityProbe: Sendable {

    /// Lets the handle go the way a stopped process does, then opens the same
    /// storage again.
    ///
    /// What it proves: a save that returned is readable by a handle that never
    /// saw the writer's memory. What it does not prove: that the bytes reached
    /// the platter. Only a power cut proves that, and no test has one.
    func reopenAfterAbandoning() async throws -> any BotStore

    /// A second view of the same storage, while the first is still open.
    ///
    /// The one that catches the regression most likely to be introduced by
    /// somebody making an epoch loop faster: a write pushed into a detached task
    /// still returns, and still reads back from the handle that queued it, and
    /// is invisible here until it lands.
    func independentView() async throws -> any BotStore
}
