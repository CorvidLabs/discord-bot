import Foundation

/// Where the ledger lives.
///
/// The engine has no opinion about this and must not acquire one. It does not
/// know what a database is, let alone which one; a host backs this with SQLite,
/// Postgres, a key-value row, a file, or the in-memory implementation that ships
/// beside it.
///
/// Two rules an implementation has to honour, both learned the hard way:
///
/// 1. **A row that cannot be read must throw, not come back empty.** An epoch
///    record that silently reads as blank looks like an epoch nobody was paid
///    for, and the next run pays every one of them again.
/// 2. **A save must be durable before it returns.** The whole claim-before-pay
///    discipline rests on the claim being on disk when the payment is attempted.
///    A save that is still buffered when the process dies has bought nothing.
public protocol ReserveStore: Sendable {

    /// The reserve's state, or a fresh empty one if nothing has been saved.
    func loadState() async throws -> ReserveState

    /// Saves the reserve's state.
    func save(state: ReserveState) async throws

    /// One epoch's record, or a fresh unpaid one if nothing has been saved.
    ///
    /// An epoch nobody has run reads as unpaid, which is different from missing:
    /// the caller should never have to tell the two apart.
    func loadEpoch(streamId: String, epoch: UInt64) async throws -> ReserveEpochRecord

    /// Saves one epoch's record.
    func save(epoch record: ReserveEpochRecord) async throws
}

/// A ledger in memory, for tests and for trying things out.
///
/// Deliberately stores its rows as encoded text rather than as live values, so
/// it exercises the same encode/decode path a real store would and the
/// "unreadable row throws" rule is genuinely tested rather than asserted. Rows
/// do not survive the process, which is exactly why it must not be used to pay
/// anybody real.
public actor InMemoryReserveStore: ReserveStore {

    // MARK: - Properties

    private var rows: [String: String] = [:]

    // MARK: - Initializers

    public init() {}

    // MARK: - Public Methods

    /// The row key holding the reserve's state.
    public static let stateKey = "reserve.state"

    /// The row key holding one epoch's record.
    public static func epochKey(streamId: String, epoch: UInt64) -> String {
        "reserve.epoch.\(streamId).\(epoch)"
    }

    public func loadState() async throws -> ReserveState {
        guard let raw = rows[Self.stateKey] else { return ReserveState() }
        return try ReserveCoding.decode(ReserveState.self, from: raw)
    }

    public func save(state: ReserveState) async throws {
        rows[Self.stateKey] = try ReserveCoding.encode(state)
    }

    public func loadEpoch(streamId: String, epoch: UInt64) async throws -> ReserveEpochRecord {
        guard let raw = rows[Self.epochKey(streamId: streamId, epoch: epoch)] else {
            return ReserveEpochRecord(streamId: streamId, epoch: epoch)
        }
        return try ReserveCoding.decode(ReserveEpochRecord.self, from: raw)
    }

    public func save(epoch record: ReserveEpochRecord) async throws {
        let key = Self.epochKey(streamId: record.streamId, epoch: record.epoch)
        rows[key] = try ReserveCoding.encode(record)
    }

    /// Writes a row verbatim, for tests that need to see what a corrupt one does.
    public func setRaw(key: String, value: String) {
        rows[key] = value
    }

    /// Reads a row verbatim.
    public func raw(key: String) -> String? {
        rows[key]
    }

    /// How many rows exist, for tests that care about write volume.
    public var rowCount: Int { rows.count }
}
