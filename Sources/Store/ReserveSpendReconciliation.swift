@preconcurrency import Foundation
import Reserve

/// Putting the reserve's recorded spend back in step with its epoch rows at
/// boot.
///
/// ## The window this closes
///
/// `ReserveStore` has four methods, and a runner claims an entry by calling two
/// of them: `save(epoch:)` then `save(state:)`. They are two commits. A crash
/// between them leaves the entry claimed, so nobody is paid twice, and leaves
/// `spentBaseUnits` short by that entry, which `ReserveState.recordingSpend`
/// names as the unsafe direction: an under-count lets a later epoch spend past
/// the allocation.
///
/// Nothing inside a store can merge two protocol calls into one transaction, so
/// this does not try. It recomputes what a stream has spent as the sum of the
/// `paidBaseUnits` on its epoch rows and takes the **larger** of that and the
/// stored figure. Upward only: an over-count tightens the ceiling and is safe,
/// so a recomputation can only ever refuse to pay something, never allow it.
///
/// It reads through the four methods the engine already declared and adds no
/// fifth, which is deliberate. The real fix is at the seam, where one call
/// writing both rows in one transaction would delete the window rather than
/// compensate for it. That is a protocol change with one implementation and no
/// deployed rows, and it is written down in the module's spec as the thing to
/// do rather than quietly worked around here.
///
/// ## When to run it
///
/// Once at boot, before anything can start an epoch, and never while a run is
/// in flight: the gate that serialises reserve runs does not know about this.
public enum ReserveSpendReconciliation: Sendable {

    // MARK: - Properties

    /// The most epochs a stream is walked back over.
    ///
    /// Comfortably past the longest schedule anybody runs. A stored epoch
    /// number beyond it is a corrupt state rather than a long schedule, and
    /// walking a truncated range would answer with a spend figure that is
    /// quietly too small, which is the exact failure this exists to prevent.
    public static let epochWalkLimit: UInt64 = 1_024

    // MARK: - Public Methods

    /// What each stream has provably spent, read off its epoch rows.
    ///
    /// - Parameters:
    ///   - store: The ledger.
    ///   - streamIds: The streams to walk. A stream nobody names is left
    ///     alone, because a walk needs a stream id and the engine holds the
    ///     catalogue, not the store.
    ///   - state: The state already loaded, so a caller that has it does not
    ///     read it twice.
    /// - Returns: The state, with any stream whose rows account for more than
    ///   its recorded figure raised to match. Never lowered.
    public static func reconciled(
        store: some ReserveStore,
        streamIds: [String],
        state: ReserveState
    ) async throws -> ReserveState {
        var corrected = state
        for streamId in streamIds {
            let throughEpoch = state.nextEpoch(streamId)
            guard throughEpoch <= epochWalkLimit else {
                throw StoreError.epochRangeTooLarge(
                    streamId: streamId,
                    epochs: throughEpoch,
                    limit: epochWalkLimit
                )
            }
            var recomputed: UInt64 = 0
            var epoch: UInt64 = 1
            while epoch <= throughEpoch {
                let record = try await store.loadEpoch(streamId: streamId, epoch: epoch)
                let (sum, overflow) = recomputed.addingReportingOverflow(record.paidBaseUnits)
                recomputed = overflow ? UInt64.max : sum
                epoch += 1
            }
            if recomputed > corrected.spent(streamId) {
                corrected.spentBaseUnits[streamId] = recomputed
            }
        }
        return corrected
    }

    /// Reconciles and writes the result back, when anything moved.
    ///
    /// - Returns: The streams whose recorded spend was raised, so a boot log
    ///   can name them. An empty answer is the ordinary case and means the
    ///   rows and the state already agreed.
    @discardableResult
    public static func reconcile(
        store: some ReserveStore,
        streamIds: [String]
    ) async throws -> [String] {
        let state = try await store.loadState()
        let corrected = try await reconciled(store: store, streamIds: streamIds, state: state)
        guard corrected != state else { return [] }
        try await store.save(state: corrected)
        return streamIds
            .filter { corrected.spent($0) != state.spent($0) }
            .sorted()
    }
}
