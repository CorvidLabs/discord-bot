import Chain
import Foundation
import Reserve
import Store
import Testing

/// A store whose day count throws, and which is otherwise a real one.
///
/// The case exists because a row that cannot be read must **throw** rather
/// than come back empty: an unreadable count read as "nothing recorded" hands
/// the process a fresh budget, which is the exact failure writing the count
/// down exists to prevent. Everything else forwards, so the boot gate under
/// test is the only thing behaving differently.
internal actor UnreadableBudgetStore: BotStore {

    // MARK: - Properties

    private let wrapped: any BotStore

    // MARK: - Initializers

    internal init(wrapped: any BotStore) {
        self.wrapped = wrapped
    }

    // MARK: - The one thing that is different

    internal func loadBudgetUsage() async throws -> RequestBudgetUsage? {
        throw StoreError.unreadableRow(
            row: "the day's request count",
            reason: "the test made it unreadable on purpose"
        )
    }

    internal func saveBudgetUsage(_ usage: RequestBudgetUsage) async throws {
        try await wrapped.saveBudgetUsage(usage)
    }

    // MARK: - Everything else, forwarded

    internal func member(externalId: String) async throws -> MemberRecord? {
        try await wrapped.member(externalId: externalId)
    }

    internal func member(key: MemberKey) async throws -> MemberRecord? {
        try await wrapped.member(key: key)
    }

    internal func admitMember(externalId: String, at date: Date) async throws -> MemberRecord {
        try await wrapped.admitMember(externalId: externalId, at: date)
    }

    internal func verifiedMemberCount() async throws -> Int {
        try await wrapped.verifiedMemberCount()
    }

    internal func disclosure(memberKey: MemberKey) async throws -> MemberDisclosure? {
        try await wrapped.disclosure(memberKey: memberKey)
    }

    @discardableResult
    internal func forget(memberKey: MemberKey) async throws -> ForgetOutcome {
        try await wrapped.forget(memberKey: memberKey)
    }

    internal func accounts(memberKey: MemberKey) async throws -> [AccountRecord] {
        try await wrapped.accounts(memberKey: memberKey)
    }

    internal func account(address: String) async throws -> AccountRecord? {
        try await wrapped.account(address: address)
    }

    internal func prove(account: AccountRecord) async throws {
        try await wrapped.prove(account: account)
    }

    @discardableResult
    internal func recordBalances(
        address: String,
        directBaseUnits: UInt64,
        liquidityBaseUnits: UInt64,
        at date: Date
    ) async throws -> Bool {
        try await wrapped.recordBalances(
            address: address,
            directBaseUnits: directBaseUnits,
            liquidityBaseUnits: liquidityBaseUnits,
            at: date
        )
    }

    @discardableResult
    internal func unlink(address: String) async throws -> Bool {
        try await wrapped.unlink(address: address)
    }

    internal func loadRoleBaseline() async throws -> RoleBaselineRecord? {
        try await wrapped.loadRoleBaseline()
    }

    internal func save(roleBaseline: RoleBaselineRecord) async throws {
        try await wrapped.save(roleBaseline: roleBaseline)
    }

    internal func loadState() async throws -> ReserveState {
        try await wrapped.loadState()
    }

    internal func save(state: ReserveState) async throws {
        try await wrapped.save(state: state)
    }

    internal func loadEpoch(streamId: String, epoch: UInt64) async throws -> ReserveEpochRecord {
        try await wrapped.loadEpoch(streamId: streamId, epoch: epoch)
    }

    internal func save(epoch record: ReserveEpochRecord) async throws {
        try await wrapped.save(epoch: record)
    }

    internal func close() async {
        await wrapped.close()
    }
}
