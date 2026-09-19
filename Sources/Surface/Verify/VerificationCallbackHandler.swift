@preconcurrency import Foundation
import Chain
import Gating
import Store

/// What a callback did.
public struct VerificationOutcome: Sendable, Equatable {

    // MARK: - Properties

    /// The member, as this instance names them.
    public let memberKey: MemberKey

    /// The account they proved.
    public let address: String

    /// What the rules decided, or nil when the roles were held.
    public let decision: RoleDecision?

    /// Whether the decision reached the chat client.
    public let applied: Bool

    /// Anything an operator should read, in the order it happened.
    public let notes: [String]

    // MARK: - Initializers

    /// - Parameters:
    ///   - memberKey: The member.
    ///   - address: The account they proved.
    ///   - decision: What the rules decided.
    ///   - applied: Whether it reached the chat client.
    ///   - notes: Anything an operator should read.
    public init(
        memberKey: MemberKey,
        address: String,
        decision: RoleDecision?,
        applied: Bool,
        notes: [String]
    ) {
        self.memberKey = memberKey
        self.address = address
        self.decision = decision
        self.applied = applied
        self.notes = notes
    }
}

/// Why a callback did nothing.
public enum VerificationCallbackError: Error, Equatable, LocalizedError, Sendable {

    /// It did not pass ``CallbackValidation``.
    case refused(CallbackRefusal)

    /// Another member already proved this account. One account, one member.
    case accountBelongsToSomebodyElse(address: String)

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case .refused(let refusal):
            return refusal.reason
        case .accountBelongsToSomebodyElse:
            return "That account is already proved by another member of this server."
        }
    }
}

/// The path a member actually takes into a role.
///
/// The order is the contract and every step of it was paid for.
///
/// 1. **Refuse a foreign server and a malformed id**, before anything is
///    written. A callback carries a member's chat id and an address in clear
///    text, and believing the server id in it is how one community's member
///    lands in another's store (`HOST-6`).
/// 2. **Admit the member**, which mints a ``Store/MemberKey`` the first time
///    and returns the same one every time after. Minting per call would give
///    the same person a new identity on every command and the payout ledger
///    would stop recognising anybody.
/// 3. **Prove the account.**
/// 4. **Read the chain for every account they have**, not only the one that
///    just signed. A member who links a second, empty wallet must not be
///    demoted for it (`VERIFY-2.a`).
/// 5. **Build the holdings with unknown where a read failed.** Never zero.
///    Silence from a node is not evidence that somebody sold up (`ROLE-1.a`).
/// 6. **Decide**, with `Gating/RoleRules`, which is the only thing in this
///    package that turns holdings into roles.
/// 7. **Apply the managed set in one call**, and only if the member's current
///    roles could be read.
public struct VerificationCallbackHandler: Sendable {

    // MARK: - Properties

    /// The one server this process serves.
    public let servedGuildId: String

    /// What the operator configured.
    public let configuration: GatingConfiguration

    /// Where members and accounts are kept.
    private let store: any BotStore

    /// How an account is read.
    private let reader: any AccountHoldingsReader

    /// How a decision reaches the chat client.
    private let roles: any RoleApplier

    /// Whether an address parses on this chain.
    private let isValidAddress: @Sendable (String) -> Bool

    /// The clock.
    private let now: @Sendable () -> Date

    // MARK: - Initializers

    /// - Parameters:
    ///   - servedGuildId: The one server this process serves.
    ///   - configuration: What the operator configured.
    ///   - store: Where members and accounts are kept.
    ///   - reader: How an account is read.
    ///   - roles: How a decision reaches the chat client.
    ///   - isValidAddress: Whether an address parses on this chain.
    ///   - now: The clock.
    public init(
        servedGuildId: String,
        configuration: GatingConfiguration,
        store: any BotStore,
        reader: any AccountHoldingsReader,
        roles: any RoleApplier,
        isValidAddress: @escaping @Sendable (String) -> Bool,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.servedGuildId = servedGuildId
        self.configuration = configuration
        self.store = store
        self.reader = reader
        self.roles = roles
        self.isValidAddress = isValidAddress
        self.now = now
    }

