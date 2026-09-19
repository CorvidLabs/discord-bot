@preconcurrency import Foundation
import Reserve
import Store

/// A ledger that stops answering part way through an epoch.
///
/// The closest a test in one process gets to a machine losing power in the
/// middle of a payout: every write up to the cut lands and is readable, the
/// write at the cut never happens, and the run throws from inside the loop
/// rather than finishing tidily. That is the shape a crash actually has, and it
/// is what the resume has to survive.
internal actor CuttingReserveStore: ReserveStore {

    // MARK: - Properties

    /// Whether the cut happens instead of the write, or just after it.
    internal enum Moment: Sendable {

        /// The write never reaches the store.
        case insteadOfWriting

        /// The write lands and the process dies before the caller returns.
        case afterWriting
    }

    private let inner: any ReserveStore
    private let cutAfterSaves: Int
    private let moment: Moment
    private var saves = 0

    // MARK: - Initializers

    /// - Parameters:
    ///   - inner: The real ledger.
    ///   - cutAfterSaves: Which save is the last one, counting from one.
    ///   - moment: Whether the last save lands.
    internal init(inner: any ReserveStore, cutAfterSaves: Int, moment: Moment) {
        self.inner = inner
        self.cutAfterSaves = cutAfterSaves
        self.moment = moment
    }

    // MARK: - Internal Methods

    internal func loadState() async throws -> ReserveState {
        try await inner.loadState()
    }

    internal func save(state: ReserveState) async throws {
        try await cut { try await self.inner.save(state: state) }
    }

    internal func loadEpoch(streamId: String, epoch: UInt64) async throws -> ReserveEpochRecord {
        try await inner.loadEpoch(streamId: streamId, epoch: epoch)
    }

    internal func save(epoch record: ReserveEpochRecord) async throws {
        try await cut { try await self.inner.save(epoch: record) }
    }

    // MARK: - Private Methods

    private func cut(_ write: () async throws -> Void) async throws {
        saves += 1
        guard saves >= cutAfterSaves else {
            try await write()
            return
        }
        if case .afterWriting = moment {
            try await write()
        }
        throw CutShort()
    }
}

/// What a cut throws.
///
/// Its own type so a test can tell a deliberate cut from a store that broke,
/// and so the runner treats it the way it treats any store failure rather than
/// the way it treats a payment refusal.
internal struct CutShort: Error, Equatable, Sendable {}

/// A payer that writes down every line it was asked to pay.
///
/// The record is the assertion. "Nobody was paid twice" is only checkable
/// against a list of who was actually asked, kept somewhere the crash does not
/// reach, which is why this is separate from the ledger under test.
internal actor RecordingPayer: ReservePayer {

    // MARK: - Properties

    /// Accounts this payer was asked to pay, in order, across every run.
    internal private(set) var paidAccounts: [String] = []

    /// Holding ids paid for, in order, across every run.
    internal private(set) var paidHoldingIds: [String] = []

    // MARK: - Initializers

    internal init() {}

    // MARK: - Internal Methods

    internal func pay(entry: ReserveEpochEntry, streamId: String, epoch: UInt64) async throws -> String {
        paidAccounts.append(entry.account)
        paidHoldingIds.append(contentsOf: entry.claimedHoldingIds)
        return "RECEIPT-\(streamId)-\(epoch)-\(paidAccounts.count)"
    }

    /// Accounts paid more than once, which must always be empty.
    internal var duplicateAccounts: [String] {
        Self.duplicates(in: paidAccounts)
    }

    /// Holdings paid for more than once, which must always be empty.
    internal var duplicateHoldingIds: [String] {
        Self.duplicates(in: paidHoldingIds)
    }

    /// Forgets everything, for a behaviour that reuses one payer across epochs.
    internal func reset() {
        paidAccounts = []
        paidHoldingIds = []
    }

    // MARK: - Private Methods

    private static func duplicates(in values: [String]) -> [String] {
        var seen: Set<String> = []
        var repeated: Set<String> = []
        for value in values where !seen.insert(value).inserted {
            repeated.insert(value)
        }
        return repeated.sorted()
    }
}
