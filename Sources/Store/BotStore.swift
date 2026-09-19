@preconcurrency import Foundation
import Chain
import Gating
import Reserve

/// Members, and the keys this instance drew for them.
public protocol MemberDirectory: Sendable {

    /// The member behind a chat account id, or nil when this instance has
    /// never seen them.
    func member(externalId: String) async throws -> MemberRecord?

    /// The member a key names, or nil when nothing is on record under it.
    func member(key: MemberKey) async throws -> MemberRecord?

    /// The member behind a chat account id, minting a key the first time.
    ///
    /// Idempotent: a member already on record comes back with the key and the
    /// arrival time they already had. Re-minting on every call would give the
    /// same person a new identity every time they ran a command, and the epoch
    /// ledger would stop recognising anybody.
    func admitMember(externalId: String, at date: Date) async throws -> MemberRecord

    /// How many members have at least one proved account.
    ///
    /// Read by the sweep guard, so this counts members and not accounts: a
    /// member with three accounts is one member, and counting accounts would
    /// hide the collapse the guard exists to catch.
    func verifiedMemberCount() async throws -> Int

    /// Everything held about a member, or nil when nothing is.
    func disclosure(memberKey: MemberKey) async throws -> MemberDisclosure?

    /// Removes everything about a member (VERIFY-7).
    ///
    /// One transaction. A crash half way through would otherwise leave a member
    /// gone from one table and present in another, and half a member is a
    /// member the next sweep still acts on.
    ///
    /// Forgetting somebody who is not on record is not an error: it answers
    /// with nothing cleared. A member asking twice should be told the same
    /// thing both times.
    @discardableResult
    func forget(memberKey: MemberKey) async throws -> ForgetOutcome
}

/// The accounts members proved, and what they were last read as holding.
public protocol AccountStore: Sendable {

    /// Every account this member proved, oldest first.
    func accounts(memberKey: MemberKey) async throws -> [AccountRecord]

    /// The account at this address, whoever proved it, or nil.
    func account(address: String) async throws -> AccountRecord?

    /// Records a proved account.
    ///
    /// Re-proving an account the same member already has updates when they
    /// proved it and leaves the stored figures alone, because the caller that
    /// just read them passes them through ``recordBalances(address:directBaseUnits:liquidityBaseUnits:at:)``.
    ///
    /// - Throws: ``StoreError/accountAlreadyProven(address:)`` when a different
    ///   member proved it. One account, one member.
    func prove(account: AccountRecord) async throws

    /// Writes what an account was just read as holding.
    ///
    /// - Throws: ``StoreError/accountAlreadyProven(address:)`` is not thrown
    ///   here; an address nobody proved is simply not written, and the answer
    ///   says so.
    /// - Returns: Whether an account was there to write to.
    @discardableResult
    func recordBalances(
        address: String,
        directBaseUnits: UInt64,
        liquidityBaseUnits: UInt64,
        at date: Date
    ) async throws -> Bool

    /// Removes one account, leaving the member and their other accounts alone
    /// (VERIFY-3).
    /// - Returns: Whether there was one to remove.
    @discardableResult
    func unlink(address: String) async throws -> Bool
}

extension AccountStore {

    /// A member's stored figures, in the shape the ladder adds up.
    ///
    /// The list
    /// ``Gating/CombinedBalance/afterLinking(account:directBaseUnits:liquidityBaseUnits:knownAccounts:)``
    /// asks for. Offered here rather than left to each caller so nobody writes
    /// the one-line sum that demotes a member for linking an empty wallet.
    public func balances(memberKey: MemberKey) async throws -> [AccountBalance] {
        try await accounts(memberKey: memberKey).map(\.balance)
    }
}

/// The sweep guard's baseline.
public protocol RoleBaselineStore: Sendable {

    /// What the last sweep that ran recorded, or nil before any has.
    ///
    /// Nil falls back to the zero floor alone, which is the documented
    /// behaviour of a first run. An unreadable row throws instead, because a
    /// corrupt baseline read as nil disarms the halving check silently.
    func loadRoleBaseline() async throws -> RoleBaselineRecord?

    /// Records the count a sweep that ran observed.
    func save(roleBaseline: RoleBaselineRecord) async throws
}

/// Everything one instance keeps, in one value a host can hold.
///
/// Composed from the concerns rather than gathered into one wide protocol,
/// because a concern is the unit a backend implements and a test covers. The
/// last two are the seams the engine declared before any of this existed, and
/// they are adopted exactly as written.
public protocol BotStore: MemberDirectory, AccountStore, RoleBaselineStore, ReserveStore, RequestBudgetStore {

    /// Releases whatever the store is holding: the file, the handle, and the
    /// lock that keeps a second process out.
    ///
    /// Not a `deinit`, because releasing the lock has to be something a caller
    /// can order and wait for. A store that is not closed is released when the
    /// process ends, which is the ordinary case and is why nothing depends on
    /// this being called.
    func close() async
}
