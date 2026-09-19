@preconcurrency import Foundation
import Gating

/// An account a member proved, and what it was last read as holding.
///
/// Two balance halves rather than one, and that is not padding. Verification
/// reads the account that just signed and nothing else, so deciding roles from
/// that account alone demotes a member who links an empty second wallet. The
/// stored halves are what
/// ``Gating/CombinedBalance/afterLinking(account:directBaseUnits:liquidityBaseUnits:knownAccounts:)``
/// adds the new reading to, and it wants them apart because a card says how
/// much of a total is pooled (VERIFY-2.a, ROLE-2).
public struct AccountRecord: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// The member this account belongs to.
    public let memberKey: MemberKey

    /// The account. Unique across the instance: one account, one member.
    public let address: String

    /// When the member proved it.
    public let provenAt: Date

    /// The gated token held directly, in base units, as last read.
    public let directBaseUnits: UInt64

    /// The gated token inside this account's liquidity positions, in base
    /// units, as last read.
    public let liquidityBaseUnits: UInt64

    /// When the two figures were last read, or nil when nobody has read them.
    ///
    /// Nil is not zero. An account proved a minute ago whose balances have not
    /// been read yet holds an unknown amount, and a caller that treats the
    /// stored zero as a reading takes a rung off somebody nobody looked at.
    public let balancesReadAt: Date?

    // MARK: - Initializers

    /// - Parameters:
    ///   - memberKey: The member this account belongs to.
    ///   - address: The account.
    ///   - provenAt: When the member proved it, recorded to the second.
    ///   - directBaseUnits: Held directly, in base units.
    ///   - liquidityBaseUnits: Held in pools, in base units.
    ///   - balancesReadAt: When the figures were read, or nil.
    public init(
        memberKey: MemberKey,
        address: String,
        provenAt: Date,
        directBaseUnits: UInt64 = 0,
        liquidityBaseUnits: UInt64 = 0,
        balancesReadAt: Date? = nil
    ) {
        self.memberKey = memberKey
        self.address = address
        self.provenAt = StoreDate.whole(provenAt)
        self.directBaseUnits = directBaseUnits
        self.liquidityBaseUnits = liquidityBaseUnits
        self.balancesReadAt = StoreDate.whole(balancesReadAt)
    }

    // MARK: - Public Methods

    /// The stored figures in the shape the ladder adds up.
    public var balance: AccountBalance {
        AccountBalance(
            account: address,
            directBaseUnits: directBaseUnits,
            liquidityBaseUnits: liquidityBaseUnits
        )
    }
}
