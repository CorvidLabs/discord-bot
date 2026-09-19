@preconcurrency import Foundation
import Chain
import Reserve
import Store

extension SQLiteStore {

    // MARK: - Public Methods, the reserve seam

    public func loadState() async throws -> ReserveState {
        var scheduleId: String?
        var activatedAt: Date?
        var found = false
        let scalars = try handle.prepare(
            "SELECT schedule_id, activated_at FROM reserve_state WHERE id = 1"
        )
        if try scalars.step() {
            found = true
            scheduleId = scalars.text(0)
            activatedAt = try scalars.instant(1, row: StoreTable.reserveState)
        }

        var completedEpochs: [String: UInt64] = [:]
        var spentBaseUnits: [String: UInt64] = [:]
        var lastPeriodKeys: [String: String] = [:]
        let streams = try handle.prepare(
            """
            SELECT stream_id, completed_epochs, spent_base_units, last_period_key
            FROM reserve_streams
            ORDER BY stream_id ASC
            """
        )
        while try streams.step() {
            found = true
            let streamId = try streams.requiredText(0, row: "reserve_streams")
            // Zero is left out of both maps rather than written into them. The
            // value answers zero for a stream it has never heard of, so an
            // entry saying zero and no entry at all are the same reading, and
            // putting one in would make a state that went through this store
            // unequal to the state that was handed to it.
            let completed = try streams.amount(1, row: "reserve_streams")
            if completed != 0 { completedEpochs[streamId] = completed }
            let spent = try streams.amount(2, row: "reserve_streams")
            if spent != 0 { spentBaseUnits[streamId] = spent }
            if let key = streams.text(3) { lastPeriodKeys[streamId] = key }
        }

        // Nothing written at all is a fresh reserve. Anything written is read
        // back whole, because a half-read state is how a stream loses an epoch
        // it already finished.
        guard found else { return ReserveState() }
        return ReserveState(
            scheduleId: scheduleId,
            activatedAt: activatedAt,
            completedEpochs: completedEpochs,
            spentBaseUnits: spentBaseUnits,
            lastPeriodKeys: lastPeriodKeys
        )
    }

    public func save(state: ReserveState) async throws {
        let recorded = StoreDate.recorded(state)
        var streamIds = Set(recorded.completedEpochs.keys)
        streamIds.formUnion(recorded.spentBaseUnits.keys)
        streamIds.formUnion(recorded.lastPeriodKeys.keys)

        try write { connection in
            try connection.execute(
                """
                INSERT INTO reserve_state (id, schedule_id, activated_at)
                VALUES (1, ?, ?)
                ON CONFLICT (id) DO UPDATE SET
                    schedule_id = excluded.schedule_id,
                    activated_at = excluded.activated_at
                """,
                [
                    recorded.scheduleId.map { .text($0) } ?? .null,
                    recorded.activatedAt.map { .integer(StoreDate.seconds($0)) } ?? .null
                ]
            )
            // The state is one value the engine writes back whole, so the rows
            // are replaced whole. A stream that has gone from the value has to
            // go from the file, or it comes back on the next read.
            try connection.execute("DELETE FROM reserve_streams")
            for streamId in streamIds.sorted() {
                try connection.execute(
                    """
                    INSERT INTO reserve_streams (
                        stream_id, completed_epochs, spent_base_units, last_period_key
                    )
                    VALUES (?, ?, ?, ?)
                    """,
                    [
                        .text(streamId),
                        BaseUnits.value(recorded.completedEpochs(streamId)),
                        BaseUnits.value(recorded.spent(streamId)),
                        recorded.lastPeriodKey(streamId).map { .text($0) } ?? .null
                    ]
                )
            }
        }
    }

    public func loadEpoch(streamId: String, epoch: UInt64) async throws -> ReserveEpochRecord {
        let row = "\(StoreTable.reserveEpochs)/\(streamId)/\(epoch)"
        let statement = try handle.prepare(
            """
            SELECT paid_base_units, started_at, completed_at
            FROM reserve_epochs
            WHERE stream_id = ? AND epoch = ?
            """,
            [.text(streamId), BaseUnits.value(epoch)]
        )
        // An epoch nobody has run reads as unpaid, which is different from
        // missing and the caller must never have to tell them apart.
        guard try statement.step() else {
            return ReserveEpochRecord(streamId: streamId, epoch: epoch)
        }
        let paidBaseUnits = try statement.amount(0, row: row)
        let startedAt = try statement.instant(1, row: row)
        let completedAt = try statement.instant(2, row: row)

        var claims: [Schema.ClaimKind: [String]] = [:]
        let rows = try handle.prepare(
            """
            SELECT kind, value
            FROM reserve_epoch_claims
            WHERE stream_id = ? AND epoch = ?
            ORDER BY kind ASC, ordinal ASC
            """,
            [.text(streamId), BaseUnits.value(epoch)]
        )
        while try rows.step() {
            let rawKind = try rows.requiredInteger(0, row: row)
            guard let kind = Schema.ClaimKind(rawValue: rawKind) else {
                throw StoreError.unreadableRow(
                    row: row,
                    reason: "a claim of kind \(rawKind), which this build does not know"
                )
            }
            claims[kind, default: []].append(try rows.requiredText(1, row: row))
        }

        return ReserveEpochRecord(
            streamId: streamId,
            epoch: epoch,
            paidAccounts: claims[.account] ?? [],
            paidRecipientIds: claims[.recipient] ?? [],
            claimedHoldingIds: claims[.holding] ?? [],
            paidBaseUnits: paidBaseUnits,
            startedAt: startedAt,
            completedAt: completedAt
        )
    }

