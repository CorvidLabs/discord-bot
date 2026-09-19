import Foundation
import Testing
@testable import Gating

/// The difference between nothing and nobody looked.
@Suite("Readings")
struct ReadingTests {

    // MARK: - The distinction

    @Test("Nothing read and nothing held are different answers to different questions")
    func unknownIsNotEmpty() {
        let nothing: Reading<UInt64> = .known(0)
        let nobodyLooked: Reading<UInt64> = .unknown
        #expect(nothing != nobodyLooked)
        #expect(nothing.isKnown)
        #expect(nobodyLooked.isKnown == false)
    }

    @Test("Asking an unread fact for its value refuses, and says what was not read")
    func requireThrows() throws {
        let reading: Reading<UInt64> = .unknown
        #expect(throws: UnreadableError(subject: "the member's balance")) {
            _ = try reading.require("the member's balance")
        }
        #expect(try Reading.known(UInt64(7)).require("the member's balance") == 7)
    }

    @Test("An unread fact stays unread however it is transformed")
    func mappingKeepsTheUnknown() {
        let known: Reading<Int> = .known(3)
        let unknown: Reading<Int> = .unknown
        #expect(known.map { $0 * 2 } == .known(6))
        #expect(unknown.map { $0 * 2 } == Reading<Int>.unknown)
    }

    // MARK: - Holdings

    @Test("A combined balance needs both halves before it is a number at all")
    func combinedNeedsBothHalves() {
        let missingDirect = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .unknown,
            liquidityPositions: .known([])
        )
        let missingPositions = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(100),
            liquidityPositions: .unknown
        )
        let both = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(100),
            liquidityPositions: .known([
                LiquidityPosition(poolId: "a", lpBaseUnits: 1, tokenBaseUnits: 25)
            ])
        )
        #expect(missingDirect.combinedBalance == .unknown)
        #expect(missingPositions.combinedBalance == .unknown)
        #expect(both.combinedBalance == .known(125))
        #expect(both.liquidityBalance == .known(25))
        #expect(both.isProvidingLiquidity == .known(true))
    }

    @Test("A balance that would overflow stops at the ceiling rather than wrapping to nothing")
    func combinedSaturates() {
        // A wrapped sum would put the largest holder in the server on no rung
        // at all, which is the one failure nobody would think to look for.
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(UInt64.max),
            liquidityPositions: .known([
                LiquidityPosition(poolId: "a", lpBaseUnits: 1, tokenBaseUnits: 1_000)
            ])
        )
        #expect(holdings.combinedBalance == .known(UInt64.max))
    }

    @Test("A pool the member is absent from is a zero position, once the list has been read")
    func absentPoolIsZero() {
        let holdings = MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            liquidityPositions: .known([
                LiquidityPosition(poolId: "a", lpBaseUnits: 5, tokenBaseUnits: 10)
            ])
        )
        #expect(holdings.position(inPool: "a").isKnown)
        #expect(holdings.position(inPool: "b") == .known(
            LiquidityPosition(poolId: "b", lpBaseUnits: 0, tokenBaseUnits: 0)
        ))
        // With no list read at all, the same question has no answer.
        let unread = MemberHoldings(memberId: "member-1", isVerified: true)
        #expect(unread.position(inPool: "a") == .unknown)
    }

    // MARK: - Adding accounts up

    @Test("Linking an empty second account does not demote somebody for owning two wallets")
    func linkingAnEmptyAccount() {
        // This happened, to a real person, on a real morning: verification
        // read only the account that had just signed, so the member's whole
        // holding looked like the nothing in the new wallet.
        let totals = CombinedBalance.afterLinking(
            account: "ACCOUNT-NEW",
            directBaseUnits: 0,
            liquidityBaseUnits: 0,
            knownAccounts: [
                AccountBalance(account: "ACCOUNT-OLD", directBaseUnits: 5_000, liquidityBaseUnits: 500)
            ]
        )
        #expect(totals.direct == 5_000)
        #expect(totals.liquidity == 500)
        #expect(totals.combined == 5_500)
        #expect(totals.otherAccountsExist)
    }

    @Test("Verifying an account again uses the figure just read, not the one stored beside it")
    func reverifyingUsesTheFreshFigure() {
        let totals = CombinedBalance.afterLinking(
            account: "ACCOUNT-ONE",
            directBaseUnits: 9_000,
            liquidityBaseUnits: 0,
            knownAccounts: [
                AccountBalance(account: "ACCOUNT-ONE", directBaseUnits: 1, liquidityBaseUnits: 0),
                AccountBalance(account: "ACCOUNT-TWO", directBaseUnits: 1_000, liquidityBaseUnits: 0)
            ]
        )
        #expect(totals.direct == 10_000)
        #expect(totals.otherAccountsExist)
    }

    @Test("A member with one account is told they have only the one")
    func singleAccount() {
        let totals = CombinedBalance.afterLinking(
            account: "ACCOUNT-ONE",
            directBaseUnits: 10,
            liquidityBaseUnits: 0,
            knownAccounts: []
        )
        #expect(totals.combined == 10)
        #expect(totals.otherAccountsExist == false)
    }

    @Test("Every account a member has is added up, wallet side and pool side separately")
    func addingAccountsUp() throws {
        let totals = try CombinedBalance.across([
            AccountBalance(account: "ACCOUNT-ONE", directBaseUnits: 100, liquidityBaseUnits: 2),
            AccountBalance(account: "ACCOUNT-TWO", directBaseUnits: 200, liquidityBaseUnits: 10)
        ]).require("the member's accounts")

        #expect(totals.direct == 300)
        #expect(totals.liquidity == 12)
        #expect(totals.combined == 312)
        #expect(totals.otherAccountsExist)

        let alone = try CombinedBalance.across([
            AccountBalance(account: "ACCOUNT-ONE", directBaseUnits: 7)
        ]).require("the member's accounts")
        #expect(alone.combined == 7)
        #expect(alone.liquidity == 0)
        #expect(alone.otherAccountsExist == false)
    }

    @Test("Accounts that would overflow added together stop at the ceiling")
    func addingAccountsSaturates() throws {
        let totals = try CombinedBalance.across([
            AccountBalance(account: "ACCOUNT-ONE", directBaseUnits: UInt64.max, liquidityBaseUnits: UInt64.max),
            AccountBalance(account: "ACCOUNT-TWO", directBaseUnits: 1, liquidityBaseUnits: 1)
        ]).require("the member's accounts")

        #expect(totals.direct == UInt64.max)
        #expect(totals.liquidity == UInt64.max)
        #expect(totals.combined == UInt64.max)
    }

    @Test("No account read is not a member who holds nothing")
    func noAccountsIsUnread() {
        // A locked store, a migration halfway through, a member who unlinked
        // between one query and the next: each hands the caller an empty
        // array. Adding that up to a confident nought is the collapse this
        // whole type exists to prevent, and it reads as somebody who sold up.
        #expect(CombinedBalance.across([]) == .unknown)

        // A member who provably has no account says so instead, and is read.
        let configuration = try? Fixture.configuration()
        if let configuration {
            let unlinked = MemberHoldings.unlinked(memberId: "member-1", configuration: configuration)
            #expect(unlinked.directBalance == .known(0))
            #expect(unlinked.isVerified == false)
        }
    }
}
