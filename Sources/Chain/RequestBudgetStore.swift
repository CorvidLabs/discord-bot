import Foundation

/// The day's request count as it is written down.
public struct RequestBudgetUsage: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// Requests reserved so far in that day.
    public let usedRequests: UInt64

    /// Midnight UTC at the start of the day the count belongs to.
    ///
    /// Stored with the count rather than inferred on read, so yesterday's
    /// number is recognised as yesterday's and ignored instead of being spent
    /// against today.
    public let dayStart: Date

    // MARK: - Initializers

    /// - Parameter dayStart: Midnight UTC of the day the count belongs to,
    ///   stored rather than inferred later.
    public init(usedRequests: UInt64, dayStart: Date) {
        self.usedRequests = usedRequests
        self.dayStart = dayStart
    }
}

/// Where the day's request count is kept between restarts.
///
/// This layer has no idea what a database is and must not acquire one. A host
/// backs this with whatever it already has: a row, a key-value entry, a file.
///
/// Two obligations, both learned the hard way:
///
/// 1. **A row that cannot be read must throw, not come back empty.** An
///    unreadable count read as "nothing recorded" hands the process a fresh
///    budget, which is the exact failure the persistence exists to prevent.
///    `nil` means genuinely never written, and nothing else.
/// 2. **The count is written periodically, not on every request.** Writing on
///    every request would put a database write in front of every read of the
///    chain. A crash therefore loses a few requests of the count, which is a
///    trade made deliberately and bounded by
///    ``ChainLimits/budgetPersistEvery``.
public protocol RequestBudgetStore: Sendable {

    /// The last count written, or nil when nothing has ever been written.
    func loadBudgetUsage() async throws -> RequestBudgetUsage?

    /// Writes the day's count.
    func saveBudgetUsage(_ usage: RequestBudgetUsage) async throws
}

/// A count kept in memory, for tests and for trying things out.
///
/// Rows do not survive the process, which is precisely the situation the real
/// store exists to fix, so this must not be used by a deployment that restarts.
public actor InMemoryRequestBudgetStore: RequestBudgetStore {

    // MARK: - Properties

    private var usage: RequestBudgetUsage?
    private var failure: (any Error)?

    /// How many times a count has been written, for tests that care about
    /// write volume.
    public private(set) var writeCount: Int = 0

    // MARK: - Initializers

    /// - Parameter usage: A count to start with, as though a previous process
    ///   had written it.
    public init(usage: RequestBudgetUsage? = nil) {
        self.usage = usage
    }

    // MARK: - Public Methods

    /// Makes the next read throw, so a caller's handling of an unreadable row
    /// can be exercised.
    public func failReads(with error: any Error) {
        self.failure = error
    }

    public func loadBudgetUsage() async throws -> RequestBudgetUsage? {
        if let failure { throw failure }
        return usage
    }

    public func saveBudgetUsage(_ usage: RequestBudgetUsage) async throws {
        self.usage = usage
        writeCount += 1
    }

    /// The count as it stands, without going through the protocol.
    public var storedUsage: RequestBudgetUsage? { usage }
}
