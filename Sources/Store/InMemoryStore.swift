@preconcurrency import Foundation
import Chain
import Gating
import Reserve

/// The whole store, in memory, as a real implementation rather than a stub.
///
/// It exists so a contributor can build the rest of the product against a store
/// on the first afternoon, with no file, no driver, no server and nothing
/// installed (BUILD-2). It passes the same conformance suite the durable
/// backend does, minus the durability behaviours, which it refuses to supply a
/// probe for: a green tick against a store that forgets everything on exit
/// would be the suite telling a comfortable lie.
///
/// Two things it does on purpose, both so a test that passes here means
/// something:
///
/// - **Rows are kept as encoded text, not as live values.** Every read goes
///   through the same decode a file-backed store does, so the rule that an
///   unreadable row throws is exercised rather than asserted.
/// - **Instants are rounded to whole seconds**, exactly as a column would round
///   them, so a record that round-trips here round-trips on disk too.
public actor InMemoryStore: BotStore {

    // MARK: - Properties

    private var memberRows: [String: String] = [:]
    private var externalIndex: [ByteKey: String] = [:]
    private var accountRows: [ByteKey: String] = [:]
    private var baselineRow: String?
    private var reserveStateRow: String?
    private var reserveEpochRows: [String: String] = [:]
    private var budgetRow: String?

    // MARK: - Initializers

    public init() {}

    // MARK: - Public Methods

    /// The row key one epoch is kept under.
    public static func epochKey(streamId: String, epoch: UInt64) -> String {
        "\(streamId)#\(epoch)"
    }

    // MARK: - Public Methods, members

    public func member(externalId: String) async throws -> MemberRecord? {
        guard let key = externalIndex[ByteKey(externalId)] else { return nil }
        return try decodeMember(key: key)
    }

    public func member(key: MemberKey) async throws -> MemberRecord? {
        try decodeMember(key: key.value)
    }

    public func admitMember(externalId: String, at date: Date) async throws -> MemberRecord {
        if let existing = try await member(externalId: externalId) { return existing }
        let record = MemberRecord(key: MemberKey.mint(), externalId: externalId, firstSeenAt: date)
        memberRows[record.key.value] = try ReserveCoding.encode(record)
        externalIndex[ByteKey(externalId)] = record.key.value
        return record
    }

    public func verifiedMemberCount() async throws -> Int {
        var keys: Set<String> = []
        for raw in accountRows.values {
            keys.insert(try decodeAccount(raw: raw).memberKey.value)
        }
        return keys.count
    }

    public func disclosure(memberKey: MemberKey) async throws -> MemberDisclosure? {
        guard let member = try decodeMember(key: memberKey.value) else { return nil }
        return MemberDisclosure(
            member: member,
            accounts: try await accounts(memberKey: memberKey),
            retainedAfterForgetting: [MemberDisclosure.payoutLedgerSentence]
        )
    }

    @discardableResult
    public func forget(memberKey: MemberKey) async throws -> ForgetOutcome {
        var cleared: [String: Int] = [:]
        let owned = try await accounts(memberKey: memberKey)
        for account in owned {
            accountRows[ByteKey(account.address)] = nil
        }
        cleared[StoreTable.accounts] = owned.count
        if let member = try decodeMember(key: memberKey.value) {
            memberRows[memberKey.value] = nil
            externalIndex[ByteKey(member.externalId)] = nil
            cleared[StoreTable.members] = 1
        } else {
            cleared[StoreTable.members] = 0
        }
        return ForgetOutcome(memberKey: memberKey, cleared: cleared)
    }

    // MARK: - Public Methods, accounts

    public func accounts(memberKey: MemberKey) async throws -> [AccountRecord] {
        var owned: [AccountRecord] = []
        for raw in accountRows.values {
            let record = try decodeAccount(raw: raw)
            if record.memberKey == memberKey { owned.append(record) }
        }
        // Oldest first, then by address, because two accounts proved in the
        // same second must still come back in one order rather than whichever
        // the dictionary felt like.
        return owned.sorted { lhs, rhs in
            lhs.provenAt == rhs.provenAt ? lhs.address < rhs.address : lhs.provenAt < rhs.provenAt
        }
    }

    public func account(address: String) async throws -> AccountRecord? {
        guard let raw = accountRows[ByteKey(address)] else { return nil }
        return try decodeAccount(raw: raw)
    }

    public func prove(account: AccountRecord) async throws {
        if let existing = try await self.account(address: account.address) {
            guard existing.memberKey == account.memberKey else {
                throw StoreError.accountAlreadyProven(address: account.address)
            }
            let kept = AccountRecord(
                memberKey: account.memberKey,
                address: account.address,
                provenAt: account.provenAt,
                directBaseUnits: existing.directBaseUnits,
                liquidityBaseUnits: existing.liquidityBaseUnits,
                balancesReadAt: existing.balancesReadAt
            )
            accountRows[ByteKey(account.address)] = try ReserveCoding.encode(kept)
            return
        }
        guard memberRows[account.memberKey.value] != nil else {
            throw StoreError.memberNotFound(key: account.memberKey.value)
        }
        accountRows[ByteKey(account.address)] = try ReserveCoding.encode(account)
    }

    @discardableResult
    public func recordBalances(
        address: String,
        directBaseUnits: UInt64,
        liquidityBaseUnits: UInt64,
        at date: Date
    ) async throws -> Bool {
        guard let existing = try await account(address: address) else { return false }
        let updated = AccountRecord(
            memberKey: existing.memberKey,
            address: existing.address,
            provenAt: existing.provenAt,
            directBaseUnits: directBaseUnits,
            liquidityBaseUnits: liquidityBaseUnits,
            balancesReadAt: date
        )
        accountRows[ByteKey(address)] = try ReserveCoding.encode(updated)
        return true
    }

    @discardableResult
    public func unlink(address: String) async throws -> Bool {
        guard accountRows[ByteKey(address)] != nil else { return false }
        accountRows[ByteKey(address)] = nil
        return true
    }

    // MARK: - Public Methods, the sweep baseline

    public func loadRoleBaseline() async throws -> RoleBaselineRecord? {
        guard let baselineRow else { return nil }
        return try decode(RoleBaselineRecord.self, from: baselineRow, row: StoreTable.roleBaseline)
    }

    public func save(roleBaseline: RoleBaselineRecord) async throws {
        baselineRow = try ReserveCoding.encode(roleBaseline)
    }

    // MARK: - Public Methods, the reserve seam

    public func loadState() async throws -> ReserveState {
        guard let reserveStateRow else { return ReserveState() }
        return try decode(ReserveState.self, from: reserveStateRow, row: StoreTable.reserveState)
    }

    public func save(state: ReserveState) async throws {
        reserveStateRow = try ReserveCoding.encode(StoreDate.recorded(state))
    }

    public func loadEpoch(streamId: String, epoch: UInt64) async throws -> ReserveEpochRecord {
        let key = Self.epochKey(streamId: streamId, epoch: epoch)
        guard let raw = reserveEpochRows[key] else {
            return ReserveEpochRecord(streamId: streamId, epoch: epoch)
        }
        return try decode(ReserveEpochRecord.self, from: raw, row: "\(StoreTable.reserveEpochs)/\(key)")
    }

    public func save(epoch record: ReserveEpochRecord) async throws {
        let key = Self.epochKey(streamId: record.streamId, epoch: record.epoch)
        reserveEpochRows[key] = try ReserveCoding.encode(StoreDate.recorded(record))
    }

    // MARK: - Public Methods, the request budget seam

    public func loadBudgetUsage() async throws -> RequestBudgetUsage? {
        guard let budgetRow else { return nil }
        return try decode(RequestBudgetUsage.self, from: budgetRow, row: StoreTable.requestBudget)
    }

    public func saveBudgetUsage(_ usage: RequestBudgetUsage) async throws {
        budgetRow = try ReserveCoding.encode(StoreDate.recorded(usage))
    }

    // MARK: - Public Methods, lifecycle and probes

    public func close() async {}

    /// Writes an epoch row verbatim, so a test can see what a corrupt one does.
    public func corruptEpoch(streamId: String, epoch: UInt64, raw: String) {
        reserveEpochRows[Self.epochKey(streamId: streamId, epoch: epoch)] = raw
    }

    /// Writes the budget row verbatim.
    public func corruptBudget(raw: String) {
        budgetRow = raw
    }

    /// Writes an account row verbatim.
    public func corruptAccount(address: String, raw: String) {
        accountRows[ByteKey(address)] = raw
    }

    /// Writes the reserve's state row verbatim.
    public func corruptState(raw: String) {
        reserveStateRow = raw
    }

    /// Writes the sweep baseline row verbatim.
    public func corruptBaseline(raw: String) {
        baselineRow = raw
    }

    // MARK: - Private Methods

    private func decodeMember(key: String) throws -> MemberRecord? {
        guard let raw = memberRows[key] else { return nil }
        return try decode(MemberRecord.self, from: raw, row: "\(StoreTable.members)/\(key)")
    }

    private func decodeAccount(raw: String) throws -> AccountRecord {
        try decode(AccountRecord.self, from: raw, row: StoreTable.accounts)
    }

    /// Decodes, turning any failure into the store's own refusal.
    ///
    /// Named rather than inlined so every read in this actor throws the same
    /// thing, and so there is exactly one place where somebody could be tempted
    /// to write `?? .init()`.
    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from raw: String,
        row: String
    ) throws -> Value {
        do {
            return try ReserveCoding.decode(Value.self, from: raw)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.unreadableRow(row: row, reason: "\(error)")
        }
    }
}

/// A text key compared byte by byte, the way a column is.
///
/// Swift's `String` equality is canonical equivalence: two identifiers whose
/// bytes differ but whose characters normalise to the same thing are one key.
/// A database column's `UNIQUE` is a byte comparison. Keyed by `String`, this
/// store would hand the second of two byte-distinct chat ids the first one's
/// member key, and with it the first one's wallets and rungs, while the durable
/// backend treated them as two people. Keyed by the bytes, both answer the same.
private struct ByteKey: Hashable {

    // MARK: - Properties

    private let bytes: [UInt8]

    // MARK: - Initializers

    fileprivate init(_ value: String) {
        self.bytes = Array(value.utf8)
    }
}
