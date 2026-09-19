import Foundation
import Gating
import Testing
@testable import Chain

/// The one token, and the two ways a whole number of it becomes smallest
/// units.
///
/// The precision is half the suite. A layer that assumes six decimals is
/// correct for exactly one token and wrong by a factor of ten for every
/// missing place everywhere else, and it is wrong silently: every balance
/// still looks like a balance (ADOPT-1.d, LEARN-7.b).
///
/// The overflow behaviour is the other half, and the two are **not** the
/// same. A threshold saturates so that a typo becomes a rung nobody reaches;
/// an amount throws so that a typo becomes a refusal. Both are pinned here,
/// because a later reader tidying one into the other would break something
/// nobody would notice for months (RAIN-15.b).
@Suite("The token, and whole units becoming smallest units")
internal struct TokenAmountTests {

    // MARK: - Precision

    @Test("A token with two decimal places is not quietly given six")
    internal func precisionComesFromConfiguration() throws {
        let cents = try TokenProfile(assetId: 11, symbol: "CENTS", decimals: 2)
        #expect(cents.baseUnitsPerWholeUnit == 100)
        #expect(try cents.amountBaseUnits(whole: 7) == 700)
        #expect(cents.format(12_345) == "123.45")

        let six = try Fixture.token()
        #expect(six.baseUnitsPerWholeUnit == 1_000_000)
        #expect(six.format(12_345) == "0.012345")
    }

    @Test("A token with no decimal places counts in whole things")
    internal func zeroDecimals() throws {
        let tickets = try TokenProfile(assetId: 3, symbol: "TICKETS", decimals: 0)
        #expect(tickets.baseUnitsPerWholeUnit == 1)
        #expect(try tickets.amountBaseUnits(whole: 9) == 9)
        #expect(tickets.wholeUnits(baseUnits: 9) == 9)
        #expect(tickets.format(9) == "9")
    }

    @Test("Smallest units come back as whole tokens rounded down, never up")
    internal func wholeUnitsRoundDown() throws {
        let token = try Fixture.token()
        #expect(token.wholeUnits(baseUnits: 1_999_999) == 1)
        #expect(token.wholeUnits(baseUnits: 2_000_000) == 2)
        #expect(token.wholeUnits(baseUnits: 999) == 0)
    }

    @Test("Twenty decimal places is refused rather than overflowing later")
    internal func tooManyDecimalsRefused() {
        #expect(throws: GatingConfigurationError.unsupportedDecimals(
            key: TokenProfile.decimalsKey,
            value: 20
        )) {
            _ = try TokenProfile(assetId: 1, symbol: "TOKEN", decimals: 20)
        }
    }

    // MARK: - Two overflow behaviours, on purpose

    @Test("An amount too large to count in smallest units refuses instead of wrapping")
    internal func amountOverflowRefused() throws {
        let token = try Fixture.token()
        #expect(throws: ChainConfigurationError.amountOverflows(whole: UInt64.max, decimals: 6)) {
            _ = try token.amountBaseUnits(whole: UInt64.max)
        }
    }

    @Test("A threshold too large to count saturates instead, so the rung is unreachable rather than free")
    internal func thresholdOverflowSaturates() throws {
        let token = try Fixture.token()
        // Deliberately the opposite of the test above. An operator who typed
        // too many zeros into a rung gets a rung nobody reaches, which is
        // visible in the server; wrapping would give them one everybody
        // reaches, which is not (ADOPT-2).
        #expect(token.baseUnits(whole: UInt64.max) == UInt64.max)
        #expect(token.baseUnits(whole: 7) == 7_000_000)
    }

    @Test("The two conversions agree on every amount that does fit")
    internal func bothAgreeWhereTheyCan() throws {
        let token = try Fixture.token()
        for whole: UInt64 in [0, 1, 7, 1_000, 1_000_000_000] {
            #expect(try token.amountBaseUnits(whole: whole) == token.baseUnits(whole: whole))
        }
    }

    // MARK: - Writing amounts out

    @Test("An amount keeps every digit it was given")
    internal func amountsKeepTheirDigits() throws {
        let token = try Fixture.token()
        #expect(token.format(269_230_769_230) == "269,230.76923")
        #expect(token.formatWithSymbol(1_000_000) == "1 TOKEN")
        #expect(token.format(1) == "0.000001")
        #expect(token.format(0) == "0")
    }

    @Test("This layer's own formatter still writes what the token's does")
    internal func chainFormattingMatchesTheToken() throws {
        let token = try Fixture.token()
        for units: UInt64 in [0, 1, 12_345, 1_000_000, 269_230_769_230] {
            #expect(ChainFormatting.amount(units, decimals: Int(token.decimals)) == token.format(units))
        }
    }

    @Test("A silly number of decimal places answers rather than taking the process down")
    internal func sillyDecimalsAreSurvivable() {
        #expect(ChainFormatting.amount(1_234, decimals: 0) == "1,234")
        #expect(ChainFormatting.amount(1_234, decimals: 99) == "1,234")
    }

    @Test("A share is written as a percentage with four places, from whole millionths")
    internal func percentages() {
        #expect(ChainFormatting.percent(millionths: 1_000_000) == "100.0000%")
        #expect(ChainFormatting.percent(millionths: 5_000) == "0.5000%")
        #expect(ChainFormatting.percent(millionths: 1) == "0.0001%")
        #expect(ChainFormatting.percent(millionths: 0) == "0.0000%")
    }

    @Test("An address keeps both ends so two of mine are still told apart")
    internal func shortening() {
        #expect(ChainFormatting.shortenAddress("ABCDEFGHIJKLMNOPQRSTUVWXYZ") == "ABCDEF...UVWXYZ")
        #expect(ChainFormatting.shortenAddress("SHORT") == "SHORT")
    }
}
