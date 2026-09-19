import Foundation
import Store

/// A store that was opened, and what opening it did.
public struct OpenedStore: Sendable {

    // MARK: - Properties

    /// What this instance remembers between restarts.
    public let store: any BotStore

    /// Migrations this start applied, named.
    public let migrationsApplied: [String]

    /// Whether there was no store at this path and this start made one.
    ///
    /// **Worth printing at every start.** A volume that did not mount, a
    /// mistyped path and a deleted file all arrive looking exactly like a
    /// genuine first boot, and this is the one thing that tells them apart
    /// (SEE-8).
    public let createdFile: Bool

    // MARK: - Initializers

    /// - Parameters:
    ///   - store: What this instance remembers.
    ///   - migrationsApplied: Migrations this start applied.
    ///   - createdFile: Whether this start made the store rather than found
    ///     it.
    public init(store: any BotStore, migrationsApplied: [String], createdFile: Bool) {
        self.store = store
        self.migrationsApplied = migrationsApplied
        self.createdFile = createdFile
    }
}

/// Why a store could not be opened, in the two shapes the boot has to tell
/// apart.
public enum StoreGateError: Error, LocalizedError, Sendable, Equatable {

    /// Another process is holding this store.
    ///
    /// The other copy keeps serving, and this one stops. An exclusive lease
    /// asks the exact question a port clash only approximates: whether
    /// another instance is using **this data**. One machine hosting several
    /// communities has several instances with their own stores and their own
    /// ports, and a second instance pointed at the same store on a different
    /// port would pass a port check and fail this (RUN-7.a).
    case heldByAnotherProcess(path: String)

    /// The store is there and cannot be used: the volume cannot promise a
    /// write, the schema came from a newer build, the file is not readable.
    case unusable(path: String, reason: String)

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case .heldByAnotherProcess(let path):
            return "Another process is already holding the store at \(path). That copy is still "
                + "serving your server, so this one stopped rather than taking its place. Stop "
                + "the other instance, or give this one its own \(RuntimeEnvironment.storePath)."
        case let .unusable(path, reason):
            return "The store at \(path) cannot be used: \(reason)"
        }
    }
}

/// Where the durable store comes from.
///
/// A seam, so the store gate's refusals are reported by this module while this
/// module still links no database. The concrete store is chosen in the
/// executable, which is the only place both it and this are visible
/// (RT-001).
public protocol StoreOpening: Sendable {

    /// Opens the store, taking whatever lock keeps a second process out.
    ///
    /// - Parameter path: The store file, absolute.
    /// - Throws: ``StoreGateError``.
    func open(path: String) async throws -> OpenedStore
}