    public func save(epoch record: ReserveEpochRecord) async throws {
        let recorded = StoreDate.recorded(record)
        let memoKey = Self.memoKey(streamId: recorded.streamId, epoch: recorded.epoch)
        // Nil means this handle has not written this epoch yet, so what is on
        // disk is unknown and every claim row is written out in full. After
        // that first save the memo is what the rows are, and only the
        // difference goes to disk.
        let previous = lastWrittenClaims[memoKey]
        let current: [Int64: [String]] = [
            Schema.ClaimKind.account.rawValue: recorded.paidAccounts,
            Schema.ClaimKind.recipient.rawValue: recorded.paidRecipientIds,
            Schema.ClaimKind.holding.rawValue: recorded.claimedHoldingIds
        ]

        try write { connection in
            try connection.execute(
                """
                INSERT INTO reserve_epochs (
                    stream_id, epoch, paid_base_units, started_at, completed_at
                )
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (stream_id, epoch) DO UPDATE SET
                    paid_base_units = excluded.paid_base_units,
                    started_at = excluded.started_at,
                    completed_at = excluded.completed_at
                """,
                [
                    .text(recorded.streamId),
                    BaseUnits.value(recorded.epoch),
                    BaseUnits.value(recorded.paidBaseUnits),
                    recorded.startedAt.map { .integer(StoreDate.seconds($0)) } ?? .null,
                    recorded.completedAt.map { .integer(StoreDate.seconds($0)) } ?? .null
                ]
            )
            for kind in Schema.ClaimKind.allCases {
                try Self.syncClaims(
                    connection: connection,
                    streamId: recorded.streamId,
                    epoch: recorded.epoch,
                    kind: kind,
                    values: current[kind.rawValue] ?? [],
                    stored: previous?[kind.rawValue]
                )
            }
        }

        // Only after the commit. A transaction that rolled back would leave a
        // memo describing rows that are not there, and the next save would
        // append to a prefix that never landed.
        lastWrittenClaims[memoKey] = current
    }

    // MARK: - Public Methods, the request budget seam

    public func loadBudgetUsage() async throws -> RequestBudgetUsage? {
        let statement = try handle.prepare(
            "SELECT used_requests, day_start FROM request_budget WHERE id = 1"
        )
        // Nil means never written and nothing else. An unreadable row throws
        // instead, because a count read as absent hands the process a fresh
        // budget, which is the exact failure the persistence exists to prevent.
        guard try statement.step() else { return nil }
        return RequestBudgetUsage(
            usedRequests: try statement.amount(0, row: StoreTable.requestBudget),
            dayStart: try statement.requiredInstant(1, row: StoreTable.requestBudget)
        )
    }

    public func saveBudgetUsage(_ usage: RequestBudgetUsage) async throws {
        let recorded = StoreDate.recorded(usage)
        try write { connection in
            try connection.execute(
                """
                INSERT INTO request_budget (id, used_requests, day_start)
                VALUES (1, ?, ?)
                ON CONFLICT (id) DO UPDATE SET
                    used_requests = excluded.used_requests,
                    day_start = excluded.day_start
                """,
                [
                    BaseUnits.value(recorded.usedRequests),
                    .integer(StoreDate.seconds(recorded.dayStart))
                ]
            )
        }
    }

    // MARK: - Private Methods

    /// The key an epoch's claim rows are remembered under.
    internal static func memoKey(streamId: String, epoch: UInt64) -> String {
        "\(streamId)#\(epoch)"
    }

    /// Brings one kind of claim row in line with the list the record carries.
    ///
    /// Written as an append wherever it can be, and that is the point rather
    /// than an optimisation. A runner saves the whole record once per
    /// recipient, so a list stored inside the epoch row is rewritten and
    /// flushed at a size that grows with the epoch: hundreds of megabytes for
    /// a few thousand slots, quadratic beyond that, and a payout slow enough
    /// for an operator to kill half way through, which delivers the
    /// half-finished payout the whole design exists to prevent.
    ///
    /// The append is only sound when the rows already there really are a
    /// prefix of what is being saved. Comparing the whole prefix is what makes
    /// that exact: checking only the last element would let a list that
    /// changed in the middle at the same length be stored as it used to be.
    /// The comparison is in memory and the saving is on disk, which is the
    /// right way round.
    ///
    /// - Parameter stored: What the rows are, or nil when that is not known,
    ///   which means writing them all out.
    private static func syncClaims(
        connection: Connection,
        streamId: String,
        epoch: UInt64,
        kind: Schema.ClaimKind,
        values: [String],
        stored: [String]?
    ) throws {
        let keys: [SQLValue] = [.text(streamId), BaseUnits.value(epoch), .integer(kind.rawValue)]
        var appendFrom = 0
        if let stored, stored.count <= values.count, Array(values.prefix(stored.count)) == stored {
            appendFrom = stored.count
        } else if stored?.isEmpty != true {
            try connection.execute(
                """
                DELETE FROM reserve_epoch_claims
                WHERE stream_id = ? AND epoch = ? AND kind = ?
                """,
                keys
            )
        }

        guard appendFrom < values.count else { return }
        for index in appendFrom..<values.count {
            try connection.execute(
                """
                INSERT OR REPLACE INTO reserve_epoch_claims (
                    stream_id, epoch, kind, value, ordinal
                )
                VALUES (?, ?, ?, ?, ?)
                """,
                keys + [.text(values[index]), .integer(Int64(index))]
            )
        }
    }
}
