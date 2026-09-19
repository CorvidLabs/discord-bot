@preconcurrency import Foundation
import Store

extension SQLiteStore {

    // MARK: - Public Methods, members

    /// The one statement that reads a member by chat account id.
    ///
    /// Named once because two callers use it, and two spellings of the same
    /// read are two things to keep in step.
    internal static let memberByExternalId: SQL = """
        SELECT member_key, external_id, first_seen_at
        FROM members
        WHERE external_id = ?
        """

    public func member(externalId: String) async throws -> MemberRecord? {
        let statement = try handle.prepare(Self.memberByExternalId, [.text(externalId)])
        guard try statement.step() else { return nil }
        return try Self.member(from: statement)
    }

    public func member(key: MemberKey) async throws -> MemberRecord? {
        let statement = try handle.prepare(
            """
            SELECT member_key, external_id, first_seen_at
            FROM members
            WHERE member_key = ?
            """,
            [.text(key.value)]
        )
        guard try statement.step() else { return nil }
        return try Self.member(from: statement)
    }

    public func admitMember(externalId: String, at date: Date) async throws -> MemberRecord {
        if let existing = try await member(externalId: externalId) { return existing }
        let record = MemberRecord(
            key: MemberKey.mint(),
            externalId: externalId,
            firstSeenAt: date
        )
        return try write { connection in
            // Read again inside the transaction that would insert. Two commands
            // arriving together would otherwise both decide the member is new,
            // and the second would fail on the unique chat id. The arrival time
            // comes off the row rather than from this call, because the member
            // arrived when they arrived.
            let racing = try connection.prepare(SQLiteStore.memberByExternalId, [.text(externalId)])
            if try racing.step() {
                return MemberRecord(
                    key: try MemberKey(try racing.requiredText(0, row: StoreTable.members)),
                    externalId: try racing.requiredText(1, row: StoreTable.members),
                    firstSeenAt: try racing.requiredInstant(2, row: StoreTable.members)
                )
            }
            try connection.execute(
                """
                INSERT INTO members (member_key, external_id, first_seen_at)
                VALUES (?, ?, ?)
                """,
                [
                    .text(record.key.value),
                    .text(externalId),
                    .integer(StoreDate.seconds(record.firstSeenAt))
                ]
            )
            return record
        }
    }

    public func verifiedMemberCount() async throws -> Int {
        // The keys are read out and decoded rather than counted in the
        // database, because `COUNT(DISTINCT member_key)` counts whatever the
        // column holds. A value that is not a key would be counted as one more
        // member, which raises the very baseline the sweep guard measures a
        // collapse against, and it would do it without a word.
        var keys: Set<String> = []
        let statement = try handle.prepare("SELECT DISTINCT member_key FROM accounts")
        while try statement.step() {
            let value = try statement.requiredText(0, row: StoreTable.accounts)
            keys.insert(try MemberKey(value).value)
        }
        return keys.count
    }

    public func disclosure(memberKey: MemberKey) async throws -> MemberDisclosure? {
        guard let member = try await member(key: memberKey) else { return nil }
        return MemberDisclosure(
            member: member,
            accounts: try await accounts(memberKey: memberKey),
            retainedAfterForgetting: [MemberDisclosure.payoutLedgerSentence]
        )
    }

    @discardableResult
    public func forget(memberKey: MemberKey) async throws -> ForgetOutcome {
        // One transaction. A crash half way through would otherwise leave a
        // member gone from one table and present in another, and half a member
        // is a member the next sweep still acts on.
        try write { connection in
            let accountCount = try connection.firstInteger(
                "SELECT COUNT(*) FROM accounts WHERE member_key = ?",
                [.text(memberKey.value)]
            ) ?? 0
            try connection.execute(
                "DELETE FROM members WHERE member_key = ?",
                [.text(memberKey.value)]
            )
            // The accounts go by cascade rather than by a second statement, so
            // a table added in two years is forgotten by the migration that
            // creates it rather than by somebody remembering this method.
            return ForgetOutcome(
                memberKey: memberKey,
                cleared: [
                    StoreTable.members: connection.changes,
                    StoreTable.accounts: Int(accountCount)
                ]
            )
        }
    }

    // MARK: - Public Methods, accounts

    public func accounts(memberKey: MemberKey) async throws -> [AccountRecord] {
        let statement = try handle.prepare(
            """
            SELECT address, member_key, proven_at, direct_base_units, liquidity_base_units,
                   balances_read_at
            FROM accounts
            WHERE member_key = ?
            ORDER BY proven_at ASC, address ASC
            """,
            [.text(memberKey.value)]
        )
        var records: [AccountRecord] = []
        while try statement.step() {
            records.append(try Self.account(from: statement))
        }
        return records
    }

    public func account(address: String) async throws -> AccountRecord? {
        let statement = try handle.prepare(
            """
            SELECT address, member_key, proven_at, direct_base_units, liquidity_base_units,
                   balances_read_at
            FROM accounts
            WHERE address = ?
            """,
            [.text(address)]
        )
        guard try statement.step() else { return nil }
        return try Self.account(from: statement)
    }

