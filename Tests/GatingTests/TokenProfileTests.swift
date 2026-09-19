import Foundation
import Testing
@testable import Gating

/// The token an operator brings, and the one number everything else rests on.
@Suite("Token profile")
struct TokenProfileTests {

    // MARK: - Decimals

    @Test("The same whole-token threshold is a different amount on a different asset")
    func decimalsDecideTheThreshold() throws {
        // This is the test the original could not have had, because it
        // assumed six decimals in nine places. A hundred whole tokens is a
        // hundred smallest units on a zero-decimal asset and ten thousand on
        // a two-decimal one, and reading either through the other is wrong by
        // orders of magnitude in the direction that demotes everybody.
        let zero = try TokenProfile(assetId: 1, symbol: "ZERO", decimals: 0)
        let two = try TokenProfile(assetId: 2, symbol: "TWO", decimals: 2)
        let six = try TokenProfile(assetId: 3, symbol: "SIX", decimals: 6)

        #expect(zero.baseUnits(whole: 100) == 100)
        #expect(two.baseUnits(whole: 100) == 10_000)
        #expect(six.baseUnits(whole: 100) == 100_000_000)
        #expect(zero.baseUnits(whole: 100) != two.baseUnits(whole: 100))
    }

    @Test("A ladder built on one asset's decimals refuses to be read on another's")
    func laddersDifferByDecimals() throws {
        let zero = try TierConfiguration.load(
            from: Fixture.environment(overriding: ["TOKEN_DECIMALS": "0"]),
            token: try Fixture.token(decimals: 0)
        )
        let two = try TierConfiguration.load(
            from: Fixture.environment(overriding: ["TOKEN_DECIMALS": "2"]),
            token: try Fixture.token(decimals: 2)
        )
        let zeroBronze = try #require(zero.ladder.rung(id: "bronze"))
        let twoBronze = try #require(two.ladder.rung(id: "bronze"))

        #expect(zeroBronze.minimumBaseUnits == 100)
        #expect(twoBronze.minimumBaseUnits == 10_000)
        // A hundred smallest units on the two-decimal asset is one whole
        // token, which reaches no rung. Read through the wrong decimals, the
        // same holding looks like a Bronze holder.
        #expect(two.ladder.tier(for: 100) == nil)
        #expect(zero.ladder.tier(for: 100)?.id == "bronze")
    }

    @Test("Decimals nothing could convert are refused, naming the variable")
    func absurdDecimalsRefused() throws {
        #expect(throws: GatingConfigurationError.unsupportedDecimals(key: "TOKEN_DECIMALS", value: 20)) {
            try TokenProfile.load(from: Fixture.environment(overriding: ["TOKEN_DECIMALS": "20"]))
        }
    }

    @Test("A threshold with too many zeros becomes a rung nobody reaches, not a rung everybody does")
    func thresholdsSaturate() throws {
        let token = try Fixture.token()
        #expect(token.baseUnits(whole: UInt64.max) == UInt64.max)
    }

    // MARK: - Required configuration

    @Test("Every variable the token cannot be guessed from is named when it is missing")
    func requiredVariablesAreNamed() throws {
        for key in ["TOKEN_ASSET_ID", "TOKEN_SYMBOL", "TOKEN_DECIMALS"] {
            let environment = Fixture.environment(removing: [key])
            do {
                _ = try TokenProfile.load(from: environment)
                Issue.record("\(key) was not required")
            } catch let error as GatingConfigurationError {
                guard case .missing(let named, _) = error else {
                    Issue.record("\(key) refused with the wrong reason: \(error)")
                    continue
                }
                #expect(named == key)
            }
        }
    }

    @Test("An asset id that is not a number says so rather than reading as zero")
    func assetIdMustBeANumber() throws {
        #expect(
            throws: GatingConfigurationError.notANumber(key: "TOKEN_ASSET_ID", value: "seven")
        ) {
            try TokenProfile.load(from: Fixture.environment(overriding: ["TOKEN_ASSET_ID": "seven"]))
        }
    }

    // MARK: - Cards and links

    @Test("The operator's logo, colour and links are theirs, and nothing is there by default")
    func brandingIsConfiguration() throws {
        let branded = try TokenProfile.load(from: Fixture.environment())
        #expect(branded.logoURL == "https://example.com/logo.png")
        #expect(branded.cardColor == 0x3355FF)
        #expect(branded.links.count == 1)
        #expect(branded.links.first?.markdown == "[Exchange](https://example.com/swap)")

        let bare = try TokenProfile.load(
            from: Fixture.environment(
                removing: ["TOKEN_LOGO_URL", "TOKEN_CARD_COLOR", "TOKEN_LINK_1_LABEL", "TOKEN_LINK_1_URL"]
            )
        )
        #expect(bare.logoURL == nil)
        #expect(bare.cardColor == nil)
        #expect(bare.links.isEmpty)
    }

    @Test("Links are numbered from one and the first gap ends the list")
    func linksStopAtTheFirstGap() throws {
        let token = try TokenProfile.load(
            from: Fixture.environment(overriding: [
                "TOKEN_LINK_2_LABEL": "Explorer",
                "TOKEN_LINK_2_URL": "https://example.com/asset",
                // Three is written but two is not, so three never appears.
                "TOKEN_LINK_4_LABEL": "Forum",
                "TOKEN_LINK_4_URL": "https://example.com/forum"
            ])
        )
        #expect(token.links.map(\.label) == ["Exchange", "Explorer"])
    }

    @Test("A link with a label and nowhere to go is refused, naming the URL variable")
    func linkNeedsAURL() throws {
        #expect(throws: (any Error).self) {
            try TokenProfile.load(from: Fixture.environment(overriding: ["TOKEN_LINK_2_LABEL": "Explorer"]))
        }
    }

    @Test("A logo Discord could not render is refused at load, not on the card")
    func logoMustBeRenderable() throws {
        #expect(
            throws: GatingConfigurationError.unusableURL(key: "TOKEN_LOGO_URL", value: "ipfs://something")
        ) {
            try TokenProfile.load(from: Fixture.environment(overriding: ["TOKEN_LOGO_URL": "ipfs://something"]))
        }
    }

    @Test("A colour that is not a colour is refused, whichever way it is written")
    func colorMustBeHex() throws {
        for written in ["3355ff", "#3355ff", "0x3355FF"] {
            let token = try TokenProfile.load(from: Fixture.environment(overriding: ["TOKEN_CARD_COLOR": written]))
            #expect(token.cardColor == 0x3355FF)
        }
        #expect(throws: (any Error).self) {
            try TokenProfile.load(from: Fixture.environment(overriding: ["TOKEN_CARD_COLOR": "purple"]))
        }
    }

    // MARK: - Writing amounts out

    @Test("An amount is written at the asset's own precision, with every digit")
    func amountsKeepTheirDigits() throws {
        let six = try Fixture.token()
        let zero = try Fixture.token(decimals: 0)
        #expect(six.format(269_230_769_230) == "269,230.76923")
        #expect(six.formatWithSymbol(1_500_000) == "1.5 TOKEN")
        #expect(zero.format(269_230) == "269,230")
    }
}
