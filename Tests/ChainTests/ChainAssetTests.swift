import Foundation
import Testing
@testable import Chain

/// The asset an operator brings, and writing its amounts out.
///
/// The precision is the whole suite. A layer that assumes six decimals is
/// correct for exactly one token and wrong by a factor of ten for every missing
/// place everywhere else, and it is wrong silently: every balance still looks
/// like a balance.
@Suite("The asset an operator brings")
internal struct ChainAssetTests {

    // MARK: - Precision

    @Test("An asset with two decimal places is not quietly given six")
    internal func precisionComesFromConfiguration() throws {
        let cents = try ChainAsset(id: 11, symbol: "CENTS", decimals: 2)
        #expect(cents.baseUnitsPerWholeUnit == 100)
        #expect(try cents.baseUnits(whole: 7) == 700)
        #expect(cents.format(12_345) == "123.45")

        let six = try Fixture.asset()
        #expect(six.baseUnitsPerWholeUnit == 1_000_000)
        #expect(six.format(12_345) == "0.012345")
    }

    @Test("An asset with no decimal places counts in whole things")
    internal func zeroDecimals() throws {
        let tickets = try ChainAsset(id: 3, symbol: "TICKETS", decimals: 0)
        #expect(tickets.baseUnitsPerWholeUnit == 1)
        #expect(try tickets.baseUnits(whole: 9) == 9)
        #expect(tickets.format(9) == "9")
    }

    @Test("An asset id of zero is refused, because an unset variable arrives as zero")
    internal func assetIdZeroRefused() {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.assetId,
            value: "0",
            expected: "an asset id greater than zero"
        )) {
            _ = try ChainAsset(id: 0, symbol: "TOKEN", decimals: 6)
        }
    }

    @Test("A blank symbol is refused rather than printed as nothing")
    internal func blankSymbolRefused() {
        #expect(throws: ChainConfigurationError.missing(variable: ChainEnvironment.assetSymbol)) {
            _ = try ChainAsset(id: 1, symbol: "   ", decimals: 6)
        }
    }

    @Test("Twenty decimal places is refused rather than overflowing later")
    internal func tooManyDecimalsRefused() {
        #expect(throws: ChainConfigurationError.invalidValue(
            variable: ChainEnvironment.assetDecimals,
            value: "20",
            expected: "0 to 19 decimal places"
        )) {
            _ = try ChainAsset(id: 1, symbol: "TOKEN", decimals: 20)
        }
    }

    @Test("A whole amount too large to count in smallest units refuses instead of wrapping")
    internal func overflowRefused() throws {
        let asset = try Fixture.asset()
        #expect(throws: ChainConfigurationError.self) {
            _ = try asset.baseUnits(whole: UInt64.max)
        }
    }

    // MARK: - Writing amounts out

    @Test("An amount keeps every digit it was given")
    internal func amountsKeepTheirDigits() throws {
        let asset = try Fixture.asset()
        #expect(asset.format(269_230_769_230) == "269,230.76923")
        #expect(asset.formatWithSymbol(1_000_000) == "1 TOKEN")
        #expect(asset.format(1) == "0.000001")
        #expect(asset.format(0) == "0")
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