    public func prove(account: AccountRecord) async throws {
        try write { connection in
            let owner = try connection.firstText(
                "SELECT member_key FROM accounts WHERE address = ?",
                [.text(account.address)]
            )
            if let owner {
                // One account, one member. A quiet overwrite would move
                // somebody else's holdings onto a stranger's ladder, and the
                // member whose account it was would be demoted by a sweep they
                // never saw.
                guard owner == account.memberKey.value else {
                    throw StoreError.accountAlreadyProven(address: account.address)
                }
                // Re-proving your own account is ordinary. The figures stay,
                // because whoever just read them writes them through
                // `recordBalances` and this call carries no reading.
                try connection.execute(
                    "UPDATE accounts SET proven_at = ? WHERE address = ?",
                    [.integer(StoreDate.seconds(account.provenAt)), .text(account.address)]
                )
                return
            }
            let member = try connection.firstText(
                "SELECT member_key FROM members WHERE member_key = ?",
                [.text(account.memberKey.value)]
            )
            guard member != nil else {
                throw StoreError.memberNotFound(key: account.memberKey.value)
            }
            try connection.execute(
                """
                INSERT INTO accounts (
                    address, member_key, proven_at, direct_base_units, liquidity_base_units,
                    balances_read_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(account.address),
                    .text(account.memberKey.value),
                    .integer(StoreDate.seconds(account.provenAt)),
                    BaseUnits.value(account.directBaseUnits),
                    BaseUnits.value(account.liquidityBaseUnits),
                    account.balancesReadAt.map { .integer(StoreDate.seconds($0)) } ?? .null
                ]
            )
        }
    }

    @discardableResult
    public func recordBalances(
        address: String,
        directBaseUnits: UInt64,
        liquidityBaseUnits: UInt64,
        at date: Date
    ) async throws -> Bool {
        try write { connection in
            try connection.execute(
                """
                UPDATE accounts
                SET direct_base_units = ?, liquidity_base_units = ?, balances_read_at = ?
                WHERE address = ?
                """,
                [
                    BaseUnits.value(directBaseUnits),
                    BaseUnits.value(liquidityBaseUnits),
                    .integer(StoreDate.seconds(date)),
                    .text(address)
                ]
            )
            return connection.changes > 0
        }
    }

    @discardableResult
    public func unlink(address: String) async throws -> Bool {
        try write { connection in
            try connection.execute(
                "DELETE FROM accounts WHERE address = ?",
                [.text(address)]
            )
            return connection.changes > 0
        }
    }

    // MARK: - Public Methods, the sweep baseline

    public func loadRoleBaseline() async throws -> RoleBaselineRecord? {
        let statement = try handle.prepare(
            "SELECT verified_member_count, recorded_at FROM role_baseline WHERE id = 1"
        )
        guard try statement.step() else { return nil }
        // A baseline that will not read throws rather than answering with
        // nothing. Nothing is what a first run answers, and a first run is
        // allowed to sweep, so a corrupt row read as nil is the halving check
        // disarming itself on the morning it is most needed.
        let count = try statement.requiredInteger(0, row: StoreTable.roleBaseline)
        let recordedAt = try statement.requiredInstant(1, row: StoreTable.roleBaseline)
        return RoleBaselineRecord(
            verifiedMemberCount: Int(count),
            recordedAt: recordedAt
        )
    }

    public func save(roleBaseline: RoleBaselineRecord) async throws {
        try write { connection in
            try connection.execute(
                """
                INSERT INTO role_baseline (id, verified_member_count, recorded_at)
                VALUES (1, ?, ?)
                ON CONFLICT (id) DO UPDATE SET
                    verified_member_count = excluded.verified_member_count,
                    recorded_at = excluded.recorded_at
                """,
                [
                    .integer(Int64(roleBaseline.verifiedMemberCount)),
                    .integer(StoreDate.seconds(roleBaseline.recordedAt))
                ]
            )
        }
    }

    // MARK: - Private Methods

    private static func member(from statement: Statement) throws -> MemberRecord {
        MemberRecord(
            key: try MemberKey(try statement.requiredText(0, row: StoreTable.members)),
            externalId: try statement.requiredText(1, row: StoreTable.members),
            firstSeenAt: try statement.requiredInstant(2, row: StoreTable.members)
        )
    }

    private static func account(from statement: Statement) throws -> AccountRecord {
        AccountRecord(
            memberKey: try MemberKey(try statement.requiredText(1, row: StoreTable.accounts)),
            address: try statement.requiredText(0, row: StoreTable.accounts),
            provenAt: try statement.requiredInstant(2, row: StoreTable.accounts),
            directBaseUnits: try statement.amount(3, row: StoreTable.accounts),
            liquidityBaseUnits: try statement.amount(4, row: StoreTable.accounts),
            balancesReadAt: try statement.instant(5, row: StoreTable.accounts)
        )
    }
}
