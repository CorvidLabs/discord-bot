import Foundation

/// The accounts allowed to change a server's gating from outside Discord.
///
/// **The list starts empty, and nobody is on it who was not put there by the
/// operator.** There is no built-in member, nothing this software adds for
/// itself at boot, and no entry that refuses to be removed, including the
/// last one, because an allowlist somebody cannot empty is an allowlist
/// somebody does not own. Nobody but the operator decides who may administer
/// their project (HOST-3).
///
/// An empty allowlist is a legitimate state: it means nothing can be
/// administered by signing, which is a safe place to start and the place a
/// fresh deployment starts from.
public struct AdminAllowlist: Sendable, Equatable {

    // MARK: - Properties

    /// The allowed accounts, in the order they were configured, with
    /// duplicates removed.
    public let accounts: [String]

    // MARK: - Initializers

    /// - Parameter accounts: Accounts the operator named. Compared exactly:
    ///   an address is a fixed alphabet, and folding case here would be this
    ///   layer guessing at an encoding it deliberately knows nothing about.
    public init(accounts: [String] = []) {
        var seen: Set<String> = []
        var kept: [String] = []
        for account in accounts {
            let trimmed = account.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            kept.append(trimmed)
        }
        self.accounts = kept
    }

    // MARK: - Public Methods

    /// True when nobody can administer by signing.
    public var isEmpty: Bool { accounts.isEmpty }

    /// True when this account may administer.
    public func allows(_ account: String) -> Bool {
        accounts.contains(account)
    }

    /// The list with an account added. Adding one already on it changes
    /// nothing.
    public func adding(_ account: String) -> AdminAllowlist {
        AdminAllowlist(accounts: accounts + [account])
    }

    /// The list with an account removed.
    ///
    /// Any account, including the last one. There is deliberately no entry
    /// this refuses to remove: an allowlist somebody cannot empty is an
    /// allowlist somebody does not own.
    public func removing(_ account: String) -> AdminAllowlist {
        AdminAllowlist(accounts: accounts.filter { $0 != account })
    }
}

extension AdminAllowlist {

    // MARK: - Loading

    /// Reads the allowlist from a dictionary. The shape tests use.
    public static func load(from environment: [String: String]) throws -> AdminAllowlist {
        try load { environment[$0] }
    }

    /// Reads `ADMIN_WALLET_n` upward from 1, stopping at the first gap.
    ///
    /// Unset means an empty list, not a default member. A list longer than
    /// ``NumberedEnvironment/maxEntries`` is refused rather than cut short:
    /// an administrator the operator wrote down and this module dropped is
    /// somebody locked out of their own deployment with nothing said.
    public static func load(_ lookup: (String) -> String?) throws -> AdminAllowlist {
        var accounts: [String] = []
        for index in 1...NumberedEnvironment.maxEntries {
            guard let account = NumberedEnvironment.nonEmpty("ADMIN_WALLET_\(index)", lookup) else {
                break
            }
            accounts.append(account)
        }
        if accounts.count == NumberedEnvironment.maxEntries {
            try NumberedEnvironment.refuseOverflow("ADMIN_WALLET_\(NumberedEnvironment.maxEntries + 1)", lookup)
        }
        return AdminAllowlist(accounts: accounts)
    }
}
