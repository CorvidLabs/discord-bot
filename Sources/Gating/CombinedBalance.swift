import Foundation

/// What one account is recorded as holding.
public struct AccountBalance: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The account.
    public let account: String

    /// The gated token held directly, in base units.
    public let directBaseUnits: UInt64

    /// The gated token inside this account's liquidity positions, in base
    /// units.
    public let liquidityBaseUnits: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - account: The account.
    ///   - directBaseUnits: Held directly, in base units.
    ///   - liquidityBaseUnits: Held in pools, in base units.
    public init(account: String, directBaseUnits: UInt64, liquidityBaseUnits: UInt64 = 0) {
        self.account = account
        self.directBaseUnits = directBaseUnits
        self.liquidityBaseUnits = liquidityBaseUnits
    }
}

/// Adding a member's accounts up without demoting them for owning more than
/// one.
public enum CombinedBalance: Sendable {

    /// A member's holdings across every account, added up.
    public struct Totals: Sendable, Equatable {

        // MARK: - Properties

        /// Held directly, across every account.
        public let direct: UInt64

        /// Held inside liquidity positions, across every account.
        public let liquidity: UInt64

        /// The two added together. This is what the ladder is read against.
        public let combined: UInt64

        /// Whether the member has more than the one account in hand.
        ///
        /// True from ``CombinedBalance/across(_:)`` when the list held more
        /// than one account, and true from
        /// ``CombinedBalance/afterLinking(account:directBaseUnits:liquidityBaseUnits:knownAccounts:)``
        /// when something was on record besides the account that just signed.
        /// Both answer the question a card asks: is this figure the whole of
        /// what they hold, or only the part in front of us?
        public let otherAccountsExist: Bool

        // MARK: - Initializers

        /// - Parameters:
        ///   - direct: Held directly, across every account.
        ///   - liquidity: Held in pools, across every account.
        ///   - combined: The two added together.
        ///   - otherAccountsExist: Whether there is more than the one account
        ///     in hand.
        public init(direct: UInt64, liquidity: UInt64, combined: UInt64, otherAccountsExist: Bool) {
            self.direct = direct
            self.liquidity = liquidity
            self.combined = combined
            self.otherAccountsExist = otherAccountsExist
        }
    }

    // MARK: - Public Methods

    /// Adds every account up, or says that nothing was added up.
    ///
    /// **An empty list is ``Reading/unknown``, never a total of nothing.** A
    /// caller reaches an empty array two ways, and they want opposite
    /// decisions: the member really has no account, or the accounts could not
    /// be listed, because the store was locked, a migration was halfway
    /// through, or the member unlinked between one query and the next.
    /// Handing back a confident zero for both is the same collapse
    /// ``Reading`` exists to prevent, one level up: the zero reads as a member
    /// who sold everything, and a sweep takes every rung off somebody whose
    /// holdings nobody looked at, while reporting a complete decision with
    /// nothing to investigate.
    ///
    /// A member who provably has no account is
    /// ``MemberHoldings/unlinked(memberId:configuration:)``, which says so and
    /// is read rather than unread.
    public static func across(_ accounts: [AccountBalance]) -> Reading<Totals> {
        guard !accounts.isEmpty else { return .unknown }
        let direct = accounts.reduce(UInt64(0)) { saturatingSum($0, $1.directBaseUnits) }
        let liquidity = accounts.reduce(UInt64(0)) { saturatingSum($0, $1.liquidityBaseUnits) }
        return .known(
            Totals(
                direct: direct,
                liquidity: liquidity,
                combined: saturatingSum(direct, liquidity),
                otherAccountsExist: accounts.count > 1
            )
        )
    }

    /// The totals to decide roles on straight after a member links an
    /// account.
    ///
    /// Verification reads only the account that just signed; a sweep reads
    /// them all. Deciding on the new account alone is what demoted a member
    /// on the top rung for linking an empty second wallet, which happened on
    /// a real morning to a real person and is the reason this function is not
    /// a one-line sum at the call site.
    ///
    /// The account being linked is dropped from `knownAccounts` before the
    /// sum, so re-verifying an account already on record uses the figure just
    /// read rather than the stale one stored beside it.
    ///
    /// - Parameters:
    ///   - account: The account that just signed.
    ///   - directBaseUnits: What it was just read as holding directly.
    ///   - liquidityBaseUnits: What it was just read as holding in pools.
    ///   - knownAccounts: Every account already on record for this member,
    ///     with their stored figures.
    public static func afterLinking(
        account: String,
        directBaseUnits: UInt64,
        liquidityBaseUnits: UInt64,
        knownAccounts: [AccountBalance]
    ) -> Totals {
        let others = knownAccounts.filter { $0.account != account }
        let direct = others.reduce(directBaseUnits) { saturatingSum($0, $1.directBaseUnits) }
        let liquidity = others.reduce(liquidityBaseUnits) { saturatingSum($0, $1.liquidityBaseUnits) }
        return Totals(
            direct: direct,
            liquidity: liquidity,
            combined: saturatingSum(direct, liquidity),
            otherAccountsExist: !others.isEmpty
        )
    }

    // MARK: - Private Methods

    /// Adds, stopping at the ceiling rather than wrapping.
    ///
    /// A wrapped sum puts the largest holder in the server on no rung, which
    /// is the one failure mode nobody would think to look for.
    private static func saturatingSum(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
        return overflowed ? UInt64.max : sum
    }
}