    // MARK: - Public Methods

    /// Runs one callback.
    ///
    /// - Parameter callback: What the other half sent.
    /// - Throws: ``VerificationCallbackError`` when nothing was done, or
    ///   whatever the store threw.
    @discardableResult
    public func handle(_ callback: VerificationCallback) async throws -> VerificationOutcome {
        if let refusal = CallbackValidation.refusal(
            for: callback,
            servedGuildId: servedGuildId,
            isValidAddress: isValidAddress
        ) {
            throw VerificationCallbackError.refused(refusal)
        }

        var notes: [String] = []
        let member = try await store.admitMember(externalId: callback.externalId, at: now())

        // Re-proving an account the same member already has is not an error;
        // another member's account is.
        if let existing = try await store.account(address: callback.address),
           existing.memberKey != member.key {
            throw VerificationCallbackError.accountBelongsToSomebodyElse(address: callback.address)
        }
        try await store.prove(account: AccountRecord(
            memberKey: member.key,
            address: callback.address,
            provenAt: now(),
            // The portal's figure, as a starting value. It is overwritten
            // below the moment a chain read succeeds, and it is never used to
            // decide a role: what is stored and what the rules read are two
            // different things on purpose.
            directBaseUnits: callback.balanceBaseUnits
        ))

        let accounts = try await store.accounts(memberKey: member.key)
        var checks: [WalletCheck] = []
        for account in accounts {
            do {
                // The member's own read, rationed to their share of the day, so
                // one member cannot spend the whole guild's budget by
                // verifying repeatedly. The key is this instance's own, never
                // anything that came from a chat account.
                let check = try await reader.check(
                    address: account.address,
                    for: .member(key: member.key.value)
                )
                checks.append(check)
                let direct = check.directBalance.completeValue
                let liquidity = check.liquidityAmount.completeValue
                // Both halves or neither. Writing a direct balance beside a
                // pooled half nobody could read stores a total that is wrong
                // in the direction that demotes somebody.
                if let direct, let liquidity {
                    try await store.recordBalances(
                        address: account.address,
                        directBaseUnits: direct,
                        liquidityBaseUnits: liquidity,
                        at: now()
                    )
                }
            } catch {
                // Unreadable, not empty. One wallet short makes the whole
                // member unknown, which holds every role the balance decides
                // rather than taking them away for a node that blinked.
                checks.append(.unreadable(
                    address: account.address,
                    gap: .requestFailed(String(describing: error))
                ))
                notes.append("Could not read \(Self.tail(account.address)); roles it decides were held.")
            }
        }

        let holdings = MemberHoldings.fromChain(
            memberId: member.key.value,
            isVerified: !accounts.isEmpty,
            checks: checks,
            pools: configuration.pools.pools,
            collections: configuration.collections
        )

        let currentRoleIds: Set<String>
        do {
            currentRoleIds = try await roles.currentRoleIds(externalId: callback.externalId)
        } catch {
            // An empty set here would revoke every managed role this member
            // holds, for a member nobody could look at.
            notes.append("Could not read this member's current roles, so nothing was changed.")
            return VerificationOutcome(
                memberKey: member.key,
                address: callback.address,
                decision: nil,
                applied: false,
                notes: notes
            )
        }

        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: holdings,
            currentRoleIds: currentRoleIds
        )

        var applied = false
        do {
            try await roles.apply(decision, externalId: callback.externalId)
            applied = true
        } catch {
            notes.append("Could not apply roles in Discord; the record is kept and the next sweep "
                + "will try again.")
        }
        for unknown in decision.unknowns {
            notes.append(unknown.sentence)
        }

        return VerificationOutcome(
            memberKey: member.key,
            address: callback.address,
            decision: decision,
            applied: applied,
            notes: notes
        )
    }

    // MARK: - Private Methods

    /// The last few characters of an account, so an operator log names enough
    /// to act on without printing the whole of it.
    private static func tail(_ address: String) -> String {
        address.count <= 8 ? address : "\u{2026}" + String(address.suffix(6))
    }
}
