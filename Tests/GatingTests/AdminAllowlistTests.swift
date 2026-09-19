import Foundation
import Testing
@testable import Gating

/// Who may administer a server's gating, and the entry that is deliberately
/// not there.
@Suite("Admin allowlist")
struct AdminAllowlistTests {

    // MARK: - Nobody is on it by default

    @Test("A fresh deployment has no administrators except the ones its operator named (HOST-3)")
    func noBuiltInMember() throws {
        // Nothing is added to this list at boot, by anybody. A list with a
        // member in it that the person running the software did not put there
        // is an administrator they never agreed to.
        #expect(try AdminAllowlist.load(from: [:]).isEmpty)
        #expect(AdminAllowlist().accounts.isEmpty)
        #expect(try AdminAllowlist.load(from: [:]).allows("ANY-ACCOUNT") == false)
    }

    @Test("The allowlist is exactly the accounts the operator numbered")
    func loadsFromConfiguration() throws {
        let list = try AdminAllowlist.load(from: [
            "ADMIN_WALLET_1": "ACCOUNT-ONE",
            "ADMIN_WALLET_2": "ACCOUNT-TWO",
            // Four is written but three is not, so four never appears.
            "ADMIN_WALLET_4": "ACCOUNT-FOUR"
        ])
        #expect(list.accounts == ["ACCOUNT-ONE", "ACCOUNT-TWO"])
        #expect(list.allows("ACCOUNT-TWO"))
        #expect(list.allows("ACCOUNT-FOUR") == false)
    }

    // MARK: - It can always be emptied

    @Test("Every entry can be taken off, including the last one")
    func everythingIsRemovable() {
        // An allowlist somebody cannot empty is an allowlist somebody does
        // not own.
        let list = AdminAllowlist(accounts: ["ACCOUNT-ONE", "ACCOUNT-TWO"])
        let alone = list.removing("ACCOUNT-ONE")
        #expect(alone.accounts == ["ACCOUNT-TWO"])
        #expect(alone.removing("ACCOUNT-TWO").isEmpty)
    }

    @Test("Adding an account already on the list changes nothing")
    func addingIsIdempotent() {
        let list = AdminAllowlist(accounts: ["ACCOUNT-ONE"])
        #expect(list.adding("ACCOUNT-ONE").accounts == ["ACCOUNT-ONE"])
        #expect(list.adding("ACCOUNT-TWO").accounts == ["ACCOUNT-ONE", "ACCOUNT-TWO"])
    }

    @Test("Blank entries and repeats are dropped, and the order the operator wrote is kept")
    func tidying() {
        let list = AdminAllowlist(accounts: ["  ACCOUNT-ONE  ", "", "ACCOUNT-TWO", "ACCOUNT-ONE"])
        #expect(list.accounts == ["ACCOUNT-ONE", "ACCOUNT-TWO"])
    }

    @Test("An allowlist longer than this module reads is refused, not quietly cut short")
    func tooManyAccountsRefused() throws {
        // An administrator the operator wrote down and this module dropped is
        // somebody locked out of their own deployment with nothing said.
        var environment: [String: String] = [:]
        for index in 1...(NumberedEnvironment.maxEntries + 1) {
            environment["ADMIN_WALLET_\(index)"] = "ACCOUNT-\(index)"
        }
        #expect(
            throws: GatingConfigurationError.tooManyEntries(
                key: "ADMIN_WALLET_\(NumberedEnvironment.maxEntries + 1)",
                limit: NumberedEnvironment.maxEntries
            )
        ) {
            try AdminAllowlist.load(from: environment)
        }
    }

    @Test("An account is compared exactly, because this layer does not know the alphabet")
    func comparisonIsExact() {
        let list = AdminAllowlist(accounts: ["ACCOUNT-ONE"])
        #expect(list.allows("ACCOUNT-ONE"))
        #expect(list.allows("account-one") == false)
    }
}
